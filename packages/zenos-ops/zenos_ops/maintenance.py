#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

try:
    from .common import atomic_write_json, exclusive_lock, read_json, unix_time
except ImportError:
    from common import atomic_write_json, exclusive_lock, read_json, unix_time


DEFAULT_CONFIG = "/etc/zenos/maintenance.json"
STATE_VERSION = 1
TASK_ORDER = ("journal-vacuum", "nix-gc", "update", "rebuild")


class ConfigurationError(ValueError):
    pass


def load_config(path):
    config = read_json(path)
    if not isinstance(config, dict):
        raise ConfigurationError(f"cannot read maintenance configuration: {path}")
    if not isinstance(config.get("stateDir"), str) or not Path(config["stateDir"]).is_absolute():
        raise ConfigurationError("stateDir must be an absolute path")
    guard = config.get("guard")
    if not isinstance(guard, dict):
        raise ConfigurationError("guard must be an object")
    tasks = config.get("tasks")
    if not isinstance(tasks, dict):
        raise ConfigurationError("tasks must be an object")
    unknown = set(tasks) - set(TASK_ORDER)
    if unknown:
        raise ConfigurationError(f"unknown maintenance tasks: {', '.join(sorted(unknown))}")
    for name, task in tasks.items():
        if not isinstance(task, dict) or not isinstance(task.get("command"), list):
            raise ConfigurationError(f"{name}.command must be an array")
        if not task["command"] or not all(isinstance(item, str) and item for item in task["command"]):
            raise ConfigurationError(f"{name}.command must contain non-empty strings")
        if not isinstance(task.get("intervalSeconds"), int) or task["intervalSeconds"] <= 0:
            raise ConfigurationError(f"{name}.intervalSeconds must be positive")
        if not isinstance(task.get("timeoutSeconds", 3600), int) or task.get("timeoutSeconds", 3600) <= 0:
            raise ConfigurationError(f"{name}.timeoutSeconds must be positive")
    return config


def _read_meminfo(proc_root):
    values = {}
    with open(Path(proc_root) / "meminfo", "r", encoding="ascii") as handle:
        for line in handle:
            key, raw = line.split(":", 1)
            fields = raw.strip().split()
            if fields:
                values[key] = int(fields[0])
    total = values.get("MemTotal", 0)
    available = values.get("MemAvailable", values.get("MemFree", 0))
    if total <= 0:
        raise ValueError("MemTotal is unavailable")
    return round(available * 100.0 / total, 2)


def _read_psi(proc_root, resource):
    path = Path(proc_root) / "pressure" / resource
    with open(path, "r", encoding="ascii") as handle:
        for line in handle:
            fields = line.split()
            if fields and fields[0] == "some":
                values = dict(field.split("=", 1) for field in fields[1:])
                return float(values["avg10"])
    raise ValueError(f"some avg10 is unavailable for {resource} PSI")


def _read_ac(sys_root):
    root = Path(sys_root) / "class" / "power_supply"
    mains = []
    batteries = 0
    try:
        supplies = sorted(root.iterdir(), key=lambda item: item.name)
    except FileNotFoundError:
        supplies = []
    for supply in supplies:
        try:
            supply_type = (supply / "type").read_text(encoding="ascii").strip()
        except (FileNotFoundError, OSError):
            continue
        if supply_type == "Battery":
            batteries += 1
        if supply_type in {"Mains", "USB", "USB_C", "Wireless"}:
            try:
                online = (supply / "online").read_text(encoding="ascii").strip() == "1"
            except (FileNotFoundError, OSError):
                online = False
            mains.append({"name": supply.name, "online": online, "type": supply_type})
    if mains:
        return any(item["online"] for item in mains), {"supplies": mains, "assumed": False}
    return batteries == 0, {"supplies": [], "assumed": batteries == 0}


def guard_report(config, proc_root="/proc", sys_root="/sys"):
    guard = config["guard"]
    checks = []

    def measure(name, limit, comparator, reader, unavailable_message):
        if limit is None:
            checks.append({"name": name, "enabled": False, "passed": True})
            return
        try:
            value = reader()
            checks.append({
                "name": name,
                "enabled": True,
                "limit": limit,
                "passed": comparator(value, limit),
                "value": value,
            })
        except (OSError, ValueError, KeyError) as error:
            checks.append({
                "name": name,
                "enabled": True,
                "limit": limit,
                "passed": False,
                "error": f"{unavailable_message}: {error}",
            })

    measure(
        "load-per-cpu",
        guard.get("maxLoadPerCpu"),
        lambda value, limit: value <= limit,
        lambda: round(os.getloadavg()[0] / max(os.cpu_count() or 1, 1), 3),
        "load average unavailable",
    )
    measure(
        "memory-available-percent",
        guard.get("minMemoryAvailablePercent"),
        lambda value, limit: value >= limit,
        lambda: _read_meminfo(proc_root),
        "memory data unavailable",
    )
    measure(
        "cpu-psi-some-avg10",
        guard.get("maxCpuPsiSomeAvg10"),
        lambda value, limit: value <= limit,
        lambda: _read_psi(proc_root, "cpu"),
        "CPU PSI unavailable",
    )
    measure(
        "memory-psi-some-avg10",
        guard.get("maxMemoryPsiSomeAvg10"),
        lambda value, limit: value <= limit,
        lambda: _read_psi(proc_root, "memory"),
        "memory PSI unavailable",
    )

    if guard.get("requireAC", True):
        on_ac, detail = _read_ac(sys_root)
        checks.append({"name": "ac-power", "enabled": True, "passed": on_ac, "value": on_ac, **detail})
    else:
        checks.append({"name": "ac-power", "enabled": False, "passed": True})
    return {"passed": all(check["passed"] for check in checks), "checks": checks, "checkedAt": unix_time()}


