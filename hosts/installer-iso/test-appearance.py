"""Live appearance acceptance. Run runtime mode only inside the port-2225 VM."""

import argparse
import configparser
import hashlib
import json
import os
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--generated", required=True, type=Path)
    parser.add_argument("--expected", type=Path, default=Path(__file__).parent / "fixtures/appearance-expected.json")
    parser.add_argument("--system", type=Path, default=Path("/run/current-system/sw"))
    parser.add_argument("--home", type=Path)
    parser.add_argument("--assets-only", action="store_true")
    args = parser.parse_args()
    if not args.assets_only:
        assert os.environ.get("ZENOS_ACCEPTANCE_VM") == "1", "Runtime checks require the separate acceptance VM"
        assert subprocess.check_output(["systemd-detect-virt", "--vm"], text=True).strip()
    from gi.repository import Gio, GLib

    expected = json.loads(args.expected.read_text())
    generated = json.loads(args.generated.read_text())
    assert sorted(generated["enabled"]) == sorted(expected["enabled"])
    assert len(generated["enabled"]) == 13
    extensions = args.system / "share/gnome-shell/extensions"
    installed = {path.name for path in extensions.iterdir() if (path / "metadata.json").is_file()}
    required = set(expected["enabled"] + expected["disabled"])
    assert required <= installed, f"Missing extension assets: {required - installed}"
    assert len(required) == 20  # 19 historical extensions plus the session's OOBE extension.
    for uuid in required:
        metadata = json.loads((extensions / uuid / "metadata.json").read_text())
        assert metadata["uuid"] == uuid

    # Validate all emitted extension values against the installed, pinned schemas.
    # GLib parsing also catches incorrect tuple/dictionary encodings and scalar types.
    schemas = {}
    for uuid in required:
        for path in (extensions / uuid / "schemas").glob("*.gschema.xml"):
            for schema in ET.parse(path).getroot().findall("schema"):
                if "path" in schema.attrib:
                    schemas[schema.attrib["path"].strip("/")] = {
                        key.attrib["name"]: key.attrib.get("type", "s") for key in schema.findall("key")
                    }
    for schema, values in generated["encoded"].items():
        for key, text in values.items():
            value = GLib.Variant.parse(None, text, None, None)
            if schema in schemas:
                assert key in schemas[schema], f"Unknown installed extension key: {schema}/{key}"
                assert value.get_type_string() == schemas[schema][key], (schema, key, text, schemas[schema][key])
    for schema, values in expected["settings"].items():
        for key, (kind, wanted) in values.items():
            value = GLib.Variant.parse(None, generated["encoded"][schema][key], None, None)
            assert value.get_type_string() == kind and value.unpack() == wanted, (schema, key, value, wanted)
    preferences = GLib.Variant.parse(None, generated["encoded"]["org/gnome/shell/extensions/gsconnect/preferences"]["window-size"], None, None)
    assert preferences.get_type_string() == "(ii)" and preferences.unpack() == (945, 478)
    stacks = GLib.Variant.parse(None, generated["encoded"]["org/gnome/shell/extensions/dash-stacks"]["stacks"], None, None).unpack()
    assert json.loads(stacks) == [
        {"autoIcon": False, "icon": "folder-download", "name": "Downloads", "path": "~/Downloads"},
        {"autoIcon": False, "icon": "folder-documents", "name": "Projects", "path": "~/Projects"},
        {"autoIcon": False, "icon": "folder-music", "name": "Music", "path": "~/Music"},
    ]
    policies = generated["policies"]
    assert all(policies[key] is True for key in ["DisableAccounts", "DisableAppUpdate", "DisableFirefoxStudies", "DisableTelemetry", "DontCheckDefaultBrowser"])
    assert policies["DisplayBookmarksToolbar"] == "never"
    assert policies["DisplayMenuBar"] == "default-off"
    assert not policies["PasswordManagerEnabled"] and not policies["OfferToSaveLogins"]
    assert policies["SearchEngines"]["Default"] == "DuckDuckGo"
    assert policies["EnableTrackingProtection"] == {"Value": True, "Locked": True, "Cryptomining": True, "Fingerprinting": True}
    assert set(policies["ExtensionSettings"]) == {
        "uBlock0@raymondhill.net", "sponsorBlocker@ajay.app", "{a6c4a591-f1b2-4f03-b3ff-767e5bedf4e7}",
        "keepassxc-browser@keepassxc.org", "{2598f043-d16d-4122-9945-fd253ed12f23}",
    }
    assert all(item["installation_mode"] == "force_installed" and item["default_area"] == "menupanel"
               for item in policies["ExtensionSettings"].values())
    assert generated["preferences"]["browser.startup.homepage"] == "about:blank"
    assert generated["preferences"]["toolkit.legacyUserProfileCustomizations.stylesheets"]
    if args.assets_only:
        assert args.home is not None
        for relative, digest in {
            "scalable/apps/zenos.svg": "db7aca4ddb68e17f552722677c1435e00edb463fc815678e120070d97ce5aa36",
            "symbolic/apps/zenos-symbolic.svg": "1188c36637b301ed92a94262ab43f9f6cdb94ef914e4386010b526f2c39fd343",
        }.items():
            icon = args.system / "share/icons/hicolor" / relative
            assert hashlib.sha256(icon.read_bytes()).hexdigest() == digest, icon
        css = args.system / "share/themes/ClockOverride/gnome-shell/gnome-shell.css"
        text = css.read_text()
        assert 'font-family: "Zero"' in text and "font-size: 12px" in text
        assert 'resource:///org/gnome/shell/theme/default.css' in text
        # The generated Home Manager generation contains all appearance files.
        profile = args.home / "home-files/.private/Config/burn-my-windows/profiles/nix-managed.conf"
        ini = configparser.ConfigParser()
        ini.read(profile)
        effects = ini["burn-my-windows-profile"]
        assert effects.getboolean("glide-enable-effect")
        assert all(key == "glide-enable-effect" or not effects.getboolean(key)
                   for key in effects if key.endswith("-enable-effect"))
        assert effects.getint("glide-animation-time") == 150
        assert effects.getfloat("glide-scale") == 0.74
        files = args.home / "home-files/.private/Config"
        assert (files / "mozilla/firefox/profiles.ini").is_file()
        assert (files / "mozilla/firefox/default/chrome/gnome-theme/userChrome.css").is_file()
        for version in ["gtk-3.0", "gtk-4.0"]:
            gtk = configparser.ConfigParser()
            gtk.read(files / version / "settings.ini")
            settings = gtk["Settings"]
            assert settings.getboolean("gtk-application-prefer-dark-theme")
            assert settings["gtk-decoration-layout"] == ":close"
            assert settings["gtk-cursor-theme-name"] == "GoogleDot-Black"
            assert settings.getint("gtk-cursor-theme-size") == 24
            assert settings["gtk-font-name"] == "Atkinson Hyperlegible 11"
            assert settings["gtk-icon-theme-name"] == "Adwaita-hacks"
            # GTK4 keeps native styling; adw-gtk3 is the GTK3 theme only.
            if version == "gtk-3.0":
                assert settings["gtk-theme-name"] == "adw-gtk3-dark"
        for desktop in expected["favorites"]:
            assert (args.system / "share/applications" / desktop).is_file(), desktop
        print("Appearance assets and effect profile checked; runtime validation still required.")
        return

    def read(key):
        text = subprocess.check_output(["dconf", "read", key], text=True).strip()
        assert text, f"No user/session value for {key}"
        return GLib.Variant.parse(None, text, None, None)

    actual = read("/org/gnome/shell/enabled-extensions").unpack()
    assert len(actual) == 13 and set(actual) == set(expected["enabled"]), actual
    assert not set(expected["disabled"]) & set(actual)
    active = set(subprocess.check_output(["gnome-extensions", "list", "--enabled"], text=True).splitlines())
    assert set(expected["enabled"]) <= active, ("Extensions not active in GNOME Shell", set(expected["enabled"]) - active)
    assert not active & set(expected["disabled"]), active
    assert read("/org/gnome/shell/favorite-apps").unpack() == expected["favorites"]
    for schema, values in expected["settings"].items():
        for key, (kind, value) in values.items():
            actual = read(f"/{schema}/{key}")
            assert actual.get_type_string() == kind, (schema, key, actual)
            assert actual.unpack() == value, (schema, key, actual, value)
    for schema, values in generated["encoded"].items():
        for key, text in values.items():
            # GSConnect replaces these empty defaults with its generated host identity.
            if schema == "org/gnome/shell/extensions/gsconnect" and key in {"id", "name"}:
                continue
            value = GLib.Variant.parse(None, text, None, None)
            if schema in schemas:
                assert key in schemas[schema], f"Unknown installed extension key: {schema}/{key}"
                assert value.get_type_string() == schemas[schema][key], (schema, key, text, schemas[schema][key])
            actual = read(f"/{schema}/{key}")
            assert actual.equal(value), (schema, key, actual, value)
    source = Gio.SettingsSchemaSource.get_default()
    for schema, key in [("org.gnome.desktop.interface", "font-name"), ("org.gnome.shell", "enabled-extensions")]:
        assert source.lookup(schema, True)
        value = Gio.Settings.new(schema).get_value(key)
        assert value.equal(read("/" + schema.replace(".", "/") + "/" + key))
    for family in expected["fontFamilies"]:
        match = subprocess.check_output(["fc-match", "--format=%{family}", family], text=True)
        assert family in match, (family, match)
    assert subprocess.check_output(["fc-match", "--format=%{family}", "sans-serif"], text=True).startswith("Atkinson Hyperlegible")
    assert "AtkynsonMono NF" in subprocess.check_output(["fc-match", "--format=%{family}", "monospace"], text=True)
    print("Live appearance, merged UUIDs, schema types, font resolution and generated settings verified.")


if __name__ == "__main__":
    main()
