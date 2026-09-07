{
  inputs,
  pkgs,
  lib,
}:
let
  # Pin every transitive input to its retained source, including non-flake assets.
  pin =
    input:
    {
      url = "path:${input.outPath}";
    }
    // (
      if input ? inputs then
        {
          inputs = builtins.mapAttrs (_: pin) input.inputs;
        }
      else
        { flake = false; }
    );
  pinnedInputs = {
    nixpkgs = pin inputs.nixpkgs;
    zenpkgs = pin inputs.zenpkgs;
    zenosSource = {
      url = "path:${inputs.self.outPath}";
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
