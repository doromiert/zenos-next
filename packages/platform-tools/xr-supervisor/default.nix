{
  lib,
  python3,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "zen-xr-supervisor";
  version = "0.1.0";

  src = ./.;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 zen_xr_supervisor.py "$out/bin/zen-xr-supervisor"
    substituteInPlace "$out/bin/zen-xr-supervisor" \
      --replace-fail '#!/usr/bin/env python3' '#!${lib.getExe python3}'
    runHook postInstall
  '';

  meta = {
    description = "Owned-process supervisor skeleton for XR runtimes";
    license = lib.licenses.napalm;
    mainProgram = "zen-xr-supervisor";
    platforms = lib.platforms.linux;
  };
}
