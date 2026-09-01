{
  lib,
  python3,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "zen-dsl";
  version = "0.1.0";
  src = ../tools/zen-dsl;

  dontConfigure = true;
  dontBuild = true;
  nativeCheckInputs = [ python3 ];
  doCheck = true;

  checkPhase = ''
    runHook preCheck
    PYTHONPATH="$PWD" python3 -m unittest discover -s tests -v
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin" "$out/lib/zen-dsl"
    cp -r zcfg "$out/lib/zen-dsl/"
    cat > "$out/bin/zcfg" <<'EOF'
    #!${stdenvNoCC.shell}
    export PYTHONPATH="@out@/lib/zen-dsl''${PYTHONPATH:+:$PYTHONPATH}"
    exec ${python3}/bin/python3 -m zcfg "$@"
    EOF
    substituteInPlace "$out/bin/zcfg" --replace-fail @out@ "$out"
    chmod +x "$out/bin/zcfg"
    runHook postInstall
  '';

  meta = {
    description = "Restricted ZenOS configuration DSL compiler";
    license = lib.licenses.napalm;
    mainProgram = "zcfg";
    platforms = lib.platforms.all;
  };
}
