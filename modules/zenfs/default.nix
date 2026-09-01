{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    concatLists
    concatMapStringsSep
    escapeShellArg
    filterAttrs
    mapAttrs
    mapAttrsToList
    mkEnableOption
    mkIf
    mkOption
    nameValuePair
    optional
    types
    unique
    ;
  cfg = config.zenfs;
  zenfsctl = pkgs.callPackage ../../packages/zenfsctl { };
  appIndex = pkgs.callPackage ../../packages/app-index { };
  nautilusApps = pkgs.callPackage ../../packages/nautilus-apps { inherit appIndex; };
  hasManagedUsers = cfg.users != { };
  managedIdentityPatterns = concatMapStringsSep "|" escapeShellArg (
    mapAttrsToList (name: userCfg: "${name}:${getUserHome name userCfg}") cfg.users
  );

  enabledAliases = filterAttrs (_: target: target != null) cfg.hierarchy.aliases;
  aliasPairs = mapAttrsToList (path: target: { inherit path target; }) enabledAliases;
  managedDirectories = cfg.hierarchy.directories;

  getUserHome = _name: userCfg: userCfg.home;

  isSafeRelative =
    path:
    path != ""
    && !(lib.hasPrefix "/" path)
    && builtins.all (component: component != "" && component != "." && component != "..") (
      lib.splitString "/" path
    );

  userDirectories = concatLists (
    mapAttrsToList (
      name: userCfg:
      let
        home = getUserHome name userCfg;
        directoryRule = mode: path: {
          inherit path mode;
          user = name;
          inherit (userCfg) group;
        };
      in
      [ (directoryRule userCfg.homeMode home) ]
      ++ map (directory: directoryRule "0700" "${home}/${directory}") userCfg.privateDirectories
      ++ map (directory: directoryRule "0750" "${home}/${directory}") userCfg.xdgDirectories
    ) cfg.users
  );

  driveList = mapAttrsToList (name: drive: drive // { inherit name; }) cfg.roaming.drives;
  enabledDrives = builtins.filter (drive: drive.enable) driveList;
  privateMounts = concatLists (
    map (
      drive:
      mapAttrsToList (
        mountName: mount:
        let
          userCfg =
            cfg.users.${mount.user} or {
              home = "/Users/${mount.user}";
              group = "users";
            };
          home = getUserHome mount.user userCfg;
        in
        mount
        // {
          inherit drive mountName;
          inherit (userCfg) group;
          sourcePath = "${drive.mountPoint}/${mount.source}";
          targetPath = if mount.target == null then "${home}/${mountName}" else mount.target;
        }
      ) drive.privateMounts
    ) enabledDrives
  );

  tmpfileDirectories =
    map (path: {
      inherit path;
      mode = "0755";
      user = "root";
      group = "root";
    }) managedDirectories
    ++ userDirectories
    ++ map (drive: {
      path = drive.mountPoint;
      mode = "0755";
      user = "root";
      group = "root";
    }) enabledDrives
    ++ map (mount: {
      path = mount.targetPath;
      mode = "0700";
      user = mount.user;
      inherit (mount) group;
    }) privateMounts;

  userCompatibilityLinks = concatLists (
    mapAttrsToList (
      name: userCfg:
      let
        home = getUserHome name userCfg;
        linkRule = path: target: {
          inherit path target;
          user = name;
          inherit (userCfg) group;
        };
      in
      [
        (linkRule "${home}/.config" "${home}/.private/Config")
        (linkRule "${home}/.cache" "${home}/.private/Live")
        (linkRule "${home}/.local" "${home}/.private/Local")
        (linkRule "${home}/.private/Local/lib" "${home}/.private/Packages/lib")
        (linkRule "${home}/.private/Local/share" "${home}/.private/Packages")
        (linkRule "${home}/.private/Local/state" "${home}/.private/State")
      ]
    ) cfg.users
  );

  userDirsConfig = pkgs.writeText "zenfs-user-dirs.dirs" ''
    XDG_DESKTOP_DIR="$HOME/Desktop"
    XDG_DOWNLOAD_DIR="$HOME/Downloads"
    XDG_TEMPLATES_DIR="$HOME/Templates"
    XDG_PUBLICSHARE_DIR="$HOME/Public"
    XDG_DOCUMENTS_DIR="$HOME/Documents"
    XDG_MUSIC_DIR="$HOME/Music"
    XDG_PICTURES_DIR="$HOME/Pictures"
    XDG_VIDEOS_DIR="$HOME/Videos"
  '';

  userInit = pkgs.writeShellApplication {
    name = "zenfs-user-init";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.xdg-user-dirs
    ];
    text = ''
      private="$HOME/.private"

      migrate_directory() {
        source="$1"
        target="$2"
        if [ -L "$source" ]; then
          return
        fi
        install -d -m 0700 "$target"
        if [ -d "$source" ]; then
          cp -a "$source/." "$target/"
          rm -rf --one-file-system "$source"
        elif [ -e "$source" ]; then
          echo "ZenFS: refusing to replace non-directory $source" >&2
          return 1
        fi
        ln -s "$target" "$source"
      }

      install -d -m 0700 \
        "$private/Config" \
        "$private/Live" \
        "$private/Local" \
        "$private/Packages" \
        "$private/Packages/lib" \
        "$private/State"

      migrate_directory "$HOME/.config" "$private/Config"
      migrate_directory "$HOME/.cache" "$private/Live"

      if [ -d "$HOME/.local" ] && [ ! -L "$HOME/.local" ]; then
        for entry in lib share state; do
          if [ -L "$private/Local/$entry" ]; then
            rm "$private/Local/$entry"
          fi
        done
        migrate_directory "$HOME/.local/lib" "$private/Packages/lib"
        migrate_directory "$HOME/.local/share" "$private/Packages"
        migrate_directory "$HOME/.local/state" "$private/State"
      fi
      migrate_directory "$HOME/.local" "$private/Local"

      ln -sfn "$private/Packages/lib" "$private/Local/lib"
      ln -sfn "$private/Packages" "$private/Local/share"
      ln -sfn "$private/State" "$private/Local/state"

      export XDG_CACHE_HOME="$private/Live"
      export XDG_CONFIG_HOME="$private/Config"
      export XDG_DATA_HOME="$private/Packages"
      export XDG_STATE_HOME="$private/State"

      install -m 0600 ${userDirsConfig} "$XDG_CONFIG_HOME/user-dirs.dirs"
      xdg-user-dirs-update
    '';
  };

  userDirFiles = mapAttrsToList (name: userCfg: {
    path = "${getUserHome name userCfg}/.private/Config/user-dirs.dirs";
    user = name;
    inherit (userCfg) group;
  }) cfg.users;

  tmpfileSettings =
    builtins.listToAttrs (
      map (
        directory:
        nameValuePair directory.path {
          d = {
            inherit (directory) mode user group;
          };
        }
      ) tmpfileDirectories
    )
    // builtins.listToAttrs (
      map (
        link:
        nameValuePair link.path {
          L = {
            argument = link.target;
            inherit (link) user group;
          };
        }
      ) userCompatibilityLinks
    )
    // builtins.listToAttrs (
      map (
        file:
        nameValuePair file.path {
          C = {
            argument = "${userDirsConfig}";
            mode = "0600";
            inherit (file) user group;
          };
        }
      ) userDirFiles
    );

  driveFileSystems = builtins.listToAttrs (
    map (
      drive:
      nameValuePair drive.mountPoint {
        inherit (drive) device fsType options;
      }
    ) enabledDrives
  );

  privateFileSystems = builtins.listToAttrs (
    map (
      mount:
      nameValuePair mount.targetPath {
        device = mount.sourcePath;
        fsType = "none";
        options = [
          "bind"
          "nofail"
          "nodev"
          "nosuid"
          "noexec"
          "x-systemd.requires-mounts-for=${mount.drive.mountPoint}"
          "x-systemd.requires=zenfs-roaming-${mount.drive.name}-marker.service"
          "x-systemd.after=zenfs-roaming-${mount.drive.name}-marker.service"
        ]
        ++ optional mount.readOnly "ro";
      }
    ) privateMounts
  );

  markerServices = builtins.listToAttrs (
    map (
      drive:
      nameValuePair "zenfs-roaming-${drive.name}-marker" {
        description = "Verify ZenFS marker for roaming drive ${drive.name}";
        after = [ "local-fs-pre.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = concatMapStringsSep " " escapeShellArg [
            "${zenfsctl}/bin/zenfsctl"
            "verify-marker"
            "${drive.mountPoint}/${drive.markerFile}"
            "--id"
            drive.markerId
          ];
        };
        unitConfig.RequiresMountsFor = [ drive.mountPoint ];
      }
    ) enabledDrives
  );

  manifest = pkgs.writeText "zenfs-manifest.json" (
    builtins.toJSON {
      schema = "zenfs-v1";
      aliases = enabledAliases;
      directories = managedDirectories;
      users = mapAttrs (name: userCfg: {
        home = getUserHome name userCfg;
        inherit (userCfg) group;
      }) cfg.users;
      roaming = mapAttrs (_: drive: {
        inherit (drive)
          enable
          markerId
          markerFile
          mountPoint
          ;
      }) cfg.roaming.drives;
    }
  );

  hiddenRootEntries = pkgs.writeText "zenfs-hidden-root-entries" (
    concatMapStringsSep "\n" (entry: entry) cfg.hierarchy.hiddenRootEntries + "\n"
  );

  hierarchyMigration = ''
    if [ -L /Live ] && [ "$(${pkgs.coreutils}/bin/readlink -- /Live)" = /run ]; then
      ${pkgs.coreutils}/bin/rm -- /Live
    fi
    if [ -L /Packages ] && [ "$(${pkgs.coreutils}/bin/readlink -- /Packages)" = /nix/store ]; then
      ${pkgs.coreutils}/bin/rm -- /Packages
    fi
    if [ -d /Config ] && [ ! -L /Config ]; then
      if [ -e /Config/ZenOS ]; then
        if [ -e /etc/ZenOS ]; then
          echo "ZenFS: refusing to merge both /Config/ZenOS and /etc/ZenOS" >&2
          exit 1
        fi
        ${pkgs.coreutils}/bin/mv -- /Config/ZenOS /etc/ZenOS
      fi
      ${pkgs.coreutils}/bin/rmdir -- /Config || {
        echo "ZenFS: refusing to replace non-empty /Config" >&2
        exit 1
      }
    fi
    if [ -L /Users ] && [ "$(${pkgs.coreutils}/bin/readlink -- /Users)" = /home ] \
      && [ -d /home ] && [ ! -L /home ]; then
      if ${pkgs.util-linux}/bin/mountpoint -q /home; then
        echo "ZenFS: refusing to migrate a separately mounted /home" >&2
        exit 1
      fi
      ${pkgs.coreutils}/bin/rm -- /Users
      if ${pkgs.coreutils}/bin/mv -- /home /Users; then
        ${pkgs.coreutils}/bin/ln -s -- /Users /home
      else
        ${pkgs.coreutils}/bin/ln -s -- /home /Users
        echo "ZenFS: failed to migrate /home to /Users" >&2
        exit 1
      fi
    fi
  '';

  aliasActivation = concatMapStringsSep "\n" (
    alias:
    let
      path = escapeShellArg alias.path;
      target = escapeShellArg alias.target;
    in
    ''
      if [ -L ${path} ]; then
        actual="$(${pkgs.coreutils}/bin/readlink -- ${path})"
        if [ "$actual" != ${target} ]; then
          echo "ZenFS: refusing to replace ${alias.path}: symlink points to $actual" >&2
          exit 1
        fi
      elif [ -e ${path} ]; then
        echo "ZenFS: refusing to replace existing path ${alias.path}" >&2
        exit 1
      else
        ${pkgs.coreutils}/bin/ln -s -- ${target} ${path}
      fi
    ''
  ) aliasPairs;

  directoryActivation = concatMapStringsSep "\n" (path: ''
    if [ -L ${escapeShellArg path} ]; then
      echo "ZenFS: refusing to replace symlink ${path}" >&2
      exit 1
    fi
    if [ -e ${escapeShellArg path} ] && [ ! -d ${escapeShellArg path} ]; then
      echo "ZenFS: refusing to replace non-directory ${path}" >&2
      exit 1
    fi
    ${pkgs.coreutils}/bin/install -d -m 0755 -- ${escapeShellArg path}
  '') managedDirectories;

  allMountTargets =
    map (drive: drive.mountPoint) enabledDrives ++ map (mount: mount.targetPath) privateMounts;
  allPrivateUsers = map (mount: mount.user) privateMounts;
  restrictiveOptions = [
    "nodev"
    "nosuid"
    "noexec"
  ];
