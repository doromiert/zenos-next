{
  inputs,
  pkgs,
  lib,
}:
let
  revision = name: input:
    let value = input.rev or input.dirtyRev or null;
    in assert lib.assertMsg (
      builtins.isString value && builtins.match "[0-9a-f]{40}" value != null
    ) "${name} must have an immutable 40-character Git revision";
    value;
  pinnedInputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/${revision "nixpkgs" inputs.nixpkgs}";
    zenpkgs = {
      url = "github:zenos-n/zenpkgs/${revision "zenpkgs" inputs.zenpkgs}";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zenosSource = {
      url = "github:doromiert/zenos-next/${revision "zenos-next" inputs.self}";
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
