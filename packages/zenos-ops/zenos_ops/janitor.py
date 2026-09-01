#!/usr/bin/env python3
import argparse
import errno
import fnmatch
import hashlib
import json
import os
import stat
import sys
from pathlib import Path

try:
    from .common import exclusive_lock, read_json, unix_time
except ImportError:
    from common import exclusive_lock, read_json, unix_time


DEFAULT_CONFIG = "/etc/zenos/janitor-rules.json"


class ConfigurationError(ValueError):
    pass


def _expanded(path):
    return Path(os.path.expandvars(os.path.expanduser(path)))


def _is_within(path, roots):
    resolved = path.resolve(strict=False)
    for root in roots:
        allowed = root.resolve(strict=False)
        if resolved == allowed or allowed in resolved.parents:
            return True
    return False


def load_config(path):
    config = read_json(path)
    if not isinstance(config, dict) or config.get("version") != 1:
        raise ConfigurationError("rules file must be a version 1 object")
    raw_allowed = config.get("allowedDestinations")
    rules = config.get("rules")
    if not isinstance(raw_allowed, list) or not raw_allowed or not all(isinstance(item, str) and item for item in raw_allowed):
        raise ConfigurationError("allowedDestinations must contain paths")
    if not isinstance(rules, list):
        raise ConfigurationError("rules must be an array")
    allowed = [_expanded(item) for item in raw_allowed]
    if not all(item.is_absolute() for item in allowed):
        raise ConfigurationError("allowedDestinations must expand to absolute paths")
    names = set()
    normalized = []
    for index, rule in enumerate(rules):
        if not isinstance(rule, dict):
            raise ConfigurationError(f"rule {index} must be an object")
        name = rule.get("name")
        source = rule.get("source")
        destination = rule.get("destination")
        extensions = rule.get("extensions", [])
        if not isinstance(name, str) or not name or name in names:
            raise ConfigurationError(f"rule {index} has an empty or duplicate name")
        names.add(name)
        if not isinstance(source, str) or not source or not isinstance(destination, str) or not destination:
            raise ConfigurationError(f"rule {name} requires source and destination paths")
        expanded_source = _expanded(source)
        target = _expanded(destination)
        if not expanded_source.is_absolute() or not target.is_absolute():
            raise ConfigurationError(f"rule {name} paths must expand to absolute paths")
        if not isinstance(extensions, list) or not all(
            isinstance(item, str) and item.startswith(".") and len(item) > 1 for item in extensions
        ):
            raise ConfigurationError(f"rule {name} has an invalid extension")
        pattern = rule.get("namePattern")
        if pattern is not None and (not isinstance(pattern, str) or not pattern):
            raise ConfigurationError(f"rule {name} has an invalid namePattern")
        minimum = rule.get("minSizeBytes")
        maximum = rule.get("maxSizeBytes")
        for label, value in (("minSizeBytes", minimum), ("maxSizeBytes", maximum)):
            if value is not None and (not isinstance(value, int) or isinstance(value, bool) or value < 0):
                raise ConfigurationError(f"rule {name} has an invalid {label}")
        if minimum is not None and maximum is not None and minimum > maximum:
            raise ConfigurationError(f"rule {name} has minSizeBytes greater than maxSizeBytes")
        recursive = rule.get("recursive", False)
        if not isinstance(recursive, bool):
            raise ConfigurationError(f"rule {name} recursive must be a boolean")
        if not _is_within(target, allowed):
            raise ConfigurationError(f"rule {name} destination is outside allowedDestinations")
        normalized.append({
            "destination": target,
            "extensions": tuple(item.lower() for item in extensions),
            "maxSizeBytes": maximum,
            "minSizeBytes": minimum,
            "name": name,
            "namePattern": pattern,
            "recursive": recursive,
            "source": expanded_source,
        })
    return {"allowedDestinations": allowed, "rules": normalized, "version": 1}


