# Live Configuration Integration

## Readable Seed Acceptance (2026-09-08)

The builder VM on SSH 2225 passed all four actual-image checks with the injected
five-source integration harness, plus the synthetic priority/value contract.
Only the five owned source/documentation files were overlaid into
`/tmp/restored-image-integration-20260907/zenos-next`; the image lock and temporary
ZenPkgs flake/lock were preserved. All builds used `--max-jobs 1 --cores 2`.

VM command for actual-image acceptance (run from the harness directory):

```sh
nix build path:./zenos-next#checks.x86_64-linux.installer-appearance \
  path:./zenos-next#checks.x86_64-linux.installer-contract \
  path:./zenos-next#checks.x86_64-linux.live-config-contract \
  path:./zenos-next#checks.x86_64-linux.repository-structure \
  --override-input zenpkgs path:./zenpkgs --no-write-lock-file \
  --offline --no-link --json --max-jobs 1 --cores 2
```

Logs in that VM directory: `readable-live-config.log`, `readable-all-checks.log`,
`readable-all-checks.json`, and `readable-fixture.log`. Acceptance checks raw and
lowered desktop edits, unedited package/desktop identity, protected live state,
wrapper priorities, package/function values, binary Nix tools, generated exports,
source retention and no editable backend Nix. This is evaluation/build acceptance,
not activation: no ISO build/restart, switch, reboot, publication or host Nix
evaluation was performed. Older results below are historical, not current blockers.

## Contract

`hosts/installer-iso/live-config.nix` exports `{ seed, sources }` from
`{ inputs, pkgs, lib ? pkgs.lib, hostName ? "zenos-installer",
imageName ? "zenos-installer-iso", desktopSource ? null }`. `seed` contains
`flake.nix`, `README.md`, `base-effective.json`, `hosts/<hostName>/host.zcfg`,
`hosts/<hostName>/system.zcfg`, and, when supplied, `hosts/<hostName>/desktop.zcfg`.
`sources` lists the
image source and all recursively pinned input sources to retain offline.

The seed's `actualImage` input points at the actual image flake source with
its transitive inputs pinned to retained store paths. Its output extends
`actualImage.nixosConfigurations.<imageName>` with store-compiled local ZCFG.
It does not reconstruct an approximate live host from the installed template.
The editable README documents the generated view and persistence boundary.
The seed contains neither a hardware placeholder nor generated host Nix.

Only the original image **source** is embedded as an input path. Never copy
the generated seed into that source, point `actualImage` at the seed, or pin
`inputs.self` recursively through its outputs. `extendModules` preserves the
actual image composition while adding the current compiler output. Whole-root
`sourcesRoot`, generated Nix, and image inputs remain in extra dependencies.

## Readable Editable Seed

The actual image passes its existing `appearance.zcfg` as `desktopSource`.
The image compiler and seed therefore use the same authored desktop source,
not independently maintained desktop defaults. `host.zcfg` imports the desktop
copy: its dock, extensions, animation settings, font and theme package selections
are real rebuild inputs. The copy also exposes selected effective live-user
GNOME interface and GTK font/theme/cursor values from `appearance.nix`, through
`users.zenos.legacy.homeManager`. These are separate backend settings: changing
a GNOME font/theme name does not change the corresponding GTK name automatically.

`system.zcfg` exposes actual timezone, locale, keyboard, fwupd, fstrim, zram and
Nix maintenance defaults as editable legacy assignments. Removing an assignment
returns to inheritance. The seed README lists each file and the exact read-only
store roots for the image, system, appearance, ZenPkgs and Nixpkgs sources.

`base-effective.json` is a pretty-printed, selected original-image snapshot. It
lists package names/store identities, normal-user homes/groups, service flags,
boot/filesystem settings and exposed tuning/interface defaults. It is never
imported, is not updated by rebuild, and deliberately excludes passwords, secret
options, functions and the full module fixed point. It is not a full editable
NixOS dump. Boot, hardware, login and Setup still inherit the frozen actual image;
the existing override restrictions remain effective. No backend Nix is copied
under `/Config/ZenOS`, satisfying D19's only-`flake.nix` rule.

The contract compares unedited desktop/dconf/font values and package identities
with the actual image. A second seed copy edits the actual notification timeout,
GNOME font and fstrim setting, and checks those changes while retaining the
desktop, shell extensions, package identities, media, graphics and login session.
The synthetic fixture leaves `desktopSource = null`; it does not acquire GNOME.

