{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.zenos.appPlatform.flatpak;
  appIndex = pkgs.callPackage ../packages/app-index { };
  remoteName = lib.escapeShellArg cfg.remote.name;
  remoteDescriptor = lib.escapeShellArg cfg.remote.descriptor;
  systemPolicy = pkgs.writeShellApplication {
    name = "zenos-system-flatpak-policy";
    runtimeInputs = [ pkgs.flatpak ];
    text = ''
      flatpak remote-delete --system --force ${remoteName} 2>/dev/null || true
      exec flatpak remote-add --system --from ${remoteName} ${remoteDescriptor}
    '';
  };
  userPolicy = pkgs.writeShellApplication {
    name = "zenos-user-flatpak-policy";
    runtimeInputs = [ pkgs.flatpak ];
    text = ''
      if [[ -d "$HOME/.private/Packages" ]]; then
        export XDG_DATA_HOME="$HOME/.private/Packages"
      fi
      flatpak remote-delete --user --force ${remoteName} 2>/dev/null || true
      exec flatpak remote-add --user --from ${remoteName} ${remoteDescriptor}
    '';
  };
in
{
  options.zenos.appPlatform.flatpak = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Flatpak and reconcile the default ZenOS remote.";
    };

    remote = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "zenos-flathub";
        description = "Name of the Flatpak remote owned and reconciled by ZenOS.";
      };

      descriptor = lib.mkOption {
        type = lib.types.path;
        default = pkgs.fetchurl {
          url = "https://dl.flathub.org/repo/flathub.flatpakrepo";
          hash = "sha256-M3HdJQ5h2eFjNjAHP+/aFTzUQm9y9K+gwzc64uj+oDo=";
        };
        description = "Pinned Flatpak repository descriptor used to recreate the owned remote.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.flatpak.enable = true;
    xdg.portal.enable = true;
    environment.systemPackages = [ appIndex ];
    environment.profiles = [ "$HOME/.private/Packages/flatpak/exports" ];
    environment.sessionVariables.ZENOS_FLATPAK_REMOTE = cfg.remote.name;

    systemd.services.zenos-flatpak-policy = {
      description = "Reconcile the ZenOS system Flatpak remote";
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [ systemPolicy ];
      unitConfig.StartLimitIntervalSec = 0;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe systemPolicy;
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };

    systemd.user.services.zenos-flatpak-policy = {
      description = "Reconcile the ZenOS user Flatpak remote";
      wantedBy = [ "graphical-session-pre.target" ];
      after = [ "zenfs-user-init.service" ];
      before = [ "zenos-user-app-index.service" ];
      restartTriggers = [ userPolicy ];
      unitConfig = {
        ConditionUser = "!@system";
        StartLimitIntervalSec = 0;
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe userPolicy;
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };

    systemd.user.services.zenos-user-app-index.after = [
      "zenos-flatpak-policy.service"
    ];
  };
}