def _state_paths(config):
    state_dir = Path(config["stateDir"])
    return state_dir, state_dir / "state.json", state_dir / "requests", state_dir / "maintenance.lock"


def _load_state(path):
    state = read_json(path, default={})
    if not isinstance(state, dict) or state.get("version") != STATE_VERSION:
        return {"version": STATE_VERSION, "tasks": {}}
    if not isinstance(state.get("tasks"), dict):
        state["tasks"] = {}
    return state


def pending_requests(config):
    _, _, request_dir, _ = _state_paths(config)
    pending = []
    for task in TASK_ORDER:
        if (request_dir / f"{task}.json").is_file():
            pending.append(task)
    return pending


def request_task(config, task, now=None):
    if task not in config["tasks"]:
        raise ConfigurationError(f"task is not enabled: {task}")
    _, _, request_dir, _ = _state_paths(config)
    request_dir.mkdir(parents=True, exist_ok=True)
    atomic_write_json(request_dir / f"{task}.json", {"requestedAt": now or unix_time(), "task": task})


def run_tick(config, only=None, now=None, runner=subprocess.run, proc_root="/proc", sys_root="/sys"):
    now = now or unix_time()
    _, state_path, request_dir, lock_path = _state_paths(config)
    try:
        with exclusive_lock(lock_path):
            state = _load_state(state_path)
            pending = pending_requests(config)
            selected = []
            for task in TASK_ORDER:
                if task not in config["tasks"]:
                    continue
                previous = state["tasks"].get(task, {})
                due = now - previous.get("lastAttempt", 0) >= config["tasks"][task]["intervalSeconds"]
                if task in pending or due or task == only:
                    selected.append(task)
            if only is not None:
                if only not in config["tasks"]:
                    raise ConfigurationError(f"task is not enabled: {only}")
                selected = [only]

            report = guard_report(config, proc_root=proc_root, sys_root=sys_root)
            state.update({"lastGuard": report, "lastTick": now})
            if selected and not report["passed"]:
                state["lastResult"] = "deferred"
                atomic_write_json(state_path, state)
                return {"guard": report, "result": "deferred", "tasks": selected}, 75

            results = []
            for task in selected:
                task_config = config["tasks"][task]
                task_state = state["tasks"].setdefault(task, {})
                task_state["lastAttempt"] = now
                atomic_write_json(state_path, state)
                try:
                    completed = runner(
                        task_config["command"],
                        capture_output=True,
                        check=False,
                        text=True,
                        timeout=task_config.get("timeoutSeconds", 3600),
                    )
                    return_code = completed.returncode
                    output = (completed.stdout + completed.stderr)[-4096:]
                    result = "success" if return_code == 0 else "failed"
                except (OSError, subprocess.TimeoutExpired) as error:
                    return_code = 124 if isinstance(error, subprocess.TimeoutExpired) else 127
                    output = str(error)[-4096:]
                    result = "failed"
                task_state.update({"lastOutput": output, "lastResult": result, "returnCode": return_code})
                if result == "success":
                    task_state["lastSuccess"] = now
                results.append({"name": task, "result": result, "returnCode": return_code})
                if task in pending:
                    try:
                        (request_dir / f"{task}.json").unlink()
                    except FileNotFoundError:
                        pass
                atomic_write_json(state_path, state)
            if not results:
                state["lastResult"] = "idle"
            else:
                state["lastResult"] = "failed" if any(item["result"] == "failed" for item in results) else "success"
            atomic_write_json(state_path, state)
            return {"guard": report, "result": state["lastResult"], "tasks": results}, 1 if state["lastResult"] == "failed" else 0
    except BlockingIOError:
        return {"result": "locked", "tasks": []}, 73


def status(config):
    _, state_path, _, _ = _state_paths(config)
    return {"pending": pending_requests(config), "state": _load_state(state_path)}


def _print(value, as_json):
    if as_json:
        print(json.dumps(value, indent=2, sort_keys=True))
        return
    if "passed" in value:
        print("guards: " + ("pass" if value["passed"] else "blocked"))
        for check in value["checks"]:
            result = "pass" if check["passed"] else "fail"
            detail = check.get("value", check.get("error", "disabled"))
            print(f"  {check['name']}: {result} ({detail})")
    else:
        print(json.dumps(value, indent=2, sort_keys=True))


def main(argv=None):
    parser = argparse.ArgumentParser(prog="zenos-maintenance", description="Guarded ZenOS maintenance dispatcher")
    parser.add_argument("--config", default=os.environ.get("ZENOS_MAINTENANCE_CONFIG", DEFAULT_CONFIG))
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in ("status", "check"):
        subparsers.add_parser(command).add_argument("--json", action="store_true")
    request_parser = subparsers.add_parser("request")
    request_parser.add_argument("task", choices=TASK_ORDER)
    tick_parser = subparsers.add_parser("tick")
    tick_parser.add_argument("--target", choices=TASK_ORDER)
    tick_parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    try:
        config = load_config(args.config)
        if args.command == "status":
            _print(status(config), args.json)
            return 0
        if args.command == "check":
            report = guard_report(config)
            _print(report, args.json)
            return 0 if report["passed"] else 75
        if args.command == "request":
            request_task(config, args.task)
            print(f"queued: {args.task}")
            return 0
        result, return_code = run_tick(config, only=args.target)
        _print(result, args.json)
        return return_code
    except (ConfigurationError, json.JSONDecodeError, OSError) as error:
        print(f"zenos-maintenance: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
