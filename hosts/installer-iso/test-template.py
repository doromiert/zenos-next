"""Evaluate the actual installed flake in a private ZenOS VM directory; never install."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


def run(*args):
    result = subprocess.run(args, text=True, capture_output=True, timeout=300)
    if result.returncode:
        diagnostics = "\n".join(
            line for line in result.stderr.splitlines()
            if not line.startswith("trace: ZenPkgs metadata warning:")
        )
        raise RuntimeError(f"{' '.join(args)}\n{diagnostics}")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("template", type=Path)
    parser.add_argument("--setup-source", type=Path)
    args = parser.parse_args()
    template = args.template.resolve()
    template_text = (template / "flake.nix").read_text()
    placeholder = "@ZENOS_SETUP_HARDWARE@"
    assert template_text.count(placeholder) == 1
    assert f'url = "path:{placeholder}";' in template_text
    public = {
        "nixpkgs": ("NixOS", "nixpkgs"),
        "zenpkgs": ("zenos-n", "zenpkgs"),
        "zenosSource": ("doromiert", "zenos-next"),
    }
    revisions = {}
    for name, (owner, repo) in public.items():
        match = re.search(rf'github:{owner}/{repo}/([0-9a-f]{{40}})', template_text)
        assert match, (name, template_text)
        revisions[name] = match.group(1)
    assert "path:/nix/store" not in template_text
    fixtures = Path(__file__).resolve().parent / "fixtures"
    with tempfile.TemporaryDirectory(prefix="zenos-template-test-", dir="/tmp") as work:
        config = Path(work) / "config"
        shutil.copytree(fixtures / "config", config)
        hardware = run("nix", "store", "add-path", "--name", "zenos-setup-hardware",
                       str(fixtures / "hardware")).strip()
        (config / "flake.nix").write_text(template_text.replace(placeholder, hardware))
        detection = json.loads((Path(hardware) / "detection.json").read_text())
        assert detection == {"version": 1, "graphics": [], "laptop": False}
        hardware_metadata = {
            "version": 1,
            "storePath": hardware,
            "sha256": hashlib.sha256((Path(hardware) / "hardware-configuration.nix").read_bytes()).hexdigest(),
        }
        pending_dir = config / "hosts/oobe-test"
        for host in (config / "hosts").iterdir():
            (host / "hardware.json").write_text(json.dumps(hardware_metadata))
        (pending_dir / "graphics.zcfg").write_text("legacy.hardware.graphics.enable = true;\n")
        marker = {
            "version": 3, "status": "pending", "temporaryHost": "oobe-test",
            "artifacts": {
                name: {"file": filename, "sha256": hashlib.sha256((pending_dir / filename).read_bytes()).hexdigest()}
                for name, filename in (("hardware", "hardware.json"), ("graphics", "graphics.zcfg"))
            },
        }
        (pending_dir / "oobe.json").write_text(json.dumps(marker))
        ref = f"path:{config}"
        run("nix", "flake", "lock", ref)
        lock = json.loads((config / "flake.lock").read_text())
        root_inputs = lock["nodes"]["root"]["inputs"]
        hardware_node = root_inputs["setup-hardware"]
        assert lock["nodes"][hardware_node]["flake"] is False
        assert lock["nodes"][hardware_node]["locked"]["path"] == hardware
        for name, (owner, repo) in public.items():
            node = lock["nodes"][root_inputs[name]]
            assert node["locked"]["type"] == "github", node
            assert node["locked"]["owner"] == owner, node
            assert node["locked"]["repo"] == repo, node
            assert node["locked"]["rev"] == revisions[name], node
        run("nix", "flake", "lock", "--offline", ref)

        def evaluate(host, expression):
            return json.loads(run(
                "nix", "eval", "--offline", "--no-write-lock-file", "--json",
                f"{ref}#nixosConfigurations.{host}.config", "--apply", expression,
            ))

        summary = """c: {
          gnome = c.services.desktopManager.gnome.enable;
          gdm = c.services.displayManager.gdm.enable;
          sddm = c.services.displayManager.sddm.enable;
          plasmaLogin = c.services.displayManager.plasma-login-manager.enable;
          greetd = c.services.greetd.enable;
          temporaryUser = c.users.users ? zenos;
          setupService = c.systemd.user.services ? zenos-setup;
          root = c.fileSystems."/".device;
          esp = c.boot.loader.efi.efiSysMountPoint;
        }"""
        pending = evaluate("oobe-test", summary)
        assert pending["greetd"] and pending["temporaryUser"] and pending["setupService"]
        assert not pending["gdm"]
        desktop = evaluate("desktop-test", summary)
        assert desktop["gdm"] and not desktop["greetd"]
        assert not desktop["temporaryUser"] and not desktop["setupService"]
        assert pending["root"] == desktop["root"] == "/dev/disk/by-uuid/fixture-root"
        assert pending["esp"] == desktop["esp"] == "/boot"
        for host in ("headless-test", "kde-test"):
            selected = evaluate(host, summary)
            assert not selected["gnome"] and not selected["gdm"] and not selected["greetd"]
            assert not selected["sddm"]
            assert selected["plasmaLogin"] == (host == "kde-test")
        retained = evaluate("desktop-test", "c: map toString c.system.extraDependencies")
        assert hardware in retained
        assert evaluate("desktop-test", "c: c.home-manager.users.alice.xdg.configHome") == (
            "/Users/alice/.private/Config"
        )
        assert evaluate("desktop-test", "c: c.home-manager.users.alice.xdg.cacheHome") == (
            "/Users/alice/.private/Live"
        )
        desktop_drv = evaluate("desktop-test", "c: c.system.build.toplevel.drvPath")
        assert desktop_drv.startswith("/nix/store/") and desktop_drv.endswith(".drv")

        marker_path = pending_dir / "oobe.json"
        for invalid in (dict(marker, version=2), dict(marker, temporaryHost="other-host"), []):
            marker_path.write_text(json.dumps(invalid))
            try:
                evaluate("oobe-test", summary)
            except RuntimeError as error:
                assert "Invalid Setup marker" in str(error), error
            else:
                raise AssertionError(f"invalid marker accepted: {invalid}")
        marker_path.write_text(json.dumps(dict(marker, status="complete")))
        assert evaluate("oobe-test", summary) == desktop
        marker_path.unlink()
        completed = evaluate("oobe-test", summary)
        assert completed == desktop
        assert list(config.rglob("*.nix")) == [config / "flake.nix"]
        print("PASS: online source lock, private hardware input, offline evaluation, ZCFG check/parse,")
        print("      private hardware retention, XDG, GNOME/KDE/headless choices, version-3 markers")
        print(f"Permanent desktop derivation: {desktop_drv}")

        if args.setup_source:
            # Import only the external generator. Never call installation/lifecycle functions.
            sys.path.insert(0, str(args.setup_source.resolve()))
            from src.builder import build_config_documents
            from src.runner import build_disko_zcfg

            generated_root = Path(work) / "generated"
            generated_host = generated_root / "hosts/generated-test"
            generated_host.mkdir(parents=True)
            payload = {"pages": [
                {"id": "computer_name", "hostname": "generated-test"},
                {"id": "user", "username": "alice", "fullname": "Fixture User"},
                {"id": "desktop", "install_de": False},
            ]}
            documents = build_config_documents(payload, password_hash="$6$fixture$not-a-login")
            for name, text in documents.items():
                target = generated_host / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(text)
            drives = build_disko_zcfg("/dev/vda")
            (generated_host / "drives.zcfg").write_text(drives)
            with (generated_host / "host.zcfg").open("a") as output:
                output.write("import ./drives.zcfg;\n")
            automatic_hardware = Path(work) / "automatic-hardware"
            automatic_hardware.mkdir()
            (automatic_hardware / "hardware-configuration.nix").write_text(
                '{ ... }: { boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" ]; }\n'
            )
            shutil.copyfile(Path(hardware) / "detection.json", automatic_hardware / "detection.json")
            automatic_source = run("nix", "store", "add-path", "--name", "zenos-setup-hardware",
                                   str(automatic_hardware)).strip()
            (generated_host / "hardware.json").write_text(json.dumps({
                "version": 1, "storePath": automatic_source,
                "sha256": hashlib.sha256((automatic_hardware / "hardware-configuration.nix").read_bytes()).hexdigest(),
            }))
            (generated_root / "flake.nix").write_text(template_text.replace(placeholder, automatic_source))
            generated_ref = f"path:{generated_root}"
            run("nix", "flake", "lock", "--offline", generated_ref)
            actual = json.loads(run(
                "nix", "eval", "--offline", "--no-write-lock-file", "--json",
                f"{generated_ref}#nixosConfigurations.generated-test.config", "--apply", """c: {
                  disk = c.disko.devices.disk.main.device;
                  root = c.fileSystems."/".fsType;
                  boot = c.fileSystems."/boot".fsType;
                  host = c.networking.hostName;
                  uid = c.users.users.alice.uid;
                  home = c.users.users.alice.home;
                  gnome = c.services.desktopManager.gnome.enable;
                  drv = c.system.build.toplevel.drvPath;
                }""",
            ))
            assert actual["disk"] == "/dev/vda"
            assert actual["root"] == "ext4" and actual["boot"] == "vfat"
            assert actual["uid"] == 1000 and actual["home"] == "/Users/alice"
            assert actual["host"] == "generated-test" and not actual["gnome"]
            print("PASS: external Setup generator, automatic Disko filesystem mapping, hostname and user choices")


if __name__ == "__main__":
    main()
