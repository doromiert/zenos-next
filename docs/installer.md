# Installer ISO

The image and its installed-system template live in `hosts/installer-iso`.
They import `zenpkgs.nixosModules.default` and use its canonical `zen-dsl`.
GNOME, login, boot, users, and the temporary session use existing typed NixOS
options. No public schema or package implementation is added here.

## Setup handoff: ready contract

- This follows `ZenOS-Setup/TEMPLATE-CONTRACT.md`. The runner reads
  `/iso-config-template/flake.nix` before disk work and copies it to
  `/mnt/etc/ZenOS/flake.nix`. It generates `hosts/<host>/host.zcfg` and its ZCFG
  imports, not `host.nix`. The template compiles them into the Nix store.
- The template contains `inputs.setup-hardware`, with
  `url = "path:@ZENOS_SETUP_HARDWARE@"` and `flake = false`. The placeholder
  occurs exactly once. Setup substitutes an immutable store directory containing
  `hardware-configuration.nix` and `detection.json`, produced privately with
  `nix store add-path --name zenos-setup-hardware`. The editable `hardware.json`
  records version 1, `storePath`, and the hardware Nix SHA-256. Keep this input
  when OOBE renames the host. The template checks the metadata checksum against
  the imported hardware and retains both the input and the original named path:
  Nix may rename the input to `-source`, but Setup still uses `storePath` in OOBE.
  No hardware Nix belongs in `/Config/ZenOS`.
- Hardware includes filesystems for manual partition selection. For automatic
  partitioning, `drives.zcfg` supplies the disk layout and hardware detection
  must use `--no-filesystems`. Root and a FAT ESP mounted at `/boot` are required.
  The installed system uses removable-path UEFI GRUB, without NVRAM writes.
- Only a parsed version-3 `hosts/<host>/oobe.json` with `status = "pending"`
  and matching `temporaryHost` enables temporary GNOME, greetd autologin as
  `zenos`, and `zenos-setup --oobe`. Invalid versions and mismatched pending
  hosts fail evaluation. Absent or complete markers do not enable OOBE.
  Setup owns artifact checksum validation and rollback. Its pending marker
  records `graphics.zcfg`, `hardware.json`, and optional `drives.zcfg` hashes.
  Publish the final host without a pending marker before evaluating its boot
  generation; remove the old temporary host only after a successful rebuild.
- The live session is `zenos-oobe`, but launches `zenos-setup` without `--oobe`.
  Both temporary stages set `ZENOS_SETUP_DRY_RUN=0`. Starting the app must not
  install anything: partitioning and installation wait for the user's clicks.
- Setup comes only from `pkgs.zenos.system.zenos-setup`; the GNOME mode comes
  only from `pkgs.zenos.system.zenos-oobe-mode`. Setup must export
  `meta.mainProgram = "zenos-setup"`. The mode package must install
  `share/gnome-shell/modes/zenos-oobe.json` and extension UUID
  `zenos-oobe-mode@neg-zero.com`. The image supplies GnomeDesktop, GWeather,
  and NetworkManager typelib search paths as well as the GNOME session wrapper.
- The installed composition does not select GNOME, force its public enable
  option off, or add GNOME applications against the user's selections. GNOME,
  other desktops, and no-desktop choices come from Setup's generated ZCFG.
  Permanent users use `users.<name>.legacy`, UID 1000 for Setup's first user,
  and `/Users/<name>` homes. The hostname comes from
  `legacy.networking.hostName`. Packages use full-path boolean selectors.
- Automatic drives lower from `system.disks.disk.main` to `disko.devices.disk.main`.
  Its GPT layout has a 1G FAT ESP at
  `/boot` with `umask=0077` and an ext4 root using the remaining space.
  Manual preflight supplies `legacy.fileSystems` without mounting devices.
  The template checks ZCFG, compiles it in the store, and parses generated Nix.
- `/Config` is a symlink to `/etc`; XDG config/data/cache/state point to
  `$HOME/.private/{Config,Packages,Live,State}`. The composition creates those
  directories for normal users. It does not implement the rest of ZenFS.
- All input sources are pinned to retained Nix store paths, including transitive
  ZenPkgs inputs and the composition source. The runner locks offline after
  replacing the hardware input. Installed generations retain those sources and
  hardware. This retains source closures, not every unbuilt package; package
  builds can still require network access.

## Canonical user sources

Setup writes `hosts/<host>/users/<user>/main.zcfg`, then publishes the canonical
file at `/Users/<user>/.private/Config/main.zcfg`. The host entry becomes a
symlink. Existing user sources are not overwritten.

Before passing configuration to pure Nix, Setup copies those linked files into
a private snapshot. The installed closure retains both that snapshot and its
generated host Nix, as well as hardware and input sources. The editable tree
keeps its links. Later rebuild tooling must use the same snapshot step rather
than directly evaluating home symlinks from the flake.

## Outputs

```text
packages.x86_64-linux.iso
nixosConfigurations.zenos-installer-iso.config.system.build.isoImage
packages.x86_64-linux.config-template
checks.x86_64-linux.installer-contract
checks.x86_64-linux.repository-structure
```

Build and evaluate only in the ZenOS VM. Use a private snapshot below `/tmp`
and `path:` flake references so untracked composition files are included.
The final ZenPkgs commit and lock update belong to the integration owner after
the two packages are published. Until then, use `--override-input zenpkgs
path:/tmp/<private-zenpkgs-snapshot>`; do not publish that temporary override.

After building `packages.x86_64-linux.config-template` in the VM, run:

```sh
python3 hosts/installer-iso/test-template.py /nix/store/<template-output>
python3 hosts/installer-iso/test-template.py /nix/store/<template-output> --setup-source /tmp/<setup-snapshot>
```

This only evaluates private fixtures. It checks offline store-only inputs,
private hardware metadata, checked/parsed ZCFG, XDG defaults, desktop choices,
and version-3 marker transitions without installing or activating a system.
The optional source argument exercises the external Setup generator's actual
automatic-disk and account output. No Setup package is mocked by these tests.
`installer-contract` also checks package
contents and the live/OOBE commands, and therefore needs the two public packages.

The manual acceptance run is live app -> short install -> reboot -> OOBE ->
permanent desktop. Check the session, app log, `/boot` loader, private hardware
input, and absence of generated Nix under `/Config/ZenOS` at each installed
stage. This task does not boot the ISO or perform those disk operations.
