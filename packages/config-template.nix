{
  inputs,
  lib,
  stdenvNoCC,
}:

let
  collectInputSources =
    input:
    if builtins.isAttrs input then
      lib.optional (input ? outPath) input.outPath
      ++ lib.concatMap collectInputSources (builtins.attrValues (input.inputs or { }))
    else
      lib.optional (builtins.isPath input) input;
  inputSources = lib.unique (
    lib.concatMap collectInputSources [
      inputs.nixpkgs
      inputs.disko
      # inputs.popcorn
      inputs.zenpkgs
      inputs.zenos-setup
      inputs.zenos-oobe-mode
      inputs.self
    ]
  );
  sourceRevision = builtins.substring 0 7 (inputs.self.rev or (inputs.self.dirtyRev or "unknown"));
  offlineSourceReferences = lib.concatMapStringsSep "\n" (source: "# ${source}") inputSources;
  flake = builtins.toFile "zenos-installed-config-flake.nix" ''
    # Store references retained for offline lock generation:
    ${offlineSourceReferences}
    {
      description = "ZenOS installed system configuration";

      inputs = {
        nixpkgs.url = "path:${inputs.nixpkgs.outPath}";

        disko = {
          url = "path:${inputs.disko.outPath}";
          inputs.nixpkgs.follows = "nixpkgs";
        };

        # popcorn = {
        #   url = "path:<popcorn-out-path>";
        # };

        zenpkgs = {
          url = "path:${inputs.zenpkgs.outPath}";
          inputs.nixpkgs.follows = "nixpkgs";
        };

        zenos-setup = {
          url = "path:${inputs.zenos-setup.outPath}";
          inputs.nixpkgs.follows = "nixpkgs";
        };

        zenos-oobe-mode = {
          url = "path:${inputs.zenos-oobe-mode}";
          flake = false;
        };

        zenosSource = {
          url = "path:${inputs.self.outPath}";
          flake = false;
        };
      };

      outputs =
        inputs@{
          nixpkgs,
          disko,
          # popcorn,
          zenpkgs,
          zenos-oobe-mode,
          zenos-setup,
          zenosSource,
          ...
        }:
        let
          system = "x86_64-linux";
          lib = nixpkgs.lib;
          hostEntries = if builtins.pathExists ./hosts then builtins.readDir ./hosts else { };
          hostNames = builtins.filter (
            name:
            let
              hostDir = ./hosts + ("/" + name);
            in
            builtins.getAttr name hostEntries == "directory"
            && builtins.pathExists (hostDir + "/host.nix")
          ) (builtins.attrNames hostEntries);
          inputPath = input: if builtins.isAttrs input then input.outPath else input;
          extensionManifest = builtins.fromJSON (
            builtins.readFile ((inputPath zenos-setup) + "/data/gnome-extensions.json")
          );

          mkSetupPackage =
            pkgs:
            (builtins.getAttr system zenos-setup.packages).zenos-install.overrideAttrs (old: {
              buildInputs = (old.buildInputs or [ ]) ++ [
                pkgs.gnome-desktop
              ];
              meta = (old.meta or { }) // {
                mainProgram = "zenos-setup";
              };
            });

          mkOobeExtension =
            pkgs:
            let
              extensionUuid = "zenos-oobe-mode@neg-zero.com";
            in
            pkgs.stdenvNoCC.mkDerivation {
              pname = "gnome-shell-extension-zenos-oobe-mode";
              version = "1.0.0";
              src = zenos-oobe-mode;
              dontBuild = true;

              installPhase = builtins.concatStringsSep "\n" [
                "runHook preInstall"
                ("install -d \"$out/share/gnome-shell/extensions/" + extensionUuid + "\"")
                ("install -m 0644 extension.js metadata.json \"$out/share/gnome-shell/extensions/" + extensionUuid + "/\"")
                "install -d \"$out/share/gnome-shell/modes\""
                "install -m 0644 zenos-oobe.json \"$out/share/gnome-shell/modes/zenos-oobe.json\""
                "runHook postInstall"
              ];

              meta = {
                description = "GNOME Shell mode for the ZenOS out-of-box experience";
                license = zenpkgs.lib.utils.licenses.napalm;
                platforms = lib.platforms.linux;
              };
            };

          mkZcfgPackage = pkgs: pkgs.callPackage (zenosSource + "/packages/zen-dsl.nix") { };
          mkAppIndex = pkgs: pkgs.callPackage (zenosSource + "/packages/app-index") { };
          mkNautilusApps =
            pkgs:
            pkgs.callPackage (zenosSource + "/packages/nautilus-apps") {
              appIndex = mkAppIndex pkgs;
            };

          mkHost =
            hostName:
            let
              hostDir = ./hosts + ("/" + hostName);
              oobeEnabled = builtins.pathExists (hostDir + "/oobe.json");
            in
            lib.nixosSystem {
              inherit system;
              specialArgs = { inherit inputs; };
              modules = [
                zenpkgs.nixosModules.interface
                zenpkgs.nixosModules.installed-base
                zenpkgs.nixosModules.oobe
                zenpkgs.nixosModules.webapps
                zenpkgs.nixosModules.desktops.gnome.tweaks.firefox-theming."module.nix"
                disko.nixosModules.disko
                (zenosSource + "/modules/gnome-profile.nix")
                (zenosSource + "/modules/platform/refind.nix")
                (zenosSource + "/modules/zenfs")
                (
                  { config, pkgs, ... }:
                  let
                    resolveExtension = entry: lib.getAttrFromPath entry.packagePath pkgs;
                    extensionPackages = map resolveExtension extensionManifest;
                    liveExtensions = map resolveExtension (
                      builtins.filter (entry: entry.liveEnabled) extensionManifest
                    );
                    recommendedExtensionIds = map (entry: entry.id) (
                      builtins.filter (entry: entry.recommended) extensionManifest
                    );
                    selectedExtensions = map resolveExtension (
                      builtins.filter (
                        entry: lib.elem entry.id config.zenos.gnomeProfile.extensionIds
                      ) extensionManifest
                    );
                  in
                  {
                    nixpkgs.overlays = [ zenpkgs.overlays.default ];
                    zenos.system.release.revision = lib.mkDefault "${sourceRevision}";
                    zenos.platform.refind.enable = true;
                    zenfs.enable = true;
                    zenfs.users = lib.optionalAttrs oobeEnabled {
                      "''${config.zenos.oobe.userName}" = {
                        home = config.users.users.''${config.zenos.oobe.userName}.home;
                        group = config.users.users.''${config.zenos.oobe.userName}.group;
                      };
                    };
                    zenos.gnomeProfile = {
                      inherit extensionPackages;
                      extensionIds = lib.mkDefault recommendedExtensionIds;
                      enabledExtensionUuids = map (extension: extension.extensionUuid) selectedExtensions;
                      manageExtensions = !oobeEnabled;
                      wallpaper = "''${pkgs.zenos.theming.wallpapers.destination-2}/share/backgrounds/destination-2/purple dark.png";
                    };
                    system.extraDependencies = map inputPath [
                      nixpkgs
                      disko
                      # popcorn
                      zenpkgs
                      zenos-setup
                      zenos-oobe-mode
                      zenosSource
                    ];
                     zenos.oobe = {
                       enable = oobeEnabled;
                    }
                    // lib.optionalAttrs oobeEnabled {
                      setupPackage = mkSetupPackage pkgs;
                      extensionPackage = mkOobeExtension pkgs;
                      extraExtensionPackages = liveExtensions;
                      extraExtensionUuids = map (extension: extension.extensionUuid) liveExtensions;
                      authorizedKeys = [
                        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH4+fQMTy7FaLwqDOumL1y3uW+WMWpoc12MEeQXeF+VF zenos-next-vm-debug"
                       ];
                     };
                    services.greetd.enable = lib.mkIf (!oobeEnabled) (lib.mkForce false);
                    services.getty.autologinUser = lib.mkIf (!oobeEnabled) (lib.mkForce null);
                    environment.systemPackages = [
                      (mkNautilusApps pkgs)
                      (mkZcfgPackage pkgs)
                      pkgs.zenos.apps.system.gnome-console
                      pkgs.zenos.apps.system.nautilus-python
                      pkgs.zenos.programs.zenos-rebuild
                    ]
                    ;
                    environment.pathsToLink = [ "/share/nautilus-python/extensions" ];
                    xdg.mime.defaultApplications."application/x-desktop" =
                      "com.negzero.zenos.AppLauncher.desktop";
                    systemd.user.services.zenos-oobe.environment.ZENOS_SETUP_DRY_RUN =
                      lib.mkIf oobeEnabled "0";
                    systemd.user.services.zenos-oobe.environment.ZENOS_WALLPAPER_FILE =
                      lib.mkIf oobeEnabled "''${pkgs.zenos.theming.wallpapers.destination-2}/share/backgrounds/destination-2/purple dark.png";
                    assertions = [
                      {
                        assertion = config.fileSystems ? "/";
                        message = "ZenOS installed hosts must declare the root filesystem";
                      }
                    ];
                  }
                )
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
        in
        {
          nixosConfigurations = lib.genAttrs hostNames mkHost;
        };
    }
  '';
in
stdenvNoCC.mkDerivation {
  pname = "zenos-config-template";
  version = "1.0.0";
  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm0644 ${flake} "$out/flake.nix"
    runHook postInstall
  '';

  meta = {
    description = "Clean installed-system configuration template for ZenOS";
    license = lib.licenses.napalm;
    platforms = lib.platforms.linux;
  };
}