## Main Wiring

The main wiring is in `flake.nix`; activation remains owned by `image.nix`.
Package pins and the image/system backends are not changed by this seed work.

1. Instantiate `liveConfig = import ./hosts/installer-iso/live-config.nix {
   inherit inputs pkgs lib;
   desktopSource = ./hosts/installer-iso/appearance.zcfg; };` outside the installer
   configuration fixed point. Selected base values are read lazily; do not add
   `system.extraDependencies` or activation output to the snapshot (seed recursion).
2. Pass `liveConfig` through the image's special arguments, expose
   `packages.<system>.live-config = liveConfig.seed`, and retain
   `[ liveConfig.seed ] ++ liveConfig.sources` in live `system.extraDependencies`.
3. In **live-only** activation, populate `/etc/ZenOS` from the seed only when
   it is absent or empty, before the session starts. It must be a writable copy
   for the live user, not a store symlink. Preserve every existing nonempty
   configuration, dangling link and installed user source. Do not seed installed
   or OOBE configurations, overwrite files, or follow redirected destinations.
   Keep `/Config -> /etc`; restore the separate `/iso-config` alias in main.
4. After external package review/pinning, use the external rebuild `package.nix`
   rather than the old single-script ZenPkgs install recipe. Include the package
   in the actual image composition so the seed inherits it too. Do not restore
   the old per-user `NIX_PROFILE` override.
5. The installed template also exports `system.build.zenosGeneratedConfig =
   generated`. Preserve its whole-root compiler/import-root and hardware/source
   `extraDependencies` contract when changing the main wiring.
6. Wire `checks.<system>.live-config-contract = import
   ./hosts/installer-iso/live-config-checks.nix { inherit inputs pkgs liveConfig; };`.
   This checks actual identity/session/filesystems/package preservation, local
   ZCFG edits, source retention, and separation from the installed template.

## Later Activation Acceptance

The following requires separate activation authorization and was not run during
the non-activating acceptance below. Run the external rebuild unit tests and build its package before pinning it.
Build the live-config contract check and the wired image. In main's independent
VM on SSH port 2225, verify fresh `/Config/ZenOS`, live-user write access,
`--show-generated`, then a real local ZCFG edit and `zenos-rebuild` switch.
Verify ZenOS release/machine identity, session, Setup command, live filesystems,
tmux, logs and notifications after switching. Exercise an absolute canonical
user link: its edited contents must affect evaluation, the link must survive,
and neither editable tree may contain generated Nix. Repeat activation with
existing config/user data and verify byte-for-byte preservation. Check the
source snapshot and compiler output remain reachable from the built closure.

The generated view is
`nixosConfigurations.<host>.config.system.build.zenosGeneratedConfig`
(also `packages.<system>.generated-host` in the live seed). Use
`zenos-rebuild --show-generated` for the private snapshot handoff, not direct
pure evaluation of an editable flake containing external home links.

No active user VM is reset, reconfigured or switched by these source changes.

## Local Priorities

The live extension applies `mkOverride 90` only to authored local leaves, not
to the whole `zenos` submodule. Ordinary image literals (100) can therefore be
edited without conflicting or dropping unrelated image definitions. Image
`mkForce` restrictions (50) still win. Lists are authored values and replace
the ordinary value of that same setting; they do not append implicitly.
The shared appearance source needs two concrete exceptions: package selector
trees are a single ZSTR custom option and merge local booleans onto base
selectors before applying priority 90; `legacy.fonts.packages` retains the base
font list/order and adds only new font packages, preserving fallback fonts and
the exact unedited font-directory package identity. Removing a font from the
editable list does not remove a base font. Compiler package literals use the
frozen image's package set to avoid the legacy alias's `pkgs` fixed point.
The traversal handles `mkMerge` and `mkIf` at every depth, including the root,
recursing only through their definitions without rewriting wrapper metadata or
evaluating conditions early. Explicit `mkOverride` records (including `mkForce`)
keep their existing priority and content. Functions, callable attribute sets,
derivations, lists and other typed `_type` records remain atomic values.
This is a live composition rule, not a compiler/schema change or a new public option. The generated view
remains the raw compiler output, before the composition applies its priority.
It prioritizes authored definitions and forwarded legacy values, without changing
the compiler/runtime's module action weights.

