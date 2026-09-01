{
  config,
  configTemplate,
  inputs,
  lib,
  modulesPath,
  options,
  pkgs,
  ...
}:

let
  setupApp =
    inputs.zenos-setup.packages.${pkgs.stdenv.hostPlatform.system}.zenos-install.overrideAttrs
      (old: {
        buildInputs = (old.buildInputs or [ ]) ++ [
          pkgs.gnome-desktop
        ];
        meta = (old.meta or { }) // {
          mainProgram = "zenos-setup";
        };
      });
  zenDsl = pkgs.callPackage ../packages/zen-dsl.nix { };
  extensionUuid = "zenos-oobe-mode@neg-zero.com";
  oobeExtension = pkgs.stdenvNoCC.mkDerivation {
    pname = "gnome-shell-extension-zenos-oobe-mode";
    version = "1.0.0";
    src = inputs.zenos-oobe-mode;
    dontBuild = true;
    installPhase = ''
      install -d "$out/share/gnome-shell/extensions/${extensionUuid}"
      install -m 0644 extension.js metadata.json \
        "$out/share/gnome-shell/extensions/${extensionUuid}/"
      install -d "$out/share/gnome-shell/modes"
      install -m 0644 zenos-oobe.json \
        "$out/share/gnome-shell/modes/zenos-oobe.json"
    '';
  };
  wallpaper = "${inputs.zenos-setup}/data/wallpapers/purple.png";
  recoveryTools = pkgs.callPackage ../packages/recovery-tools { };
  appIndex = pkgs.callPackage ../packages/app-index { };
  nautilusApps = pkgs.callPackage ../packages/nautilus-apps { inherit appIndex; };
  recovery = pkgs.zenos.apps.recovery;
  extensionManifest = builtins.fromJSON (
    builtins.readFile "${inputs.zenos-setup}/data/gnome-extensions.json"
  );
  resolveExtension = entry: lib.getAttrFromPath entry.packagePath pkgs;
  extensionPackages = map resolveExtension extensionManifest;
  initialExtensionPackages = map resolveExtension (
    builtins.filter (entry: entry.liveEnabled) extensionManifest
  );
  initialExtensionUuids = [
    extensionUuid
  ]
  ++ map (extension: extension.extensionUuid) initialExtensionPackages;
  btopCli = pkgs.runCommand "zenos-btop-cli" { } ''
    install -d "$out/bin"
    ln -s ${lib.getExe pkgs.zenos.apps.system.btop} "$out/bin/btop"
  '';
  neovimCli = pkgs.runCommand "zenos-neovim-cli" { } ''
    install -d "$out/bin"
    ln -s ${lib.getExe pkgs.zenos.apps.development.neovim} "$out/bin/nvim"
    ln -s ${lib.getExe pkgs.zenos.apps.development.neovim} "$out/bin/vim"
  '';
  firefoxGnomeTheme = pkgs.fetchFromGitHub {
    owner = "rafaelmardojai";
    repo = "firefox-gnome-theme";
    rev = "v143";
    hash = "sha256-0E3TqvXAy81qeM/jZXWWOTZ14Hs1RT7o78UyZM+Jbr4=";
  };
  firefoxProfiles = pkgs.writeText "firefox-profiles.ini" ''
    [Profile0]
    Name=default
    IsRelative=1
    Path=default
    Default=1

    [General]
    StartWithLastProfile=1
    Version=2
  '';
  firefoxUserChrome = pkgs.writeText "firefox-userChrome.css" ''
    @import "gnome-theme/userChrome.css";
  '';
  firefoxUserContent = pkgs.writeText "firefox-userContent.css" ''
    @import "gnome-theme/userContent.css";
  '';
  burnMyWindowsProfile = pkgs.writeText "zenos-burn-my-windows.conf" ''
    [burn-my-windows-profile]
    apparition-enable-effect=false
    fire-enable-effect=false
    apparition-twirl-intensity=0.0
    apparition-shake-intensity=0.0
    apparition-suction-intensity=1.0
    apparition-randomness=0.0
    aura-glow-enable-effect=false
    broken-glass-enable-effect=false
    broken-glass-gravity=-2.0
    broken-glass-blow-force=2.0
    doom-enable-effect=false
    energize-a-enable-effect=false
    energize-b-enable-effect=false
    focus-enable-effect=false
    glide-enable-effect=true
    glitch-enable-effect=false
    hexagon-enable-effect=false
    incinerate-enable-effect=false
    matrix-enable-effect=false
    mushroom-enable-effect=false
    paint-brush-enable-effect=false
    pixelate-enable-effect=false
    pixel-wheel-enable-effect=false
    pixel-wipe-enable-effect=false
    portal-enable-effect=false
    rgbwarp-enable-effect=false
    snap-enable-effect=false
    team-rocket-enable-effect=false
    trex-enable-effect=false
    tv-enable-effect=false
    tv-glitch-enable-effect=false
    wisps-enable-effect=false
    glide-scale=0.74
    glide-squish=1.0
    glide-tilt=-0.7
    glide-shift=-0.05
    glide-animation-time=150
  '';
  clockTheme = pkgs.runCommand "zenos-clock-theme" { } ''
    install -d "$out/share/themes/ClockOverride/gnome-shell"
    cat > "$out/share/themes/ClockOverride/gnome-shell/gnome-shell.css" <<'EOF'
    @import url("resource:///org/gnome/shell/theme/default.css");

    .clock-display {
      font-family: "Zero", sans-serif !important;
      font-size: 12px;
      font-style: normal !important;
      font-weight: normal !important;
      letter-spacing: 0 !important;
    }
    EOF
  '';
  hiddenRootEntries = pkgs.writeText "zenos-hidden-root-entries" ''
    bin
    boot
    dev
    etc
    home
    iso
    iso-config
    iso-config-template
    lib64
    mnt
    nix
    opt
    proc
    root
    run
    srv
    sys
    tmp
    usr
    var
  '';
  desktopItems = map pkgs.makeDesktopItem [
    {
      name = "zenos-recovery-report";
      desktopName = "Hardware and Recovery Report";
      comment = "Collect hardware, storage, network, and boot diagnostics";
      exec = ''kgx -- bash -lc "zen-recovery-diagnostics; echo; read -p 'Press Enter to close'"'';
      icon = "utilities-system-monitor";
      categories = [ "System" ];
    }
    {
      name = "zenos-recover-files";
      desktopName = "Recover Deleted Files";
      comment = "Open TestDisk and PhotoRec";
      exec = "kgx -- sudo -n testdisk";
      icon = "drive-harddisk";
      categories = [ "System" ];
    }
    {
      name = "zenos-recover-nixos";
      desktopName = "Repair ZenOS or NixOS";
      exec = ''kgx -- bash -lc "zen-recover-nixos; exec bash"'';
      icon = "nix-snowflake";
      categories = [ "System" ];
    }
    {
      name = "zenos-recover-linux";
      desktopName = "Repair Arch, Ubuntu, or Fedora";
      exec = ''kgx -- bash -lc "echo 'Use zen-recover-arch, zen-recover-ubuntu, or zen-recover-fedora with a mounted root'; exec bash"'';
      icon = "system-linux";
      categories = [ "System" ];
    }
    {
      name = "zenos-recover-windows";
      desktopName = "Windows Recovery Guide";
      exec = ''kgx -- bash -lc "zen-recover-windows /mnt/recovery/windows; exec bash"'';
      icon = "computer";
      categories = [ "System" ];
    }
  ];
