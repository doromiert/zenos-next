{
  configTemplate,
  liveConfig,
  inputs,
  lib,
  modulesPath,
  pkgs,
  ...
}:
let
  configHash = builtins.substring 0 7 (builtins.hashString "sha256" inputs.self.sourceInfo.narHash);
  bootHooks = import (inputs.zenpkgs + "/lib/installer-boot.nix") {
    inherit pkgs lib;
    bootPackage = pkgs.zenos.theming.system.zenos-plymouth.override {
      distroName = "ZenOS";
      releaseVersion = "1.0.0Nb (${configHash})";
      deviceName = "ZenOS Installer";
    };
    refindInstaller = pkgs.zenos.system.zenos-refind-installer;
    refindTheme = pkgs.zenos.theming.system.zenos-refind-theme;
  };
in
{
  imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix" bootHooks.iso ];

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
    pkgs.zenos.system.zenos-recovery-tools
    pkgs.zenos.apps.utilities.resources
    pkgs.zenos.apps.system.btop
    pkgs.zenos.apps.system.eza
    pkgs.zenos.apps.development-tools.nano
    pkgs.zenos.apps.development.neovim
  ] ++ builtins.attrValues pkgs.zenos.apps.recovery;
  environment.shellAliases.vim = "nvim";
  environment.shellAliases.ls = "eza";
  services.spice-vdagentd.enable = true;
  services.qemuGuest.enable = true;
  virtualisation.vmware.guest.enable = true;
  virtualisation.hypervGuest.enable = true;
  services.xe-guest-utilities.enable = true;
  systemd.services.xe-daemon.unitConfig.ConditionVirtualization = "xen";
  services.xserver.enable = true;
  powerManagement.enable = true;
  security.unprivilegedUsernsClone = true;
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (subject.isInGroup("wheel")) return polkit.Result.YES;
    });
  '';
  system.extraDependencies = [
    configTemplate
    liveConfig.seed
    inputs.zenpkgs.packages.x86_64-linux.dsl-bundle
  ] ++ liveConfig.sources;
  systemd.tmpfiles.rules = [
    "L+ /iso-config-template - - - - ${configTemplate}"
    "L+ /iso-config - - - - ${configTemplate}"
    "d /mnt/recovery 0755 root root -"
    "d /run/zenos-recovery 0700 zenos users -"
  ];
  system.activationScripts.zenos-live-config = {
    deps = [ "users" "etc" ];
    text = ''
      target=/etc/ZenOS
      if [ -L "$target" ]; then
        echo "Keeping redirected live configuration: $target" >&2
      elif [ -e "$target" ] && [ ! -d "$target" ]; then
        echo "Refusing to replace live configuration path: $target" >&2
        exit 1
      elif [ ! -d "$target" ] || [ -z "$(${pkgs.findutils}/bin/find "$target" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
        ${pkgs.coreutils}/bin/install -d -m 0755 -o zenos -g users "$target"
        ${pkgs.coreutils}/bin/cp -r --no-preserve=ownership ${liveConfig.seed}/. "$target/"
        ${pkgs.coreutils}/bin/chown -R --no-dereference zenos:users "$target"
        ${pkgs.coreutils}/bin/chmod -R u+rwX "$target"
      fi
    '';
  };

  isoImage = {
    edition = "zenos";
    volumeID = "ZENOS_INSTALLER";
    storeContents = [
      configTemplate
      liveConfig.seed
      inputs.zenpkgs.packages.x86_64-linux.dsl-bundle
    ] ++ liveConfig.sources;
    makeEfiBootable = true;
    makeUsbBootable = true;
    squashfsCompression = "zstd -Xcompression-level 6";
  };
  image.baseName = lib.mkForce "zenos-installer";
}
