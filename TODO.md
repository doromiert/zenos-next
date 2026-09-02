# ZenOS Next Installation Readiness

## Next session priorities

- [x] Fix the installed rEFInd configuration so EFI Shell is actually hidden; verify the generated menu and theme config, not only the source template.
- [x] Hide the `.desktop` suffix in `/Apps` and `~/.private/Apps` while retaining managed-launcher MIME classification and validated token launching.
- [x] Remove or namespace every home dotfile and dot-directory except `.private`, including shell history, SSH/GnuPG state, Mozilla state, Nix profiles, and compatibility links; applications must use XDG relocation or explicit per-app compatibility namespaces.
- [ ] Preconfigure Flatpak and build the Windows application compatibility system plus its configuration UI.
  - User and system Flatpak policy, remotes, install/remove/details integration, and app-index refresh.
  - Isolated Wine prefixes for desktop applications and UMU-Proton for games.
  - Per-app runner, prefix, environment, and compatibility settings in the app details UI.
- [ ] Add hardware detection, support, and optimization templates for testable Lenovo systems.
  - ThinkPad L13 Yoga Gen 1.
  - ThinkPad X13 Yoga Gen 2.
  - Detect exact model identifiers and expose applied template decisions through ZCFG diagnostics.
- [ ] Add proper GNOME extension configuration modules with 1:1 feature parity with the current imperative dconf profile, but organize options around user workflows rather than mirroring raw dconf keys.
- [x] Make `/Config/ZenOS` the canonical default target used and reported by `zenos-rebuild`, never `/etc/ZenOS`, and add `tmux` as an explicit runtime dependency.
- [ ] Build a properly fleshed-out GNOME ZMDL covering desktop packages, defaults, extensions, shortcuts, branding, theming, sessions, and ergonomic typed configuration.

## Resume State

- The current installed VM is managed by virt-manager and accepts live ZCFG updates through `zenos-rebuild`.
- Registry, SSH, PWA adapter, Firefox theming, and flattened config-root changes were validated on that VM.
- Start final installer verification from a fresh qcow2 after the next completed ISO build.
- The source-level typed-empty-array fix is complete; fresh installs from the next ISO do not need that hotfix.
- Do not re-enable Popcorn until its Cachix substitution works for the host daemon.

## Installer correctness

- [x] Hide the Next button while installation or OOBE finalization is running; show it only after success.
- [x] Preserve/import the generated Disko filesystem configuration during OOBE finalization so the final host declares `/`.
- [x] Generate AMD, Intel, NVIDIA, and hybrid graphics configuration from detected PCI hardware.
- [x] Change generated `system.stateVersion` to the correct ZenOS/NixOS release value.
- [x] Port zenos-old's systemd-boot plus rEFInd activation method and exact theme resources.
- [ ] Popcorn D/L selection is implemented but commented out until cache substitution works.

## OOBE parity

- [x] Add a centered Zero Mono lock-screen clock with stacked time and numeric date.
- [x] Port zenos-old's branded GDM logo and interface profile.
- [x] Use standard folder icons by default in Dash Stacks.
- [x] Add independent direction and action keyboard-shortcut profiles to OOBE.
- [x] Apply timezone choices to the active live/OOBE session and hide the OOBE clock until successful.
- [x] Suppress GNOME Shell's non-GDM lock warning without disabling suspend or the first-boot animation.
- [x] Apply ZenOS branding in the temporary OOBE session.
- [x] Install and enable the same live-safe GNOME extensions in OOBE as on the live ISO.
- [x] Ensure the final GNOME system retains the selected ZenOS branding and recommended extension profile.
- [x] Use a black wallpaper throughout temporary OOBE until theme selection.
- [x] Start OOBE on black and apply Destination 2 Purple only after intro completion.
- [x] Package Destination 2 with GNOME Settings wallpaper metadata.
- [x] Replace GStreamer intro playback with GTK4-embedded libmpv.
- [x] Use only `ZenOS-Setup/data/intro.mp4` as the canonical HEVC Main10 intro.
- [x] Runtime center-crop the intro with mpv panscan.
- [x] Keep video diagnostics disabled by default; enable with `ZENOS_OOBE_VIDEO_DEBUG=1`.
- [x] Expose key and blank-password SSH in installer and temporary OOBE environments.

## Setup UI and defaults

- [x] Fix the Recommended Extensions popup on the desktop environment page.
- [x] Keep the recommended extension list synchronized with the live ISO extension set.
- [x] Restore the Applications page logo and package icons with a guaranteed fallback.
- [x] Select each desktop environment's core applications automatically when that desktop is selected.
- [x] Select Firefox as the default browser.
- [x] Select Resources as a default utility.
- [x] Recommended GNOME extensions use individual switches and persist selected IDs.
- [x] Desktop core apps default on and can be disabled through native desktop `excludePackages` options.
- [x] Restore the shortcut chooser to Adw action rows.
- [x] Explicitly center the installation carousel indicator.
- [x] Show Enter Live Mode after installer failure.

## Live environment

- [x] Port zenos-old's Firefox policy/profile behavior and make the live profile writable.
- [x] Use the policy-bearing Firefox wrapper rather than a duplicate raw package.
- [x] Use a minimal Firefox start page, hide a single tab, and place forced extensions in the extension menu.

## Verification

