{
  nixpkgs,
  system,
}:

let
  evaluated = nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      ../../modules/app-platform.nix
      {
        boot.loader.grub.enable = false;
        fileSystems."/" = {
          device = "/dev/null";
          fsType = "tmpfs";
        };
        system.stateVersion = "26.05";
      }
    ];
  };
  cfg = evaluated.config;
in
assert cfg.services.flatpak.enable;
assert cfg.xdg.portal.enable;
assert cfg.systemd.services ? zenos-flatpak-policy;
assert cfg.systemd.user.services ? zenos-flatpak-policy;
assert cfg.systemd.user.services.zenos-flatpak-policy.unitConfig.ConditionUser == "!@system";
assert cfg.systemd.user.services.zenos-flatpak-policy.serviceConfig.Restart == "on-failure";
assert builtins.elem "$HOME/.private/Packages/flatpak/exports" cfg.environment.profiles;
assert cfg.environment.sessionVariables.ZENOS_FLATPAK_REMOTE == "zenos-flathub";
{
  systemPolicy = cfg.systemd.services.zenos-flatpak-policy.serviceConfig.ExecStart;
  userPolicy = cfg.systemd.user.services.zenos-flatpak-policy.serviceConfig.ExecStart;
}
