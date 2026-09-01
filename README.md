# ZenOS Next

Bootable NixOS-based ZenOS development system. The repository currently ships
an OOBE VM, a graphical installer ISO, the restricted `zcfg` compiler, and
disabled-by-default MVP modules for the remaining system designs.

The system and ZenPkgs are pinned to the NixOS 26.05 channel. ZenPkgs wraps
upstream packages without copying their build recipes, attaches ZenOS metadata,
and exposes curated paths such as `pkgs.zenos.catalog.firefox`.

The supported and internal command surfaces are documented in
[`docs/commands.md`](docs/commands.md).

## Build outputs

```sh
# Interactive OOBE VM
nix build .#vm --max-jobs 1 --cores 20
nix run .#vm

# Bootable graphical installer ISO
nix build .#iso --max-jobs 1 --cores 20
ls result/iso/zenos-installer.iso

# DSL and service tools
nix build .#zen-dsl .#zenfsctl .#zenos-ops
```

The ISO automatically starts GNOME as the temporary `zenos` account and
launches `zenos-setup` in installer mode. The VM launches the same application
with `--oobe` and enables `zenos-oobe-mode@neg-zero.com`. Both temporary users
can obtain root with passwordless `sudo`; direct root login remains locked.

The live ISO also includes Firefox, GNOME Console, Kitty, Disks, GParted,
TestDisk/PhotoRec, storage/filesystem utilities, hardware diagnostics, network
tools, and conservative recovery helpers:

```sh
zen-recovery-detect
zen-recovery-mount /dev/DEVICE
zen-recovery-diagnostics
zen-recover-zenos MOUNTED_ROOT
zen-recover-nixos MOUNTED_ROOT
zen-recover-arch MOUNTED_ROOT
zen-recover-ubuntu MOUNTED_ROOT
zen-recover-fedora MOUNTED_ROOT
zen-recover-windows MOUNTED_ROOT
```

Recovery mounts are read-only by default. Chroot entry requires `--apply`;
Windows recovery remains instruction-only and directs filesystem/boot repair to
WinRE rather than treating `ntfsfix` as a replacement for `chkdsk`.

## Configuration flow

ZenOS Setup now builds configuration as a structured value, serializes it to a
restricted `.zcfg`, and stores disk/source choices separately in
`install-plan.json`. Passwords are converted to SHA-512 modular crypt hashes
through OpenSSL and plaintext is never written to the generated config.
Generated package selections use `pkgs.zenos.catalog.*`; curated system options
use the `zenos.*` option interface and map to legacy NixOS options centrally.

Compile or validate a generated configuration with:

```sh
nix run .#zen-dsl -- check hosts/demo/host.zcfg
nix run .#zen-dsl -- compile hosts/demo/host.zcfg -o hosts/demo/host.nix
```

The supported MVP grammar covers assignments, nested attribute sets, lists,
literals, `$pkgs` references, and relative imports. It deliberately rejects raw
Nix expressions and the unfinished zmdl/zpkg action language.

## Modules

The flake exports these NixOS modules:

- `base`, `oobe`
- `zenfs`
- `maintenance`, `janitor`
- `platform`
- `platform-hardware`, `platform-connection-suite`
- `platform-refind`, `platform-xr-supervisor`

ZenFS, maintenance, Janitor, connection, hardware matching, rEFInd, and XR are
imported into development systems but remain disabled by default. Risky or
incomplete protocol behavior requires explicit acknowledgement when enabled.

## Verification

```sh
nix flake check --max-jobs 1 --cores 20
```

Checks cover the DSL, Setup builder and dry-run safety, Setup-to-DSL contract,
ZenFS CLI and module evaluation, maintenance/Janitor, platform tools, the OOBE
system, and installer system. The ISO is built separately through `.#iso`.

## Current safety boundary

`ZenOS-Setup/src/runner.py` still has `DRY_RUN = True`. Configuration generation
and the installer UI are real, but disk formatting, mounting, `nixos-install`,
`nixos-rebuild`, and reboot remain simulated until a disposable destructive VM
test covers the complete installation transaction. Online configs with Disko
are rejected until AST-aware merging exists.

The development flake consumes local path inputs for ZenOS Setup, the OOBE
extension, ZenPkgs, Plymouth assets, and ZeroBridge. Replace them with pinned
repository inputs before release builds.
