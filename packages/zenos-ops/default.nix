{
  lib,
  makeWrapper,
  python3,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "zenos-ops";
  version = "0.1.0";
  src = ./.;

  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -d "$out/lib/zenos-ops" "$out/bin"
    cp -r zenos_ops "$out/lib/zenos-ops/"

    makeWrapper ${python3}/bin/python "$out/bin/zenos-maintenance" \
      --add-flags "$out/lib/zenos-ops/zenos_ops/maintenance.py"
    makeWrapper ${python3}/bin/python "$out/bin/zenos-janitor" \
      --add-flags "$out/lib/zenos-ops/zenos_ops/janitor.py"

    runHook postInstall
  '';

  meta = {
    description = "Deterministic ZenOS maintenance and file janitor tools";
    license = lib.licenses.napalm;
    platforms = lib.platforms.linux;
  };
}
