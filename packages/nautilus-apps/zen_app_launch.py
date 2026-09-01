#!/usr/bin/env python3
"""Validate and launch a generated ZenOS /Apps entry."""

from __future__ import annotations

import configparser
import json
import os
from pathlib import Path
import stat
import sys
from typing import Mapping, Sequence


INDEX_SCHEMA = 3
MAX_FILE_BYTES = 4 * 1024 * 1024
SOURCE_LABELS = {
    "nix-config": "Nix (Config)",
    "nix-imperative": "Nix (Imperative)",
    "flatpak": "Flatpak",
    "manual": "Manually Installed",
}


def source_roots(home: Path, user: str | None = None) -> dict[str, tuple[Path, ...]]:
    username = user or home.name
    return {
        "manual": (home / ".local/share/applications",),
        "flatpak": (
            home / ".local/share/flatpak/exports/share/applications",
            Path("/var/lib/flatpak/exports/share/applications"),
        ),
        "nix-imperative": (
            home / ".nix-profile/share/applications",
            home / ".local/state/nix/profiles/profile/share/applications",
            Path(
                f"/nix/var/nix/profiles/per-user/{username}/profile/share/applications"
            ),
        ),
        "nix-config": (
            Path("/run/current-system/sw/share/applications"),
            Path(f"/etc/profiles/per-user/{username}/share/applications"),
        ),
    }


def _simple_basename(value: object) -> bool:
    return (
        isinstance(value, str)
        and bool(value)
        and value not in {".", ".."}
        and len(value.encode("utf-8")) <= 255
        and "\x00" not in value
        and Path(value).name == value
        and "/" not in value
        and "\\" not in value
    )


def _read_regular(path: Path, maximum: int) -> bytes:
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        details = os.fstat(descriptor)
        if not stat.S_ISREG(details.st_mode) or details.st_size > maximum:
            raise ValueError(f"not a bounded regular file: {path}")
        chunks = []
        remaining = maximum + 1
        while remaining:
            chunk = os.read(descriptor, min(65536, remaining))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        contents = b"".join(chunks)
        if len(contents) > maximum:
            raise ValueError(f"file is too large: {path}")
        return contents
    finally:
        os.close(descriptor)


def _metadata(contents: bytes) -> tuple[configparser.ConfigParser, dict[str, str]]:
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    parser.read_string(contents.decode("utf-8"))
    entry = parser["Desktop Entry"]
    normalized: dict[str, str] = {}
    for option, value in entry.items():
        key = option.strip().casefold()
        if key.startswith("x-zenos-") and key in normalized:
            raise ValueError(f"duplicate index metadata: {option}")
        normalized[key] = value.strip()
    return parser, normalized


def _real_directory(path: Path) -> Path:
    absolute = Path(os.path.abspath(path))
    details = os.lstat(absolute)
    if not stat.S_ISDIR(details.st_mode) or stat.S_ISLNK(details.st_mode):
        raise ValueError(f"not a real directory: {absolute}")
    if absolute.resolve(strict=True) != absolute:
        raise ValueError(f"directory contains a symlink: {absolute}")
    return absolute


def _manifest_contains(view: Path, launcher_name: str) -> bool:
    try:
        manifest = json.loads(
            _read_regular(view / ".zenos-app-index.json", 1024 * 1024)
        )
        applications = manifest["applications"]
    except (KeyError, OSError, TypeError, ValueError, UnicodeError):
        return False
    return (
        manifest.get("schema") == INDEX_SCHEMA
        and isinstance(applications, list)
        and all(_simple_basename(name) for name in applications)
        and launcher_name in applications
    )


def validate_launcher(
    value: Path,
    apps_root: Path = Path("/Apps"),
    roots: Mapping[str, Sequence[Path]] | None = None,
) -> Path:
    apps_root = _real_directory(apps_root)
    candidate = Path(os.path.abspath(value))
    views = {"all": apps_root}
    for source in SOURCE_LABELS:
        view = apps_root / ".sources" / source
        if view.exists():
            views[source] = _real_directory(view)
    view_key = next(
        (key for key, view in views.items() if candidate.parent == view), None
    )
    if view_key is None or not _simple_basename(candidate.name):
        raise ValueError("launcher is outside the generated /Apps source views")
    contents = _read_regular(candidate, MAX_FILE_BYTES)
    if not _manifest_contains(views[view_key], candidate.name):
        raise ValueError("launcher is not recorded by the app index")
    _parser, metadata = _metadata(contents)
    source = metadata.get("x-zenos-source")
    desktop_id = metadata.get("x-zenos-desktopid")
    source_path_value = metadata.get("x-zenos-sourcepath")
    if (
        metadata.get("x-zenos-managed", "").casefold() != "true"
        or metadata.get("x-zenos-indexversion") != str(INDEX_SCHEMA)
        or source not in SOURCE_LABELS
        or metadata.get("x-zenos-sourcelabel") != SOURCE_LABELS[source]
        or not _simple_basename(desktop_id)
        or not desktop_id.endswith(".desktop")
        or not source_path_value
    ):
        raise ValueError("launcher has invalid index provenance metadata")
    if view_key != "all" and view_key != source:
        raise ValueError("launcher source does not match its /Apps view")

    source_path = Path(source_path_value)
    if not source_path.is_absolute() or source_path.name != desktop_id:
        raise ValueError("launcher source path does not match its desktop ID")
    allowed_roots = roots or source_roots(Path.home(), os.environ.get("USER"))
    allowed = {Path(os.path.abspath(root)) for root in allowed_roots[source]}
    if Path(os.path.abspath(source_path.parent)) not in allowed:
        raise ValueError("launcher source path is outside its classified source")
    try:
        if not source_path.resolve(strict=True).is_file():
            raise ValueError("launcher source is not a desktop file")
    except OSError as error:
        raise ValueError("launcher source no longer exists") from error
    return candidate


def main() -> int:
    if len(sys.argv) != 2:
        return 2
    try:
        launcher = validate_launcher(
            Path(sys.argv[1]),
            Path(os.environ.get("ZENOS_APPS_DIR", "/Apps")),
        )
    except (configparser.Error, KeyError, OSError, UnicodeError, ValueError) as error:
        print(f"zen-app-launch: {error}", file=sys.stderr)
        return 1

    from gi.repository import Gio

    app = Gio.DesktopAppInfo.new_from_filename(str(launcher))
    if app is None:
        return 1
    app.launch([], None)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
