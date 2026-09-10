{
  inputs,
  pkgs,
  liveConfig,
  desktopSource ? ./appearance.zcfg,
}:
let
  inherit (pkgs) lib;
  inherit (liveConfig) seed;
  original = inputs.self.nixosConfigurations.zenos-installer-iso.config;
  evaluate =
    root:
    ((import (root + "/flake.nix")).outputs {
      actualImage = inputs.self;
      inherit (inputs) nixpkgs zenpkgs;
    }).nixosConfigurations.zenos-installer.config;
  live = evaluate seed;
  edited = pkgs.runCommand "zenos-live-config-edited-fixture" { } ''
    cp -r ${seed} "$out"
    chmod -R u+w "$out"
    mkdir -p "$out/hosts/shared"
    sed -i '/^legacy.time.timeZone = /d' "$out/hosts/zenos-installer/system.zcfg"
    printf '\n_import "../shared/local.zcfg";\n' >> "$out/hosts/zenos-installer/host.zcfg"
    cp ${./fixtures/live-config-overlap.zcfg} "$out/hosts/shared/local.zcfg"
  '';
  changed = evaluate edited;
  desktopEdited = pkgs.runCommand "zenos-live-config-desktop-edited" { } ''
    cp -r ${seed} "$out"
    chmod -R u+w "$out"
    substituteInPlace "$out/hosts/zenos-installer/desktop.zcfg" \
      --replace-fail 'timeout = 2000;' 'timeout = 3500;' \
      --replace-fail '"font-name" = "Atkinson Hyperlegible 11";' '"font-name" = "Atkinson Hyperlegible 13";'
    substituteInPlace "$out/hosts/zenos-installer/system.zcfg" \
      --replace-fail 'legacy.services.fstrim.enable = true;' 'legacy.services.fstrim.enable = false;'
  '';
  desktopChanged = evaluate desktopEdited;
  desktopSettings = config: config.home-manager.users.zenos.dconf.settings;
  gvariant = import "${inputs.zenpkgs.inputs.home-manager}/modules/lib/gvariant.nix" { inherit lib; };
  encodedSettings = config: lib.mapAttrs (_: lib.mapAttrs (_: value:
    toString (gvariant.mkValue value))) (desktopSettings config);
  packageIds = config: map toString config.environment.systemPackages;
  report = builtins.fromJSON (builtins.unsafeDiscardStringContext
    (builtins.readFile (seed + "/base-effective.json")));
  generated = live.system.build.zenosGeneratedConfig;
  exported = ((import (seed + "/flake.nix")).outputs {
    actualImage = inputs.self;
    inherit (inputs) nixpkgs zenpkgs;
  }).packages.${pkgs.stdenv.hostPlatform.system}.generated-host;
  nativeTools = map toString generated.nativeBuildInputs;
  pinned = (import (seed + "/flake.nix")).inputs;
  retained = map toString live.system.extraDependencies;
  valid =
    config:
    let
      failures = builtins.filter (entry: !entry.assertion) config.assertions;
    in
    lib.assertMsg (failures == [ ]) (lib.concatMapStringsSep "\n" (entry: entry.message) failures);
in
assert pinned.actualImage.url == "path:${inputs.self.outPath}";
assert !(pinned ? setup-hardware);
assert pinned.zenpkgs.follows == "actualImage/zenpkgs";
assert generated == exported;
assert live.networking.hostName == original.networking.hostName;
assert live.system.nixos.distroId == "zenos";
assert live.system.nixos.distroName == original.system.nixos.distroName;
assert live.system.nixos.extraOSReleaseArgs == original.system.nixos.extraOSReleaseArgs;
assert live.system.name == original.system.name;
assert live.system.nixos.variant_id == original.system.nixos.variant_id;
assert live.environment.etc."machine-info".text == original.environment.etc."machine-info".text;
assert live.fileSystems == original.fileSystems;
assert live.services.greetd.settings == original.services.greetd.settings;
assert live.users.users.zenos.home == original.users.users.zenos.home;
assert live.environment.systemPackages == original.environment.systemPackages;
assert map (package: package.storePath) report.packages == packageIds original;
assert live.fonts.fontconfig.defaultFonts == original.fonts.fontconfig.defaultFonts;
assert live.fonts.packages == original.fonts.packages;
assert desktopSource == null || encodedSettings live == encodedSettings original;
assert desktopSource == null || live.zenos.desktops.gnome == original.zenos.desktops.gnome;
assert desktopSource == null || lib.hasPrefix (builtins.readFile desktopSource)
  (lib.trim (builtins.readFile (seed + "/hosts/zenos-installer/desktop.zcfg")));
