{ config, lib, ... }:
let
  gdmGreeterUsers = [
    "gdm-greeter"
    "gdm-greeter-2"
    "gdm-greeter-3"
    "gdm-greeter-4"
    "gdm-greeter-5"
  ];
in
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
    autoLogin = {
      enable = lib.mkForce false;
      user = lib.mkForce null;
    };
    gdm = {
      enable = lib.mkDefault true;
      settings.daemon = {
        AutomaticLoginEnable = lib.mkForce false;
        TimedLoginEnable = lib.mkForce false;
      };
    };
  };

  systemd.tmpfiles.rules = lib.optionals config.services.displayManager.gdm.enable (
    [ "d /var/lib/AccountsService/users 0755 root root -" ]
    ++ map (
      user: "f+ /var/lib/AccountsService/users/${user} 0644 root root - [User]\\nSystemAccount=true\\n"
    ) gdmGreeterUsers
  );
}
