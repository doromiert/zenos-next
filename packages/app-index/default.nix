{
  bubblewrap,
  flatpak,
  lib,
  python3,
  squashfsTools,
  symlinkJoin,
  writeShellApplication,
}:

let
  appIndex = writeShellApplication {
    name = "zen-app-index";
    runtimeInputs = [ python3 ];
    text = ''
      export PYTHONPATH=${./.}
      exec python3 ${./app_index.py} "$@"
    '';
  };
  appImage = writeShellApplication {
    name = "zen-appimage";
    runtimeInputs = [
      bubblewrap
      python3
      squashfsTools
    ];
    text = ''
      export PYTHONPATH=${./.}
      exec python3 ${./appimage.py} "$@"
    '';
  };
  compatibility = writeShellApplication {
    name = "zen-compat";
    runtimeInputs = [
      bubblewrap
      python3
    ];
    text = ''
      export PYTHONPATH=${./.}
      exec python3 ${./compat.py} "$@"
    '';
  };
  flatpakApps = writeShellApplication {
    name = "zen-flatpak";
    runtimeInputs = [
      flatpak
      python3
    ];
    text = ''
      export PYTHONPATH=${./.}
      exec python3 ${./flatpak.py} "$@"
    '';
  };
in
symlinkJoin {
  name = "zenos-app-index";
  paths = [
    appIndex
    appImage
    compatibility
    flatpakApps
  ];
  meta = {
    description = "Build ZenOS application views and manage application compatibility";
    license = lib.licenses.napalm or lib.licenses.unfree;
    mainProgram = "zen-app-index";
    platforms = lib.platforms.linux;
  };
}
