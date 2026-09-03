{
  lib,
  nix,
  python3,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "zen-dsl";
  version = "0.1.0";
  src = ../tools/zen-dsl;

  dontConfigure = true;
  dontBuild = true;
  nativeCheckInputs = [
    nix
    python3
  ];
  doCheck = true;
  doInstallCheck = true;

  checkPhase = ''
    runHook preCheck
    test -f zenlang/compiler.py
    test -f zenlang/emitter.py
    test -f tests/zenlang/test_compiler.py
    python3 -m py_compile zenlang/compiler.py zenlang/emitter.py tests/zenlang/test_compiler.py
    PYTHONPATH="$PWD" python3 -m unittest discover -s tests -v
    PYTHONPATH="$PWD" python3 -m unittest discover -s tests/zenlang -p 'test_*.py' -v
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin" "$out/lib/zen-dsl"
    cp -r zcfg zenlang "$out/lib/zen-dsl/"
    cat > "$out/bin/zcfg" <<'EOF'
    #!${stdenvNoCC.shell}
    export PYTHONPATH="@out@/lib/zen-dsl''${PYTHONPATH:+:$PYTHONPATH}"
    exec ${python3}/bin/python3 -m zenlang "$@"
    EOF
    substituteInPlace "$out/bin/zcfg" --replace-fail @out@ "$out"
    chmod +x "$out/bin/zcfg"
    cat > "$out/bin/zcfg-legacy" <<'EOF'
    #!${stdenvNoCC.shell}
    export PYTHONPATH="@out@/lib/zen-dsl''${PYTHONPATH:+:$PYTHONPATH}"
    exec ${python3}/bin/python3 -m zcfg "$@"
    EOF
    substituteInPlace "$out/bin/zcfg-legacy" --replace-fail @out@ "$out"
    chmod +x "$out/bin/zcfg-legacy"
    cat > "$out/bin/zen-dsl" <<'EOF'
    #!${stdenvNoCC.shell}
    export PYTHONPATH="@out@/lib/zen-dsl''${PYTHONPATH:+:$PYTHONPATH}"
    exec ${python3}/bin/python3 -m zenlang "$@"
    EOF
    substituteInPlace "$out/bin/zen-dsl" --replace-fail @out@ "$out"
    chmod +x "$out/bin/zen-dsl"
    runHook postInstall
  '';

  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/zcfg" --help >/dev/null
    "$out/bin/zcfg-legacy" --help >/dev/null
    "$out/bin/zen-dsl" --help >/dev/null
    test -f "$out/lib/zen-dsl/zenlang/compiler.py"
    test -f "$out/lib/zen-dsl/zenlang/emitter.py"
    "$out/bin/zen-dsl" check tests/zenlang/fixtures/bat.zpkg --diagnostic-format json >/dev/null
    cat > "$TMPDIR/compile.zcfg" <<'EOF'
    system.enabled = true;
    EOF
    "$out/bin/zen-dsl" compile "$TMPDIR/compile.zcfg" -o "$TMPDIR/compile.nix"
    grep -q 'zenos = {' "$TMPDIR/compile.nix"
    "$out/bin/zen-dsl" compile tests/zenlang/fixtures/gnome.zmdl --target system -o "$TMPDIR/module.nix"
    "$out/bin/zen-dsl" compile tests/zenlang/fixtures/bat.zpkg --mode interface -o "$TMPDIR/package.nix"
    "$out/bin/zen-dsl" compile tests/zenlang/fixtures/structure.zstr -o "$TMPDIR/structure.nix"
    "$out/bin/zen-dsl" check-tree --root tests/zenlang/fixtures
    "$out/bin/zen-dsl" compile-tree --root tests/zenlang/fixtures --output "$TMPDIR/bundle.json" --mode interface
    python3 - "$TMPDIR/bundle.json" <<'PY'
    import json
    import sys

    with open(sys.argv[1], encoding="utf-8") as source:
        bundle = json.load(source)
    assert bundle["bundleVersion"] == "zenlang.bundle/1"
    assert {entry["kind"] for entry in bundle["sources"]} == {"zcfg", "zmdl", "zpkg", "zstr"}
    PY
    runHook postInstallCheck
  '';

  meta = {
    description = "Canonical parser and compiler frontend for the four ZenOS DSL formats";
    license = lib.licenses.napalm;
    mainProgram = "zcfg";
    platforms = lib.platforms.all;
  };
}
