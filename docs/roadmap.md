# Composition Roadmap

- Add concrete host and installer image compositions below `hosts/`.
- Consume only published ZenPkgs package and unified module interfaces.
- Keep generated ISOs, VM disks, firmware state, and build results outside the
  repository.
- Keep reusable packages, modules, compilers, and package assets out of this
  repository.
- Run host and image integration acceptance inside a ZenOS VM.