in
{
  imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-graphical-gnome.nix" ];

  system = {
    name = lib.mkForce "zenos-installer";
    nixos = {
      variant_id = "installer";
      variantName = "ZenOS Installer";
    };
  };

  environment.etc."machine-info".text = lib.mkForce ''
    PRETTY_HOSTNAME="ZenOS Installer"
  '';

  services.displayManager = {
    autoLogin.enable = lib.mkForce false;
    gdm.enable = lib.mkForce false;
  };

  services.xserver.excludePackages = [ pkgs.xterm ];

  environment.defaultPackages = lib.mkForce (
    options.environment.defaultPackages.default
    ++ [
      pkgs.zenos.apps.development-tools.nano
      neovimCli
      nautilusApps
    ]
  );

  environment.gnome.excludePackages = [
    pkgs.gnome-calendar
    pkgs.gnome-clocks
    pkgs.gnome-contacts
    pkgs.gnome-maps
    pkgs.gnome-music
    pkgs.gnome-weather
    pkgs.epiphany
    pkgs.simple-scan
  ];

  zenfs = {
    enable = true;
    hierarchy.directories = [ "/System" ];
    users.zenos = {
      home = "/home/zenos";
      group = "users";
    };
  };

  systemd.user.services.zenos-installer = {
    description = "ZenOS installer";
    wantedBy = [ "graphical-session.target" ];
    after = [ "gnome-session.target" ];
    partOf = [ "graphical-session.target" ];
    path = lib.mkForce [ ];
    environment = {
      PATH = "/run/wrappers/bin:/run/current-system/sw/bin";
      ZENOS_SETUP_DRY_RUN = "0";
    };
    serviceConfig = {
      Type = "exec";
      ExecStart = lib.getExe setupApp;
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  systemd.services.zenos-app-index = {
    description = "Build the ZenOS application directory";
    wantedBy = [
      "multi-user.target"
      "greetd.service"
    ];
    wants = [ "systemd-tmpfiles-setup.service" ];
    after = [ "systemd-tmpfiles-setup.service" ];
    before = [ "greetd.service" ];
    unitConfig = {
      ConditionPathIsDirectory = "/home/zenos";
      RequiresMountsFor = [ "/home/zenos" ];
    };
    path = [ config.system.path ];
    serviceConfig = {
      Type = "oneshot";
      User = "zenos";
      Group = "users";
      ExecStart = "${lib.getExe appIndex} --home /home/zenos --user zenos --target /Apps";
    };
  };

  users = {
    mutableUsers = false;
    users = {
      root.hashedPassword = lib.mkForce "!";
      nixos.enable = lib.mkForce false;
      zenos = {
        isNormalUser = true;
        description = "ZenOS Installer";
        initialHashedPassword = "";
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH4+fQMTy7FaLwqDOumL1y3uW+WMWpoc12MEeQXeF+VF zenos-next-vm-debug"
        ];
        extraGroups = [
          "input"
          "networkmanager"
          "video"
          "wheel"
        ];
      };
    };
  };

  services.getty.autologinUser = lib.mkForce null;
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = true;
      PermitEmptyPasswords = true;
      PermitRootLogin = "no";
    };
  };
  boot.zfs.forceImportRoot = false;
  security.sudo.wheelNeedsPassword = false;
  security.unprivilegedUsernsClone = true;
  nix.settings.trusted-users = lib.mkForce [
    "root"
    "zenos"
  ];

  programs.firefox = {
    package = pkgs.zenos.apps.browsers.firefox;
    policies = {
      DisableAccounts = true;
      DisableAppUpdate = true;
      DisableFirefoxStudies = true;
      DisableTelemetry = true;
      DisplayBookmarksToolbar = "never";
      DisplayMenuBar = "default-off";
      DontCheckDefaultBrowser = true;
      EnableTrackingProtection = {
        Value = true;
        Locked = true;
        Cryptomining = true;
        Fingerprinting = true;
      };
      ExtensionSettings = {
        "uBlock0@raymondhill.net" = {
          default_area = "menupanel";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
          installation_mode = "force_installed";
        };
        "sponsorBlocker@ajay.app" = {
          default_area = "menupanel";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/sponsorblock/latest.xpi";
          installation_mode = "force_installed";
        };
        "{a6c4a591-f1b2-4f03-b3ff-767e5bedf4e7}" = {
          default_area = "menupanel";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/user-agent-string-switcher/latest.xpi";
          installation_mode = "force_installed";
        };
        "keepassxc-browser@keepassxc.org" = {
          default_area = "menupanel";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/keepassxc-browser/latest.xpi";
          installation_mode = "force_installed";
        };
        "{2598f043-d16d-4122-9945-fd253ed12f23}" = {
          default_area = "menupanel";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/consent-o-matic/latest.xpi";
          installation_mode = "force_installed";
        };
      };
      OfferToSaveLogins = false;
      PasswordManagerEnabled = false;
      SearchEngines = {
        Default = "DuckDuckGo";
        PreventInstalls = false;
      };
      UserMessaging = {
        ExtensionRecommendations = false;
        FeatureRecommendations = false;
        MoreFromMozilla = false;
        SkipOnboarding = true;
        WhatsNew = false;
      };
    };
    preferences = {
      "browser.newtabpage.activity-stream.feeds.topsites" = false;
      "browser.newtabpage.activity-stream.showSearch" = false;
      "browser.newtabpage.enabled" = false;
      "browser.startup.homepage" = "about:blank";
      "browser.startup.page" = 0;
      "browser.tabs.drawInTitlebar" = true;
      "browser.toolbars.bookmarks.visibility" = "never";
      "browser.uidensity" = 1;
      "gnomeTheme.bookmarksToolbarUnderTabs" = true;
      "gnomeTheme.hideSingleTab" = true;
      "gnomeTheme.normalWidthTabs" = false;
      "svg.context-properties.content.enabled" = true;
      "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
      "widget.gtk.rounded-bottom-corners.enabled" = true;
    };
    preferencesStatus = "locked";
  };

  environment = {
    systemPackages = [
      oobeExtension
      appIndex
      btopCli
      clockTheme
      neovimCli
      pkgs.zenos.apps.system.gnome-console
      pkgs.zenos.apps.system.gnome-control-center
      pkgs.zenos.apps.system.gnome-system-monitor
      pkgs.zenos.apps.system.nautilus
      pkgs.zenos.apps.system.nautilus-python
      pkgs.zenos.apps.system.ncurses
      pkgs.zenos.apps.utilities.resources
      pkgs.zenos.apps.cursors.google-dot
      pkgs.zenos.apps.themes.adw-gtk3
      pkgs.zenos.theming.icons.adwaita-hacks
      recoveryTools
      inputs.disko.packages.${pkgs.stdenv.hostPlatform.system}.disko
      recovery.arch-install-scripts
      recovery.btrfs-progs
      recovery.cryptsetup
      recovery.curl
      recovery.ddrescue
      recovery.dmidecode
      recovery.dnsutils
      recovery.dosfstools
      recovery.e2fsprogs
      recovery.efibootmgr
      recovery.exfatprogs
      recovery.f2fs-tools
      recovery.gnome-disks
      recovery.gparted-live
      recovery.gptfdisk
      recovery.iproute2
      recovery.iputils
      recovery.jq
      recovery.less
      recovery.lshw
      recovery.lvm2
      recovery.mdadm
      recovery.mokutil
      recovery.nixos-install-tools
      recovery.ntfs3g
      recovery.nvme-cli
      recovery.openssh
      recovery.parted
      recovery.pciutils
      recovery.rsync
      recovery.smartmontools
      recovery.squashfs-tools
      recovery.testdisk
      recovery.unzip
      recovery.usbutils
      recovery.util-linux
      recovery.wget
      recovery.xfsprogs
      recovery.zip
      recovery.zstd
      setupApp
      zenDsl
    ]
    ++ extensionPackages
    ++ desktopItems;
    sessionVariables = {
      MOZ_LEGACY_PROFILES = "1";
      ZENOS_INSTALLER = "1";
    };
  };

  programs.dconf.profiles.user.databases = [
    {
      settings = {
        "org/gnome/shell" = {
          disable-user-extensions = false;
          enabled-extensions = initialExtensionUuids;
          favorite-apps = [
            "com.negzero.zenos.setup.desktop"
            "firefox.desktop"
            "org.gnome.Nautilus.desktop"
            "org.gnome.Console.desktop"
            "org.gnome.SystemMonitor.desktop"
            "org.gnome.Settings.desktop"
            "org.gnome.DiskUtility.desktop"
            "gparted.desktop"
          ];
        };
        "org/gnome/desktop/interface" = {
          accent-color = "purple";
          color-scheme = "prefer-dark";
          cursor-size = lib.gvariant.mkInt32 24;
          cursor-theme = "GoogleDot-Black";
          font-name = "Atkinson Hyperlegible 11";
          document-font-name = "Atkinson Hyperlegible 11";
          monospace-font-name = "AtkynsonMono NF 11";
          gtk-theme = "adw-gtk3-dark";
          icon-theme = "Adwaita-hacks";
          show-battery-percentage = true;
        };
        "org/gnome/desktop/lockdown".disable-lock-screen = true;
        "org/gnome/desktop/screensaver".lock-enabled = false;
        "org/gnome/desktop/session".idle-delay = lib.gvariant.mkUint32 0;
        "org/gnome/desktop/app-folders".folder-children =
          lib.gvariant.mkEmptyArray lib.gvariant.type.string;
        "org/gnome/shell/extensions/alphabetical-app-grid".folder-order-position = "end";
        "org/gnome/shell/extensions/burn-my-windows" = {
          active-profile = "/home/zenos/.config/burn-my-windows/profiles/zenos.conf";
          show-support-dialog = false;
        };
        "org/gnome/shell/extensions/clipboard-indicator" = {
          clear-on-boot = true;
          display-mode = lib.gvariant.mkInt32 0;
        };
        "org/gnome/shell/extensions/clipboard-indicator/keybindings".toggle-menu = [
          "<Control><Super>v"
        ];
        "org/gnome/shell/extensions/com/github/hermes83/compiz-windows-effect" = {
          friction = 4.9;
          mass = 50.0;
          resize-effect = true;
          speedup-factor-divider = 4.7;
          spring-k = 2.2;
        };
        "org/gnome/shell/extensions/coverflowalttab" = {
          desaturate-factor = 0.0;
          icon-style = "Classic";
          use-glitch-effect = true;
        };
        "org/gnome/shell/extensions/date-menu-formatter" = {
          font-size = lib.gvariant.mkInt32 12;
          formatter = "01_luxon";
          pattern = "dd.MM  HH:mm";
          text-align = "center";
          update-level = lib.gvariant.mkInt32 1;
        };
        "org/gnome/shell/extensions/dash-stacks" = {
          popup-height = lib.gvariant.mkInt32 400;
          popup-width = lib.gvariant.mkInt32 400;
          stacks = builtins.toJSON [
            {
              autoIcon = false;
              icon = "folder-download";
              name = "Downloads";
              path = "~/Downloads";
            }
            {
              autoIcon = false;
              icon = "folder-documents";
              name = "Projects";
              path = "~/Projects";
            }
            {
              autoIcon = false;
              icon = "folder-music";
              name = "Music";
              path = "~/Music";
            }
          ];
        };
        "org/gnome/shell/extensions/forge" = {
          css-last-update = lib.gvariant.mkUint32 37;
          dnd-center-layout = "swap";
          float-always-on-top-enabled = false;
          focus-border-toggle = false;
          quick-settings-enabled = false;
          split-border-toggle = false;
          stacked-tiling-mode-enabled = false;
          tabbed-tiling-mode-enabled = false;
          window-gap-size = lib.gvariant.mkUint32 4;
        };
        "org/gnome/shell/extensions/forge/keybindings" = {
          window-focus-left = [ "<Super>h" ];
          window-focus-down = [ "<Super>j" ];
          window-focus-up = [ "<Super>k" ];
          window-focus-right = [ "<Super>l" ];
          window-move-left = [ "<Shift><Super>h" ];
          window-move-down = [ "<Shift><Super>j" ];
          window-move-up = [ "<Shift><Super>k" ];
          window-move-right = [ "<Shift><Super>l" ];
          window-toggle-always-float = [ "<Super><Shift>f" ];
          window-toggle-float = [ "<Super>f" ];
        };
        "org/gnome/shell/extensions/gsconnect/preferences" = {
          window-maximized = false;
          window-size = lib.gvariant.mkTuple [
            (lib.gvariant.mkInt32 945)
            (lib.gvariant.mkInt32 478)
          ];
        };
        "org/gnome/shell/extensions/hidetopbar" = {
          enable-intellihide = false;
          mouse-sensitive = true;
          mouse-sensitive-fullscreen-window = false;
        };
        "org/gnome/shell/extensions/mouse-tail".render-mode = "precise";
        "org/gnome/shell/extensions/notification-timeout".timeout = lib.gvariant.mkInt32 2000;
        "org/gnome/shell/extensions/rounded-window-corners-reborn" = {
          border-width = lib.gvariant.mkInt32 1;
          settings-version = lib.gvariant.mkUint32 7;
        };
        "org/gnome/shell/extensions/user-theme".name = "ClockOverride";
        "org/gnome/settings-daemon/plugins/media-keys".custom-keybindings = [
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/terminal/"
        ];
        "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/terminal" = {
          binding = "<Super>t";
          command = "kgx";
          name = "Terminal";
        };
        "org/gnome/desktop/background" = {
          color-shading-type = "solid";
          picture-options = "zoom";
          picture-uri = "file://${wallpaper}";
          picture-uri-dark = "file://${wallpaper}";
          primary-color = "#000000";
          secondary-color = "#000000";
        };
      };
      locks = [
        "/org/gnome/shell/disable-user-extensions"
        "/org/gnome/shell/favorite-apps"
      ];
    }
  ];

  systemd.tmpfiles.rules = [
    "L+ /iso-config-template - - - - ${configTemplate}"
    "L+ /iso-config - - - - ${configTemplate}"
    "L+ /.hidden - - - - ${hiddenRootEntries}"
    "d /Apps 0755 zenos users -"
    "d /home/zenos/.config/burn-my-windows/profiles 0755 zenos users -"
    "d /home/zenos/.cache/clipboard-indicator@tudmotu.com 0700 zenos users -"
    "L+ /home/zenos/.config/burn-my-windows/profiles/zenos.conf - zenos users - ${burnMyWindowsProfile}"
    "d /home/zenos/.mozilla 0700 zenos users -"
    "d /home/zenos/.mozilla/firefox 0700 zenos users -"
    "d /home/zenos/.mozilla/firefox/default 0700 zenos users -"
    "d /home/zenos/.mozilla/firefox/default/chrome 0755 zenos users -"
    "L+ /home/zenos/.mozilla/firefox/profiles.ini - zenos users - ${firefoxProfiles}"
    "L+ /home/zenos/.mozilla/firefox/default/chrome/gnome-theme - zenos users - ${firefoxGnomeTheme}"
    "L+ /home/zenos/.mozilla/firefox/default/chrome/userChrome.css - zenos users - ${firefoxUserChrome}"
    "L+ /home/zenos/.mozilla/firefox/default/chrome/userContent.css - zenos users - ${firefoxUserContent}"
  ];

  isoImage = {
    edition = "zenos";
    volumeID = "ZENOS_INSTALLER";
    squashfsCompression = "zstd -Xcompression-level 6";
  };
  image.baseName = lib.mkForce "zenos-installer";
}
