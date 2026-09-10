# Compile with the bootstrap package set, before collecting NixOS modules.
{ inputs, pkgs }:
let
  generated = pkgs.runCommand "zenos-live-appearance.nix" {
    nativeBuildInputs = [ inputs.zenpkgs.packages.${pkgs.stdenv.hostPlatform.system}.zen-dsl ];
    src = ./appearance.zcfg;
  } ''
    zen-dsl compile "$src" --import-root "$(dirname "$src")" -o "$out"
  '';
in
{ installerStage, ... }:
{
  imports = [ (import generated) ./appearance.nix ];
  assertions = [{ assertion = installerStage == "live"; message = "appearance-hook.nix belongs only to the live installer image"; }];
}
