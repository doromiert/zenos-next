# Evaluate/build only in the separate acceptance VM, after wiring appearance-hook.nix.
{ inputs, pkgs, installer }:
let
  inherit (pkgs) lib;
  live = installer.config;
  home = live.home-manager.users.zenos;
  settings = home.dconf.settings;
  expected = builtins.fromJSON (builtins.readFile ./fixtures/appearance-expected.json);
  gvariant = import "${inputs.zenpkgs.inputs.home-manager}/modules/lib/gvariant.nix" { inherit lib; };
  encoded = lib.mapAttrs (_: lib.mapAttrs (_: value: toString (gvariant.mkValue value))) settings;
  unpack = value:
    if gvariant.isGVariant value then unpack value.value
    else if builtins.isList value then map unpack value
    else value;
  python = pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);
  actualEnabled = unpack settings."org/gnome/shell".enabled-extensions;
  sorted = lib.sort builtins.lessThan;
  enabledModules = [
    "compiz-alike-magic-lamp-effect" "compiz-windows-effect" "coverflow-alt-tab"
    "date-menu-formatter" "gsconnect" "hide-cursor" "hide-minimized" "mouse-tail"
    "notification-timeout" "rounded-window-corners-reborn" "user-themes" "window-is-ready-remover"
  ];
  disabledModules = [ "alphabetical-app-grid" "app-hider" "burn-my-windows" "clipboard-indicator" "hide-top-bar" "dash-stacks" "forge" ];
  fontPackages = with pkgs.zenos; [
    apps.fonts.atkinson-hyperlegible apps.fonts.atkinson-hyperlegible-mono
    legacy.nerd-fonts.atkynson-mono apps.fonts.inter
    theming.fonts.zero.regular theming.fonts.zero.mono-thin
  ];
  snapshot = pkgs.writeText "appearance-generated.json" (builtins.toJSON {
    inherit encoded;
    enabled = actualEnabled;
    policies = live.programs.firefox.policies;
    preferences = live.programs.firefox.preferences;
  });
  keyfile = pkgs.writeText "appearance-generated.ini" (lib.generators.toINI {
    mkKeyValue = key: value: "${key}=${value}";
  } encoded);
in
assert lib.all (entry: entry.assertion) live.assertions;
assert live.zenos.desktops.gnome.enable;
assert live.fonts.fontconfig.enable;
assert lib.all (font: lib.elem font live.fonts.packages) fontPackages;
assert live.fonts.fontconfig.defaultFonts.monospace == [ "AtkynsonMono NF" ];
assert live.fonts.fontconfig.defaultFonts.sansSerif == [ "Atkinson Hyperlegible" ];
assert home.xdg.configHome == "/Users/zenos/.private/Config";
assert !live.services.displayManager.gdm.enable && live.services.greetd.enable;
assert lib.elem pkgs.xterm live.services.xserver.excludePackages;
assert lib.all (package: lib.elem package live.environment.gnome.excludePackages) (with pkgs; [
  gnome-calendar gnome-clocks gnome-contacts gnome-maps gnome-music gnome-weather epiphany simple-scan
]);
assert sorted actualEnabled == sorted expected.enabled;
assert builtins.length actualEnabled == 13;
assert lib.intersectLists expected.disabled actualEnabled == [ ];
assert lib.all (name: live.zenos.desktops.gnome.extensions.${name}.enable) enabledModules;
assert lib.all (name: !live.zenos.desktops.gnome.extensions.${name}.enable) disabledModules;
assert unpack settings."org/gnome/shell".favorite-apps == expected.favorites;
assert lib.all (schema: lib.all (key:
  (gvariant.mkValue settings.${schema}.${key}).type == builtins.elemAt expected.settings.${schema}.${key} 0
  && unpack settings.${schema}.${key} == builtins.elemAt expected.settings.${schema}.${key} 1
) (builtins.attrNames expected.settings.${schema})) (builtins.attrNames expected.settings);
assert (gvariant.mkValue settings."org/gnome/shell/extensions/gsconnect/preferences".window-size).type == "(ii)";
assert live.programs.firefox.preferencesStatus == "locked";
assert builtins.length (builtins.attrNames live.programs.firefox.policies.ExtensionSettings) == 5;
pkgs.runCommand "zenos-live-appearance-contract" {
  nativeBuildInputs = [ python pkgs.gobject-introspection ];
  buildInputs = [ pkgs.glib ];
} ''
  mkdir -p "$out"
  cp ${snapshot} "$out/generated.json"
  cp ${keyfile} "$out/generated.ini"
  cp ${./fixtures/appearance-expected.json} "$out/expected.json"
  ${python}/bin/python ${./test-appearance.py} \
    --generated "$out/generated.json" --expected "$out/expected.json" \
    --system ${live.system.path} --home ${home.home.activationPackage} --assets-only
  test -s ${pkgs.zenos.system.zenos-setup.src}/data/wallpapers/purple.png
  test -f ${home.xdg.configFile."mozilla/firefox/default/chrome/gnome-theme".source}/userChrome.css
''