def _files(rule):
    source = rule["source"]
    if source.is_symlink() or not source.is_dir():
        return []
    if not rule["recursive"]:
        entries = source.iterdir()
        return sorted((item for item in entries if _regular_file(item)), key=lambda item: item.name)
    found = []
    for current, directories, filenames in os.walk(source, followlinks=False):
        directories[:] = sorted(
            name for name in directories if not (Path(current) / name).is_symlink()
        )
        for filename in sorted(filenames):
            candidate = Path(current) / filename
            if _regular_file(candidate):
                found.append(candidate)
    return sorted(found, key=lambda item: str(item.relative_to(source)))


def _regular_file(path):
    try:
        return stat.S_ISREG(path.stat(follow_symlinks=False).st_mode)
    except (FileNotFoundError, OSError):
        return False


def matches(rule, path, size):
    lower_name = path.name.lower()
    if rule["extensions"] and not any(lower_name.endswith(extension) for extension in rule["extensions"]):
        return False
    if rule["namePattern"] is not None and not fnmatch.fnmatchcase(path.name, rule["namePattern"]):
        return False
    if rule["minSizeBytes"] is not None and size < rule["minSizeBytes"]:
        return False
    if rule["maxSizeBytes"] is not None and size > rule["maxSizeBytes"]:
        return False
    return True


def scan(config):
    operations = []
    seen = set()
    for rule in config["rules"]:
        for source in _files(rule):
            try:
                metadata = source.stat(follow_symlinks=False)
            except (FileNotFoundError, OSError):
                continue
            identity = (metadata.st_dev, metadata.st_ino)
            if identity in seen or not matches(rule, source, metadata.st_size):
                continue
            seen.add(identity)
            destination = rule["destination"] / source.name
            operations.append({
                "destination": str(destination),
                "rule": rule["name"],
                "size": metadata.st_size,
                "source": str(source),
                "status": "blocked" if os.path.lexists(destination) else "ready",
            })
    return operations


def _state_dir(override=None):
    if override:
        return Path(override)
    root = os.environ.get("XDG_STATE_HOME")
    return Path(root) / "zenos-janitor" if root else Path.home() / ".local/state/zenos-janitor"


