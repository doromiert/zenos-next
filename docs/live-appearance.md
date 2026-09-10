# Live Appearance Handoff

## Ownership And Integration

The behavior reference is `c24244cbf` (September 3), especially
`profiles/installer-iso.nix` and `modules/base.nix`. The old declarations are not
the current public schema. `gnome-profile.nix` is not imported or reproduced.

New files owned by this change:

- `hosts/installer-iso/appearance.zcfg`: concrete live package selectors and current extension options.
- `hosts/installer-iso/appearance.nix`: appearance-only backend settings not currently exposed by public modules.
- `hosts/installer-iso/appearance-hook.nix`: optional compilation/import hook, live stage only.
- `hosts/installer-iso/appearance-checks.nix`: evaluated live configuration and built asset check.
- `hosts/installer-iso/test-appearance.py`: generated-setting/schema checks and live session acceptance.
- `hosts/installer-iso/fixtures/appearance-expected.json`: independent behavior assertions, not a runtime package manifest.

The main integration agent has wired the appearance hook and check, enabled the
core GNOME module, and retained the temporary greetd/GDM override. The core
module now contributes explicitly provided `extensionUuids` via a guarded `u!`
action only when the list is nonempty. Its empty default contributes nothing;
the direct mounted-action test verifies this alongside the 12+OOBE merge.
The live declarations leave this legacy extras option empty.

```nix
installer-appearance = import ./hosts/installer-iso/appearance-checks.nix {
  inherit inputs pkgs installer;
};
```

This work does not edit the main-owned `flake.nix` or `system.nix`. Do not use this hook
for installed/OOBE hosts: the live username, paths and app favorites are concrete.
The 12 extensions coexist with the OOBE *extension in the live session*; this
does not install the live profile into the separate installed OOBE stage.

## Extension Semantics

All existing extension modules now contribute their own package's
`extensionUuid` through an `enable`-guarded `u!` action. The historical set's
dconf settings use that same user backend, not per-module global dconf databases.
Other extension modules retain their pre-existing settings lowering; the scoped
UUID activation fix applies to all of them.

Six optional extensions expose `configure`, defaulting to `enable`, to prepare
settings without activation. Their packages are independently selected by the
live config. App Hider has no historical settings to prepare. Dash Stacks was
missing a public module, so it was added using its existing external package.
No extension UUID list is passed to the GNOME base module.

The mounted compiler gives shared user actions default priority. The live
backend therefore adds OOBE with `lib.mkDefault` too. An ordinary-priority OOBE
assignment would replace all 12 shared UUID contributions. The check compares
the actual merged Home Manager list with all 13 independent expected UUIDs and
asserts the seven disabled extensions are absent.

The old global OOBE database entry in `system.nix` is not used to assemble this
list. It can be removed for the live stage when the main agent migrates that
entry; it must not become a second manually assembled list of historical UUIDs.

Enabled modules: `compiz-alike-magic-lamp-effect`, `compiz-windows-effect`,
`coverflow-alt-tab`, `date-menu-formatter`, `gsconnect`, `hide-cursor`,
`hide-minimized`, `mouse-tail`, `notification-timeout`,
`rounded-window-corners-reborn`, `user-themes`, `window-is-ready-remover`.

Installed but disabled: `alphabetical-app-grid`, `app-hider`, `burn-my-windows`,
`clipboard-indicator`, `hide-top-bar`, `dash-stacks`, `forge`.

ZenPkgs also has new `tests/gnome-extension-actions.nix` and
`tests/test-gnome-extension-actions.py`. The optional check accepts `pkgs`,
`zenDsl`, `nixpkgsSrc`, and `homeManagerSrc`. It compiles the real mounted modules, tests each
module's on/off action, settings-only configuration, and a 12+OOBE merge. Package
identities are mocked there; merging uses the real Home Manager GVariant option
type. The live image check checks real package metadata.
The measured current count is **69 public ZMDL sources / 69 compiled bundle
modules**, including **46 extension modules**. The earlier 70-to-71 estimate was
incorrect. The owner of `tests/dsl-module-parity.nix` must change its stale
`expectedModuleCount = 70` to `69`. Inventory compilation uses the same source
filter as production, excluding test fixtures from the public module tree.

## Expected Settings

Exact declarations are in `appearance.zcfg`; expected UUIDs and key values/types
are in the JSON fixture. The built check exports `generated.json` (all merged
GVariant strings, Firefox policies and preferences), `generated.ini`, and
`expected.json`. This includes defaults emitted by current modules, not only the
historical overrides. It validates extension keys against the installed schemas.

