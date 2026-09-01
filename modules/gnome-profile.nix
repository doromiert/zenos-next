{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.zenos.gnomeProfile;
  emptyStringArray = lib.gvariant.mkEmptyArray lib.gvariant.type.string;
  directionKey = direction: if cfg.directionKeys == "vim" then {
    left = "h";
    down = "j";
    up = "k";
    right = "l";
  }.${direction} else {
    left = "Left";
    down = "Down";
    up = "Up";
    right = "Right";
  }.${direction};
  directionSettings = {
    "org/gnome/desktop/wm/keybindings" = {
      switch-to-workspace-left = [ "<Super><Control>${directionKey "left"}" ];
      switch-to-workspace-right = [ "<Super><Control>${directionKey "right"}" ];
      move-to-workspace-left = [ "<Super><Control><Shift>${directionKey "left"}" ];
      move-to-workspace-right = [ "<Super><Control><Shift>${directionKey "right"}" ];
      move-to-monitor-left = [ "<Super><Alt>${directionKey "left"}" ];
      move-to-monitor-right = [ "<Super><Alt>${directionKey "right"}" ];
    };
    "org/gnome/mutter/keybindings" = {
      toggle-tiled-left = emptyStringArray;
      toggle-tiled-right = emptyStringArray;
    };
    "org/gnome/shell/extensions/forge/keybindings" = {
      window-focus-left = [ "<Super>${directionKey "left"}" ];
      window-focus-down = [ "<Super>${directionKey "down"}" ];
      window-focus-up = [ "<Super>${directionKey "up"}" ];
      window-focus-right = [ "<Super>${directionKey "right"}" ];
      window-move-left = [ "<Shift><Super>${directionKey "left"}" ];
      window-move-down = [ "<Shift><Super>${directionKey "down"}" ];
      window-move-up = [ "<Shift><Super>${directionKey "up"}" ];
      window-move-right = [ "<Shift><Super>${directionKey "right"}" ];
    };
  };
  zenosActionSettings = lib.optionalAttrs (cfg.actionKeys == "zenos") {
    "org/gnome/desktop/wm/keybindings" = {
      close = [ "<Super>q" ];
      toggle-maximized = [ "<Super>w" ];
      minimize = [ "<Super>Page_Down" ];
      activate-window-menu = [ "<Alt>space" ];
      begin-resize = [ "<Control><Super>c" ];
      switch-input-source = [ "<Super>space" ];
      switch-input-source-backward = [ "<Shift><Super>space" ];
    };
    "org/gnome/settings-daemon/plugins/media-keys" = {
      maximize = emptyStringArray;
      unmaximize = emptyStringArray;
      screensaver = [ "<Super>Escape" ];
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/files/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/terminal/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/resources/"
      ];
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/files" = {
      name = "Files";
      command = "nautilus --new-window";
      binding = "<Super>e";
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/terminal" = {
      name = "Console";
      command = "kgx";
      binding = "<Super>t";
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/resources" = {
      name = "Resources";
      command = "resources";
      binding = "<Control><Shift>Escape";
    };
  };
  shortcutSettings = lib.recursiveUpdate directionSettings zenosActionSettings;
  gdmLogo = pkgs.runCommand "zenos-gdm-logo" { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
    install -d "$out/share/pixmaps"
    magick -background none -density 2400 \
      ${pkgs.zenos.theming.system.zenos-plymouth.src}/icons/zenos.svg \
      -resize 256x256 "$out/share/pixmaps/zenos-gdm.png"
  '';
  lockClockUuid = "CustomizeClockOnLockScreen@pratap.fastmail.fm";
  lockClockExtension = pkgs.runCommand "gnome-shell-extension-zenos-lock-clock" {
    nativeBuildInputs = [ pkgs.jq ];
  } ''
    cp -R ${pkgs.gnomeExtensions.customize-clock-on-lock-screen}/. "$out"
    chmod -R u+w "$out"
    metadata="$out/share/gnome-shell/extensions/${lockClockUuid}/metadata.json"
    jq '."shell-version" |= (. + ["50"] | unique)' "$metadata" > "$metadata.tmp"
    mv "$metadata.tmp" "$metadata"
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
in
{
  options.zenos.gnomeProfile = {
    enable = lib.mkEnableOption "the ZenOS GNOME profile";
    enableBranding = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether ZenOS GNOME visual branding is applied.";
    };
    enableExtensions = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether the ZenOS GNOME extension set is installed and enabled.";
    };
    directionKeys = lib.mkOption {
      type = lib.types.enum [ "standard" "vim" ];
      default = "vim";
      description = "Directional key family used by ZenOS navigation shortcuts.";
    };
    actionKeys = lib.mkOption {
      type = lib.types.enum [ "traditional" "zenos" ];
      default = "zenos";
      description = "Action shortcut profile used by the GNOME session.";
    };
    extensionPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "GNOME extension packages installed by the ZenOS profile.";
    };
    extensionIds = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Manifest extension IDs selected for the final GNOME session.";
    };
    enabledExtensionUuids = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "GNOME extension UUIDs enabled outside the temporary OOBE session.";
    };
    manageExtensions = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether this profile owns the enabled-extensions dconf key.";
    };
    wallpaper = lib.mkOption {
      type = lib.types.nullOr (lib.types.either lib.types.path lib.types.str);
      default = null;
      description = "ZenOS wallpaper used by this profile.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = lib.optionals cfg.enableBranding [
      clockTheme
      gdmLogo
      lockClockExtension
      pkgs.zenos.apps.cursors.google-dot
      pkgs.zenos.apps.themes.adw-gtk3
      pkgs.zenos.theming.fonts.zero.mono
      pkgs.zenos.theming.icons.adwaita-hacks
    ] ++ lib.optionals cfg.enableExtensions cfg.extensionPackages;

    programs.dconf.profiles.user.databases = [
      {
        settings = lib.optionalAttrs cfg.enableBranding ({
          "org/gnome/desktop/interface" = {
            accent-color = "purple";
            color-scheme = "prefer-dark";
            cursor-size = lib.gvariant.mkInt32 24;
            cursor-theme = "GoogleDot-Black";
            document-font-name = "Atkinson Hyperlegible 11";
            font-name = "Atkinson Hyperlegible 11";
            gtk-theme = "adw-gtk3-dark";
            icon-theme = "Adwaita-hacks";
            monospace-font-name = "AtkynsonMono NF 11";
            show-battery-percentage = true;
          };
        } // lib.optionalAttrs (cfg.wallpaper != null) {
          "org/gnome/desktop/background" = {
            color-shading-type = "solid";
            picture-options = "zoom";
            picture-uri = "file://${cfg.wallpaper}";
            picture-uri-dark = "file://${cfg.wallpaper}";
            primary-color = "#000000";
            secondary-color = "#000000";
          };
        }) // lib.optionalAttrs cfg.enableExtensions {
          "org/gnome/shell" = {
            disable-user-extensions = false;
          } // lib.optionalAttrs cfg.manageExtensions {
            enabled-extensions = cfg.enabledExtensionUuids ++ lib.optional cfg.enableBranding lockClockUuid;
          };
          "org/gnome/shell/extensions/customize-clock-on-lockscreen" = {
            remove-command-output = true;
            remove-time = false;
            remove-date = false;
            remove-hint = false;
            custom-time-text = "%H\n%M";
            custom-date-text = "%d.%m.%Y";
            clock-style = "digital";
            time-font-color = "rgba(255, 255, 255, 1.0)";
            time-font-size = lib.gvariant.mkInt32 96;
            time-font-family = "Zero Mono";
            time-font-weight = "Default";
            time-font-style = "Default";
            date-font-color = "rgba(255, 255, 255, 1.0)";
            date-font-size = lib.gvariant.mkInt32 36;
            date-font-family = "Zero Mono";
            date-font-weight = "Default";
            date-font-style = "Default";
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
          "org/gnome/shell/extensions/forge" = {
            dnd-center-layout = "swap";
            float-always-on-top-enabled = false;
            focus-border-toggle = false;
            quick-settings-enabled = false;
            split-border-toggle = false;
            stacked-tiling-mode-enabled = false;
            tabbed-tiling-mode-enabled = false;
            window-gap-size = lib.gvariant.mkUint32 4;
          };
          "org/gnome/shell/extensions/mouse-tail".render-mode = "precise";
          "org/gnome/shell/extensions/notification-timeout".timeout = lib.gvariant.mkInt32 2000;
        } // lib.optionalAttrs cfg.enableBranding {
          "org/gnome/shell/extensions/user-theme".name = "ClockOverride";
        } // shortcutSettings;
      }
    ];

    programs.dconf.profiles.gdm.databases = lib.optionals cfg.enableBranding [
      {
        settings = {
          "org/gnome/login-screen".logo = "${gdmLogo}/share/pixmaps/zenos-gdm.png";
          "org/gnome/desktop/interface" = {
            accent-color = "purple";
            color-scheme = "prefer-dark";
            cursor-theme = "GoogleDot-Black";
            font-name = "Atkinson Hyperlegible 11";
            icon-theme = "Adwaita-hacks";
          };
        };
      }
    ];
  };
}
