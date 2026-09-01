{
  nixpkgs,
  system ? "x86_64-linux",
}:

let
  baseModule = {
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
            "/Users" = "/Users/backing";
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
assert builtins.elem "nodev" cfg.fileSystems."/home/alice/Documents".options;
assert builtins.elem "nosuid" cfg.fileSystems."/home/alice/Documents".options;
assert builtins.elem "noexec" cfg.fileSystems."/home/alice/Documents".options;
assert builtins.elem "ro" cfg.fileSystems."/home/alice/Documents".options;
assert cfg.systemd.tmpfiles.settings."10-zenfs"."/home/alice/.config".d.mode == "0700";
assert cfg.environment.sessionVariables.XDG_STATE_HOME == "$HOME/.local/state";
assert cfg.zenfs.hierarchy.aliases."/Boot" == "/boot";
assert cfg.zenfs.hierarchy.aliases."/System/Config" == "/etc";
assert !(cfg.zenfs.hierarchy.aliases ? "/Config");
assert builtins.elem "/Config" cfg.zenfs.hierarchy.directories;
assert
  cfg.systemd.services.zenfs-roaming-work-marker.unitConfig.RequiresMountsFor == [
    "/Mount/work"
  ];
{
  aliases = builtins.attrNames cfg.zenfs.hierarchy.aliases;
  privateMount = cfg.fileSystems."/home/alice/Documents";
  roamingMount = cfg.fileSystems."/Mount/work";
  tmpfiles = builtins.attrNames cfg.systemd.tmpfiles.settings."10-zenfs";
}
