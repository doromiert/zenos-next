{
  description = "ZenOS next-generation base system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # popcorn.url = "github:zenos-n/popcorn";

    zenpkgs = {
      url = "github:zenos-n/zenpkgs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zenos-setup = {
      url = "github:zenos-n/zenos-setup";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zenos-oobe-mode = {
      url = "github:zenos-n/zenos-oobe-mode-extension";
      flake = false;
    };

    zenos-plymouth-assets = {
      url = "github:zenos-n/plymouth-theme";
      flake = false;
    };

    zerobridge = {
      url = "github:doromiert/zerobridge";
      flake = false;
    };
  };

  outputs =
    inputs@{ self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ inputs.zenpkgs.overlays.default ];
        config.allowUnfree = true;
      };

      zenpkgsIntegration = {
        imports = [ inputs.zenpkgs.nixosModules.interface ];
        nixpkgs.overlays = [ inputs.zenpkgs.overlays.default ];
        nix.registry.zenpkgs.flake = inputs.zenpkgs;
      };

      coreModules = [
        ./modules/zenfs
        ./modules/maintenance
        ./modules/janitor
        ./modules/platform
      ];

      platformTools = import ./packages/platform-tools {
        inherit pkgs;
        zerobridgeSource = inputs.zerobridge;
      };

      configTemplate = pkgs.callPackage ./packages/config-template.nix { inherit inputs; };

      installedHostNames =
        if builtins.pathExists ./hosts then
          builtins.filter (
            name:
            let
              hostDir = ./hosts + "/${name}";
            in
            (builtins.readDir ./hosts).${name} == "directory" && builtins.pathExists (hostDir + "/host.nix")
          ) (builtins.attrNames (builtins.readDir ./hosts))
        else
          [ ];

      mkInstalledHost =
        hostName:
        let
          hostDir = ./hosts + "/${hostName}";
        in
        lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules =
            coreModules
            ++ [
              zenpkgsIntegration
              inputs.disko.nixosModules.disko
              ./modules/installed-base.nix
              (
                { pkgs, ... }:
                import (hostDir + "/host.nix") { inherit pkgs; }
              )
            ]
            ++ lib.optional (builtins.pathExists (hostDir + "/hardware-configuration.nix")) (
              hostDir + "/hardware-configuration.nix"
            );
          # Popcorn disabled: re-enable the generated kernel module import with the flake input.
          # ++ lib.optional (builtins.pathExists (hostDir + "/kernel.nix")) (hostDir + "/kernel.nix");
        };

      zenosOobeVm = lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          zenpkgsIntegration
          ./modules/base.nix
          ./modules/oobe.nix
        ]
        ++ coreModules
        ++ [
          ./profiles/vm.nix
        ];
      };

      zenosInstallerIso = lib.nixosSystem {
        inherit system;
        specialArgs = { inherit configTemplate inputs; };
        modules = [
          zenpkgsIntegration
          ./modules/base.nix
        ]
        ++ coreModules
        ++ [
          ./profiles/installer-iso.nix
        ];
      };

      forceEvalCheck = name: value: builtins.deepSeq value (pkgs.runCommand name { } "touch $out");

      pythonCheck =
        name: suite: extraEnv:
        pkgs.runCommand name { nativeBuildInputs = [ pkgs.python3 ]; } ''
          export PYTHONDONTWRITEBYTECODE=1
          ${extraEnv}
          python -m unittest discover -s ${./tests}/${suite} -p 'test_*.py' -v
          touch "$out"
        '';
    in
    {
      nixosModules = {
        base = import ./modules/base.nix;
        oobe = import ./modules/oobe.nix;
        zenfs = import ./modules/zenfs;
        maintenance = import ./modules/maintenance;
        janitor = import ./modules/janitor;
        gnome-profile = import ./modules/gnome-profile.nix;
        platform = import ./modules/platform;
        platform-hardware = import ./modules/platform/hardware.nix;
        platform-connection-suite = import ./modules/platform/connection-suite.nix;
        platform-refind = import ./modules/platform/refind.nix;
        platform-xr-supervisor = import ./modules/platform/xr-supervisor.nix;
        default = self.nixosModules.base;
      };

      nixosConfigurations = lib.genAttrs installedHostNames mkInstalledHost // {
        zenos-oobe-vm = zenosOobeVm;
        zenos-installer-iso = zenosInstallerIso;
      };

      packages.${system} = platformTools // {
        config-template = configTemplate;
        vm = zenosOobeVm.config.system.build.vm;
        iso = zenosInstallerIso.config.system.build.isoImage;
        zen-dsl = pkgs.callPackage ./packages/zen-dsl.nix { };
        zenfsctl = pkgs.callPackage ./packages/zenfsctl { };
        zenos-ops = pkgs.callPackage ./packages/zenos-ops { };
        recovery-tools = pkgs.callPackage ./packages/recovery-tools { };
        app-index = pkgs.callPackage ./packages/app-index { };
        nautilus-apps = pkgs.callPackage ./packages/nautilus-apps {
          appIndex = self.packages.${system}.app-index;
        };
        default = self.packages.${system}.vm;
      };

      apps.${system} = {
        vm = {
          type = "app";
          program = "${zenosOobeVm.config.system.build.vm}/bin/run-zenos-oobe-vm";
        };
        zen-dsl = {
          type = "app";
          program = lib.getExe self.packages.${system}.zen-dsl;
        };
        default = self.apps.${system}.vm;
      };

      checks.${system} = {
        config-template = import ./tests/config-template {
          inherit configTemplate pkgs;
        };
        iso-version =
          assert lib.hasPrefix "1.0.0Nb-" zenosInstallerIso.config.system.nixos.label;
          assert zenosInstallerIso.config.isoImage.grubTheme != null;
          assert lib.hasInfix "#FFC532FF" zenosInstallerIso.config.isoImage.syslinuxTheme;
          pkgs.runCommand "zenos-iso-version-check" { } "touch $out";
        vm-system = zenosOobeVm.config.system.build.toplevel;
        installer-iso-system = zenosInstallerIso.config.system.build.toplevel;
        zen-dsl = self.packages.${system}.zen-dsl;
        zenfsctl = self.packages.${system}.zenfsctl;
        zenos-ops = self.packages.${system}.zenos-ops;
        platform =
          builtins.deepSeq
            (import ./tests/platform/eval.nix {
              inherit nixpkgs system;
              zenpkgs = inputs.zenpkgs;
            })
            (
              import ./tests/platform {
                inherit nixpkgs system;
                zenpkgs = inputs.zenpkgs;
              }
            );
        zenfs-eval = forceEvalCheck "zenfs-evaluation" (
          import ./tests/zenfs/eval.nix {
            inherit nixpkgs system;
            zenpkgs = inputs.zenpkgs;
          }
        );
        zenfs-unit = pythonCheck "zenfs-unit-tests" "zenfs" ''
          export ZENFSCTL_SCRIPT=${./packages/zenfsctl/zenfsctl.py}
        '';
        ops-unit = pythonCheck "zenos-ops-unit-tests" "ops" ''
          export ZENOS_OPS_SOURCE=${./packages/zenos-ops}
        '';
        platform-unit = pythonCheck "zenos-platform-unit-tests" "platform" ''
           export REFIND_SCRIPT=${./scripts/refind.py}
           export REFIND_THEME=${./assets/refind/themes/zenos-picker/theme.conf}
          export ZEN_HARDWARE_SCRIPT=${./packages/platform-tools/zen-hardware/zen_hardware.py}
          export ZEN_HARDWARE_DATABASE=${./packages/platform-tools/zen-hardware/presets.json}
          export ZEN_XR_SUPERVISOR_SCRIPT=${./packages/platform-tools/xr-supervisor/zen_xr_supervisor.py}
        '';
        app-index-unit = pythonCheck "zenos-app-index-unit-tests" "app-index" ''
          export PYTHONPATH=${./packages/app-index}:${./packages/nautilus-apps}
        '';
        nautilus-apps-unit =
          pkgs.runCommand "zenos-nautilus-apps-unit-tests"
            {
              nativeBuildInputs = [
                pkgs.python3
                pkgs.python3Packages.pygobject3
                pkgs.gobject-introspection
                pkgs.gtk4
                pkgs.zenos.apps.system.nautilus
                pkgs.zenos.apps.system.nautilus-python
              ];
            }
            ''
              python -m py_compile ${./packages/nautilus-apps/zenos_apps.py}
              python -m py_compile ${./packages/nautilus-apps/zen_app_launch.py}
              python -m py_compile ${./packages/nautilus-apps/zen_app_icons.py}
              export GI_TYPELIB_PATH=${pkgs.zenos.apps.system.nautilus}/lib/girepository-1.0:''${GI_TYPELIB_PATH:-}
              python - <<'PY'
              import gi
              import importlib.util

              gi.require_version("Gtk", "4.0")
              gi.require_version("Nautilus", "4.1")
              spec = importlib.util.spec_from_file_location(
                  "zenos_apps", "${./packages/nautilus-apps/zenos_apps.py}"
              )
              module = importlib.util.module_from_spec(spec)
              spec.loader.exec_module(module)
              from gi.repository import Nautilus

              menu = Nautilus.Menu()
              Nautilus.MenuItem(name="ZenOSApps::ApiCheck", label="API Check", menu=menu, sensitive=True)
              assert module.ZenOSAppsExtension
              PY
              touch "$out"
            '';
        setup-unit = pkgs.runCommand "zenos-setup-unit-tests" { nativeBuildInputs = [ pkgs.python3 ]; } ''
          export PYTHONDONTWRITEBYTECODE=1
          export PYTHONPATH=${inputs.zenos-setup}
          python -m unittest discover -s ${inputs.zenos-setup}/tests -p 'test_*.py' -v
          touch "$out"
        '';
        setup-zcfg-contract =
          pkgs.runCommand "zenos-setup-zcfg-contract"
            {
              nativeBuildInputs = [ pkgs.python3 ];
            }
            ''
              export PYTHONDONTWRITEBYTECODE=1
              export PYTHONPATH=${./tools/zen-dsl}
              export ZENOS_SETUP_SOURCE=${inputs.zenos-setup}
              python -m unittest discover -s ${./tests/setup} -p 'test_*.py' -v
              touch "$out"
            '';
      };

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree;
    };
}
