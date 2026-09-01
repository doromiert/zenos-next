# ZenOS Next Installation Readiness

## Resume State

- The previous VM disk was raced by a new installer run during rescue and should be discarded.
- Start final verification from a fresh qcow2 after the next completed ISO build.
- The source-level typed-empty-array fix is complete; fresh installs from the next finished ISO do not need that hotfix.
- The most recent ISO build was interrupted during SquashFS creation and must be rerun before another clean install.
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
