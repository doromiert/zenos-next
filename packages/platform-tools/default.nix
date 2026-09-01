{
  pkgs,
  zerobridgeSource ? null,
}:

{
  zen-hardware = pkgs.callPackage ./zen-hardware { };
  zen-xr-supervisor = pkgs.callPackage ./xr-supervisor { };
}
// pkgs.lib.optionalAttrs (zerobridgeSource != null) {
  zenos-zerobridge = pkgs.callPackage ./zerobridge { source = zerobridgeSource; };
}
