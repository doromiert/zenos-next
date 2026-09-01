{
  nixpkgs,
  zenpkgs,
  system ? "x86_64-linux",
}:

let
  lib = nixpkgs.lib;
  pkgs = import nixpkgs {
    inherit system;
    overlays = [ zenpkgs.overlays.default ];
    config.allowUnfree = true;
  };
  platformModule = ../../modules/platform;
  evaluate =
    moduleConfig:
    lib.nixosSystem {
      inherit system;
      modules = [
        { nixpkgs.pkgs = pkgs; }
        platformModule
        ({ ... }: {
          system.stateVersion = "26.05";
          fileSystems."/" = {
            device = "none";
            fsType = "tmpfs";
          };
        })
        moduleConfig
      ];
    };
  disabled = evaluate { };
  hardware = evaluate {
    zenos.platform.hardware.enable = true;
  };
  connectionPackage = pkgs.writeShellScriptBin "zb-daemon" "exit 0";
  connection = evaluate {
    zenos.platform.connectionSuite = {
      enable = true;
      package = connectionPackage;
    };
  };
  connectionAutostartRejected = evaluate {
    zenos.platform.connectionSuite = {
      enable = true;
      package = connectionPackage;
      autoStart = true;
    };
  };
  xr = evaluate {
    zenos.platform.xr = {
      enable = true;
      command = [
        "${pkgs.coreutils}/bin/sleep"
        "1"
      ];
    };
  };
  refind = evaluate {
    zenos.platform.refind.enable = true;
  };
  failedAssertions =
    systemConfig: builtins.filter (assertion: !assertion.assertion) systemConfig.config.assertions;
  hasFailedAssertion =
    messageFragment: systemConfig:
    lib.any (assertion: lib.hasInfix messageFragment assertion.message) (failedAssertions systemConfig);
in
assert disabled.config.zenos.platform.hardware.enable == false;
assert disabled.config.zenos.platform.connectionSuite.enable == false;
assert disabled.config.zenos.platform.xr.enable == false;
assert disabled.config.zenos.platform.refind.enable == false;
assert hardware.config.systemd.services.zenos-hardware.wantedBy == [ "multi-user.target" ];
assert lib.hasInfix "/run/zenos-hardware/preset.json"
  hardware.config.systemd.services.zenos-hardware.serviceConfig.ExecStart;
assert connection.config.systemd.user.services.zenos-connection-suite.wantedBy == [ ];
assert connection.config.networking.firewall.allowedUDPPorts == [ ];
assert hasFailedAssertion "acknowledgeUnauthenticatedProtocol" connectionAutostartRejected;
assert xr.config.systemd.user.services.zenos-xr-supervisor.wantedBy == [ ];
assert !refind.config.boot.loader.refind.enable;
assert !refind.config.boot.loader.grub.enable;
assert refind.config.boot.loader.systemd-boot.enable;
assert refind.config.boot.loader.systemd-boot.configurationLimit == 10;
assert refind.config.boot.loader.timeout == 0;
assert !refind.config.boot.loader.efi.canTouchEfiVariables;
assert lib.hasInfix "refind-install --yes"
  refind.config.boot.loader.systemd-boot.extraInstallCommands;
assert lib.hasInfix "Syncing NixOS generations"
  refind.config.boot.loader.systemd-boot.extraInstallCommands;
{
  connectionManualStart =
    connection.config.systemd.user.services.zenos-connection-suite.wantedBy == [ ];
  disabledByDefault = true;
  refindActivationConfigured = true;
  xrManualStart = xr.config.systemd.user.services.zenos-xr-supervisor.wantedBy == [ ];
}
