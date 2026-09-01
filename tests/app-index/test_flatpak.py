from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

import flatpak


class FlatpakBackendTests(unittest.TestCase):
    def test_install_is_user_scoped_and_refreshes_index(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory) / "home"
            target = home / ".private/Apps"
            home.mkdir()
            run = mock.Mock(return_value=subprocess.CompletedProcess([], 0))
            with mock.patch.object(flatpak, "refresh_index") as refresh:
                flatpak.install(
                    "org.example.Editor",
                    home=home,
                    target=target,
                    user="alice",
                    run=run,
                )

            run.assert_called_once_with(
                [
                    "flatpak",
                    "install",
                    "--user",
                    "--noninteractive",
                    "flathub",
                    "org.example.Editor",
                ],
                check=True,
                text=True,
            )
            refresh.assert_called_once_with(home, target, "alice")

    def test_remove_is_user_scoped_and_refreshes_index(self) -> None:
        run = mock.Mock(return_value=subprocess.CompletedProcess([], 0))
        with mock.patch.object(flatpak, "refresh_index") as refresh:
            flatpak.remove("org.example.Editor", run=run)

        self.assertEqual("uninstall", run.call_args.args[0][1])
        self.assertIn("--user", run.call_args.args[0])
        refresh.assert_called_once()

    def test_lists_structured_user_applications(self) -> None:
        run = mock.Mock(
            return_value=subprocess.CompletedProcess(
                [],
                0,
                stdout=(
                    "org.example.Editor\tapp/org.example.Editor/x86_64/stable\tflathub\n"
                ),
            )
        )

        self.assertEqual(
            [
                {
                    "application": "org.example.Editor",
                    "ref": "app/org.example.Editor/x86_64/stable",
                    "origin": "flathub",
                }
            ],
            flatpak.list_installed(run),
        )

    def test_rejects_unsafe_identifiers_before_subprocess(self) -> None:
        run = mock.Mock()
        with self.assertRaisesRegex(ValueError, "invalid Flatpak"):
            flatpak.install("org.example.Editor;rm", run=run)
        run.assert_not_called()
