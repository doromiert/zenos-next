import importlib.util
import json
import os
import pathlib
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = pathlib.Path(
    os.environ.get(
        "ZEN_HARDWARE_SCRIPT",
        ROOT / "packages/platform-tools/zen-hardware/zen_hardware.py",
    )
)
DATABASE = pathlib.Path(
    os.environ.get(
        "ZEN_HARDWARE_DATABASE",
        ROOT / "packages/platform-tools/zen-hardware/presets.json",
    )
)
SPEC = importlib.util.spec_from_file_location("zen_hardware", SCRIPT)
ZEN_HARDWARE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ZEN_HARDWARE)


class HardwareMatcherTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.database = ZEN_HARDWARE.load_database(DATABASE)

    def test_matches_specific_framework_preset_before_generic(self):
        facts = {
            "dmi": {
                "system_vendor": "Framework",
                "product_name": "Laptop 13 (AMD Ryzen 7040Series)",
            }
        }
        preset = ZEN_HARDWARE.select_preset(self.database, facts)
        self.assertEqual(preset["id"], "framework-laptop-amd")

    def test_matching_is_case_insensitive_and_supports_globs(self):
        facts = {
            "dmi": {
                "system_vendor": "MICROSOFT CORPORATION",
                "product_name": "surface pro 9",
            }
        }
        preset = ZEN_HARDWARE.select_preset(self.database, facts)
        self.assertEqual(preset["id"], "microsoft-surface")

    def test_unknown_hardware_uses_generic_preset(self):
        preset = ZEN_HARDWARE.select_preset(
            self.database,
            {"dmi": {"system_vendor": "Unknown", "product_name": "Unknown"}},
        )
        self.assertEqual(preset["id"], "generic")

    def test_cli_writes_machine_readable_report(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = pathlib.Path(directory)
            facts_path = directory / "facts.json"
            output_path = directory / "result.json"
            facts_path.write_text(
                json.dumps({"dmi": {"product_name": "Galileo"}}), encoding="utf-8"
            )
            result = ZEN_HARDWARE.main(
                [
                    "--database",
                    str(DATABASE),
                    "match",
                    "--facts",
                    str(facts_path),
                    "--output",
                    str(output_path),
                ]
            )
            report = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertEqual(result, 0)
            self.assertEqual(report["preset"]["id"], "valve-steam-deck-oled")


if __name__ == "__main__":
    unittest.main()
