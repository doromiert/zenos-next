{
  lib,
  stdenvNoCC,
  makeWrapper,
  android-tools,
  bash,
  coreutils,
  gawk,
  gnugrep,
  gst_all_1,
  iproute2,
  jq,
  libnotify,
  pipewire,
  procps,
  pulseaudio,
  python3,
  scrcpy,
  source,
  systemd,
  toybox,
  util-linux,
  which,
}:

stdenvNoCC.mkDerivation {
  pname = "zenos-zerobridge";
  version = "1.0.0";
  src = source;

  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    scripts="$src/src/scripts"
    if [ ! -d "$scripts" ]; then
      scripts="$src"
    fi
    install -d "$out/bin"
    install -m755 "$scripts/zb-daemon.py" "$out/bin/zb-daemon"
    install -m755 "$scripts/zb-config.sh" "$out/bin/zb-config"
    install -m755 "$scripts/zb-installer.sh" "$out/bin/zb-installer"
    install -m755 "$scripts/zb-debug-phone.sh" "$out/bin/zb-debug-phone"
    runHook postInstall
  '';

  postFixup =
    let
      runtimePath = lib.makeBinPath [
        android-tools
        bash
        coreutils
        gawk
        gnugrep
        gst_all_1.gstreamer
        iproute2
        jq
        libnotify
        pipewire
        procps
        pulseaudio
        python3
        scrcpy
        systemd
        toybox
        util-linux
        which
      ];
      gstPluginPath = lib.makeSearchPathOutput "lib" "lib/gstreamer-1.0" [
        gst_all_1.gst-plugins-base
        gst_all_1.gst-plugins-good
        gst_all_1.gst-plugins-bad
        gst_all_1.gst-plugins-ugly
      ];
    in
    ''
      for program in "$out"/bin/*; do
        wrapProgram "$program" \
          --prefix PATH : ${runtimePath} \
          --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : ${gstPluginPath}
      done
    '';

  meta = {
    description = "Conservatively packaged ZeroBridge connection suite";
    license = lib.licenses.napalm;
    mainProgram = "zb-daemon";
    platforms = lib.platforms.linux;
  };
}