def _append_journal(path, record):
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_APPEND | os.O_CREAT | os.O_WRONLY, 0o600)
    try:
        payload = (json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
        written = 0
        while written < len(payload):
            written += os.write(descriptor, payload[written:])
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _move_without_overwrite(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_symlink() or os.path.lexists(destination):
        raise FileExistsError(errno.EEXIST, "destination exists", destination)
    before = source.stat(follow_symlinks=False)
    if not stat.S_ISREG(before.st_mode):
        raise OSError(errno.EINVAL, "source is not a regular file", source)
    os.link(source, destination, follow_symlinks=False)
    try:
        linked = destination.stat(follow_symlinks=False)
        if (linked.st_dev, linked.st_ino) != (before.st_dev, before.st_ino):
            raise OSError(errno.ESTALE, "source changed while moving", source)
        source.unlink()
    except BaseException:
        try:
            destination.unlink()
        except OSError:
            pass
        raise
    return linked


def process(config, state_dir=None, now=None):
    state_dir = _state_dir(state_dir)
    journal = state_dir / "operations.jsonl"
    lock = state_dir / "janitor.lock"
    timestamp = now or unix_time()
    run_id = f"{timestamp}-{os.getpid()}"
    results = []
    with exclusive_lock(lock):
        for index, operation in enumerate(scan(config), start=1):
            if operation["status"] != "ready":
                results.append({**operation, "result": "skipped"})
                continue
            source = Path(operation["source"])
            destination = Path(operation["destination"])
            if not _is_within(destination, config["allowedDestinations"]):
                results.append({**operation, "result": "failed", "reason": "destination-outside-allowlist"})
                continue
            try:
                digest = _sha256(source)
                metadata = _move_without_overwrite(source, destination)
                operation_id = f"{run_id}-{index}"
                _append_journal(journal, {
                    "destination": str(destination),
                    "device": metadata.st_dev,
                    "inode": metadata.st_ino,
                    "operationId": operation_id,
                    "rule": operation["rule"],
                    "runId": run_id,
                    "sha256": digest,
                    "size": metadata.st_size,
                    "source": str(source),
                    "timestamp": timestamp,
                    "type": "move",
                })
                results.append({**operation, "operationId": operation_id, "result": "moved"})
            except FileExistsError:
                results.append({**operation, "result": "skipped", "reason": "destination-exists"})
            except OSError as error:
                results.append({**operation, "result": "failed", "reason": str(error)})
    return {"results": results, "runId": run_id}


def _read_journal(path):
    records = []
    try:
        with open(path, "r", encoding="utf-8") as handle:
            for line in handle:
                try:
                    record = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if isinstance(record, dict):
                    records.append(record)
    except FileNotFoundError:
        pass
    return records


def undo(state_dir=None, operation_id=None, now=None):
    state_dir = _state_dir(state_dir)
    journal = state_dir / "operations.jsonl"
    lock = state_dir / "janitor.lock"
    timestamp = now or unix_time()
    results = []
    with exclusive_lock(lock):
        records = _read_journal(journal)
        undone = {record.get("operationId") for record in records if record.get("type") == "undo"}
        moves = [record for record in records if record.get("type") == "move" and record.get("operationId") not in undone]
        if operation_id is not None:
            moves = [record for record in moves if record.get("operationId") == operation_id]
        elif moves:
            latest_run = moves[-1].get("runId")
            moves = [record for record in moves if record.get("runId") == latest_run]
        for record in reversed(moves):
            source = Path(record["source"])
            destination = Path(record["destination"])
            reason = None
            if os.path.lexists(source):
                reason = "source-exists"
            elif destination.is_symlink() or not _regular_file(destination):
                reason = "destination-missing-or-not-regular"
            else:
                metadata = destination.stat(follow_symlinks=False)
                expected = (record.get("device"), record.get("inode"), record.get("size"))
                actual = (metadata.st_dev, metadata.st_ino, metadata.st_size)
                if actual != expected:
                    reason = "destination-changed"
                elif _sha256(destination) != record.get("sha256"):
                    reason = "destination-changed"
            if reason:
                results.append({"operationId": record.get("operationId"), "result": "skipped", "reason": reason})
                continue
            try:
                _move_without_overwrite(destination, source)
                _append_journal(journal, {
                    "operationId": record["operationId"],
                    "timestamp": timestamp,
                    "type": "undo",
                })
                results.append({"operationId": record["operationId"], "result": "undone"})
            except OSError as error:
                results.append({"operationId": record.get("operationId"), "result": "failed", "reason": str(error)})
    return {"results": results}


def main(argv=None):
    parser = argparse.ArgumentParser(prog="zenos-janitor", description="Deterministic one-shot file janitor")
    parser.add_argument("--config", default=os.environ.get("ZENOS_JANITOR_CONFIG", DEFAULT_CONFIG))
    parser.add_argument("--state-dir")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("validate")
    subparsers.add_parser("scan")
    subparsers.add_parser("process")
    undo_parser = subparsers.add_parser("undo")
    undo_parser.add_argument("--operation")
    args = parser.parse_args(argv)
    try:
        config = load_config(args.config)
        if args.command == "validate":
            print("rules: valid")
            return 0
        if args.command == "scan":
            result = {"operations": scan(config)}
        elif args.command == "process":
            result = process(config, state_dir=args.state_dir)
        else:
            result = undo(state_dir=args.state_dir, operation_id=args.operation)
        print(json.dumps(result, indent=2, sort_keys=True))
        return 1 if any(item.get("result") == "failed" for item in result.get("results", [])) else 0
    except (ConfigurationError, json.JSONDecodeError, OSError) as error:
        print(f"zenos-janitor: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
