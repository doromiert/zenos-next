import json
import os
import sys
import tempfile
import unittest
from pathlib import Path


OPS_SOURCE = Path(os.environ.get("ZENOS_OPS_SOURCE", Path(__file__).resolve().parents[2] / "packages/zenos-ops"))
sys.path.insert(0, str(OPS_SOURCE))

from zenos_ops import janitor


class JanitorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.source = self.root / "inbox"
        self.destination = self.root / "sorted"
        self.state = self.root / "state"
        self.source.mkdir()
        self.config_path = self.root / "rules.json"

    def tearDown(self):
        self.temporary.cleanup()

    def config(self, **rule_changes):
        rule = {
            "destination": str(self.destination),
            "extensions": [".pdf"],
            "maxSizeBytes": 20,
            "minSizeBytes": 3,
            "name": "documents",
            "namePattern": "report-*",
            "recursive": False,
            "source": str(self.source),
        }
        rule.update(rule_changes)
        self.config_path.write_text(json.dumps({
            "allowedDestinations": [str(self.destination)],
            "rules": [rule],
            "version": 1,
        }), encoding="utf-8")
        return janitor.load_config(self.config_path)

    def test_scan_matches_extension_name_and_inclusive_size_deterministically(self):
        (self.source / "report-b.PDF").write_bytes(b"123")
        (self.source / "report-a.pdf").write_bytes(b"1234")
        (self.source / "notes.pdf").write_bytes(b"1234")
        (self.source / "report-c.txt").write_bytes(b"1234")
        operations = janitor.scan(self.config())
        self.assertEqual([Path(item["source"]).name for item in operations], ["report-a.pdf", "report-b.PDF"])

    def test_process_never_overwrites_existing_symlink(self):
        source = self.source / "report-a.pdf"
        source.write_bytes(b"source")
        self.destination.mkdir()
        target = self.root / "target"
        target.write_bytes(b"target")
        os.symlink(target, self.destination / source.name)
        result = janitor.process(self.config(maxSizeBytes=100), state_dir=self.state, now=100)
        self.assertEqual(result["results"][0]["result"], "skipped")
        self.assertTrue(source.exists())
        self.assertEqual(target.read_bytes(), b"target")

    def test_process_journals_and_undo_restores_unchanged_file(self):
        source = self.source / "report-a.pdf"
        source.write_bytes(b"content")
        result = janitor.process(self.config(maxSizeBytes=100), state_dir=self.state, now=100)
        moved = self.destination / source.name
        self.assertFalse(source.exists())
        self.assertTrue(moved.exists())
        operation_id = result["results"][0]["operationId"]
        undo = janitor.undo(state_dir=self.state, operation_id=operation_id, now=101)
        self.assertEqual(undo["results"][0]["result"], "undone")
        self.assertEqual(source.read_bytes(), b"content")
        self.assertFalse(moved.exists())

    def test_undo_refuses_changed_destination(self):
        source = self.source / "report-a.pdf"
        source.write_bytes(b"content")
        result = janitor.process(self.config(maxSizeBytes=100), state_dir=self.state, now=100)
        moved = self.destination / source.name
        moved.write_bytes(b"CONTENT")
        operation_id = result["results"][0]["operationId"]
        undo = janitor.undo(state_dir=self.state, operation_id=operation_id, now=101)
        self.assertEqual(undo["results"][0]["reason"], "destination-changed")
        self.assertFalse(source.exists())

    def test_rejects_destination_outside_allowlist(self):
        with self.assertRaises(janitor.ConfigurationError):
            self.config(destination=str(self.root / "elsewhere"))

    def test_process_rechecks_destination_allowlist(self):
        source = self.source / "report-a.pdf"
        source.write_bytes(b"content")
        config = self.config(maxSizeBytes=100)
        config["rules"][0]["destination"] = self.root / "elsewhere"
        result = janitor.process(config, state_dir=self.state, now=100)
        self.assertEqual(result["results"][0]["reason"], "destination-outside-allowlist")
        self.assertTrue(source.exists())

    def test_rejects_relative_paths_and_non_boolean_recursive(self):
        with self.assertRaises(janitor.ConfigurationError):
            self.config(source="relative")
        with self.assertRaises(janitor.ConfigurationError):
            self.config(recursive="false")


if __name__ == "__main__":
    unittest.main()
