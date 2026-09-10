{
  config,
  inputs,
  installerStage,
  lib,
  pkgs,
  ...
}:
let
  releaseVersion = "1.0.0Nb";
  configHash = builtins.substring 0 7 (builtins.hashString "sha256" inputs.self.sourceInfo.narHash);
  displayVersion = "${releaseVersion} (${configHash})";
  oobeExtensions = [
    "date-menu-formatter@marcinjakubowski.github.com"
    "user-theme@gnome-shell-extensions.gcampax.github.com"
    "zenos-oobe-mode@neg-zero.com"
  ];
  clockThemeCss = ''
    @import url("resource:///org/gnome/shell/theme/default.css");

    .clock-display {
      font-family: "Zero", sans-serif !important;
      font-size: 12px;
      font-style: normal !important;
      font-weight: normal !important;
      letter-spacing: 0 !important;
    }
  '';
  live = installerStage == "live";
  temporary = live || installerStage == "oobe";
  setup = pkgs.zenos.system.zenos-setup;
  mode = pkgs.zenos.system.zenos-oobe-mode;
  home = if live then "/Users/zenos" else "/run/zenos-oobe";
  sessionCommand = "${pkgs.coreutils}/bin/env XDG_SESSION_TYPE=wayland XDG_SESSION_CLASS=user XDG_SESSION_DESKTOP=GNOME XDG_CURRENT_DESKTOP=GNOME ZENOS_OOBE=1 ${config.services.displayManager.sessionData.wrapper} ${pkgs.gnome-session}/bin/gnome-session --session=zenos-oobe";
  normalUsers = lib.filterAttrs (_: user: user.enable && user.isNormalUser) config.users.users;
  bootHooks = import (inputs.zenpkgs + "/lib/installer-boot.nix") {
    inherit pkgs lib;
    bootPackage = pkgs.zenos.theming.system.zenos-plymouth.override {
      distroName = "ZenOS";
      releaseVersion = displayVersion;
      deviceName = if live then "ZenOS Installer" else config.networking.hostName;
    };
    refindInstaller = pkgs.zenos.system.zenos-refind-installer;
    refindTheme = pkgs.zenos.theming.system.zenos-refind-theme;
  };
