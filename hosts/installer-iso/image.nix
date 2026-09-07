{
  configTemplate,
  inputs,
  lib,
  modulesPath,
  pkgs,
  ...
}:
{
  imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix" ];

  networking.hostName = "zenos-installer";
  system.name = lib.mkForce "zenos-installer";
  system.nixos.variant_id = "installer";
  system.nixos.variantName = "ZenOS Installer";
  environment.etc."machine-info".text = ''
    PRETTY_HOSTNAME="ZenOS Installer"
  '';

  users.users.nixos.enable = lib.mkForce false;
  users.users.root.hashedPassword = lib.mkForce "!";
  services.getty.autologinUser = lib.mkForce null;
  services.openssh.enable = lib.mkForce false;
  nix.settings.trusted-users = [
    "root"
    "zenos"
  ];
  boot.zfs.forceImportRoot = false;

  environment.systemPackages = [
    inputs.zenpkgs.inputs.disko.packages.x86_64-linux.disko
    pkgs.nixos-install-tools
    pkgs.nixos-rebuild
    pkgs.parted
    pkgs.gptfdisk
    pkgs.dosfstools
    pkgs.e2fsprogs
    pkgs.btrfs-progs
    pkgs.cryptsetup
    pkgs.git
    pkgs.openssl
    pkgs.gparted
    pkgs.gnome-disk-utility
  ];
  system.extraDependencies = [ configTemplate ];
  systemd.tmpfiles.rules = [
    "L+ /iso-config-template - - - - ${configTemplate}"
  ];

  isoImage = {
    edition = "zenos";
    volumeID = "ZENOS_INSTALLER";
    makeEfiBootable = true;
    makeUsbBootable = true;
    squashfsCompression = "zstd -Xcompression-level 6";
  };
  image.baseName = lib.mkForce "zenos-installer";
}
