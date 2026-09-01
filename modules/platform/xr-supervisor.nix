{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.zenos.platform.xr;
  supervisorConfig = pkgs.writeText "zenos-xr-supervisor.json" (
    builtins.toJSON {
      inherit (cfg)
        command
        environment
        requiredCommands
        requiredPaths
        ;
    }
  );
  executable = lib.getExe cfg.package;
in
{
  options.zenos.platform.xr = {
    enable = lib.mkEnableOption "the ZenOS XR runtime supervisor skeleton";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../packages/platform-tools/xr-supervisor { };
      defaultText = lib.literalExpression "pkgs.callPackage ../../packages/platform-tools/xr-supervisor { }";
      description = "Package providing preflight, status, and owned-process supervision.";
    };

    command = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "/run/current-system/sw/bin/real-xr-runtime"
        "--session"
      ];
      description = "Real XR runtime command to supervise. No streaming command is provided by this module.";
    };

    requiredCommands = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional executable names or absolute paths checked during preflight.";
    };

    requiredPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "/dev/dri/renderD128" ];
      description = "Device or filesystem paths that must exist before startup.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Environment passed to the supervised runtime.";
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Start the configured runtime with the graphical user session.";
    };

    processPolicy = lib.mkOption {
      type = lib.types.enum [ "owned-only" ];
      default = "owned-only";
      readOnly = true;
      description = "Only the direct child process group and service cgroup are managed.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.command != [ ];
        message = "zenos.platform.xr.command must name a real XR runtime when the supervisor is enabled";
      }
    ];

    environment.systemPackages = [ cfg.package ];

    systemd.user.services.zenos-xr-supervisor = {
      description = "ZenOS XR runtime supervisor";
      after = [ "graphical-session.target" ];
      partOf = lib.optional cfg.autoStart "graphical-session.target";
      wantedBy = lib.optional cfg.autoStart "graphical-session.target";
      serviceConfig = {
        Type = "exec";
        ExecStartPre = "${executable} preflight --config ${supervisorConfig}";
        ExecStart = "${executable} run --config ${supervisorConfig} --state-file %t/zenos-xr-supervisor/state.json";
        Restart = "on-failure";
        RestartSec = 2;
        RuntimeDirectory = "zenos-xr-supervisor";
        RuntimeDirectoryMode = "0700";
        KillMode = "control-group";
        TimeoutStopSec = 15;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
      };
    };
  };
}