- [x] Add focused unit/evaluation coverage for every generated configuration contract.
- [x] Build a corrected installer ISO only after the source fixes are complete.
- [ ] Replace the disposable qcow2 and run the short ISO -> OOBE -> final flow from scratch.
- [ ] Verify the first-boot animation, OOBE branding, extensions, applications, Firefox, GPU config, filesystems, and rEFInd in the VM.
- [ ] Run the long direct-to-final installation flow from scratch.
- [x] Add rEFInd parser tests against systemd-boot entry files.
- [x] Move rEFInd generation sync to `systemd-boot.extraInstallCommands` after EFI payload creation.
- [x] Hide auto-scanned rEFInd/systemd-boot/kernel entries and remove About/EFI Shell tools from the configured menu.
- [x] Manual hot-patched install verified rEFInd deployment and valid ZenOS menu generation.
- [ ] Rerun `nix flake check -L` after resume; the last complete check passed before the final wallpaper changes.
- [ ] Rebuild `nix build -L .#iso --out-link result-iso` to completion.
- [ ] Verify `intro.mp4` quality, crop, EOF transition, 50% wallpaper timing, and no visible debug panel in the rebuilt ISO.
- [ ] Verify the custom rEFInd ZenOS entry boots directly and no duplicate/tool entries appear.
- [ ] Verify GDM logo/theme and the stacked Zero Mono lock-screen clock on the final system.

## Post-install platform backlog

- [x] Register ZenPkgs system-wide and expose nested legacy package installables such as `zenpkgs#legacy.nvim`.
- [x] Install `zcfg` and `zenos-rebuild` by default and compile ZCFG automatically during rebuilds.
- [x] Keep editable configuration under `/Config/ZenOS` without the obsolete nested `Flake` directory.
- [x] Add typed `system.services.ssh` ZCFG settings and validate the live SSH service.
- [x] Add the first-class per-user PWA adapter and Home Manager integration to ZenPkgs.
- [x] Delete Forge's stray `~/undefined.bak` whenever it appears; fix the packaged source and retain cleanup as a defensive fallback.
- [ ] Remove visible `.cache`, `.config`, and `.local` compatibility paths in strict ZenFS mode.
  - Native applications use relocated XDG paths under `.private`.
  - Legacy applications declare required dot-paths and run in Bubblewrap mount namespaces that bind those paths to `.private`.
  - Monitor unmanaged writes for diagnostics; fanotify/seccomp cannot transparently redirect path resolution.
- [x] Pre-generate `/Apps` and `~/.private/Apps` icons before Nautilus displays a directory; keep the Nautilus InfoProvider only as fallback.
- [ ] Replace directory-sensitive `.desktop` launching with validated ZenOS app tokens and an app broker; normal `.desktop` files outside Apps directories must retain normal behavior.
  - [x] Add stable app tokens, per-view registries, strict managed-entry validation, Nautilus token launches, and ordinary desktop-file fallback.
  - [ ] Move token operations behind a user D-Bus app broker and add inspect/install/remove/settings methods.
- [ ] Build a proper app details window for manifest information, desktop-entry editing, compatibility settings, and app actions.
- [ ] Add first-class Flatpak support to the app index, details UI, and install/remove flows.
  - [x] Add validated user-scoped `zen-flatpak` install/remove/list operations with automatic private-index refresh.
  - [ ] Add details UI actions and explicit policy for system or declaratively managed Flatpaks.
- [ ] Complete AppImage support in the app index, details UI, and install/remove flows.
  - [x] Validate, inspect, install, list, remove, and index type-2 AppImages without executing untrusted metadata.
  - [ ] Add details UI actions and compatibility overrides for installed AppImages.
- [ ] Add Windows application support through a ZenOS compatibility broker.
  - Use isolated Wine prefixes for general desktop applications.
  - Use UMU-Proton for games; do not treat raw Proton as a general-purpose default runner.
  - Let users choose the runner/compatibility layer per app through the app details window.
- [x] Ensure `/mnt` exists before `/Mount` is created and validate the default mount hierarchy on fresh installs.
- [x] Make `/Users` the canonical real home root and reverse compatibility to `/home -> /Users`; provide stricter per-app namespace compatibility later.
- [x] Enable Firefox customization by default for new installs and in the Setup software defaults.
- [x] Document and rationalize the currently shipped custom command set.
- [ ] Make every program option enable its package automatically; add program modules for all applications selectable in Setup.
- [ ] Add proper configurable modules for every shipped GNOME extension and expose their settings through ZCFG.
- [x] Map `zenos.system.disks` declaratively to Disko.
- [x] Hide generated `host.nix` from the user-facing config view while retaining it as the compiler bridge.
- [x] Remove leftover `install-plan.json` after installation completes while retaining it during transactional install and OOBE work.
- [x] Use ZenOS state versions in ZCFG: `1.0.0` maps internally to NixOS `26.05`.
- [ ] Port remaining useful modules from zenos-old.
  - Optional full VR support module.
  - ROM MIME type support.
  - Doromiert's shell configuration 1:1 where practical, optimized for startup, including zoxide/Zsh and Vim-inspired commands such as `:q`.
  - Desktop-agnostic keyboard shortcut schema in `shortcuts.zcfg`, e.g. `zenos.system.shortcuts.windowing.close = [ "meta" "q" ];`.
- [x] Persist the installer ISO Git revision in the installed system version string: `ZenOS 1.0.0Nb (<hash>)`.
