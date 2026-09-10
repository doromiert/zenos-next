{ config, installerStage, lib, pkgs, ... }:
let
  wallpaper = "${pkgs.zenos.system.zenos-setup.src}/data/wallpapers/purple.png";
  firefoxGnomeTheme = pkgs.fetchFromGitHub {
    owner = "rafaelmardojai";
    repo = "firefox-gnome-theme";
    rev = "v143";
    hash = "sha256-0E3TqvXAy81qeM/jZXWWOTZ14Hs1RT7o78UyZM+Jbr4=";
  };
in
{
  config = lib.mkIf (installerStage == "live") {
    # installation-cd-minimal disables Fontconfig. Installing fonts alone is insufficient.
    fonts.fontconfig.enable = lib.mkForce true;
    services.xserver.excludePackages = [ pkgs.xterm ];
    environment.gnome.excludePackages = with pkgs; [
      gnome-calendar gnome-clocks gnome-contacts gnome-maps gnome-music
      gnome-weather epiphany simple-scan
    ];

    home-manager.users.zenos = {
      dconf.enable = true;
      dconf.settings = {
        "org/gnome/shell" = {
          # Match the priority of the shared u! defaults so OOBE appends to all 12.
          enabled-extensions = lib.mkDefault [ "zenos-oobe-mode@neg-zero.com" ];
          disable-user-extensions = false;
          favorite-apps = config.zenos.desktops.gnome.dockItems;
        };
        "org/gnome/desktop/interface" = {
          accent-color = "purple";
          color-scheme = "prefer-dark";
          cursor-size = 24;
          cursor-theme = "GoogleDot-Black";
          font-name = "Atkinson Hyperlegible 11";
          document-font-name = "Atkinson Hyperlegible 11";
          monospace-font-name = "AtkynsonMono NF 11";
          gtk-theme = "adw-gtk3-dark";
          icon-theme = "Adwaita-hacks";
          show-battery-percentage = true;
        };
        "org/gnome/desktop/lockdown".disable-lock-screen = true;
        "org/gnome/desktop/wm/preferences".button-layout = ":close";
        "org/gnome/desktop/screensaver".lock-enabled = false;
        "org/gnome/desktop/session".idle-delay = lib.gvariant.mkUint32 0;
        "org/gnome/desktop/app-folders".folder-children = lib.gvariant.mkEmptyArray lib.gvariant.type.string;
        "org/gnome/desktop/background" = {
          color-shading-type = "solid";
          picture-options = "zoom";
          picture-uri = "file://${wallpaper}";
          picture-uri-dark = "file://${wallpaper}";
          primary-color = "#000000";
          secondary-color = "#000000";
        };
        "org/gnome/settings-daemon/plugins/media-keys".custom-keybindings = [
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/terminal/"
        ];
        "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/terminal" = {
          binding = "<Super>t";
          command = "kgx";
          name = "Terminal";
        };
      };
      gtk = {
        enable = true;
        theme = { name = "adw-gtk3-dark"; package = pkgs.zenos.apps.themes.adw-gtk3; };
        iconTheme = { name = "Adwaita-hacks"; package = pkgs.zenos.theming.icons.adwaita-hacks; };
        cursorTheme = { name = "GoogleDot-Black"; package = pkgs.zenos.apps.cursors.google-dot; size = 24; };
        font = { name = "Atkinson Hyperlegible"; size = 11; };
        gtk3.extraConfig.gtk-application-prefer-dark-theme = true;
        gtk3.extraConfig.gtk-decoration-layout = ":close";
        gtk4.extraConfig.gtk-application-prefer-dark-theme = true;
        gtk4.extraConfig.gtk-decoration-layout = ":close";
      };
      xdg.configFile = {
        "mozilla/firefox/profiles.ini".text = ''
          [Profile0]
          Name=default
          IsRelative=1
          Path=default
          Default=1

          [General]
          StartWithLastProfile=1
          Version=2
        '';
        "mozilla/firefox/default/chrome/gnome-theme".source = firefoxGnomeTheme;
        "mozilla/firefox/default/chrome/userChrome.css".text = ''@import "gnome-theme/userChrome.css";'';
        "mozilla/firefox/default/chrome/userContent.css".text = ''@import "gnome-theme/userContent.css";'';
      };
    };

    programs.firefox = {
      enable = true;
      package = pkgs.zenos.apps.browsers.firefox;
      policies = {
        DisableAccounts = true;
        DisableAppUpdate = true;
        DisableFirefoxStudies = true;
        DisableTelemetry = true;
        DisplayBookmarksToolbar = "never";
        DisplayMenuBar = "default-off";
        DontCheckDefaultBrowser = true;
        EnableTrackingProtection = { Value = true; Locked = true; Cryptomining = true; Fingerprinting = true; };
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
        SearchEngines = { Default = "DuckDuckGo"; PreventInstalls = false; };
        UserMessaging = {
          ExtensionRecommendations = false;
          FeatureRecommendations = false;
          MoreFromMozilla = false;
          SkipOnboarding = true;
          WhatsNew = false;
        };
      };
      preferencesStatus = "locked";
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
    };
  };
}
