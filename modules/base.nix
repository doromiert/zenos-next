{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  commitId = inputs.self.shortRev or inputs.self.dirtyShortRev or "unknown";
  gnomeSessionCommand = "${pkgs.coreutils}/bin/env XDG_SESSION_TYPE=wayland XDG_SESSION_CLASS=user XDG_SESSION_DESKTOP=GNOME XDG_CURRENT_DESKTOP=GNOME ZENOS_OOBE=1 ${config.services.displayManager.sessionData.wrapper} ${pkgs.gnome-session}/bin/gnome-session --session=zenos-oobe";
  zenosPlymouth = pkgs.callPackage ../packages/zenos-plymouth.nix {
    atkinson-hyperlegible = pkgs.zenos.apps.fonts.atkinson-hyperlegible;
    deviceName =
      if config.system.name == "zenos-installer" then "ZenOS Installer" else config.networking.hostName;
    distroName = config.system.nixos.distroName;
    releaseVersion = config.zenos.system.release.full;
    source = inputs.zenos-plymouth-assets;
  };
in
{
  zenos.system.release.revision = commitId;

  # boot.kernelPackages = pkgs.linuxPackagesFor inputs.popcorn.packages.${pkgs.stdenv.hostPlatform.system}."D-generic";

  system.name = "zenos-oobe";
  system.stateVersion = "26.05";

  system.nixos = {
    distroId = "zenos";
    distroName = "ZenOS";
    vendorId = "zenos";
    vendorName = "ZenOS";
  };

  networking = {
    hostName = "zenos";
    networkmanager.enable = true;
    firewall.enable = true;
  };

  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  nixpkgs.config.allowUnfree = true;

  services = {
    desktopManager.gnome.enable = true;
    displayManager = {
      autoLogin = {
        enable = lib.mkForce false;
        user = lib.mkForce null;
      };
      gdm.enable = lib.mkForce false;
    };
    fwupd.enable = true;
    fstrim.enable = true;
    gnome.gnome-initial-setup.enable = false;
    greetd = {
      enable = true;
      restart = false;
      settings = {
        initial_session = {
          command = gnomeSessionCommand;
          user = "zenos";
        };
        default_session = {
          command = gnomeSessionCommand;
          user = "zenos";
        };
      };
    };
  };

  systemd.services.greetd.environment = {
    XDG_SESSION_TYPE = "wayland";
    XDG_SESSION_CLASS = "user";
    XDG_SESSION_DESKTOP = "GNOME";
  };

  environment.etc."xdg/gnome-session/sessions/zenos-oobe.session".text = ''
    [GNOME Session]
    Name=ZenOS OOBE
  '';

  systemd.user.targets."gnome-session@zenos-oobe" = {
    overrideStrategy = "asDropin";
    unitConfig.Requires = [
      "gnome-session-services.target"
      "org.gnome.Shell@zenos-oobe.service"
    ];
  };

  systemd.user.services."org.gnome.Shell@zenos-oobe" = {
    overrideStrategy = "asDropin";
    environment = {
      PATH = lib.mkForce "/run/wrappers/bin:/run/current-system/sw/bin";
      ZENOS_OOBE = "1";
    };
  };

  environment.gnome.excludePackages = [ pkgs.gnome-tour ];

  hardware = {
    bluetooth.enable = true;
    graphics.enable = true;
  };

  security = {
    rtkit.enable = true;
    sudo.wheelNeedsPassword = false;
  };

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  programs = {
    dconf.enable = true;
    firefox.enable = true;
  };

  environment.systemPackages = [
    pkgs.zenos.apps.development-tools.git
    pkgs.zenos.apps.system.gnome-console
    pkgs.zenos.apps.development-tools.nano
    pkgs.zenos.theming.wallpapers.destination-2
  ];

  fonts = {
    packages = [
      pkgs.zenos.apps.fonts.atkinson-hyperlegible
      pkgs.zenos.apps.fonts.atkinson-hyperlegible-mono
      pkgs.zenos.apps.fonts.inter
    ];
    fontconfig.defaultFonts = {
      monospace = [ "AtkynsonMono NF" ];
      sansSerif = [ "Atkinson Hyperlegible" ];
    };
  };

  boot.plymouth = {
    enable = true;
    theme = "zenos";
    themePackages = [ zenosPlymouth ];
  };
  boot.initrd.kernelModules = [ "virtio_gpu" ];
  boot.kernelParams = [ "vt.global_cursor_default=0" ];
  systemd.services.plymouth-quit.serviceConfig.ExecStart = lib.mkForce [
    ""
    "${lib.getExe' pkgs.plymouth "plymouth"} quit --retain-splash"
  ];
  zramSwap.enable = true;
}
