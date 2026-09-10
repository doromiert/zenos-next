{
  inputs,
  pkgs,
  lib,
}:
let
  pinnedInputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    zenpkgs = {
      url = "github:zenos-n/zenpkgs/migration/path-derived-dsl";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zenosSource = {
      url = "github:doromiert/zenos-next/main";
      flake = false;
    };
    setup-hardware = {
      url = "path:@ZENOS_SETUP_HARDWARE@";
      flake = false;
    };
  };
in
pkgs.writeTextDir "flake.nix" ''
  {
    description = "ZenOS installed system configuration";
    inputs = ${lib.generators.toPretty { } pinnedInputs};
    outputs = inputs:
      import (inputs.zenosSource + "/hosts/installer-iso/installed-hosts.nix") {
        inherit inputs;
        configRoot = ./.;
      };
  }
''
