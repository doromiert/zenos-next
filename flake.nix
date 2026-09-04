{
  description = "ZenOS host and image compositions";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    zenpkgs = {
      url = "github:zenos-n/zenpkgs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, zenpkgs }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      hostEntries = builtins.readDir ./hosts;
      hostNames = builtins.filter (
        name:
        hostEntries.${name} == "directory"
        && builtins.pathExists (./hosts + "/${name}/host.zcfg")
      ) (builtins.attrNames hostEntries);
      mkHost =
        name:
        let
          source = ./hosts + "/${name}";
          generated = pkgs.runCommand "zenos-host-${name}.nix" {
            nativeBuildInputs = [ zenpkgs.packages.${system}.zen-dsl ];
            src = source;
          } ''
            zen-dsl compile "$src/host.zcfg" --import-root "$src" -o "$out"
          '';
        in
        lib.nixosSystem {
          inherit system;
          modules = [
            {
              nixpkgs.overlays = [ zenpkgs.overlays.default ];
            }
            zenpkgs.nixosModules.default
            (import generated)
          ];
        };
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ zenpkgs.overlays.default ];
        config.allowUnfree = true;
      };
    in
    {
      nixosConfigurations = lib.genAttrs hostNames mkHost;

      checks.${system}.repository-structure =
        pkgs.runCommand "zenos-next-repository-structure" { src = self; } ''
          required='AGENTS.md LICENSE docs flake.lock flake.nix hosts readme.md'
          allowed="$required .git .gitignore"

          for name in AGENTS.md LICENSE flake.lock flake.nix readme.md; do
            if [ ! -f "$src/$name" ] || [ -L "$src/$name" ]; then
              echo "required zenos-next root file is missing or invalid: $name" >&2
              exit 1
            fi
          done
          for name in docs hosts; do
            if [ ! -d "$src/$name" ] || [ -L "$src/$name" ]; then
              echo "required zenos-next root directory is missing or invalid: $name" >&2
              exit 1
            fi
          done
          if [ -e "$src/.gitignore" ] && { [ ! -f "$src/.gitignore" ] || [ -L "$src/.gitignore" ]; }; then
            echo "zenos-next .gitignore must be a regular file" >&2
            exit 1
          fi
          if [ -e "$src/.git" ] && { [ ! -d "$src/.git" ] || [ -L "$src/.git" ]; }; then
            echo "zenos-next .git must be a directory" >&2
            exit 1
          fi

          for entry in "$src"/* "$src"/.[!.]* "$src"/..?*; do
            [ -e "$entry" ] || [ -L "$entry" ] || continue
            name="''${entry##*/}"
            case " $allowed " in
              *" $name "*) ;;
              *) echo "forbidden zenos-next root entry: $name" >&2; exit 1 ;;
            esac
            if [ -L "$entry" ]; then
              echo "symlinked zenos-next root entry is forbidden: $name" >&2
              exit 1
            fi
          done

          touch "$out"
        '';

      formatter.${system} = pkgs.nixfmt-tree;
    };
}
