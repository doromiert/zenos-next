import os
from pathlib import Path
import tempfile
import unittest

from zcfg import Loader, compile_nix


SETUP_SOURCE = Path(os.environ["ZENOS_SETUP_SOURCE"])
import sys

sys.path.insert(0, str(SETUP_SOURCE))

from src.builder import build_config_documents, process_installer_payload
from src.runner import build_disko_zcfg, build_graphics_config


class SetupZcfgContractTests(unittest.TestCase):
    def test_split_installed_config_compiles_with_drive_and_graphics_documents(self):
        payload = {
            "oobe": True,
            "pages": [
                {"id": "computer_name", "hostname": "zenos-test"},
                {
                    "id": "user",
                    "fullname": "Test User",
                    "username": "tester",
                    "password": "must-not-appear",
                },
                {
                    "id": "desktop",
                    "install_de": True,
                    "desktop_environment": "gnome",
                },
                {
                    "id": "software",
                    "apps": [
                        {
                            "app": "epiphany",
                            "enabled": False,
                            "includedByDesktop": True,
                        }
                    ],
                },
            ],
        }
        documents = build_config_documents(payload, password_hash="$6$contract$hash")
        documents["drives.zcfg"] = build_disko_zcfg("/dev/vda")
        documents["graphics.zcfg"] = build_graphics_config(
            [{"address": "0000:00:02.0", "bootVga": True, "vendor": 0x8086}]
        )
        imports = "".join(
            f"import ./{name};\n" for name in sorted(set(documents) - {"host.zcfg"})
        )
        documents["host.zcfg"] = imports

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, source in documents.items():
                (root / name).write_text(source, encoding="utf-8")
            resolved = Loader().load(root / "host.zcfg")

        compiled = compile_nix(resolved)
        self.assertIn("pkgs.zenos.legacy.epiphany", compiled)
        self.assertIn("zenos = {", compiled)
        self.assertIn("disks = {", compiled)
        self.assertIn("videoDrivers = [", compiled)
        self.assertIn("zenfs = {", compiled)
        self.assertNotIn("legacy = {", compiled)
        self.assertNotIn("must-not-appear", compiled)

    def test_setup_output_parses_and_compiles_with_real_zen_dsl(self):
        payload = {
            "oobe": False,
            "pages": [
                {"id": "language", "locale": "en_US.UTF-8"},
                {"id": "computer_name", "hostname": "zenos-test"},
                {
                    "id": "user",
                    "fullname": "Test User",
                    "username": "tester",
                    "password": "must-not-appear",
                },
                {
                    "id": "desktop",
                    "install_de": True,
                    "desktop_environment": "gnome",
                },
                {"id": "shortcuts", "directions": "vim", "actions": "zenos"},
                {
                    "id": "software",
                    "apps": [
                        {"app": "firefox", "enabled": True},
                        {
                            "app": "epiphany",
                            "enabled": False,
                            "includedByDesktop": True,
                        },
                    ],
                },
            ],
        }
        source = process_installer_payload(payload, password_hash="$6$contract$hash")
        self.assertNotIn("zenos = {", source)
        self.assertNotIn("$pkgs.zenos", source)
        self.assertIn("legacy = {", source)
        self.assertIn("programs = {", source)
        self.assertIn("firefox = {", source)
        self.assertIn("$pkgs.legacy.epiphany", source)

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "host.zcfg"
            path.write_text(source, encoding="utf-8")
            resolved = Loader().load(path)

        compiled = compile_nix(resolved)
        self.assertIn("zenos = {", compiled)
        self.assertIn("environment = {", compiled)
        self.assertIn("programs = {", compiled)
        self.assertIn("firefox = {", compiled)
        self.assertIn("pkgs.zenos.legacy.epiphany", compiled)
        self.assertIn('stateVersion = "1.0.0";', compiled)
        self.assertIn("gnomeProfile = {", compiled)
        self.assertIn("enableExtensions = true;", compiled)
        self.assertIn('directionKeys = "vim";', compiled)
        self.assertIn('actionKeys = "zenos";', compiled)
        self.assertNotIn("must-not-appear", source)


if __name__ == "__main__":
    unittest.main()
