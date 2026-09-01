#!/usr/bin/env python3
"""Match local hardware facts against the static ZenOS preset database."""

import argparse
import fnmatch
import json
import os
import tempfile


DEFAULT_DATABASE = os.environ.get(
    "ZEN_HARDWARE_DATABASE",
    os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "share",
        "zen-hardware",
        "presets.json",
    ),
)

DMI_FIELDS = (
    "bios_vendor",
    "board_name",
    "board_vendor",
    "product_name",
    "product_version",
    "sys_vendor",
)


def load_json(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def load_database(path):
    database = load_json(path)
    if database.get("schemaVersion") != 1 or not isinstance(database.get("presets"), list):
        raise ValueError("unsupported hardware preset database schema")
    return database


def read_facts(sysfs_root="/sys"):
    dmi_root = os.path.join(sysfs_root, "class", "dmi", "id")
    dmi = {}
    for field in DMI_FIELDS:
        try:
            with open(os.path.join(dmi_root, field), "r", encoding="utf-8") as handle:
                dmi[field] = handle.read().strip()
        except (FileNotFoundError, PermissionError, OSError):
            dmi[field] = ""
    return {"dmi": dmi}


def flatten_facts(facts):
    flattened = {}
    for group, values in facts.items():
        if isinstance(values, dict):
            for key, value in values.items():
                flattened[f"{group}.{key}"] = str(value)
        else:
            flattened[group] = str(values)
    return flattened


def preset_matches(preset, facts):
    flattened = flatten_facts(facts)
    rules = preset.get("match", {})
    for key, patterns in rules.items():
        value = flattened.get(key, "").casefold()
        if not any(fnmatch.fnmatchcase(value, pattern.casefold()) for pattern in patterns):
            return False
    return True


def select_preset(database, facts):
    matches = [preset for preset in database["presets"] if preset_matches(preset, facts)]
    if not matches:
        return None
    return max(
        matches,
        key=lambda preset: (
            preset.get("priority", 0),
            len(preset.get("match", {})),
            preset.get("id", ""),
        ),
    )


def write_json(path, value):
    directory = os.path.dirname(os.path.abspath(path))
    os.makedirs(directory, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".zen-hardware-", dir=directory, text=True)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(value, handle, indent=2, sort_keys=True)
            handle.write("\n")
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def emit(value, as_json=False, output=None):
    if output:
        write_json(output, value)
    if as_json:
        print(json.dumps(value, indent=2, sort_keys=True))
    elif isinstance(value, dict) and "preset" in value:
        preset = value["preset"]
        print(preset["id"] if preset else "unmatched")
    elif isinstance(value, dict):
        print(value.get("id", json.dumps(value, sort_keys=True)))
    else:
        print(value)


def facts_for_args(args):
    return load_json(args.facts) if args.facts else read_facts(args.sysfs_root)


def main(argv=None):
    parser = argparse.ArgumentParser(prog="zen-hardware")
    parser.add_argument("--database", default=DEFAULT_DATABASE)
    subparsers = parser.add_subparsers(dest="command", required=True)

    list_parser = subparsers.add_parser("list", help="list known presets")
    list_parser.add_argument("--json", action="store_true")

    show_parser = subparsers.add_parser("show", help="show one preset")
    show_parser.add_argument("preset")
    show_parser.add_argument("--json", action="store_true")
    show_parser.add_argument("--output")

    for command in ("detect", "match"):
        command_parser = subparsers.add_parser(command, help=f"{command} a hardware preset")
        command_parser.add_argument("--facts", required=command == "match")
        command_parser.add_argument("--sysfs-root", default="/sys")
        command_parser.add_argument("--json", action="store_true")
        command_parser.add_argument("--output")

    args = parser.parse_args(argv)
    database = load_database(args.database)

    if args.command == "list":
        value = database["presets"] if args.json else "\n".join(preset["id"] for preset in database["presets"])
        emit(value, args.json)
        return 0

    if args.command == "show":
        preset = next((item for item in database["presets"] if item["id"] == args.preset), None)
        if preset is None:
            parser.error(f"unknown preset: {args.preset}")
        emit(preset, args.json, args.output)
        return 0

    facts = facts_for_args(args)
    preset = select_preset(database, facts)
    result = {"facts": facts, "preset": preset, "schemaVersion": 1}
    emit(result, args.json, args.output)
    return 0 if preset is not None else 2


if __name__ == "__main__":
    raise SystemExit(main())
