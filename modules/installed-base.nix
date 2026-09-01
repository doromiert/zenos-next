{ config, lib, ... }:
{
  system.stateVersion = "26.05";

  system.nixos = {
    distroId = "zenos";
    distroName = "ZenOS";
    vendorId = "zenos";
    vendorName = "ZenOS";
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  networking.networkmanager.enable = lib.mkDefault true;
  security = {
    rtkit.enable = lib.mkDefault true;
    sudo.wheelNeedsPassword = lib.mkDefault false;
  };

  services.pipewire = {
    enable = lib.mkDefault true;
    alsa.enable = lib.mkDefault true;
    pulse.enable = lib.mkDefault true;
  };

  programs.dconf.enable = lib.mkDefault true;
  hardware.enableRedistributableFirmware = lib.mkDefault true;

  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;
  zenos.platform.refind.enable = lib.mkDefault true;

  services.displayManager = lib.mkIf config.zenos.desktops.gnome.enable {
    gdm.enable = lib.mkDefault true;
    defaultSession = lib.mkDefault "gnome";
  };
}
