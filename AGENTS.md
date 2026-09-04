# ZenOS Implementation Rules

Before editing this repository, read the relevant design in the sibling
`/home/doromiert/Projects/zenos-n-next` checkout. That repository is the
normative authority for ZenOS architecture and DSL behavior.

- Do not invent behavior when the design is missing or contradictory.
- Resolve the design in `zenos-n-next` first, then implement it here.
- This repository owns ISO composition, integration tests, documentation, and essential build/test tooling only.
- ZenPkgs owns package declarations and system modules.
- Package source and assets belong to one external repository per package.
- Runtime tests and integration acceptance must run in a ZenOS VM.
