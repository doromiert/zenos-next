# ZenOS Command Surface

ZenOS commands are grouped by who should invoke them. Commands not listed as
user-facing are implementation details and may change without compatibility
aliases.

## User-facing system commands

### `zenos-rebuild`

Compiles the active host's `host.zcfg` and switches the NixOS generation. It
resolves configuration roots in this order: `--dir`, the current directory,
the last successful root, `/Config/ZenOS`, then `/etc/nixos`.

```text
zenos-rebuild [--host HOST] [--dir CONFIG_ROOT] [--reboot | --logout]
```

### `zenfsctl`

Inspects ZenFS aliases, verifies roaming-drive markers, and performs guarded
hierarchy renames.

```text
zenfsctl status [--json]
zenfsctl verify-marker PATH --id ID
zenfsctl migrate-hierarchy SOURCE DESTINATION [--dry-run]
```

### `zen-appimage`

Validates and manages type-2 AppImages without executing metadata during
inspection or installation.

```text
zen-appimage install FILE
zen-appimage remove ID
zen-appimage list
```

### `zen-flatpak`

Manages user-scoped Flatpak applications and refreshes the private Apps index.
It never escalates to system scope implicitly.

```text
zen-flatpak install APP_ID [--remote REMOTE]
zen-flatpak remove APP_ID
zen-flatpak list [--scope user|system|all]
zen-flatpak inspect APP_ID
```

### `zen-compat`

Stores per-application compatibility policy by stable app token. Synthetic
homes keep hardcoded dotfiles out of the real home while selectively sharing
standard user directories and the ZenFS private tree.

```text
zen-compat show TOKEN
zen-compat configure TOKEN [--synthetic-home | --no-synthetic-home]
                           [--share DIRECTORY ... | --clear-shares]
zen-compat run TOKEN -- COMMAND [ARGUMENT ...]
```

## Internal system helpers

- `zcfg` validates and compiles restricted `.zcfg` documents. Normal rebuilds
  invoke it through `zenos-rebuild`; users should not compile `host.nix`
  manually.
- `zen-app-index` creates the system and per-user Apps views and token
  registries. `/Apps` contains system installations; `.private/Apps` contains
  only installations owned by that user.
- `zen-app-launch` validates managed app tokens and preserves ordinary desktop
  file launching outside Apps views.
- `zen-app-icons` seeds Nautilus icon metadata before Apps directories are
  displayed.
- `zenos-maintenance` is the guarded maintenance dispatcher used by system
  services.
- `zenos-janitor` performs deterministic cleanup and undo operations for the
  file janitor service.

## Live recovery commands

The installer and recovery environment additionally provides:

- `zen-recovery-detect [OUTPUT]`
- `zen-recovery-diagnostics [OUTPUT_DIRECTORY]`
- `zen-recovery-mount [--read-write] DEVICE [TARGET]`
- `zen-recover-{zenos,nixos,arch,ubuntu,fedora,windows} [--apply] ROOT`

Recovery mounting defaults to read-only with `nosuid,nodev,noexec`. Repair
commands print the proposed action unless `--apply` is explicitly supplied.

## Platform and development tools

- `zen-hardware` lists, inspects, applies, and removes hardware presets.
- `zen-xr-supervisor` controls and reports XR service state.
- `zenos-zerobridge` is the ZeroBridge platform service binary.

These tools are packaged independently and are not guaranteed to be installed
on every ZenOS system.

## Naming policy

- `zenos-*` names system-wide orchestration or long-running services.
- `zen-*` names focused interactive tools.
- `zcfg` and `zenfsctl` retain their established domain-specific names.
- New aliases are added only for shipped compatibility requirements, not as
  alternate spellings.
