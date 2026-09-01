import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
import os
from unittest import mock


OPS_SOURCE = Path(os.environ.get("ZENOS_OPS_SOURCE", Path(__file__).resolve().parents[2] / "packages/zenos-ops"))
sys.path.insert(0, str(OPS_SOURCE))

from zenos_ops import maintenance


class MaintenanceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        proc = self.root / "proc"
        (proc / "pressure").mkdir(parents=True)
        (proc / "meminfo").write_text("MemTotal: 1000 kB\nMemAvailable: 500 kB\n", encoding="ascii")
        (proc / "pressure/cpu").write_text("some avg10=1.00 avg60=0.00 avg300=0.00 total=1\n", encoding="ascii")
        (proc / "pressure/memory").write_text("some avg10=2.00 avg60=0.00 avg300=0.00 total=1\n", encoding="ascii")
        self.proc = proc
        self.sys = self.root / "sys"
        (self.sys / "class/power_supply/AC").mkdir(parents=True)
        (self.sys / "class/power_supply/AC/type").write_text("Mains\n", encoding="ascii")
        (self.sys / "class/power_supply/AC/online").write_text("1\n", encoding="ascii")
        self.config = {
            "guard": {
                "maxCpuPsiSomeAvg10": 10,
                "maxLoadPerCpu": 1,
                "maxMemoryPsiSomeAvg10": 10,
                "minMemoryAvailablePercent": 20,
                "requireAC": True,
            },
            "stateDir": str(self.root / "state"),
            "tasks": {
                "nix-gc": {
                    "command": ["true"],
                    "intervalSeconds": 100,
                    "timeoutSeconds": 10,
                }
            },
        }

    def tearDown(self):
        self.temporary.cleanup()

    @mock.patch("zenos_ops.maintenance.os.cpu_count", return_value=2)
    @mock.patch("zenos_ops.maintenance.os.getloadavg", return_value=(1.0, 0.0, 0.0))
    def test_guard_reports_all_inputs(self, _load, _cpus):
        report = maintenance.guard_report(self.config, proc_root=self.proc, sys_root=self.sys)
        self.assertTrue(report["passed"])
        self.assertEqual([item["name"] for item in report["checks"]], [
            "load-per-cpu",
            "memory-available-percent",
            "cpu-psi-some-avg10",
            "memory-psi-some-avg10",
            "ac-power",
        ])

    @mock.patch("zenos_ops.maintenance.os.cpu_count", return_value=1)
    @mock.patch("zenos_ops.maintenance.os.getloadavg", return_value=(4.0, 0.0, 0.0))
    def test_tick_defers_without_running_when_guard_blocks(self, _load, _cpus):
        runner = mock.Mock()
        result, return_code = maintenance.run_tick(
            self.config,
            now=1000,
            runner=runner,
            proc_root=self.proc,
            sys_root=self.sys,
        )
        self.assertEqual(return_code, 75)
        self.assertEqual(result["result"], "deferred")
        runner.assert_not_called()

    @mock.patch("zenos_ops.maintenance.os.cpu_count", return_value=2)
    @mock.patch("zenos_ops.maintenance.os.getloadavg", return_value=(1.0, 0.0, 0.0))
    def test_request_runs_once_and_is_consumed(self, _load, _cpus):
        maintenance.request_task(self.config, "nix-gc", now=1000)
        runner = mock.Mock(return_value=subprocess.CompletedProcess(["true"], 0, "ok", ""))
        result, return_code = maintenance.run_tick(
            self.config,
            now=1000,
            runner=runner,
            proc_root=self.proc,
            sys_root=self.sys,
        )
        self.assertEqual(return_code, 0)
        self.assertEqual(result["tasks"][0]["result"], "success")
        self.assertEqual(maintenance.pending_requests(self.config), [])
        state = json.loads((Path(self.config["stateDir"]) / "state.json").read_text())
        self.assertEqual(state["tasks"]["nix-gc"]["lastSuccess"], 1000)


if __name__ == "__main__":
    unittest.main()
