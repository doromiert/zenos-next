{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.zenos.maintenance;
  ops = pkgs.callPackage ../../packages/zenos-ops { };
  optionalNumber = lib.types.nullOr lib.types.number;
  task = command: intervalSeconds: timeoutSeconds: {
    inherit command intervalSeconds timeoutSeconds;
  };
  tasks =
    lib.optionalAttrs cfg.journalVacuum.enable {
      journal-vacuum = task (
        [
          "${pkgs.systemd}/bin/journalctl"
          "--vacuum-time=${cfg.journalVacuum.maxAge}"
        ]
        ++ lib.optional (cfg.journalVacuum.maxUse != null) "--vacuum-size=${cfg.journalVacuum.maxUse}"
      ) cfg.journalVacuum.intervalSeconds cfg.journalVacuum.timeoutSeconds;
    }
    // lib.optionalAttrs cfg.nixGc.enable {
      nix-gc = task [
        "${pkgs.nix}/bin/nix-collect-garbage"
        "--delete-older-than"
        cfg.nixGc.olderThan
      ] cfg.nixGc.intervalSeconds cfg.nixGc.timeoutSeconds;
    }
    // lib.optionalAttrs cfg.update.enable {
      update = task [
        "${pkgs.nix}/bin/nix"
        "flake"
        "update"
        "--flake"
        cfg.update.flake
      ] cfg.update.intervalSeconds cfg.update.timeoutSeconds;
    }
    // lib.optionalAttrs cfg.rebuild.enable {
      rebuild = task [
        "${pkgs.nixos-rebuild}/bin/nixos-rebuild"
        cfg.rebuild.action
        "--flake"
        cfg.rebuild.flake
      ] cfg.rebuild.intervalSeconds cfg.rebuild.timeoutSeconds;
    };
  configuration = pkgs.writeText "zenos-maintenance.json" (
    builtins.toJSON {
      version = 1;
      stateDir = "/var/lib/zenos-maintenance";
      guard = {
        inherit (cfg.guard)
          maxLoadPerCpu
          minMemoryAvailablePercent
          maxCpuPsiSomeAvg10
          maxMemoryPsiSomeAvg10
          requireAC
          ;
      };
      inherit tasks;
    }
  );
in
{
  options.zenos.maintenance = {
    enable = lib.mkEnableOption "guarded ZenOS maintenance";

    pollInterval = lib.mkOption {
      type = lib.types.str;
      default = "15m";
      description = "How often the dispatcher checks schedules and queued requests.";
    };

    guard = {
      maxLoadPerCpu = lib.mkOption {
        type = optionalNumber;
        default = 0.8;
        description = "Maximum one-minute load average per CPU, or null to disable.";
      };
      minMemoryAvailablePercent = lib.mkOption {
        type = optionalNumber;
        default = 20.0;
        description = "Minimum MemAvailable percentage, or null to disable.";
      };
      maxCpuPsiSomeAvg10 = lib.mkOption {
        type = optionalNumber;
        default = 25.0;
        description = "Maximum CPU PSI some avg10 value, or null to disable.";
      };
      maxMemoryPsiSomeAvg10 = lib.mkOption {
        type = optionalNumber;
        default = 10.0;
        description = "Maximum memory PSI some avg10 value, or null to disable.";
      };
      requireAC = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Only run maintenance while AC power is present.";
      };
    };

    journalVacuum = {
      enable = lib.mkEnableOption "automatic journal vacuuming" // {
        default = true;
      };
      intervalSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 86400;
      };
      timeoutSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 900;
      };
      maxAge = lib.mkOption {
        type = lib.types.strMatching "[1-9][0-9]*[smhdw]";
        default = "14d";
      };
      maxUse = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "1G";
      };
    };

    nixGc = {
      enable = lib.mkEnableOption "automatic Nix garbage collection" // {
        default = true;
      };
      intervalSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 604800;
      };
      timeoutSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 3600;
      };
      olderThan = lib.mkOption {
        type = lib.types.strMatching "[1-9][0-9]*[dhm]";
        default = "14d";
      };
    };

    update = {
      enable = lib.mkEnableOption "automatic flake lock updates (disabled by default)";
      flake = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      intervalSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 604800;
      };
      timeoutSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 3600;
      };
    };

    rebuild = {
      enable = lib.mkEnableOption "automatic guarded NixOS rebuilds (disabled by default)";
      flake = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      action = lib.mkOption {
        type = lib.types.enum [
          "build"
          "boot"
          "test"
          "switch"
        ];
        default = "switch";
      };
      intervalSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 604800;
      };
      timeoutSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 7200;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.update.enable || cfg.update.flake != null;
        message = "zenos.maintenance.update.flake must be set when automatic updates are enabled";
      }
      {
        assertion = !cfg.rebuild.enable || cfg.rebuild.flake != null;
        message = "zenos.maintenance.rebuild.flake must be set when automatic rebuilds are enabled";
      }
    ];

    environment.etc."zenos/maintenance.json".source = configuration;
    environment.systemPackages = [ ops ];

    systemd.tmpfiles.rules = [
      "d /var/lib/zenos-maintenance 0700 root root -"
      "d /var/lib/zenos-maintenance/requests 0700 root root -"
    ];

    systemd.services.zenos-maintenance = {
      description = "Guarded ZenOS maintenance dispatcher";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${ops}/bin/zenos-maintenance --config ${configuration} tick";
        StateDirectory = "zenos-maintenance";
        StateDirectoryMode = "0700";
        Nice = 10;
        IOSchedulingClass = "idle";
        SuccessExitStatus = [
          73
          75
        ];
        TimeoutStartSec = "3h";
      };
    };

    systemd.timers.zenos-maintenance = {
      description = "Periodically check guarded ZenOS maintenance";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "10m";
        OnUnitInactiveSec = cfg.pollInterval;
        Persistent = true;
        Unit = "zenos-maintenance.service";
      };
    };
  };
}
