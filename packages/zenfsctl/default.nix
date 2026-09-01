{
  lib,
  python3,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "zenfsctl";
  version = "0.1.0";

  src = ./zenfsctl.py;
  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/zenfsctl"
    substituteInPlace "$out/bin/zenfsctl" \
      --replace-fail '#!/usr/bin/env python3' '#!${lib.getExe python3}'
    runHook postInstall
  '';

  meta = {
    description = "Safe hierarchy and roaming-drive administration for ZenFS";
    license = lib.licenses.napalm;
    mainProgram = "zenfsctl";
    platforms = lib.platforms.linux;
  };
}
