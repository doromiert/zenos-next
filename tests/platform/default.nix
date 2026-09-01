{
  nixpkgs,
  zenpkgs,
  system ? "x86_64-linux",
}:

let
  pkgs = import nixpkgs {
    inherit system;
    overlays = [ zenpkgs.overlays.default ];
    config.allowUnfree = true;
  };
  evaluation = import ./eval.nix { inherit nixpkgs system zenpkgs; };
in
pkgs.runCommand "zenos-platform-tests"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    passthru = { inherit evaluation; };
  }
  ''
    export REFIND_SCRIPT=${../../scripts/refind.py}
    export REFIND_THEME=${../../assets/refind/themes/zenos-picker/theme.conf}
    export ZEN_HARDWARE_SCRIPT=${../../packages/platform-tools/zen-hardware/zen_hardware.py}
    export ZEN_HARDWARE_DATABASE=${../../packages/platform-tools/zen-hardware/presets.json}
    export ZEN_XR_SUPERVISOR_SCRIPT=${../../packages/platform-tools/xr-supervisor/zen_xr_supervisor.py}
    python -m unittest discover -s ${./.} -p 'test_*.py' -v
    touch "$out"
  ''