- Fontconfig is explicitly forced on despite the minimal CD default.
- Font packages include Atkinson Hyperlegible, the explicit upstream AtkynsonMono Nerd Font, Inter, Zero Regular and Zero Mono Thin. The main agent added the explicit Nerd Font and Mono Thin selections; the checks now require them.
- GNOME interface/document font: `Atkinson Hyperlegible 11`; monospace: `AtkynsonMono NF 11`.
- Cursor: `GoogleDot-Black`, `int32 24`; icons: `Adwaita-hacks`; GTK: `adw-gtk3-dark`.
- Scheme: `prefer-dark`; accent: `purple`; shell theme: `ClockOverride`, Zero at 12px.
- Clock: Luxon `dd.MM  HH:mm`, centered, `int32 12`, update level `int32 1`.
- Wallpaper: existing Setup package source `data/wallpapers/purple.png`, zoom, both light/dark URIs.
- Rounded corners: `border-width=int32 1`, `settings-version=uint32 7`, typed `a{sv}` with current camelCase fields.
- Notification timeout: `int32 2000`; GSConnect preferences: `(int32 945, int32 478)`.
- Forge: current nested ZMDL options lower gap/version to `uint32 4`/`uint32 37`; center drop `swap` is now accepted.
- Clipboard shortcut: current schema root `toggle-menu=['<Control><Super>v']`, not the old ineffective `/keybindings` path.
- Burn My Windows remains disabled; its managed profile contains only Glide enabled, 150ms, scale 0.74, squish 1.0, tilt -0.7 and shift -0.05.
- Firefox has the five historical force-installed add-ons, locked preferences, privacy policies, blank startup and pinned GNOME theme v143.

Source/assets are consumed from existing packages or the pinned external Firefox
theme repository. No assets or package implementations were vendored here. Boot
visuals and Setup's currently raw extension list are outside this change. Setup's
builder still needs its separately owned migration to module `enable` declarations.

## Acceptance Status

Verification ran in the independent KVM guest at SSH port 2225 as user `v`, from
the private fresh source snapshot `/tmp/zenos-gnome-acceptance.QrmalJtK`.
No host Nix evaluation or runtime tests were run. Port 2223 and all VM lifecycle
operations were left untouched. No commits or pushes were made.

Results:

- 46 extension modules pass individual on/off activation checks.
- All six `configure` cases emit settings without activating their extension.
- Current `appearance.zcfg` passes mounted schema validation of its extension declarations, expected values/types, and the exact 12 historical UUIDs plus OOBE. Synthetic package records use the fixture's real UUID strings; no package build or manual live UUID list is involved.
- Core GNOME's empty extras list contributes no activation entry and does not disturb the 13-UUID merge.
- Rounded-corner `a{sv}` and nonempty focused/unfocused `a{si}` shadow dictionaries evaluate correctly.
- All 18 legacy DSL and 349 canonical `zenlang` Python tests pass, with zero skips. The latter run enables `ZEN_ZPKG_BUILD_TESTS=1`, `ZEN_SCHEMA_NIXPKGS` and `ZEN_SCHEMA_HOME_MANAGER`.

Two defects were fixed during verification: the test harness's freeform type
must live under `config._module` when the module also declares `options`, and
Rounded Window Corners must call Nixpkgs' curried
`mkDictionaryEntry key value`, not Home Manager's list-style constructor.

Guest logs are `actions.log`, `live-actions.log`, `python-legacy.log`, and
`python-canonical.log` beneath the private snapshot directory. Reproduce the live
declaration check in that guest with:

```sh
root=/tmp/zenos-gnome-acceptance.QrmalJtK
ZENOS_ACCEPTANCE_VM=1 PYTHONPATH="$root/zenpkgs/lib/zen-dsl" \
  python3 "$root/zenpkgs/tests/test-gnome-extension-actions.py" \
  "$root/zenpkgs" /nix/store/2ans5qaidz3zysv21ydq25jz1pic7nf3-source \
  "$root/zenos-next/hosts/installer-iso/appearance.zcfg"
```

After main has wired and built the check **inside the separate acceptance VM**,
run the session check as the live `zenos` user with its real session environment:

```sh
ZENOS_ACCEPTANCE_VM=1 python3 hosts/installer-iso/test-appearance.py \
  --generated /path/to/installer-appearance/generated.json
```

Python needs PyGObject; `dconf`, `gnome-extensions`, `fc-match`, and
`systemd-detect-virt` must be available. Runtime acceptance checks the real user
database and GNOME Shell enabled list, not just generated Nix. GSConnect's
auto-generated host ID/name are intentionally not compared to their empty
initial defaults. Full-image package/schema assets, actual font resolution and
the live GNOME session acceptance have not been verified by these synthetic
action tests. Image bootstrap and external pins remain main-owned work.
