# ZenOS Implementation Rules

Before editing this repository, read the relevant design in the sibling
`/home/doromiert/Projects/zenos-n-next` checkout. That repository is the
normative authority for ZenOS architecture and DSL behavior.

- Do not invent behavior when the design is missing or contradictory.
- Resolve the design in `zenos-n-next` first, then implement it here.
- The only non-dotfile root entries are `flake.nix`, `flake.lock`, `readme.md`,
  `AGENTS.md`, `LICENSE`, `docs/`, and `hosts/`.
- The only dot entries are `.git/` and `.gitignore`.
- This repository owns concrete host and image composition plus their
  integration tests and documentation only.
- `hosts/` must not contain reusable modules, package implementations,
  compilers, vendored assets, or general-purpose tooling.
- ZenPkgs owns package declarations and every public ZenOS module.
- ZenPkgs owns the canonical DSL compiler and compiler tests.
- ZenOS has one module/configuration graph; Home Manager is only an internal
  lowering backend for user-scoped actions.
- Package source and assets belong to one external repository per package.
- Runtime tests and integration acceptance must run in a ZenOS VM.
