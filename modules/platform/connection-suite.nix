{
  config,
  lib,
  ...
}:

let
  cfg = config.zenos.platform.connectionSuite;
in
{
  options.zenos.platform.connectionSuite = {
    enable = lib.mkEnableOption "the ZeroBridge connection suite";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "ZeroBridge package supplied explicitly by a flake or module argument.";
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Start ZeroBridge with the user session.";
    };

    acknowledgeUnauthenticatedProtocol = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Acknowledge that the current UDP READY handshake does not authenticate peers.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the ZeroBridge UDP listener port in the host firewall.";
    };

    debugNotifications = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Notify the desktop when the daemon cannot find a peer.";
    };

    restartPolicy = lib.mkOption {
      type = lib.types.enum [
        "no"
        "on-failure"
        "always"
      ];
      default = "on-failure";
      description = "systemd restart policy for the user service.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.package != null;
        message = "zenos.platform.connectionSuite.package must be supplied when the module is enabled";
      }
      {
        assertion = !cfg.autoStart || cfg.acknowledgeUnauthenticatedProtocol;
        message = "ZeroBridge autostart requires acknowledgeUnauthenticatedProtocol because its UDP handshake is unauthenticated";
      }
    ];

    environment.systemPackages = lib.optional (cfg.package != null) cfg.package;
    networking.firewall.allowedUDPPorts = lib.optional cfg.openFirewall 5001;

    systemd.user.services.zenos-connection-suite = {
      description = "ZenOS ZeroBridge connection suite";
      after = [
        "network.target"
        "pipewire.service"
      ];
      wants = [ "pipewire.service" ];
      wantedBy = lib.optional cfg.autoStart "default.target";
      serviceConfig = {
        Type = "exec";
        Restart = cfg.restartPolicy;
        RestartSec = 5;
        KillMode = "control-group";
        NoNewPrivileges = true;
        PrivateTmp = false;
        ProtectSystem = "strict";
      }
      // lib.optionalAttrs (cfg.package != null) {
        ExecStart = "${lib.getExe' cfg.package "zb-daemon"}${lib.optionalString cfg.debugNotifications " --debug-notify"}";
      };
    };
  };
}
