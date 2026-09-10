{ inputs, configRoot }:
let
  inherit (inputs)
    nixpkgs
    zenpkgs
    setup-hardware
    zenosSource
    ;
  system = "x86_64-linux";
  lib = nixpkgs.lib;
  pkgs = import nixpkgs { inherit system; };
  entries =
    if builtins.pathExists (configRoot + "/hosts") then
      builtins.readDir (configRoot + "/hosts")
    else
      { };
  names = builtins.filter (
    name:
    entries.${name} == "directory" && builtins.pathExists (configRoot + "/hosts/${name}/host.zcfg")
  ) (builtins.attrNames entries);
  sources =
    input: [ input.outPath ] ++ lib.concatMap sources (builtins.attrValues (input.inputs or { }));
in
{
  nixosConfigurations = lib.genAttrs names (
    name:
    let
      host = configRoot + "/hosts/${name}";
      hardwareMetadata = if builtins.pathExists (host + "/hardware.json") then
        builtins.fromJSON (builtins.readFile (host + "/hardware.json")) else null;
      hardwareReferences = lib.optional (hardwareMetadata != null) (
        assert lib.assertMsg (
          builtins.isAttrs hardwareMetadata
          && (hardwareMetadata.version or null) == 1
          && builtins.isString (hardwareMetadata.storePath or null)
          && builtins.match "/nix/store/[a-z0-9]{32}-zenos-setup-hardware" hardwareMetadata.storePath != null
          && (hardwareMetadata.sha256 or null) == builtins.hashString "sha256"
            (builtins.readFile (setup-hardware + "/hardware-configuration.nix"))
        ) "Invalid Setup hardware metadata for ${name}";
        # fetchTree renames the input to -source; Setup still needs its original path.
        builtins.appendContext hardwareMetadata.storePath {
          ${hardwareMetadata.storePath} = { path = true; };
        }
      );
      marker = if builtins.pathExists (host + "/oobe.json") then
        builtins.fromJSON (builtins.readFile (host + "/oobe.json")) else null;
      oobe = if marker == null then false else
        assert lib.assertMsg (
          builtins.isAttrs marker
          && (marker.version or null) == 3
          && builtins.elem (marker.status or null) [ "pending" "complete" ]
          && (marker.status == "pending" -> (marker.temporaryHost or null) == name)
        ) "Invalid Setup marker for ${name}: expected version 3 and a matching pending temporaryHost";
        marker.status == "pending";
      generated =
        pkgs.runCommand "zenos-installed-${name}.nix"
          {
            nativeBuildInputs = [ zenpkgs.packages.${system}.zen-dsl (pkgs.lib.getBin pkgs.nix) ];
            src = configRoot;
            hostName = name;
          }
          ''
            zen-dsl check "$src/hosts/$hostName/host.zcfg" --import-root "$src"
            zen-dsl compile "$src/hosts/$hostName/host.zcfg" --import-root "$src" -o "$out"
            export NIX_REMOTE="local?root=$TMPDIR/parse-store"
            nix-store --init
            nix-instantiate --parse "$out" > /dev/null
          '';
    in
    lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit inputs;
        installerStage = if oobe then "oobe" else "desktop";
      };
      modules = [
        zenpkgs.nixosModules.default
        (zenosSource + "/hosts/installer-iso/system.nix")
        (import generated)
        (setup-hardware + "/hardware-configuration.nix")
        ({ config, ... }: {
          networking.hostName = lib.mkDefault name;
          system.build.zenosGeneratedConfig = generated;
          system.extraDependencies = [ configRoot generated ] ++ hardwareReferences ++ lib.unique (
            lib.concatMap sources [
              nixpkgs
              zenpkgs
              zenosSource
              setup-hardware
            ]
          );
          assertions = [
            {
              assertion = config.fileSystems ? "/";
              message = "Setup must provide the detected root filesystem";
            }
            {
              assertion = config.fileSystems ? "/boot" && config.fileSystems."/boot".fsType == "vfat";
              message = "This installer requires a FAT EFI system partition mounted at /boot";
            }
          ];
        })
      ];
    }
  );
}
