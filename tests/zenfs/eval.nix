{
  nixpkgs,
  system ? "x86_64-linux",
  zenpkgs,
}:

let
  baseModule = {
    nixpkgs.config.allowUnfree = true;
    nixpkgs.overlays = [ zenpkgs.overlays.default ];
    system.stateVersion = "25.11";
    boot.loader.grub.devices = [ "nodev" ];
    fileSystems."/" = {
      device = "/dev/null";
      fsType = "ext4";
    };
  };
  evaluated = nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      ../../modules/zenfs
      baseModule
      {
        users.users.alice = {
          isNormalUser = true;
          group = "users";
        };
        zenfs = {
          enable = true;
          users.alice = { };
          roaming.drives.work = {
            device = "/dev/disk/by-label/ZENOS_WORK";
            fsType = "ext4";
            privateMounts.Documents = {
              user = "alice";
              source = "users/alice/Documents";
            };
          };
        };
      }
    ];
  };
  cfg = evaluated.config;
  userEnvironmentGenerator = builtins.readFile (
    cfg.environment.etc."systemd/user-environment-generators/20-zenfs".source
  );
  failedAssertions = builtins.filter (assertion: !assertion.assertion) cfg.assertions;

  unsafeEvaluation = nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      ../../modules/zenfs
      baseModule
      {
        zenfs = {
          enable = true;
          hierarchy.aliases = {
            "/home" = "/home/backing";
          };
          roaming.drives.unsafe = {
            device = "/dev/null";
            options = [ "nofail" ];
          };
        };
      }
    ];
  };
  unsafeMessages = map (assertion: assertion.message) (
    builtins.filter (assertion: !assertion.assertion) unsafeEvaluation.config.assertions
  );
in
assert failedAssertions == [ ];
assert builtins.elem
  "ZenFS hierarchy targets must be absolute and outside the managed alias namespace."
  unsafeMessages;
assert builtins.elem "ZenFS roaming drives must retain nodev, nosuid, and noexec mount options."
  unsafeMessages;
assert
  cfg.fileSystems."/Mount/work".options == [
    "nofail"
    "x-systemd.automount"
    "x-systemd.device-timeout=10s"
    "nodev"
    "nosuid"
    "noexec"
  ];
assert builtins.elem "nodev" cfg.fileSystems."/Users/alice/Documents".options;
assert builtins.elem "nosuid" cfg.fileSystems."/Users/alice/Documents".options;
assert builtins.elem "noexec" cfg.fileSystems."/Users/alice/Documents".options;
assert builtins.elem "ro" cfg.fileSystems."/Users/alice/Documents".options;
assert cfg.systemd.tmpfiles.settings."10-zenfs"."/Users/alice/.private/Config".d.mode == "0700";
assert cfg.zenfs.strict;
assert !(cfg.systemd.tmpfiles.settings."10-zenfs" ? "/Users/alice/.config");
assert cfg.systemd.tmpfiles.settings."10-zenfs"."/Users/alice/.private/Legacy".d.mode == "0700";
assert
  cfg.systemd.tmpfiles.settings."10-zenfs"."/Users/alice/.private/Config/user-dirs.dirs".C.mode
  == "0600";
assert nixpkgs.lib.hasInfix "XDG_CONFIG_HOME" cfg.environment.extraInit;
assert cfg.environment.etc ? "systemd/user-environment-generators/20-zenfs";
assert nixpkgs.lib.hasInfix "alice:/Users/alice" userEnvironmentGenerator;
assert nixpkgs.lib.hasInfix "GNUPGHOME=$HOME/.private/Config/gnupg" userEnvironmentGenerator;
assert nixpkgs.lib.hasInfix "NIX_PROFILE=$HOME/.private/State/nix/profiles/profile"
  userEnvironmentGenerator;
assert !(nixpkgs.lib.hasInfix "gdm-greeter" userEnvironmentGenerator);
assert cfg.systemd.user.services.zenfs-user-init.serviceConfig.Type == "oneshot";
assert cfg.systemd.user.services.zenos-user-app-index.serviceConfig.Type == "oneshot";
assert
  cfg.systemd.user.services.zenos-user-app-index.unitConfig.ConditionPathIsDirectory
  == "%h/.private/Apps";
assert nixpkgs.lib.hasInfix "zenos-user-app-index"
  cfg.systemd.user.services.zenos-user-app-index.serviceConfig.ExecStart;
assert cfg.zenfs.hierarchy.aliases."/home" == "/Users";
assert builtins.elem "/Users" cfg.zenfs.hierarchy.directories;
assert nixpkgs.lib.hasInfix "refusing to migrate a separately mounted /home"
  cfg.system.activationScripts.zenfs-hierarchy.text;
assert builtins.elem "zenfs-hierarchy" cfg.system.activationScripts.users.deps;
assert cfg.zenfs.hierarchy.aliases."/Boot" == "/boot";
assert cfg.zenfs.hierarchy.aliases."/System/Config" == "/etc";
assert cfg.zenfs.hierarchy.aliases."/Config" == "/etc";
assert cfg.zenfs.hierarchy.aliases."/Packages" == "/nix";
assert cfg.zenfs.hierarchy.aliases."/Live/Runtime" == "/run";
assert builtins.elem "/Live" cfg.zenfs.hierarchy.directories;
assert builtins.elem "/mnt" cfg.zenfs.hierarchy.directories;
assert cfg.zenfs.hierarchy.aliases."/Mount" == "/mnt";
assert nixpkgs.lib.hasInfix "/Apps" cfg.systemd.services.zenos-app-index.serviceConfig.ExecStart;
assert nixpkgs.lib.hasInfix "--scope system"
  cfg.systemd.services.zenos-app-index.serviceConfig.ExecStart;
assert
  cfg.systemd.services.zenfs-roaming-work-marker.unitConfig.RequiresMountsFor == [
    "/Mount/work"
  ];
{
  aliases = builtins.attrNames cfg.zenfs.hierarchy.aliases;
  privateMount = cfg.fileSystems."/Users/alice/Documents";
  roamingMount = cfg.fileSystems."/Mount/work";
  tmpfiles = builtins.attrNames cfg.systemd.tmpfiles.settings."10-zenfs";
}
