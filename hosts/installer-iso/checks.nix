{
  inputs,
  pkgs,
  installer,
  configTemplate,
}:
let
  inherit (pkgs) lib;
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
  valid =
    config:
    let
      failures = builtins.filter (entry: !entry.assertion) config.assertions;
    in
    lib.assertMsg (failures == [ ]) (lib.concatMapStringsSep "\n" (entry: entry.message) failures);
  setup = pkgs.zenos.system.zenos-setup;
  mode = pkgs.zenos.system.zenos-oobe-mode;
in
assert valid live;
assert valid oobe;
assert valid desktop;
assert live.services.greetd.settings.initial_session.user == "zenos";
assert lib.hasInfix "--session=zenos-oobe" live.services.greetd.settings.initial_session.command;
assert live.systemd.user.services.zenos-setup.serviceConfig.ExecStart == lib.getExe setup;
assert live.systemd.user.services.zenos-setup.environment.ZENOS_SETUP_DRY_RUN == "0";
assert
  oobe.systemd.user.services.zenos-setup.serviceConfig.ExecStart == "${lib.getExe setup} --oobe";
assert oobe.systemd.user.services.zenos-setup.environment.ZENOS_SETUP_DRY_RUN == "0";
assert !oobe.services.displayManager.gdm.enable;
assert oobe.users.users.zenos.home == "/run/zenos-oobe";
assert !desktop.services.greetd.enable;
assert desktop.services.displayManager.gdm.enable;
assert !(desktop.users.users ? zenos);
assert !(desktop.systemd.user.services ? zenos-setup);
assert desktop.users.users.alice.home == "/Users/alice";
assert desktop.security.sudo.wheelNeedsPassword;
assert oobe.boot.loader.grub.efiSupport && desktop.boot.loader.grub.efiInstallAsRemovable;
assert desktop.boot.loader.efi.efiSysMountPoint == "/boot";
assert desktop.fileSystems."/".device == "/dev/disk/by-uuid/fixture-root";
assert builtins.elem "L /Config - - - - /etc" desktop.systemd.tmpfiles.rules;
assert desktop.environment.sessionVariables.XDG_CONFIG_HOME == "$HOME/.private/Config";
assert builtins.elem ./fixtures/hardware desktop.system.extraDependencies;
pkgs.runCommand "zenos-installer-contract" { } ''
  test -f ${configTemplate}/flake.nix
  test -x ${lib.getExe setup}
  test -f ${mode}/share/gnome-shell/modes/zenos-oobe.json
  test -f ${mode}/share/gnome-shell/extensions/zenos-oobe-mode@neg-zero.com/metadata.json
  test -f ${pkgs.gnome-desktop}/lib/girepository-1.0/GnomeDesktop-4.0.typelib
  test -f ${pkgs.libgweather}/lib/girepository-1.0/GWeather-4.0.typelib
  test -f ${pkgs.networkmanager}/lib/girepository-1.0/NM-1.0.typelib
  touch "$out"
''
