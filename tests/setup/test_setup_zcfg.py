import os
from pathlib import Path
import tempfile
import unittest

from zcfg import Loader, compile_nix


SETUP_SOURCE = Path(os.environ["ZENOS_SETUP_SOURCE"])
import sys

sys.path.insert(0, str(SETUP_SOURCE))

from src.builder import process_installer_payload


class SetupZcfgContractTests(unittest.TestCase):
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
        self.assertIn("$pkgs.catalog.firefox", source)
        self.assertIn("$pkgs.legacy.epiphany", source)

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "host.zcfg"
            path.write_text(source, encoding="utf-8")
            resolved = Loader().load(path)

        compiled = compile_nix(resolved)
        self.assertIn("zenos = {", compiled)
        self.assertIn("legacy = {", compiled)
        self.assertIn("pkgs.zenos.catalog.firefox", compiled)
        self.assertIn("pkgs.zenos.legacy.epiphany", compiled)
        self.assertIn('stateVersion = "26.05";', compiled)
        self.assertIn("gnomeProfile = {", compiled)
        self.assertIn("enableExtensions = true;", compiled)
        self.assertIn('directionKeys = "vim";', compiled)
        self.assertIn('actionKeys = "zenos";', compiled)
        self.assertNotIn("must-not-appear", source)


if __name__ == "__main__":
    unittest.main()
