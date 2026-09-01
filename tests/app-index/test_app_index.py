import json
from pathlib import Path
import tempfile
import unittest

from app_index import (
    AppSource,
    build_index,
    build_source_views,
    classify_source,
    desktop_entry,
    desktop_visible,
)
from app_registry import app_token


class AppIndexTests(unittest.TestCase):
    def write_desktop(self, directory: Path, name: str, body: str) -> Path:
        path = directory / name
        path.write_text("[Desktop Entry]\n" + body, encoding="utf-8")
        return path

    def test_indexes_only_visible_gnome_applications(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            target = root / "Apps"
            source.mkdir()
            self.write_desktop(
                source, "visible.desktop", "Type=Application\nName=Visible\nExec=true\n"
            )
            self.write_desktop(
                source,
                "hidden.desktop",
                "Type=Application\nName=Hidden\nExec=true\nNoDisplay=true\n",
            )
            self.write_desktop(
                source,
                "kde.desktop",
                "Type=Application\nName=KDE\nExec=true\nOnlyShowIn=KDE;\n",
            )

            indexed = build_index(source, target)

            self.assertEqual(["Visible.desktop"], indexed)
            self.assertTrue((target / "Visible.desktop").stat().st_mode & 0o111)
            self.assertFalse((target / "hidden.desktop").exists())

    def test_rejects_non_application_and_missing_try_exec(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            link = self.write_desktop(
                root, "link.desktop", "Type=Link\nName=Link\nURL=/\n"
            )
            missing = self.write_desktop(
                root,
                "missing.desktop",
                "Type=Application\nName=Missing\nExec=missing\nTryExec=definitely-not-installed\n",
            )

            self.assertFalse(desktop_visible(link))
            self.assertFalse(desktop_visible(missing))

    def test_classifies_user_sources(self) -> None:
        home = Path("/home/alice")
        self.assertEqual(
            "manual",
            classify_source(
                home / ".local/share/applications/editor.desktop", home, "alice"
            ),
        )
        self.assertEqual(
            "nix-imperative",
            classify_source(
                home / ".nix-profile/share/applications/editor.desktop", home, "alice"
            ),
        )
        self.assertEqual(
            "flatpak",
            classify_source(
                home / ".local/share/flatpak/exports/share/applications/editor.desktop",
                home,
                "alice",
            ),
        )
        self.assertEqual(
            "nix-config",
            classify_source(
                Path("/run/current-system/sw/share/applications/editor.desktop"), home
            ),
        )
        self.assertEqual(
            "nix-config",
            classify_source(
                Path("/etc/profiles/per-user/alice/share/applications/editor.desktop"),
                home,
            ),
        )

    def test_builds_all_source_views_with_manual_override(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home/alice"
            target = root / "Apps"
            manual = home / ".local/share/applications"
            imperative = home / ".nix-profile/share/applications"
            flatpak = home / ".local/share/flatpak/exports/share/applications"
            for source in (manual, imperative, flatpak):
                source.mkdir(parents=True)
            self.write_desktop(
                manual,
                "editor.desktop",
                "Type=Application\nName=Manual Editor\nExec=true\n",
            )
            self.write_desktop(
                imperative,
                "editor.desktop",
                "Type=Application\nName=Nix Editor\nExec=true\n",
            )
            self.write_desktop(
                flatpak,
                "chat.desktop",
                "Type=Application\nName=Chat\nExec=true\nX-Flatpak=org.example.Chat\n",
            )

            sources = (
                AppSource("manual", "Manually Installed", (manual,)),
                AppSource("flatpak", "Flatpak", (flatpak,)),
                AppSource("nix-imperative", "Nix (Imperative)", (imperative,)),
                AppSource("nix-config", "Nix (Config)", (root / "system",)),
            )
            views = build_source_views(home, target, "alice", sources)

            self.assertEqual(["Manual Editor.desktop", "Chat.desktop"], views["all"])
            self.assertEqual(["Nix Editor.desktop"], views["nix-imperative"])
            self.assertTrue((target / ".sources/manual/Manual Editor.desktop").is_file())
            self.assertTrue((target / ".sources/nix-config").is_dir())
            self.assertEqual(
                "manual", desktop_entry(target / "Manual Editor.desktop")["X-ZenOS-Source"]
            )
            manifest = json.loads(
                (target / ".sources/.zenos-source-views.json").read_text(
                    encoding="utf-8"
                )
            )
            self.assertEqual(
                [
                    "All Sources",
                    "Nix (Config)",
                    "Nix (Imperative)",
                    "Flatpak",
                    "Manually Installed",
                ],
                [view["label"] for view in manifest["views"]],
            )
            registry = json.loads(
                (target / ".zenos-app-registry.json").read_text(encoding="utf-8")
            )
            self.assertEqual(1, registry["schema"])
            self.assertEqual(
                app_token("manual", "editor.desktop"),
                registry["applications"][0]["token"],
            )
            self.assertEqual(
                registry["applications"][0]["token"],
                desktop_entry(target / "Manual Editor.desktop")["X-ZenOS-AppToken"],
            )

    def test_records_owning_nix_package(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = root / "nix/store/example-package"
            source = package / "share/applications"
            source.mkdir(parents=True)
            self.write_desktop(
                source,
                "editor.desktop",
                "Type=Application\nName=Editor\nExec=true\n",
            )

            build_index(source, root / "Apps")

            entry = desktop_entry(root / "Apps/Editor.desktop")
            self.assertEqual(str(package), entry["X-ZenOS-Package"])

    def test_skips_malformed_desktop_booleans(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            source.mkdir()
            malformed = self.write_desktop(
                source,
                "malformed.desktop",
                "Type=Application\nName=Malformed\nExec=true\nHidden=perhaps\n",
            )

            self.assertFalse(desktop_visible(malformed))
            self.assertEqual([], build_index(source, root / "Apps"))

    def test_ignores_hostile_manifest_entries(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            target = root / "Apps"
            source.mkdir()
            target.mkdir()
            victim = root / "victim"
            victim.write_text("keep", encoding="utf-8")
            notes = target / "notes"
            notes.write_text("not generated", encoding="utf-8")
            (target / ".zenos-app-index.json").write_text(
                json.dumps({"schema": 3, "applications": ["../victim", "notes"]}),
                encoding="utf-8",
            )

            build_index(source, target)

            self.assertEqual("keep", victim.read_text(encoding="utf-8"))
            self.assertEqual("not generated", notes.read_text(encoding="utf-8"))

    def test_atomic_launcher_write_replaces_symlink_not_target(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            target = root / "Apps"
            source.mkdir()
            self.write_desktop(
                source, "editor.desktop", "Type=Application\nName=Editor\nExec=true\n"
            )
            build_index(source, target)
            victim = root / "victim"
            victim.write_text("keep", encoding="utf-8")
            launcher = target / "Editor.desktop"
            launcher.unlink()
            launcher.symlink_to(victim)

            build_index(source, target)

            self.assertEqual("keep", victim.read_text(encoding="utf-8"))
            self.assertFalse(launcher.is_symlink())
            self.assertTrue(launcher.is_file())

    def test_rejects_symlinked_sources_view(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home/alice"
            target = root / "Apps"
            outside = root / "outside"
            target.mkdir()
            outside.mkdir()
            (target / ".sources").symlink_to(outside, target_is_directory=True)

            with self.assertRaises(ValueError):
                build_source_views(home, target, "alice", ())
            self.assertEqual([], list(outside.iterdir()))

    def test_replaces_spoofed_zenos_metadata_case_insensitively(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home/alice"
            manual = home / ".local/share/applications"
            manual.mkdir(parents=True)
            self.write_desktop(
                manual,
                "editor.desktop",
                "Type=Application\n"
                "Name=Editor\n"
                "Exec=true\n"
                "X-zEnOs-PaCkAgE = /etc\n"
                "X-ZENOS-SOURCE = flatpak\n"
                "x-zenos-origin = spoofed\n",
            )
            sources = (AppSource("manual", "Manually Installed", (manual,)),)

            build_source_views(home, root / "Apps", "alice", sources)

            launcher = (root / "Apps/Editor.desktop").read_text(encoding="utf-8")
            normalized = [
                line.partition("=")[0].strip().casefold()
                for line in launcher.splitlines()
                if "=" in line
            ]
            entry = desktop_entry(root / "Apps/Editor.desktop")
            self.assertEqual("manual", entry["X-ZenOS-Source"])
            self.assertNotIn("X-ZenOS-Package", entry)
            self.assertNotIn("x-zenos-origin", normalized)
            self.assertEqual(1, normalized.count("x-zenos-source"))


if __name__ == "__main__":
    unittest.main()
