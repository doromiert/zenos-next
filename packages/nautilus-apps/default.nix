{
  appIndex,
  lib,
  python3,
  stdenvNoCC,
}:

let
  pythonEnv = python3.withPackages (packages: [ packages.pygobject3 ]);
in
stdenvNoCC.mkDerivation {
  pname = "zenos-nautilus-apps";
  version = "0.1.0";
  src = ./zenos_apps.py;
  dontUnpack = true;
  installPhase = ''
    install -Dm644 "$src" \
      "$out/share/nautilus-python/extensions/zenos_apps.py"
    substituteInPlace "$out/share/nautilus-python/extensions/zenos_apps.py" \
      --replace-fail '@zen_app_launch@' "$out/bin/zen-app-launch" \
      --replace-fail '@zen_appimage@' "${appIndex}/bin/zen-appimage"
    install -Dm755 ${./zen_app_launch.py} "$out/bin/zen-app-launch"
    substituteInPlace "$out/bin/zen-app-launch" \
      --replace-fail '#!/usr/bin/env python3' '#!${pythonEnv}/bin/python3'
  '';
  meta = {
    description = "Nautilus integration for the ZenOS /Apps directory";
    license = lib.licenses.napalm;
    platforms = lib.platforms.linux;
  };
}