The overlap fixture uses root and namespace-nested true/false conditions. It
changes the actual image's normal-priority sudo-password boolean, attempts to
defeat forced SSH/system-name restrictions, and verifies
that image stage, filesystems, session, packages and unrelated GNOME settings
are preserved. All these edits are evaluation-only; acceptance must not switch
or activate the edited test configuration.

`live-config-fixture-checks.nix { inherit inputs pkgs; }` runs the same contract
against a synthetic NixOS image using the real pinned ZenPkgs compiler/runtime.
It is an evaluation-only fallback while external package pins are pending, not
evidence that the current ISO evaluates or boots. The fixture includes existing
ordinary/forced values, a list to replace, unrelated ZCFG, live-stage assertions
and a root filesystem that must remain unchanged.

`fixtures/live-config-values.zcfg` additionally tests literal backend property
records: nested `if`/`merge`, an explicit force, an ordered list, a callable
library reference and a package derivation. These records are test inputs, not
a public authored-priority API. This supplemental evaluation supplies `pkgs`
explicitly to isolate the traversal from the pinned alias runtime's package
fixed point; the ordinary overlap contract does not receive that workaround.

## Non-Activating Results

On 2026-09-07, independent SSH VM 2225 ran all 22 external rebuild tests as
user `v`, then all 22 under `sudo`; both runs passed. These exercise actual
descriptor-relative copying and canonical-link rejection in temporary fixture
trees, including redirected parent/file paths, a parent-swap race and FIFOs.
The wrapper tests mock reboot/logout/rebuild commands; no system activation
occurs. Bash syntax also passed in that VM.

The real pinned compiler/runtime built the synthetic image contract offline in
VM 2225, including the overlapping scalar edit, list replacement, forced-value
protection, source retention and image preservation assertions. The derivation
was `/nix/store/gj56kz8hv38r9nf31j7maymb4p06d746-zenos-live-config-contract`.
This verifies the extension/compilation contract, not live boot or switching.

The actual wired composition was attempted on the host and in VM 2225, but
evaluation is blocked by the current ZenPkgs pin
`2306ab6b377b2213b3a77025756e24ea24fe2438`: `lib/installer-boot.nix` is missing.
Main must publish/update the external inputs and rerun the actual contract.
This work did not change those pins or the main wiring. Logs and isolated test
sources are in `/tmp/zenos-rebuild-acceptance-1ep0jG` on VM 2225.

The VM's `/run/current-system` target stayed unchanged throughout acceptance.
No switch, boot, activation, reboot, VM reset or original-user-VM operation was
performed. Existing editable configuration and installed user data were untouched.

## Priority Fix Acceptance

On 2026-09-07, all evaluation and builds for this focused fix ran as `v` in the
ZenOS acceptance VM on SSH 2225. No host Nix evaluation/build, system activation,
switch, reboot, reset, full-image build or package-pin change was performed.
The VM connection was:

```sh
/nix/store/jqvfj1i2q0d1vx3kdz8zrjfd1wz7rhg6-sshpass-1.10/bin/sshpass -p v ssh -p 2225 v@127.0.0.1
```

After verifying the directories, acceptance copied the prior VM snapshot
`/tmp/zenos-rebuild-acceptance-1ep0jG/image` to
`/tmp/zenos-live-priority.OFp9R4/image`, then overlaid only the focused files
using a host-to-VM tar stream. The following commands run **inside that VM**.

```sh
nix build --offline --impure --no-link --print-out-paths --expr '
let flake = builtins.getFlake "path:/tmp/zenos-live-priority.OFp9R4/image";
in import /tmp/zenos-live-priority.OFp9R4/image/hosts/installer-iso/live-config-fixture-checks.nix {
  inputs = flake.inputs // { self = flake; };
  pkgs = import flake.inputs.nixpkgs { system = "x86_64-linux"; };
}'
```

Before the traversal fix, this failed with `The option '_type' does not exist`:
the root's `"merge"` tag had become an override record with priority 90.
After the fix, the final fixtures passed, producing
`/nix/store/0qvb1lvshhklwzha2pdym682gcnrprag-zenos-live-config-contract`.
Logs: `before.log` and `after.log` in `/tmp/zenos-live-priority.OFp9R4`.
The compiler check/compile/parse steps ran for the unedited and edited seeds.

