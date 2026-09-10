# Evaluation-only fallback while the actual image's external pins are pending.
{ inputs, pkgs }:
let
  inherit (pkgs) lib;
  fixture = inputs.self // {
    inputs = builtins.removeAttrs inputs [ "self" ];
    nixosConfigurations.zenos-installer-iso = inputs.nixpkgs.lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      specialArgs.installerStage = "live";
      modules = [
        inputs.zenpkgs.nixosModules.default
        ({ installerStage, ... }: {
          nixpkgs.overlays = [ inputs.zenpkgs.overlays.default ];
          boot.isContainer = true;
          boot.kernelParams = [ "image-param" ];
          fileSystems."/" = {
            device = "fixture-root";
            fsType = "tmpfs";
          };
          system.stateVersion = "26.05";
          system.name = lib.mkForce "zenos-installer";
          system.nixos = {
            distroId = "zenos";
            distroName = "ZenOS";
            variant_id = "installer";
          };
          environment.etc."machine-info".text = ''PRETTY_HOSTNAME="Fixture Installer"'';
          environment.variables.ZENOS_LIVE_FORCE = lib.mkOverride 75 "image-value";
          environment.variables.ZENOS_LIVE_NESTED_TRUE = "image-value";
          environment.variables.ZENOS_LIVE_NESTED_FALSE = "image-value";
          networking = {
            hostName = "zenos-installer";
            networkmanager.enable = true;
            firewall.allowedTCPPorts = [
              22
              80
            ];
          };
          zenos.legacy.networking.extraHosts = "192.0.2.12 fixture.example";
          services.openssh.enable = lib.mkForce false;
           security.sudo.wheelNeedsPassword = lib.mkOverride 60 false;
          services.greetd.settings.default_session = {
            command = "${pkgs.coreutils}/bin/true";
            user = "zenos";
          };
          users.users.zenos = {
            isNormalUser = true;
            home = "/Users/zenos";
            hashedPassword = "";
            extraGroups = [ "wheel" ];
          };
          systemd.user.services.zenos-setup.serviceConfig.ExecStart = "${pkgs.coreutils}/bin/true";
          assertions = [
            {
              assertion = installerStage == "live";
              message = "Fixture stage changed";
            }
          ];
        })
      ];
    };
  };
  fixtureInputs = inputs // {
    self = fixture;
  };
  liveConfig = import ./live-config.nix {
    inputs = fixtureInputs;
    inherit pkgs;
  };
  valuesSeed = pkgs.runCommand "zenos-live-config-values-fixture" { } ''
    cp -r ${liveConfig.seed} "$out"
    chmod -R u+w "$out"
    cp ${./fixtures/live-config-values.zcfg} "$out/hosts/zenos-installer/values.zcfg"
    printf '\n_import "values.zcfg";\n' >> "$out/hosts/zenos-installer/host.zcfg"
  '';
  values = ((import (valuesSeed + "/flake.nix")).outputs {
    actualImage = fixture // {
      nixosConfigurations.zenos-installer-iso =
        fixture.nixosConfigurations.zenos-installer-iso.extendModules {
          # Isolate atomic package values from the pinned alias runtime's pkgs fixed point.
          specialArgs.pkgs = import inputs.nixpkgs {
            system = pkgs.stdenv.hostPlatform.system;
            overlays = [ inputs.zenpkgs.overlays.default ];
          };
        };
    };
    inherit (inputs) nixpkgs zenpkgs;
  }).nixosConfigurations.zenos-installer.config;
in
assert values.environment.variables.ZENOS_LIVE_FORCE == "local-force";
assert values.environment.variables.ZENOS_LIVE_NESTED_TRUE == "nested-true";
assert values.environment.variables.ZENOS_LIVE_NESTED_FALSE == "image-value";
assert lib.isFunction values.services.netdata.python.extraPackages;
assert values.services.netdata.python.extraPackages { inherit (pkgs) hello; } == [ pkgs.hello ];
assert values.nix.package == pkgs.nix;
assert values.boot.kernelParams == [ "zenos-live-first" ];
assert !values.services.desktopManager.gnome.enable;
assert !builtins.pathExists (liveConfig.seed + "/hosts/zenos-installer/desktop.zcfg");
import ./live-config-checks.nix {
  inputs = fixtureInputs;
  inherit pkgs liveConfig;
  desktopSource = null;
}
