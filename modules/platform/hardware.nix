{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.zenos.platform.hardware;
  database =
    if cfg.database == null then "${cfg.package}/share/zen-hardware/presets.json" else cfg.database;
  action = if cfg.preset == null then "detect" else "show ${lib.escapeShellArg cfg.preset}";
  factsArgument = lib.optionalString (
    cfg.preset == null && cfg.factsFile != null
  ) " --facts ${lib.escapeShellArg cfg.factsFile}";
in
{
  options.zenos.platform.hardware = {
    enable = lib.mkEnableOption "ZenOS hardware preset detection";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../packages/platform-tools/zen-hardware { };
      defaultText = lib.literalExpression "pkgs.callPackage ../../packages/platform-tools/zen-hardware { }";
      description = "Package providing the zen-hardware command and static preset database.";
    };

    database = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional immutable preset database path. The package database is used by default.";
    };

    preset = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "framework-laptop-amd";
      description = "Explicit preset to report instead of matching local DMI facts.";
    };

    factsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional JSON facts file used instead of local sysfs data.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    systemd.services.zenos-hardware = {
      description = "Match the ZenOS hardware preset";
      wantedBy = [ "multi-user.target" ];
      before = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe cfg.package} --database ${lib.escapeShellArg database} ${action}${factsArgument} --json --output /run/zenos-hardware/preset.json";
        RemainAfterExit = true;
        RuntimeDirectory = "zenos-hardware";
        RuntimeDirectoryMode = "0755";
        DynamicUser = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateNetwork = true;
        ProtectHome = true;
        ProtectSystem = "strict";
      };
    };
  };
}