The installed export received a separate smoke check. It uses an identity
`nixosSystem` to inspect the installed module list without evaluating the
blocked system/package composition, but builds and imports the real generated
ZCFG. It verifies that the export is retained beside the whole source root:

```sh
nix build --offline --impure --no-link --print-out-paths --expr '
let
  flake = builtins.getFlake "path:/tmp/zenos-live-priority.OFp9R4/image";
  inputs = flake.inputs // { self = flake; };
  pkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
  lib = pkgs.lib;
  seed = (import /tmp/zenos-live-priority.OFp9R4/image/hosts/installer-iso/live-config.nix { inherit inputs pkgs; }).seed;
  installed = import /tmp/zenos-live-priority.OFp9R4/image/hosts/installer-iso/installed-hosts.nix {
    configRoot = seed;
    inputs = inputs // {
      nixpkgs = inputs.nixpkgs // { lib = lib // { nixosSystem = args: args; }; };
      zenosSource = flake;
      setup-hardware = flake;
    };
  };
  modules = installed.nixosConfigurations.zenos-installer.modules;
  definitions = (lib.last modules) { config = {}; };
  generated = definitions.system.build.zenosGeneratedConfig;
in
assert builtins.elem generated definitions.system.extraDependencies;
assert builtins.elem seed definitions.system.extraDependencies;
assert ((builtins.elemAt modules 2) { inherit pkgs lib; }).zenos.legacy.networking.hostName == "zenos-installer";
pkgs.runCommand "zenos-installed-generated-export-contract" {} "test -s ${generated}; touch $out"
'
```

Passed: `/nix/store/lwwn4hwgi7h92bb31mp7bcr1cwzk85gi-zenos-installed-generated-export-contract`.
Log: `/tmp/zenos-live-priority.OFp9R4/installed-export.log`.
This is not a full installed-system evaluation or hardware acceptance.

```sh
for file in live-config.nix live-config-checks.nix live-config-fixture-checks.nix installed-hosts.nix; do
  nix-instantiate --parse "/tmp/zenos-live-priority.OFp9R4/image/hosts/installer-iso/$file" > /dev/null || exit
  printf "PASS parse %s\n" "$file"
done
readlink /run/current-system
```

All four parses passed. The current-system target remained
`/nix/store/bzxyqxlwkkqhbahs12dyza6v5ldmpqb4-nixos-system-v-26.05.19700101.dirty`.

### Compiler Follow-Up

Two nested DSL `if` statements exposed a separate bug in the published compiler:
it emits `lib.mkIf (true) && (true) { ... }` instead of parenthesizing the combined
condition. Nix parsing succeeds, but evaluation reports `expected a Boolean but
found a function` at `&&`. The failing source and log are retained as
`nested-conditionals.zcfg` and `nested-compiler-error.log` in the acceptance
directory. The passing overlap fixture uses namespace-nested conditions, with
one guard per branch; the supplemental fixture tests genuinely nested backend
`mkIf`/`mkMerge` records independently. The current ZenPkgs worktree now fixes
the combined-guard parentheses. VM acceptance in
`/tmp/zenlang-nested-conditions.5wGg7n` passed 351 canonical and 18 legacy tests,
including actual Nix evaluation of all nested Boolean combinations. The original
reproducer also passes when recompiled. Publication is still pending.

Direct VM reproduction against the retained compiler output (exit 1, also
recorded in `nested-compiler-repro.log`):

```sh
nix eval --offline --impure --expr '
let
  flake = builtins.getFlake "path:/tmp/zenos-live-priority.OFp9R4/image";
  pkgs = import flake.inputs.nixpkgs { system = "x86_64-linux"; };
in builtins.deepSeq
  ((import /nix/store/f02xcqz8yvmlamr1nrfqmicm3jnkq6hc-zenos-live-zenos-installer.nix)
    { inherit pkgs; lib = pkgs.lib; }) true
'
```

The package-value supplemental test also encountered infinite recursion while
resolving the pinned alias runtime's `pkgs` module argument without explicit
`pkgs`. Its isolated passing result does not establish that this upstream
fixed-point issue is repaired. The actual image remains pending the integration
owner's external package wiring and pins, as described above.