in
{
  options.zenfs = {
    enable = mkEnableOption "the ZenFS hierarchy and roaming storage module";

    hierarchy.aliases = mkOption {
      type = types.attrsOf (types.nullOr types.str);
      default = {
        "/Boot" = "/boot";
        "/Config" = "/etc";
        "/home" = "/Users";
        "/Packages" = "/nix";
        "/System/Config" = "/etc";
        "/System/Current" = "/run/current-system";
        "/System/Index" = "/run/current-system/sw";
        "/Live/Devices" = "/dev";
        "/Live/Processes" = "/proc";
        "/Live/Runtime" = "/run";
        "/Live/System" = "/sys";
        "/Live/Temporary" = "/tmp";
        "/Live/Variable" = "/var";
        "/Mount" = "/mnt";
      };
      description = ''
        Absolute hierarchy aliases and their absolute targets. Set an alias to
        null to omit it. Activation refuses to replace any existing non-symlink
        or a symlink with a different target.
      '';
    };

    hierarchy.directories = mkOption {
      type = types.listOf types.str;
      default = [
        "/Apps"
        "/Live"
        "/System"
        "/Users"
        "/mnt"
      ];
      description = "Real top-level ZenFS directories created before hierarchy aliases.";
    };

    hierarchy.hiddenRootEntries = mkOption {
      type = types.listOf types.str;
      default = [
        "bin"
        "boot"
        "dev"
        "etc"
        "home"
        "lib"
        "lib32"
        "lib64"
        "media"
        "mnt"
        "nix"
        "opt"
        "proc"
        "root"
        "run"
        "sbin"
        "srv"
        "sys"
        "tmp"
        "usr"
        "var"
      ];
      description = "FHS implementation paths hidden by file managers at the filesystem root.";
    };

    users = mkOption {
      default = { };
      description = "Users whose private and XDG directory layout ZenFS manages.";
      type = types.attrsOf (
        types.submodule (
          { name, ... }: {
            options = {
              home = mkOption {
                type = types.str;
                default = "/Users/${name}";
                description = "Absolute home path managed for this user.";
              };
              group = mkOption {
                type = types.str;
                default = "users";
                description = "Owning group for managed directories.";
              };
              homeMode = mkOption {
                type = types.strMatching "0[0-7]{3}";
                default = "0700";
                description = "Mode enforced on the user's home directory.";
              };
              privateDirectories = mkOption {
                type = types.listOf types.str;
                default = [
                  ".private"
                  ".private/Apps"
                  ".private/Config"
                  ".private/Live"
                  ".private/Local"
                  ".private/Mount"
                  ".private/Packages"
                  ".private/Packages/lib"
                  ".private/State"
                ];
                description = "Private directories relative to the user's home.";
              };
              xdgDirectories = mkOption {
                type = types.listOf types.str;
                default = [
                  "Desktop"
                  "Documents"
                  "Downloads"
                  "Music"
                  "Pictures"
                  "Public"
                  "Templates"
                  "Videos"
                ];
                description = "User-facing XDG directories relative to the home.";
              };
            };
          }
        )
      );
    };

    roaming.drives = mkOption {
      default = { };
      description = "Restrictively mounted roaming drives.";
      type = types.attrsOf (
        types.submodule (
          { name, ... }: {
            options = {
              enable = mkOption {
                type = types.bool;
                default = true;
              };
              device = mkOption {
                type = types.str;
                example = "/dev/disk/by-label/zenos-roaming";
                description = "Stable block-device path or other fileSystems device.";
              };
              fsType = mkOption {
                type = types.str;
                default = "auto";
              };
              mountPoint = mkOption {
                type = types.str;
                default = "/Mount/${name}";
              };
              options = mkOption {
                type = types.listOf types.str;
                default = [
                  "nofail"
                  "x-systemd.automount"
                  "x-systemd.device-timeout=10s"
                  "nodev"
                  "nosuid"
                  "noexec"
                ];
                description = "Mount options; restrictive defaults may be extended or replaced explicitly.";
              };
              markerFile = mkOption {
                type = types.str;
                default = ".zenfs-roaming.json";
                description = "Marker path relative to the drive root.";
              };
              markerId = mkOption {
                type = types.str;
                default = name;
                description = "Identifier required in the roaming marker before private mounts activate.";
              };
              privateMounts = mkOption {
                default = { };
                description = "Private bind mounts sourced from this roaming drive.";
                type = types.attrsOf (
                  types.submodule (
                    { name, ... }: {
                      options = {
                        user = mkOption {
                          type = types.str;
                          description = "ZenFS-managed user that owns the mountpoint.";
                        };
                        source = mkOption {
                          type = types.str;
                          default = name;
                          description = "Source path relative to the drive root.";
                        };
                        target = mkOption {
                          type = types.nullOr types.str;
                          default = null;
                          description = "Absolute target, or HOME/name when null.";
                        };
                        readOnly = mkOption {
                          type = types.bool;
                          default = true;
                        };
                      };
                    }
                  )
                );
              };
            };
          }
        )
      );
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.all (alias: lib.hasPrefix "/" alias.path && alias.path != "/") aliasPairs;
        message = "ZenFS hierarchy alias paths must be absolute and cannot be /.";
      }
      {
        assertion = builtins.all (path: lib.hasPrefix "/" path && path != "/") managedDirectories;
        message = "ZenFS hierarchy directories must be absolute and cannot be /.";
      }
      {
        assertion = builtins.all (
          alias:
          lib.hasPrefix "/" alias.target
          && alias.target != alias.path
          && builtins.all (
            other: alias.target != other.path && !(lib.hasPrefix "${other.path}/" alias.target)
          ) aliasPairs
        ) aliasPairs;
        message = "ZenFS hierarchy targets must be absolute and outside the managed alias namespace.";
      }
      {
        assertion = builtins.all (
          outer:
          builtins.all (
            inner: outer.path == inner.path || !(lib.hasPrefix "${outer.path}/" inner.path)
          ) aliasPairs
        ) aliasPairs;
        message = "ZenFS hierarchy aliases cannot be nested beneath one another.";
      }
      {
        assertion = builtins.all (alias: !(builtins.hasAttr alias.path config.fileSystems)) aliasPairs;
        message = "ZenFS hierarchy aliases cannot also be filesystem mount targets.";
      }
      {
        assertion = builtins.all (userCfg: lib.hasPrefix "/" userCfg.home && userCfg.home != "/") (
          builtins.attrValues cfg.users
        );
        message = "ZenFS user homes must be absolute, non-root paths.";
      }
      {
        assertion = builtins.all isSafeRelative (
          concatLists (
            mapAttrsToList (_: userCfg: userCfg.privateDirectories ++ userCfg.xdgDirectories) cfg.users
          )
        );
        message = "ZenFS user directory entries must be safe relative paths without dot components.";
      }
      {
        assertion = builtins.all (
          drive:
          builtins.match "[A-Za-z0-9_.-]+" drive.name != null
          && lib.hasPrefix "/" drive.mountPoint
          && drive.mountPoint != "/"
          && drive.markerId != ""
        ) enabledDrives;
        message = "ZenFS roaming names must be unit-safe, mountpoints must be absolute and non-root, and marker IDs cannot be empty.";
      }
      {
        assertion = builtins.all (
          drive: builtins.all (option: builtins.elem option drive.options) restrictiveOptions
        ) enabledDrives;
        message = "ZenFS roaming drives must retain nodev, nosuid, and noexec mount options.";
      }
      {
        assertion = builtins.all (drive: isSafeRelative drive.markerFile) enabledDrives;
        message = "ZenFS roaming marker files must be safe relative paths.";
      }
      {
        assertion = builtins.all (mount: builtins.hasAttr mount.user cfg.users) privateMounts;
        message = "Every ZenFS private mount user must be declared in zenfs.users.";
      }
      {
        assertion = builtins.all (
          mount:
          isSafeRelative mount.mountName
          && isSafeRelative mount.source
          && lib.hasPrefix "/" mount.targetPath
          && mount.targetPath != "/"
        ) privateMounts;
        message = "ZenFS private mount names and sources must be safe relative paths, and targets must be absolute and non-root.";
      }
      {
        assertion = builtins.length allMountTargets == builtins.length (unique allMountTargets);
        message = "ZenFS roaming and private mount targets must be unique.";
      }
      {
        assertion = builtins.all (name: builtins.hasAttr name config.users.users) (
          builtins.attrNames cfg.users
        );
        message = "Every zenfs.users entry must name a declared NixOS user.";
      }
      {
        assertion = builtins.all (name: builtins.hasAttr name cfg.users) allPrivateUsers;
        message = "ZenFS private mounts require a matching zenfs.users entry.";
      }
    ];

    environment = {
      etc."zenfs/manifest.json".source = manifest;
      etc."systemd/user-environment-generators/20-zenfs".source = lib.mkIf hasManagedUsers (
        pkgs.writeShellScript "zenfs-user-environment-generator" ''
          case "''${USER-}:$HOME" in
          ${managedIdentityPatterns})
            printf '%s\n' \
              "XDG_CACHE_HOME=$HOME/.private/Live" \
              "XDG_CONFIG_HOME=$HOME/.private/Config" \
              "XDG_DATA_HOME=$HOME/.private/Packages" \
              "XDG_STATE_HOME=$HOME/.private/State"
            ;;
          esac
        ''
      );
      extraInit = lib.mkIf hasManagedUsers ''
        case "''${USER-}:$HOME" in
        ${managedIdentityPatterns})
          export XDG_CACHE_HOME="$HOME/.private/Live"
          export XDG_CONFIG_HOME="$HOME/.private/Config"
          export XDG_DATA_HOME="$HOME/.private/Packages"
          export XDG_STATE_HOME="$HOME/.private/State"
          ;;
        esac
      '';
      systemPackages = [ zenfsctl ];
    };

    fileSystems = driveFileSystems // privateFileSystems;
    systemd.services = markerServices // {
      zenos-app-index = {
        description = "Build the ZenOS application directory";
        wantedBy = [ "multi-user.target" ];
        wants = [ "systemd-tmpfiles-setup.service" ];
        after = [ "systemd-tmpfiles-setup.service" ];
        before = [ "display-manager.service" ];
        path = [ config.system.path ];
        restartTriggers = [ config.system.path ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe appIndex} --home /var/empty --target /Apps";
        };
      };
    };
    systemd.user.services.zenfs-user-init = {
      description = "Initialize the per-user ZenFS layout";
      wantedBy = [ "graphical-session-pre.target" ];
      before = [ "graphical-session.target" ];
      unitConfig.ConditionPathExists = "%h/.private/Config/user-dirs.dirs";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe userInit;
        RemainAfterExit = true;
      };
    };
    systemd.user.services.zenos-user-app-index = {
      description = "Build and decorate the per-user ZenOS application directory";
      wantedBy = [ "graphical-session-pre.target" ];
      requires = [ "zenfs-user-init.service" ];
      after = [ "zenfs-user-init.service" ];
      before = [ "graphical-session.target" ];
      unitConfig.ConditionPathIsDirectory = "%h/.private/Apps";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = [
          "${lib.getExe appIndex} --home %h --target %h/.private/Apps --user %u"
          "${nautilusApps}/bin/zen-app-icons /Apps"
          "${nautilusApps}/bin/zen-app-icons %h/.private/Apps"
        ];
        RemainAfterExit = true;
      };
    };
    systemd.tmpfiles.settings."10-zenfs" = tmpfileSettings;
    systemd.tmpfiles.rules = [ "L+ /.hidden - - - - ${hiddenRootEntries}" ];

    system.activationScripts.zenfs-hierarchy = {
      deps = [ "etc" ];
      text = hierarchyMigration + "\n" + directoryActivation + "\n" + aliasActivation;
    };
    system.activationScripts.users.deps = [ "zenfs-hierarchy" ];
  };
}