assert
  live.systemd.user.services.zenos-setup.serviceConfig.ExecStart
  == original.systemd.user.services.zenos-setup.serviceConfig.ExecStart;
assert changed.time.timeZone == "Europe/Warsaw";
assert changed.networking.hostName == original.networking.hostName;
assert !original.security.sudo.wheelNeedsPassword;
# Installation-media priority 60 remains stronger than local edits at 90.
assert changed.security.sudo.wheelNeedsPassword == original.security.sudo.wheelNeedsPassword;
assert changed.networking.networkmanager.enable == original.networking.networkmanager.enable;
assert !changed.services.openssh.enable;
assert changed.networking.firewall.allowedTCPPorts == [ 443 ];
assert changed.networking.extraHosts == original.networking.extraHosts;
assert changed.system.name == original.system.name;
assert changed.fileSystems == original.fileSystems;
assert changed.system.nixos.variant_id == original.system.nixos.variant_id;
assert changed.services.greetd.settings == original.services.greetd.settings;
assert changed.zenos.desktops.gnome.dockItems == original.zenos.desktops.gnome.dockItems;
assert changed.environment.systemPackages == original.environment.systemPackages;
assert builtins.elem (toString seed) retained;
assert builtins.elem (toString generated) retained;
assert lib.elem (toString (lib.getBin pkgs.nix)) nativeTools;
assert !lib.elem (toString (lib.getDev pkgs.nix)) nativeTools;
assert lib.all (source: builtins.elem (toString source) retained) liveConfig.sources;
assert valid live;
assert valid changed;
assert desktopSource == null || (
  desktopChanged.zenos.desktops.gnome.extensions.notification-timeout.timeout == 3500
  && (encodedSettings desktopChanged)."org/gnome/shell/extensions/notification-timeout".timeout == "3500"
  && (desktopSettings desktopChanged)."org/gnome/desktop/interface".font-name == "Atkinson Hyperlegible 13"
  && !desktopChanged.services.fstrim.enable
  && desktopChanged.services.desktopManager.gnome.enable
  && desktopChanged.hardware.graphics.enable == original.hardware.graphics.enable
  && desktopChanged.boot.kernelParams == original.boot.kernelParams
  && desktopChanged.fileSystems == original.fileSystems
  && desktopChanged.services.greetd.settings == original.services.greetd.settings
  && desktopChanged.system.nixos == original.system.nixos
  && packageIds desktopChanged == packageIds original
  && (encodedSettings desktopChanged)."org/gnome/shell" == (encodedSettings original)."org/gnome/shell"
  && valid desktopChanged
);
pkgs.runCommand "zenos-live-config-contract" { } ''
  test -f ${seed}/flake.nix
  test -s ${seed}/README.md
  test -f ${seed}/hosts/zenos-installer/host.zcfg
  test -s ${seed}/hosts/zenos-installer/system.zcfg
  test -s ${seed}/base-effective.json
  ${lib.optionalString (desktopSource != null) ''
    test -s ${desktopChanged.system.build.zenosGeneratedConfig}
  ''}
  test ! -e ${seed}/hosts/zenos-installer/host.nix
  test ! -e ${seed}/hosts/zenos-installer/hardware-configuration.nix
  test "$(find ${seed} -name '*.nix' -printf '%P\n')" = flake.nix
  test -s ${generated}
  test -s ${changed.system.build.zenosGeneratedConfig}
  if grep -q '@ZENOS_SETUP_HARDWARE@' ${seed}/flake.nix; then exit 1; fi
  touch "$out"
''
