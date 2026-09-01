import importlib.util
import os
from pathlib import Path
import tempfile
import unittest


REFIND_SCRIPT = os.environ.get("REFIND_SCRIPT")
REFIND_THEME = os.environ.get("REFIND_THEME")
if REFIND_SCRIPT:
    SPEC = importlib.util.spec_from_file_location("zenos_refind", REFIND_SCRIPT)
    REFIND = importlib.util.module_from_spec(SPEC)
    SPEC.loader.exec_module(REFIND)
else:
    REFIND = None


@unittest.skipUnless(REFIND_SCRIPT, "REFIND_SCRIPT is not configured for this check")
class RefindMenuTests(unittest.TestCase):
    @unittest.skipUnless(REFIND_THEME, "REFIND_THEME is not configured for this check")
    def test_theme_excludes_efi_shell(self):
        theme = Path(REFIND_THEME).read_text(encoding="utf-8")
        showtools = [line.strip() for line in theme.splitlines() if line.startswith("showtools")]
        self.assertEqual(showtools, ["showtools shutdown,reboot,firmware"])
        self.assertNotIn("shell", showtools[0].split()[1].split(","))

    def test_generates_menu_from_valid_systemd_boot_entries(self):
        with tempfile.TemporaryDirectory() as root:
            boot = Path(root)
            entries = boot / "loader/entries"
            efi = boot / "EFI/nixos"
            output = boot / "EFI/refind/zenos-entries.conf"
            entries.mkdir(parents=True)
            efi.mkdir(parents=True)
            output.parent.mkdir(parents=True)
            (efi / "kernel.efi").write_bytes(b"kernel")
            (efi / "initrd.efi").write_bytes(b"initrd")
            (entries / "nixos-generation-7.conf").write_text(
                "title ZenOS\n"
                "linux /EFI/nixos/kernel.efi\n"
                "initrd /EFI/nixos/initrd.efi\n"
                "options init=/nix/store/system/init quiet splash\n",
                encoding="utf-8",
            )

            old_values = (REFIND.ESP_MOUNT, REFIND.ENTRY_DIR, REFIND.OUTPUT_FILE)
            REFIND.ESP_MOUNT = str(boot)
            REFIND.ENTRY_DIR = str(entries)
            REFIND.OUTPUT_FILE = str(output)
            try:
                REFIND.generate_config()
            finally:
                REFIND.ESP_MOUNT, REFIND.ENTRY_DIR, REFIND.OUTPUT_FILE = old_values

            generated = output.read_text(encoding="utf-8")
            self.assertIn('menuentry "ZenOS"', generated)
            self.assertIn("loader /EFI/nixos/kernel.efi", generated)
            self.assertIn("initrd /EFI/nixos/initrd.efi", generated)
            self.assertIn('submenuentry "Generation 7"', generated)

    def test_rejects_missing_efi_payload(self):
        with tempfile.TemporaryDirectory() as root:
            entry = Path(root) / "nixos-generation-1.conf"
            entry.write_text(
                "linux /EFI/nixos/missing-kernel.efi\n"
                "initrd /EFI/nixos/missing-initrd.efi\n"
                "options init=/nix/store/system/init\n",
                encoding="utf-8",
            )
            old_mount = REFIND.ESP_MOUNT
            REFIND.ESP_MOUNT = root
            try:
                with self.assertRaisesRegex(RuntimeError, "references missing"):
                    REFIND.parse_systemd_entry(entry)
            finally:
                REFIND.ESP_MOUNT = old_mount


if __name__ == "__main__":
    unittest.main()
