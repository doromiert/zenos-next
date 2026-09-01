{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.zenos.janitor;
  ops = pkgs.callPackage ../../packages/zenos-ops { };
  ruleType = lib.types.submodule {
    options = {
      name = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9][A-Za-z0-9_-]*"; };
      source = lib.mkOption { type = lib.types.str; };
      destination = lib.mkOption { type = lib.types.str; };
      extensions = lib.mkOption {
        type = lib.types.listOf (lib.types.strMatching "\\.[A-Za-z0-9][A-Za-z0-9._+-]*");
        default = [ ];
      };
      namePattern = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      minSizeBytes = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.unsigned;
        default = null;
      };
      maxSizeBytes = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.unsigned;
        default = null;
      };
      recursive = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
    };
  };
  rulesFile = pkgs.writeText "zenos-janitor-rules.json" (
    builtins.toJSON {
      version = 1;
      inherit (cfg) allowedDestinations rules;
    }
  );
  names = map (rule: rule.name) cfg.rules;
in
{
  options.zenos.janitor = {
    enable = lib.mkEnableOption "deterministic one-shot ZenOS file janitor";
    interval = lib.mkOption {
      type = lib.types.str;
      default = "15m";
      description = "Interval between one-shot Janitor runs.";
    };
    allowedDestinations = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Destination roots under which rules may place files.";
    };
    rules = lib.mkOption {
      type = lib.types.listOf ruleType;
      default = [ ];
      description = "Ordered rules; the first matching rule handles each file.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.allowedDestinations != [ ];
        message = "zenos.janitor.allowedDestinations must not be empty";
      }
      {
        assertion = builtins.length names == builtins.length (lib.unique names);
        message = "zenos.janitor rule names must be unique";
      }
      {
        assertion = lib.all (
          rule:
          rule.minSizeBytes == null || rule.maxSizeBytes == null || rule.minSizeBytes <= rule.maxSizeBytes
        ) cfg.rules;
        message = "zenos.janitor rule minSizeBytes must not exceed maxSizeBytes";
      }
    ];

    environment.etc."zenos/janitor-rules.json".source = rulesFile;
    environment.systemPackages = [ ops ];

    systemd.user.services.zenos-janitor = {
      description = "Run one deterministic ZenOS Janitor pass";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${ops}/bin/zenos-janitor --config ${rulesFile} process";
        LockPersonality = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
      };
    };

    systemd.user.timers.zenos-janitor = {
      description = "Run the ZenOS Janitor periodically";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnStartupSec = "5m";
        OnUnitInactiveSec = cfg.interval;
        Persistent = true;
        Unit = "zenos-janitor.service";
      };
    };
  };
}
