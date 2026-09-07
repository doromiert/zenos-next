{
  config,
  inputs,
  installerStage,
  lib,
  pkgs,
  ...
}:
let
  live = installerStage == "live";
  temporary = live || installerStage == "oobe";
  setup = pkgs.zenos.system.zenos-setup;
  mode = pkgs.zenos.system.zenos-oobe-mode;
  home = if live then "/Users/zenos" else "/run/zenos-oobe";
  sessionCommand = "${pkgs.coreutils}/bin/env XDG_SESSION_TYPE=wayland XDG_SESSION_CLASS=user XDG_SESSION_DESKTOP=GNOME XDG_CURRENT_DESKTOP=GNOME ZENOS_OOBE=1 ${config.services.displayManager.sessionData.wrapper} ${pkgs.gnome-session}/bin/gnome-session --session=zenos-oobe";
  normalUsers = lib.filterAttrs (_: user: user.enable && user.isNormalUser) config.users.users;
in
{
  # Only these three installer stages consume this concrete backend composition.
  assertions = [
    {
      assertion = builtins.elem installerStage [
        "live"
        "oobe"
        "desktop"
      ];
      message = "Unknown installer stage";
    }
  ];

  # These public modules are not used until their current lowering is reliable.
  zenos.system.installed-base.enable = lib.mkForce false;
  zenos.system.oobe.enable = lib.mkForce false;
  zenos.system.zenfs.enable = lib.mkForce false;
  zenos.desktops.gnome.enable = lib.mkIf live (lib.mkForce false);

  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "26.05";
  system.nixos = {
    distroId = "zenos";
    distroName = "ZenOS";
    vendorId = "zenos";
    vendorName = "ZenOS";
    extraOSReleaseArgs = {
      VERSION = "1.0.0Nb";
      VERSION_ID = "1.0.0Nb";
      PRETTY_NAME = "ZenOS 1.0.0Nb";
    };
  };
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.registry.zenpkgs.flake = inputs.zenpkgs;
  networking.networkmanager.enable = true;
  time.timeZone = lib.mkDefault "UTC";
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
  console.keyMap = lib.mkDefault "us";

  users.mutableUsers = false;
  users.users = {
    root.hashedPassword = lib.mkDefault "!";
  }
  // lib.optionalAttrs temporary {
    zenos = {
      isNormalUser = true;
      description = if live then "ZenOS Installer" else "ZenOS Setup";
      inherit home;
      createHome = true;
      homeMode = "0700";
      hashedPassword = "";
      extraGroups = [
        "input"
        "networkmanager"
        "video"
        "wheel"
      ];
    };
  };
  security.sudo.wheelNeedsPassword = !temporary;
  security.rtkit.enable = true;
  hardware.graphics.enable = true;
  hardware.enableRedistributableFirmware = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  services.desktopManager.gnome.enable = lib.mkIf temporary true;
  services.gnome.gnome-initial-setup.enable = false;
  services.displayManager = {
    gdm.enable =
      if temporary then lib.mkForce false else lib.mkDefault config.services.desktopManager.gnome.enable;
    autoLogin.enable = lib.mkForce false;
    autoLogin.user = lib.mkForce null;
  };
  services.greetd = lib.mkIf temporary {
    enable = true;
    restart = false;
    settings = {
      initial_session = {
        command = sessionCommand;
        user = "zenos";
      };
      default_session = {
        command = sessionCommand;
        user = "zenos";
      };
    };
  };
  systemd.services.greetd.environment = lib.mkIf temporary {
    XDG_SESSION_TYPE = "wayland";
    XDG_SESSION_CLASS = "user";
    XDG_SESSION_DESKTOP = "GNOME";
  };
  environment.etc."xdg/gnome-session/sessions/zenos-oobe.session" = lib.mkIf temporary {
    text = ''
      [GNOME Session]
      Name=ZenOS Setup
    '';
  };
  systemd.user.targets."gnome-session@zenos-oobe" = lib.mkIf temporary {
    overrideStrategy = "asDropin";
    unitConfig.Requires = [
      "gnome-session-services.target"
      "org.gnome.Shell@zenos-oobe.service"
    ];
  };
  systemd.user.services."org.gnome.Shell@zenos-oobe" = lib.mkIf temporary {
    overrideStrategy = "asDropin";
    environment = {
      PATH = lib.mkForce "/run/wrappers/bin:/run/current-system/sw/bin";
      ZENOS_OOBE = "1";
      GNOME_SHELL_SESSION_MODE = "zenos-oobe";
    };
  };
  systemd.user.services.zenos-setup = lib.mkIf temporary {
    description = if live then "ZenOS installer" else "ZenOS out-of-box experience";
    wantedBy = [ "graphical-session.target" ];
    after = [ "gnome-session.target" ];
    partOf = [ "graphical-session.target" ];
    unitConfig.ConditionUser = "zenos";
    path = lib.mkForce [ ];
    environment = {
      PATH = "/run/wrappers/bin:/run/current-system/sw/bin";
      ZENOS_SETUP_DRY_RUN = "0";
      ZENOS_OOBE = if live then "0" else "1";
      GI_TYPELIB_PATH = lib.makeSearchPath "lib/girepository-1.0" [
        pkgs.gnome-desktop
        pkgs.libgweather
        pkgs.networkmanager
      ];
    };
    serviceConfig = {
      Type = "exec";
      ExecStart = "${lib.getExe setup}${lib.optionalString (!live) " --oobe"}";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  environment.systemPackages = [
    inputs.zenpkgs.packages.x86_64-linux.zen-dsl
    pkgs.nixos-rebuild
  ]
  ++ lib.optionals temporary [
    setup
    mode
  ] ++ lib.optionals live [ pkgs.gnome-console pkgs.nautilus ];
  system.extraDependencies = lib.optionals temporary [ setup.src mode.src ];
  environment.pathsToLink = lib.optionals temporary [
    "/share/gnome-shell/extensions"
    "/share/gnome-shell/modes"
  ];
  environment.gnome.excludePackages = lib.optionals live [ pkgs.gnome-tour ];
  environment.sessionVariables = {
    XDG_CONFIG_HOME = "$HOME/.private/Config";
    XDG_DATA_HOME = "$HOME/.private/Packages";
    XDG_CACHE_HOME = "$HOME/.private/Live";
    XDG_STATE_HOME = "$HOME/.private/State";
  }
  // lib.optionalAttrs temporary {
    ZENOS_SETUP_DRY_RUN = "0";
  }
  // lib.optionalAttrs live {
    ZENOS_INSTALLER = "1";
  };

  home-manager = {
    users = lib.mapAttrs (_: user: {
      home = {
        stateVersion = lib.mkDefault "26.05";
        username = lib.mkDefault user.name;
        homeDirectory = lib.mkDefault user.home;
      };
      xdg = {
        enable = true;
        configHome = "${user.home}/.private/Config";
        dataHome = "${user.home}/.private/Packages";
        cacheHome = "${user.home}/.private/Live";
        stateHome = "${user.home}/.private/State";
      };
    }) normalUsers;
  };

  programs.dconf.enable = true;
  programs.dconf.profiles.user.databases = lib.optionals temporary [
    {
      settings = {
        "org/gnome/shell" = {
          disable-user-extensions = false;
          enabled-extensions = [ "zenos-oobe-mode@neg-zero.com" ];
        };
        "org/gnome/desktop/interface".color-scheme = "prefer-dark";
        "org/gnome/desktop/lockdown".disable-lock-screen = true;
        "org/gnome/desktop/screensaver".lock-enabled = false;
        "org/gnome/desktop/session".idle-delay = lib.gvariant.mkUint32 0;
        "org/gnome/settings-daemon/plugins/power" = {
          sleep-inactive-ac-type = "nothing";
          sleep-inactive-battery-type = "nothing";
        };
      };
    }
  ];

  # Limited filesystem mapping for this installer, not the full ZenFS backend.
  systemd.tmpfiles.rules = [
    "L /Config - - - - /etc"
    "d /etc/ZenOS 0755 root root -"
    "d /Users 0755 root root -"
  ]
  ++ lib.concatMap (
    user:
    map (directory: "d ${user.home}/.private${directory} 0700 ${user.name} ${user.group} -") [
      ""
      "/Config"
      "/Packages"
      "/Live"
      "/State"
    ]
  ) (builtins.attrValues normalUsers)
  ++ lib.optionals (!live && temporary) [
    "Z /etc/ZenOS - zenos users -"
    "z /etc/ZenOS 0755 zenos users -"
  ];

  boot.loader = lib.mkIf (!live) {
    grub = {
      enable = true;
      efiSupport = true;
      efiInstallAsRemovable = true;
      device = "nodev";
    };
    efi = {
      efiSysMountPoint = "/boot";
      canTouchEfiVariables = false;
    };
    systemd-boot.enable = false;
  };
}
