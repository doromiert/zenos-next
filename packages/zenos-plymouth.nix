{
  atkinson-hyperlegible,
  deviceIcon ? "negzero",
  deviceName ? "ZenOS",
  distroName ? "ZenOS",
  imagemagick,
  lib,
  releaseVersion ? "1.0N",
  source,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "zenos-plymouth";
  version = "1.0.0";
  src = source;

  nativeBuildInputs = [ imagemagick ];
  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    mkdir -p build
    font_bold="${atkinson-hyperlegible}/share/fonts/opentype/AtkinsonHyperlegible-Bold.otf"
    font_regular="${atkinson-hyperlegible}/share/fonts/opentype/AtkinsonHyperlegible-Regular.otf"

    magick -background none -density 1200 "icons/${deviceIcon}.svg" \
      -resize 120x120 build/icon_top.png
    magick -background none -fill white -font "$font_bold" -pointsize 72 \
      label:${lib.escapeShellArg deviceName} build/host_text.png
    magick -background none -fill white -font "$font_regular" -pointsize 32 \
      label:"Powered by" build/powered_by.png
    magick -background none -density 1200 icons/zenos.svg \
      -resize 64x64 build/icon_bottom.png
    magick -background none -fill white -font "$font_regular" -pointsize 48 \
      label:${lib.escapeShellArg "${distroName} "} build/os_name.png
    magick -background none -fill white -font "$font_bold" -pointsize 48 \
      label:${lib.escapeShellArg releaseVersion} build/os_version.png
    magick -background none -density 8000 icons/zenos.svg \
      -resize 1640x1640 -channel A -evaluate multiply 0.10 build/watermark_bg.png
    magick -size 600x600 xc:transparent -fill '#C532FF' \
      -draw 'rectangle 250,250 350,350' -blur 0x100 -resize 6000x6000 build/glow.png
    cp scripts/zenos.script build/zenos.script

    cat > build/zenos.plymouth <<EOF
    [Plymouth Theme]
    Name=ZenOS
    Description=ZenOS boot animation
    ModuleName=script

    [script]
    ImageDir=$out/share/plymouth/themes/zenos
    ScriptFile=$out/share/plymouth/themes/zenos/zenos.script
    EOF

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/plymouth/themes/zenos"
    cp -r build/* "$out/share/plymouth/themes/zenos/"
    runHook postInstall
  '';

  meta = {
    description = "ZenOS Plymouth boot animation";
    license = lib.licenses.napalm;
    platforms = lib.platforms.linux;
  };
}
