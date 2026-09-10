{
  inputs,
  pkgs,
  installer,
  configTemplate,
  liveConfig,
}:
let
  inherit (pkgs) lib;
  configHash = builtins.substring 0 7 (builtins.hashString "sha256" inputs.self.sourceInfo.narHash);
  displayVersion = "1.0.0Nb (${configHash})";
  installed = import ./installed-hosts.nix {
    configRoot = ./fixtures/config;
    inputs = inputs // {
      zenosSource = inputs.self;
      setup-hardware.outPath = ./fixtures/hardware;
    };
  };
  live = installer.config;
  oobe = installed.nixosConfigurations.oobe-test.config;
  desktop = installed.nixosConfigurations.desktop-test.config;
  kde = installed.nixosConfigurations.kde-test.config;
  installedNativeTools = map toString desktop.system.build.zenosGeneratedConfig.nativeBuildInputs;
  valid =
    config:
    let
      failures = builtins.filter (entry: !entry.assertion) config.assertions;
    in
    lib.assertMsg (failures == [ ]) (lib.concatMapStringsSep "\n" (entry: entry.message) failures);
  unpack = value:
    if builtins.isAttrs value && (value._type or "") == "gvariant" then unpack value.value
    else if builtins.isList value then map unpack value
    else value;
  setup = pkgs.zenos.system.zenos-setup;
  mode = pkgs.zenos.system.zenos-oobe-mode;
  refindInstaller = pkgs.zenos.system.zenos-refind-installer;
  refindTheme = pkgs.zenos.theming.system.zenos-refind-theme;
in
assert valid live;
assert valid oobe;
assert valid desktop;
assert live.services.greetd.settings.initial_session.user == "zenos";
assert live.system.nixos.version == displayVersion;
assert live.system.nixos.label == "1.0.0Nb-${configHash}";
assert live.system.nixos.versionSuffix == "";
assert live.system.nixos.extraOSReleaseArgs.BUILD_ID == "1.0.0Nb-${configHash}";
assert live.system.nixos.extraOSReleaseArgs.CPE_NAME == "cpe:/o:zenos:zenos:1.0.0Nb";
assert live.system.nixos.extraOSReleaseArgs.LOGO == "zenos";
assert live.system.nixos.extraLSBReleaseArgs.DISTRIB_RELEASE == "1.0.0Nb";
assert live.system.image.id == "zenos-installer";
assert live.system.image.version == "1.0.0Nb-${configHash}";
assert live.system.configurationRevision == configHash;
assert lib.hasInfix "--session=zenos-oobe" live.services.greetd.settings.initial_session.command;
assert live.systemd.user.services.zenos-setup.serviceConfig.ExecStart == lib.getExe setup;
assert live.systemd.user.services.zenos-setup.environment.ZENOS_SETUP_DRY_RUN == "0";
assert
  oobe.systemd.user.services.zenos-setup.serviceConfig.ExecStart == "${lib.getExe setup} --oobe";
assert oobe.systemd.user.services.zenos-setup.environment.ZENOS_SETUP_DRY_RUN == "0";
assert !oobe.services.displayManager.gdm.enable;
assert oobe.users.users.zenos.home == "/run/zenos-oobe";
assert unpack oobe.home-manager.users.zenos.dconf.settings."org/gnome/shell".enabled-extensions
  == [
    "date-menu-formatter@marcinjakubowski.github.com"
    "user-theme@gnome-shell-extensions.gcampax.github.com"
    "zenos-oobe-mode@neg-zero.com"
  ];
assert oobe.home-manager.users.zenos.dconf.settings."org/gnome/shell/extensions/user-theme".name
  == "ClockOverride";
assert unpack oobe.home-manager.users.zenos.dconf.settings."org/gnome/shell/extensions/date-menu-formatter".pattern
  == "dd.MM  HH:mm";
assert oobe.home-manager.users.zenos.dconf.settings."org/gnome/desktop/background".picture-options
  == "none";
assert oobe.home-manager.users.zenos.dconf.settings."org/gnome/desktop/background".primary-color
  == "#000000";
assert lib.hasInfix "font-family: \"Zero\""
  oobe.home-manager.users.zenos.xdg.dataFile."themes/ClockOverride/gnome-shell/gnome-shell.css".text;
