{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  oobeUser = "zenos";
  extensionUuid = "zenos-oobe-mode@neg-zero.com";
  blackWallpaper = pkgs.writeText "zenos-oobe-black.svg" ''
    <svg xmlns="http://www.w3.org/2000/svg" width="1" height="1">
      <rect width="1" height="1" fill="#000000"/>
    </svg>
  '';

  oobeExtension = pkgs.stdenvNoCC.mkDerivation {
    pname = "gnome-shell-extension-zenos-oobe-mode";
    version = "1.0.0";
    src = inputs.zenos-oobe-mode;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      install -d "$out/share/gnome-shell/extensions/${extensionUuid}"
      install -m 0644 extension.js metadata.json \
        "$out/share/gnome-shell/extensions/${extensionUuid}/"
      install -d "$out/share/gnome-shell/modes"
      install -m 0644 zenos-oobe.json \
        "$out/share/gnome-shell/modes/zenos-oobe.json"
      runHook postInstall
    '';

    passthru.extensionUuid = extensionUuid;
  };

  setupApp =
    inputs.zenos-setup.packages.${pkgs.stdenv.hostPlatform.system}.zenos-install.overrideAttrs
      (old: {
        buildInputs = (old.buildInputs or [ ]) ++ [
          pkgs.gnome-desktop
          pkgs.gst_all_1.gst-plugins-rs
        ];
        meta = (old.meta or { }) // {
          mainProgram = "zenos-setup";
        };
      });
in
{
  users = {
    mutableUsers = false;
    users = {
      root.hashedPassword = "!";
      ${oobeUser} = {
        isNormalUser = true;
        description = "ZenOS Setup";
        initialHashedPassword = "";
        extraGroups = [
          "input"
          "networkmanager"
          "video"
          "wheel"
        ];
      };
    };
  };

  environment = {
    systemPackages = [
      oobeExtension
      setupApp
    ];
    sessionVariables.ZENOS_OOBE = "1";
  };

  programs.dconf.profiles.user.databases = [
    {
      settings = {
        "org/gnome/shell" = {
          disable-user-extensions = false;
          enabled-extensions = [ extensionUuid ];
          favorite-apps = lib.gvariant.mkEmptyArray lib.gvariant.type.string;
        };
        "org/gnome/desktop/interface" = {
          color-scheme = "prefer-dark";
          enable-animations = true;
        };
        "org/gnome/desktop/background" = {
          color-shading-type = "solid";
          picture-options = "zoom";
          picture-uri = "file://${blackWallpaper}";
          picture-uri-dark = "file://${blackWallpaper}";
          primary-color = "#000000";
          secondary-color = "#000000";
        };
        "org/gnome/desktop/lockdown" = {
          disable-lock-screen = true;
          disable-log-out = true;
          disable-user-switching = true;
        };
        "org/gnome/desktop/session".idle-delay = lib.gvariant.mkUint32 0;
        "org/gnome/settings-daemon/plugins/power" = {
          sleep-inactive-ac-type = "nothing";
          sleep-inactive-battery-type = "nothing";
        };
      };
      locks = [
        "/org/gnome/shell/disable-user-extensions"
        "/org/gnome/shell/enabled-extensions"
      ];
    }
  ];

  systemd.user.services.zenos-oobe = {
    description = "ZenOS out-of-box experience";
    wantedBy = [ "graphical-session.target" ];
    after = [ "gnome-session.target" ];
    partOf = [ "graphical-session.target" ];
    path = lib.mkForce [ ];
    environment.PATH = "/run/wrappers/bin:/run/current-system/sw/bin";
    serviceConfig = {
      Type = "exec";
      ExecStart = "${lib.getExe setupApp} --oobe";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  systemd.tmpfiles.rules = [
    "d /etc/ZenOS 0755 root root -"
    "d /etc/ZenOS/Flake 0775 ${oobeUser} users -"
  ];
}
