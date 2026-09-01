#!/usr/bin/env python3
"""Preflight and supervise one explicitly configured XR process."""

import argparse
import json
import os
import shutil
import signal
import subprocess
import tempfile


def load_config(path):
    with open(path, "r", encoding="utf-8") as handle:
        config = json.load(handle)
    command = config.get("command")
    if not isinstance(command, list) or not command or not all(isinstance(item, str) for item in command):
        raise ValueError("config.command must be a non-empty list of strings")
    return config


def executable_exists(command, environment):
    if os.path.isabs(command):
        return os.path.isfile(command) and os.access(command, os.X_OK)
    return shutil.which(command, path=environment.get("PATH")) is not None


def preflight(config):
    environment = os.environ.copy()
    environment.update(config.get("environment", {}))
    commands = [config["command"][0]] + config.get("requiredCommands", [])
    checks = {
        "commands": {command: executable_exists(command, environment) for command in commands},
        "paths": {path: os.path.exists(path) for path in config.get("requiredPaths", [])},
    }
    checks["ok"] = all(checks["commands"].values()) and all(checks["paths"].values())
    return checks


def process_start_time(pid):
    try:
        with open(f"/proc/{pid}/stat", "r", encoding="utf-8") as handle:
            stat = handle.read()
        return int(stat[stat.rfind(")") + 2 :].split()[19])
    except (FileNotFoundError, ProcessLookupError, PermissionError, ValueError, IndexError):
        return None


def write_state(path, state):
    directory = os.path.dirname(os.path.abspath(path))
    os.makedirs(directory, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".zen-xr-", dir=directory, text=True)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(state, handle, indent=2, sort_keys=True)
            handle.write("\n")
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def read_status(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            state = json.load(handle)
    except FileNotFoundError:
        return {"status": "not-started"}
    if state.get("status") != "running":
        return state
    pid = state.get("childPid")
    if not isinstance(pid, int) or process_start_time(pid) != state.get("childStartTime"):
        state["status"] = "stale"
    return state


def run(config, state_file):
    checks = preflight(config)
    if not checks["ok"]:
        print(json.dumps(checks, sort_keys=True))
        return 78

    environment = os.environ.copy()
    environment.update(config.get("environment", {}))
    child = subprocess.Popen(config["command"], env=environment, start_new_session=True)
    state = {
        "childPid": child.pid,
        "childStartTime": process_start_time(child.pid),
        "command": config["command"],
        "status": "running",
        "supervisorPid": os.getpid(),
    }
    write_state(state_file, state)

    def forward(signum, _frame):
        if child.poll() is None and os.getpgid(child.pid) == child.pid:
            os.killpg(child.pid, signum)

    signal.signal(signal.SIGINT, forward)
    signal.signal(signal.SIGTERM, forward)
    try:
        return_code = child.wait()
    finally:
        state["status"] = "stopped"
        state["exitCode"] = child.returncode
        write_state(state_file, state)
    return return_code


def main(argv=None):
    parser = argparse.ArgumentParser(prog="zen-xr-supervisor")
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in ("preflight", "run"):
        command_parser = subparsers.add_parser(command)
        command_parser.add_argument("--config", required=True)
        if command == "run":
            command_parser.add_argument("--state-file", required=True)
    status_parser = subparsers.add_parser("status")
    status_parser.add_argument("--state-file", required=True)
    args = parser.parse_args(argv)

    if args.command == "status":
        status = read_status(args.state_file)
        print(json.dumps(status, indent=2, sort_keys=True))
        return 0 if status.get("status") == "running" else 3

    config = load_config(args.config)
    if args.command == "preflight":
        checks = preflight(config)
        print(json.dumps(checks, indent=2, sort_keys=True))
        return 0 if checks["ok"] else 78
    return run(config, args.state_file)


if __name__ == "__main__":
    raise SystemExit(main())