in
{
  imports = [
    (import (inputs.zenpkgs + "/lib/zenfs-runtime.nix") {
      managedUsers = lib.mapAttrs (_: user: { inherit (user) home group; }) normalUsers;
      includeBootAlias = !live;
    })
    bootHooks.common
  ] ++ lib.optional (!live) bootHooks.installed;
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
  zenos.system.zenfs.enable = true;

  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "26.05";
  system.nixos = {
    distroId = "zenos";
    distroName = "ZenOS";
    version = displayVersion;
    versionSuffix = "";
    label = "${releaseVersion}-${configHash}";
    vendorId = "zenos";
    vendorName = "ZenOS";
    extraOSReleaseArgs = {
      BUILD_ID = "${releaseVersion}-${configHash}";
      CPE_NAME = "cpe:/o:zenos:zenos:${releaseVersion}";
      LOGO = "zenos";
      VERSION = displayVersion;
      VERSION_ID = releaseVersion;
      PRETTY_NAME = "ZenOS ${displayVersion}";
    };
    extraLSBReleaseArgs = {
      DISTRIB_DESCRIPTION = "ZenOS ${displayVersion}";
      DISTRIB_ID = "ZenOS";
      DISTRIB_RELEASE = releaseVersion;
    };
  };
  system.image = {
    id = "zenos-installer";
    version = "${releaseVersion}-${configHash}";
  };
  system.configurationRevision = configHash;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.registry.zenpkgs.flake = inputs.zenpkgs;
  networking.networkmanager.enable = true;
  services.openssh = lib.mkIf (!temporary) {
    enable = true;
    openFirewall = true;
    settings = {
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = true;
      PermitEmptyPasswords = false;
      PermitRootLogin = "no";
    };
  };
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
  fonts = lib.mkIf (!live) {
    packages = [
      pkgs.zenos.apps.fonts.atkinson-hyperlegible
      pkgs.nerd-fonts.atkynson-mono
      pkgs.zenos.apps.fonts.inter
      pkgs.zenos.theming.fonts.zero.regular
      pkgs.zenos.theming.fonts.zero.mono-thin
    ];
    fontconfig.defaultFonts = {
      sansSerif = lib.mkDefault [ "Atkinson Hyperlegible" ];
      monospace = lib.mkDefault [ "AtkynsonMono NF" ];
    };
  };
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
  services.fwupd.enable = true;
  services.fstrim.enable = true;
  services.qemuGuest.enable = true;
  zramSwap.enable = true;
  nix.settings.auto-optimise-store = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  services.desktopManager.gnome.enable = lib.mkIf temporary true;
  services.gnome.gnome-initial-setup.enable = false;
  services.displayManager = {
    gdm.enable =
      if temporary then lib.mkForce false else lib.mkDefault config.services.desktopManager.gnome.enable;
    autoLogin.enable = lib.mkForce false;
    autoLogin.user = lib.mkForce null;
    sddm.enable = lib.mkIf temporary (lib.mkForce false);
    plasma-login-manager.enable = lib.mkIf temporary (lib.mkForce false);
  };
  services.displayManager.gdm.settings.daemon.GreeterSession = lib.mkIf (!temporary) "gnome-login";
  services.xserver.displayManager.lightdm.enable = lib.mkIf temporary (lib.mkForce false);
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
    pkgs.zenos.programs.zenos-rebuild
  ]
  ++ lib.optionals temporary [
    setup
    mode
  ]
  ++ lib.optionals (temporary && !live) [ pkgs.zenos.apps.gnome-extensions.user-themes ]
  ++ lib.optionals (temporary && !live) [
    pkgs.zenos.apps.gnome-extensions.date-menu-formatter
    pkgs.zenos.theming.wallpapers.destination-2
  ]
  ++ lib.optionals live [ pkgs.gnome-console pkgs.nautilus ];
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
    useGlobalPkgs = lib.mkForce true;
    useUserPackages = lib.mkForce true;
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
    } // lib.optionalAttrs (temporary && !live) {
      # OOBE must remain isolated from the selected permanent desktop effects.
      dconf.settings = {
        "org/gnome/shell" = {
          disable-user-extensions = false;
          enabled-extensions = lib.mkForce oobeExtensions;
        };
        "org/gnome/shell/extensions/user-theme".name = lib.mkForce "ClockOverride";
        "org/gnome/shell/extensions/date-menu-formatter" = {
          formatter = lib.mkForce "01_luxon";
          pattern = lib.mkForce "dd.MM  HH:mm";
          font-size = lib.mkForce 12;
          update-level = lib.mkForce 1;
          text-align = lib.mkForce "center";
        };
        "org/gnome/desktop/background" = {
          color-shading-type = lib.mkForce "solid";
          picture-options = lib.mkForce "none";
          picture-uri = lib.mkForce "";
          picture-uri-dark = lib.mkForce "";
          primary-color = lib.mkForce "#000000";
          secondary-color = lib.mkForce "#000000";
        };
      };
      xdg.dataFile."themes/ClockOverride/gnome-shell/gnome-shell.css".text = lib.mkForce clockThemeCss;
    }) normalUsers;
  };

  programs.dconf.enable = true;
  programs.dconf.profiles.user.databases = lib.optionals (temporary && !live) [
    {
      settings = {
        "org/gnome/shell" = {
          disable-user-extensions = false;
          enabled-extensions = oobeExtensions;
        };
        "org/gnome/shell/extensions/user-theme".name = "ClockOverride";
        "org/gnome/shell/extensions/date-menu-formatter" = {
          formatter = "01_luxon";
          pattern = "dd.MM  HH:mm";
          font-size = lib.gvariant.mkInt32 12;
          update-level = lib.gvariant.mkInt32 1;
          text-align = "center";
        };
        "org/gnome/desktop/background" = {
          color-shading-type = "solid";
          picture-options = "none";
          picture-uri = "";
          picture-uri-dark = "";
          primary-color = "#000000";
          secondary-color = "#000000";
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

  systemd.tmpfiles.rules = [
    "d /etc/ZenOS 0755 ${if live then "zenos users" else "root root"} -"
  ]
  ++ lib.optionals (!live && temporary) [
    "Z /etc/ZenOS - zenos users -"
    "z /etc/ZenOS 0755 zenos users -"
  ];

}
