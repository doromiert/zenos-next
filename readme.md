# ZenOS Next

`zenos-next` is the minimal composition repository for concrete ZenOS hosts and
images. ZenPkgs owns the module tree, package declarations, canonical DSL
compiler, and compiler tests.

The repository root is intentionally restricted to:

```text
flake.nix
flake.lock
readme.md
AGENTS.md
LICENSE
docs/
hosts/
```

Only `.git/` and `.gitignore` are allowed in addition to that list. The flake's
`repository-structure` check rejects every other tracked root entry; invoke it
through `path:.` to include untracked working-tree entries as well.

Each concrete host lives at `hosts/<name>/host.zcfg` and is exported as
`nixosConfigurations.<name>`. Host and image composition may live below
`hosts/`; reusable modules, package implementations, compilers, vendored
assets, and general-purpose tooling may not.

Run the structural gate with:

```sh
nix build path:.#checks.x86_64-linux.repository-structure
```
