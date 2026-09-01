# zcfg MVP

`zcfg` is a dependency-free Python compiler for a deliberately restricted,
Nix-like ZenOS configuration language. It validates a source tree before
emitting a deterministic Nix function.

## Commands

From this directory:

```sh
python3 zcfg.py check system.zcfg
python3 zcfg.py compile system.zcfg -o system.nix
python3 zcfg.py ast system.zcfg
```

Every command accepts `--diagnostic-format human` (the default) or
`--diagnostic-format json`. `check` emits no human output on success; in JSON
mode it emits an empty diagnostics array. Diagnostics use exit status 1, while
argument errors use argparse's exit status 2.

## Grammar

```text
document    := import* assignment* EOF
import      := "import" RELATIVE_PATH ";"
assignment  := attr_path "=" value ";"
attr_path   := IDENT ("." IDENT)*
value       := STRING | INTEGER | "true" | "false" | "null"
             | pkgs_ref | list | attr_set
pkgs_ref    := "$pkgs" "." attr_path
list        := "[" value* "]"
attr_set    := "{" assignment* "}"
```

Identifiers begin with an ASCII letter or underscore and then contain letters,
digits, `_`, `-`, or `'`. Strings are double quoted and support `\"`, `\\`,
`\/`, `\n`, `\r`, `\t`, and four-digit `\u` escapes. Integers are signed
64-bit decimal values. `#` starts a line comment.

Imports are bare paths beginning with `./` or `../` and ending in `.zcfg`:

```zcfg
import ./hardware/base.zcfg;

system.network.hostName = "zenos";
system.software.packages = [
  $pkgs.catalog.git
  $pkgs.catalog.gnome-console
];

# Explicit access to an underlying NixOS option.
legacy.boot.kernelParams = [ "quiet" ];
```

Imports are resolved relative to the importing file. Imported documents merge
in declaration order, and local assignments merge last. Attribute sets merge
recursively; lists and scalar values are replaced by the later value. A local
leaf cannot be assigned twice, including through dotted and nested forms.
Import cycles and unreadable files are errors.

Only `$pkgs` attribute references are accepted. Package paths are resolved
inside the curated ZenPkgs namespace; `$pkgs.catalog.firefox`, for example,
compiles to `pkgs.zenos.catalog.firefox`. Arbitrary identifiers, function calls,
interpolation, arithmetic, conditionals, `with`, `let`, quoted attribute names,
URL/absolute imports, floats, and comma-separated lists are unsupported and
rejected.

User configuration paths omit the internal `zenos` root. The compiler adds it
to the generated Nix function, so `system.network.hostName` becomes
`zenos.system.network.hostName`. The user-facing `legacy` root is the explicit
passthrough for underlying NixOS options and becomes `zenos.legacy` internally.

The generated file always has this interface:

```nix
{ pkgs }:
{
  zenos = {
    # deterministically sorted configuration
  };
}
```

Run the test suite with:

```sh
python3 -m unittest discover -s tests -v
```
