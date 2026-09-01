{
  lib,
  python3,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "zen-hardware";
  version = "0.1.0";

  src = ./.;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 zen_hardware.py "$out/bin/zen-hardware"
    install -Dm644 presets.json "$out/share/zen-hardware/presets.json"
    substituteInPlace "$out/bin/zen-hardware" \
      --replace-fail '#!/usr/bin/env python3' '#!${lib.getExe python3}'
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    "$out/bin/zen-hardware" list >/dev/null
  '';

  meta = {
    description = "Dependency-free hardware preset matcher for ZenOS";
    license = lib.licenses.napalm;
    mainProgram = "zen-hardware";
    platforms = lib.platforms.linux;
  };
}