assert !desktop.services.greetd.enable;
assert desktop.services.openssh.enable;
assert desktop.services.openssh.openFirewall;
assert desktop.services.openssh.settings.PasswordAuthentication;
assert desktop.services.openssh.settings.PermitRootLogin == "no";
assert !oobe.services.openssh.enable;
assert !live.services.openssh.enable;
assert desktop.services.displayManager.gdm.enable;
assert !oobe.services.displayManager.gdm.enable;
assert !oobe.services.displayManager.sddm.enable;
assert !oobe.services.displayManager.plasma-login-manager.enable;
assert !oobe.services.xserver.displayManager.lightdm.enable;
assert kde.services.displayManager.plasma-login-manager.enable;
assert !kde.services.displayManager.sddm.enable;
assert !(desktop.users.users ? zenos);
assert !(desktop.systemd.user.services ? zenos-setup);
assert desktop.users.users.alice.home == "/Users/alice";
assert desktop.security.sudo.wheelNeedsPassword;
assert desktop.services.qemuGuest.enable;
assert lib.elem (toString (lib.getBin pkgs.nix)) installedNativeTools;
assert !lib.elem (toString (lib.getDev pkgs.nix)) installedNativeTools;
assert !oobe.boot.loader.grub.enable && desktop.boot.loader.systemd-boot.enable;
assert desktop.boot.loader.timeout == 0;
assert desktop.boot.loader.efi.efiSysMountPoint == "/boot";
assert lib.hasInfix "refind-install --yes" desktop.boot.loader.systemd-boot.extraInstallCommands;
assert lib.hasInfix "cp -Lrf --no-preserve=mode" desktop.boot.loader.systemd-boot.extraInstallCommands;
assert lib.hasInfix "zenos-sync-refind-generations" desktop.boot.loader.systemd-boot.extraInstallCommands;
assert lib.hasInfix "/boot/EFI/BOOT/BOOTX64.EFI" desktop.boot.loader.systemd-boot.extraInstallCommands;
assert desktop.fileSystems."/".device == "/dev/disk/by-uuid/fixture-root";
assert desktop.zenos.system.zenfs.filesystemHierarchy.enable;
assert builtins.elem "zenfs-hierarchy" desktop.system.activationScripts.users.deps;
assert builtins.elem "etc" desktop.system.activationScripts.zenfs-hierarchy.deps;
assert desktop.environment.etc ? "zenfs/manifest.json";
assert builtins.elem inputs.zenpkgs.packages.x86_64-linux.dsl-bundle live.system.extraDependencies;
assert builtins.elem inputs.zenpkgs.packages.x86_64-linux.dsl-bundle live.isoImage.storeContents;
assert lib.all (source: builtins.elem source live.isoImage.storeContents) liveConfig.sources;
assert desktop.systemd.tmpfiles.settings."10-zenfs"."/Users/alice/.private/State/nix".d.user == "alice";
assert live.systemd.tmpfiles.settings."10-zenfs"."/Users/zenos/.private/State/nix".d.user == "zenos";
assert live.systemd.services.xe-daemon.unitConfig.ConditionVirtualization == "xen";
assert desktop.environment.sessionVariables.XDG_CONFIG_HOME == "$HOME/.private/Config";
assert builtins.elem ./fixtures/hardware desktop.system.extraDependencies;
pkgs.runCommand "zenos-installer-contract" { } ''
  ${pkgs.python3}/bin/python - ${desktop.environment.etc."zenfs/manifest.json".source} ${live.environment.etc."zenfs/manifest.json".source} <<'PY'
  import json
  import sys
  with open(sys.argv[1]) as source:
      manifest = json.load(source)
  assert manifest["aliases"]["/Config"] == "/etc"
  assert manifest["aliases"]["/Boot"] == "/boot"
  assert "/Drives" not in manifest["aliases"]
  with open(sys.argv[2]) as source:
      live_manifest = json.load(source)
  assert "/Boot" not in live_manifest["aliases"]
  assert live_manifest["aliases"]["/Config"] == "/etc"
  PY
  test -f ${configTemplate}/flake.nix
  grep -Eq 'github:NixOS/nixpkgs/[0-9a-f]{40}' ${configTemplate}/flake.nix
  grep -Eq 'github:zenos-n/zenpkgs/[0-9a-f]{40}' ${configTemplate}/flake.nix
  grep -Eq 'github:doromiert/zenos-next/[0-9a-f]{40}' ${configTemplate}/flake.nix
  if grep -q 'path:/nix/store' ${configTemplate}/flake.nix; then exit 1; fi
  test -x ${lib.getExe setup}
  test -f ${mode}/share/gnome-shell/modes/zenos-oobe.json
  test -f ${mode}/share/gnome-shell/extensions/zenos-oobe-mode@neg-zero.com/metadata.json
  test -f ${refindTheme}/share/zenos/refind/refind.conf
  test -f ${refindTheme}/share/zenos/refind/themes/zenos-picker/theme.conf
  test -x ${refindInstaller}/bin/zenos-sync-refind-generations
  test -f "${oobe.system.path}/share/backgrounds/destination-2/purple dark.png"
  test -f ${pkgs.gnome-desktop}/lib/girepository-1.0/GnomeDesktop-4.0.typelib
  test -f ${pkgs.libgweather}/lib/girepository-1.0/GWeather-4.0.typelib
  test -f ${pkgs.networkmanager}/lib/girepository-1.0/NM-1.0.typelib
  touch "$out"
''
