import importlib.util
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = pathlib.Path(
    os.environ.get(
        "ZEN_XR_SUPERVISOR_SCRIPT",
        ROOT / "packages/platform-tools/xr-supervisor/zen_xr_supervisor.py",
    )
)
SPEC = importlib.util.spec_from_file_location("zen_xr_supervisor", SCRIPT)
XR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(XR)


class XrSupervisorTests(unittest.TestCase):
    def test_preflight_reports_missing_requirements(self):
        checks = XR.preflight(
            {
                "command": [sys.executable, "-c", "pass"],
                "requiredCommands": ["zenos-command-that-does-not-exist"],
                "requiredPaths": ["/zenos/path/that/does/not/exist"],
            }
        )
        self.assertFalse(checks["ok"])
        self.assertFalse(checks["commands"]["zenos-command-that-does-not-exist"])

    def test_run_tracks_only_the_spawned_child(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = pathlib.Path(directory)
            config_path = directory / "config.json"
            state_path = directory / "state.json"
            config_path.write_text(
                json.dumps(
                    {
                        "command": [sys.executable, "-c", "import time; time.sleep(30)"],
                        "requiredCommands": [],
                        "requiredPaths": [],
                        "environment": {},
                    }
                ),
                encoding="utf-8",
            )
            supervisor = subprocess.Popen(
                [
                    sys.executable,
                    str(SCRIPT),
                    "run",
                    "--config",
                    str(config_path),
                    "--state-file",
                    str(state_path),
                ]
            )
            try:
                for _ in range(100):
                    if state_path.exists():
                        break
                    time.sleep(0.02)
                state = json.loads(state_path.read_text(encoding="utf-8"))
                self.assertEqual(state["supervisorPid"], supervisor.pid)
                self.assertNotEqual(state["childPid"], supervisor.pid)
                self.assertEqual(os.getpgid(state["childPid"]), state["childPid"])
                self.assertEqual(XR.read_status(state_path)["status"], "running")
            finally:
                supervisor.terminate()
                supervisor.wait(timeout=5)
            self.assertEqual(XR.read_status(state_path)["status"], "stopped")


if __name__ == "__main__":
    unittest.main()
