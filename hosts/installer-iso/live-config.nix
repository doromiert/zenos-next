{
  inputs,
  pkgs,
  lib ? pkgs.lib,
  hostName ? "zenos-installer",
  imageName ? "zenos-installer-iso",
  desktopSource ? null,
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  base = inputs.self.nixosConfigurations.${imageName}.config;
  # Deliberately selected scalar/list options, never serialize the module fixed point.
  tuning = {
    "time.timeZone" = base.time.timeZone;
    "i18n.defaultLocale" = base.i18n.defaultLocale;
    "console.keyMap" = base.console.keyMap;
    "services.fwupd.enable" = base.services.fwupd.enable;
    "services.fstrim.enable" = base.services.fstrim.enable;
    "zramSwap.enable" = base.zramSwap.enable;
    "nix.settings.auto-optimise-store" = base.nix.settings.auto-optimise-store or false;
    "nix.gc.automatic" = base.nix.gc.automatic;
    "nix.gc.dates" = base.nix.gc.dates;
    "nix.gc.options" = base.nix.gc.options;
  };
  home = base.home-manager.users.zenos;
  desktopValues = lib.optionalAttrs (desktopSource != null) (
    lib.mapAttrs' (key: value: lib.nameValuePair
      "dconf.settings.\"org/gnome/desktop/interface\".\"${key}\"" value)
      (lib.getAttrs [ "accent-color" "color-scheme" "cursor-size" "cursor-theme"
        "font-name" "document-font-name" "monospace-font-name" "gtk-theme" "icon-theme"
        "show-battery-percentage" ] home.dconf.settings."org/gnome/desktop/interface")
    // {
      "gtk.font.name" = home.gtk.font.name;
      "gtk.font.size" = home.gtk.font.size;
      "gtk.theme.name" = home.gtk.theme.name;
      "gtk.iconTheme.name" = home.gtk.iconTheme.name;
      "gtk.cursorTheme.name" = home.gtk.cursorTheme.name;
      "gtk.cursorTheme.size" = home.gtk.cursorTheme.size;
    }
  );
  assignments = prefix: values: lib.concatStringsSep "\n"
    (lib.mapAttrsToList (path: value: "${prefix}.${path} = ${builtins.toJSON value};") values);
  tuningSource = pkgs.writeText "zenos-live-system.zcfg" ''
    # Selected effective image defaults. Edit these values, then rebuild.
    # Boot, hardware, live login and installer restrictions remain in the base.
    ${assignments "legacy" tuning}
  '';
  desktop = pkgs.writeText "zenos-live-desktop.zcfg" (lib.optionalString (desktopSource != null) ''
    ${builtins.readFile desktopSource}

    # User interface defaults from the image's appearance backend.
    # GNOME dconf and GTK font/theme names are separate settings; edit both.
    ${assignments "users.zenos.legacy.homeManager" desktopValues}
  '');
  # Reference paths must not make reading this report build every listed package.
  snapshot = (pkgs.formats.json { }).generate "zenos-live-base-effective.json"
    (builtins.fromJSON (builtins.unsafeDiscardStringContext (builtins.toJSON {
    description = "Selected original image settings, not an editable or complete NixOS dump. Never imported.";
    sources = {
      image = "${inputs.self.outPath}/hosts/installer-iso/image.nix";
      system = "${inputs.self.outPath}/hosts/installer-iso/system.nix";
      appearance = "${inputs.self.outPath}/hosts/installer-iso/appearance.nix";
      zenpkgs = toString inputs.zenpkgs.outPath;
    };
    identity = { inherit (base.system.nixos) distroId distroName variant_id; };
    inherit tuning desktopValues;
    packages = map (package: { name = lib.getName package; storePath = toString package; })
      base.environment.systemPackages;
    users = lib.mapAttrs (_: user: {
      inherit (user) home isNormalUser extraGroups;
    }) (lib.filterAttrs (_: user: user.isNormalUser) base.users.users);
    services = {
      networkmanager = base.networking.networkmanager.enable;
      openssh = base.services.openssh.enable;
      pipewire = base.services.pipewire.enable;
      greetd = base.services.greetd.enable;
      gnome = base.services.desktopManager.gnome.enable;
    };
    boot = {
      inherit (base.boot) kernelParams supportedFilesystems;
      kernel = toString base.boot.kernelPackages.kernel;
      filesystems = lib.mapAttrs (_: fs: { inherit (fs) device fsType options; }) base.fileSystems;
    };
  })));
  pin =
    input:
    {
      url = "path:${input.outPath}";
    }
    // (
      if input ? inputs then
        {
          inputs = builtins.mapAttrs (_: pin) input.inputs;
        }
      else
        {
          flake = false;
        }
    );
  inputSources =
    input: [ input.outPath ] ++ lib.concatMap inputSources (builtins.attrValues (input.inputs or { }));
  # Refer to the image source, never to this generated seed or its own outputs.
  # In particular, do not recurse through inputs.self when pinning the graph.
  pinnedInputs = {
    actualImage = {
      url = "path:${inputs.self.outPath}";
      inputs = builtins.mapAttrs (_: pin) (builtins.removeAttrs inputs [ "self" ]);
    };
    nixpkgs.follows = "actualImage/nixpkgs";
    zenpkgs.follows = "actualImage/zenpkgs";
  };
  flake = pkgs.writeText "zenos-live-flake.nix" ''
    {
      description = "Editable ZenOS live image configuration";
      inputs = ${lib.generators.toPretty { } pinnedInputs};
      outputs = inputs:
        let
          system = ${builtins.toJSON system};
          pkgs = import inputs.nixpkgs { inherit system; };
          sourcesRoot = ./.;
          generated = pkgs.runCommand "zenos-live-${hostName}.nix" {
            nativeBuildInputs = [ inputs.zenpkgs.packages.''${system}.zen-dsl (pkgs.lib.getBin pkgs.nix) ];
            src = sourcesRoot;
          } '''
            zen-dsl check "$src/hosts/${hostName}/host.zcfg" --import-root "$src"
            zen-dsl compile "$src/hosts/${hostName}/host.zcfg" --import-root "$src" -o "$out"
            export NIX_REMOTE="local?root=$TMPDIR/parse-store"
            nix-store --init
            nix-instantiate --parse "$out" > /dev/null
          ''';
          sources = input: [ input.outPath ] ++ pkgs.lib.concatMap sources
            (builtins.attrValues (input.inputs or { }));
        in {
          nixosConfigurations.${builtins.toJSON hostName} =
            inputs.actualImage.nixosConfigurations.${builtins.toJSON imageName}.extendModules {
              modules = [
                (args@{ lib, pkgs, ... }:
                  let
                    # Traverse definitions, not wrapper metadata or atomic values.
                    prioritize = path: value:
                      if path == [ "zenos" "legacy" "fonts" "packages" ] && builtins.isList value then
                        # Keep the base's fallback fonts and ordering as well as authored fonts.
                        let inherited = inputs.actualImage.nixosConfigurations.${builtins.toJSON imageName}.config.fonts.packages;
                        in lib.mkOverride 90 (inherited ++ builtins.filter
                          (font: !builtins.elem font inherited) value)
                      else if !builtins.isAttrs value || lib.isDerivation value || lib.isFunction value then
                        lib.mkOverride 90 value
                      else if (value._type or "") == "merge" then
                        value // { contents = map (prioritize path) value.contents; }
                      else if (value._type or "") == "if" then
                        value // { content = prioritize path value.content; }
                      else if (value._type or "") == "override" then
                        value
                      else if value ? _type then
                        lib.mkOverride 90 value
                      # ZSTR selectors are one custom option, not leaf options.
                      else if path == [ "zenos" "system" "packages" ]
                        || (builtins.length path == 4 && lib.take 2 path == [ "zenos" "users" ]
                          && lib.last path == "packages") then
                        lib.mkOverride 90 (lib.recursiveUpdate
                          (lib.attrByPath path { }
                            inputs.actualImage.nixosConfigurations.${builtins.toJSON imageName}.config)
                          value)
                      else
                        lib.mapAttrs (name: prioritize (path ++ [ name ])) value;
                  in {
                    config = prioritize [ ] ((import generated) (args // {
                      # Package literals use the frozen image package set, avoiding
                      # the legacy alias module's own pkgs argument fixed point.
                      pkgs = inputs.actualImage.nixosConfigurations.${builtins.toJSON imageName}.pkgs;
                    }));
                  })
                {
                  system.build.zenosGeneratedConfig = generated;
                  system.extraDependencies = [ sourcesRoot generated ]
                    ++ pkgs.lib.unique (sources inputs.actualImage);
                }
              ];
            };
          packages.''${system}.generated-host = generated;
        };
    }
  '';
  readme = pkgs.writeText "zenos-live-README.md" ''
    # Live ZenOS Configuration

    This flake extends the frozen actual image composition in `actualImage`.
    It preserves the image's ZenOS identity, live filesystems, session, Setup,
    packages and services; it is not an installed-system hardware template.

    ## Files to read and edit

    - `hosts/${hostName}/host.zcfg`: entry point importing the editable files below.
    - `hosts/${hostName}/system.zcfg`: locale, timezone, console keyboard, firmware
      updates, SSD trimming, compressed swap and Nix garbage collection defaults.
    ${lib.optionalString (desktopSource != null) ''
    - `hosts/${hostName}/desktop.zcfg`: the actual authored image appearance source,
      including dock, extensions, animation values, fonts and theme packages;
      followed by the actual user's GNOME/GTK font, cursor and theme defaults.
      For example, change `notification-timeout.timeout = 2000` to `3500`.
      GNOME interface settings at the bottom control the live user's theme/font;
      update corresponding GTK values too. Package selections and activation are
      separate: disabling an extension does not necessarily remove its package.
    ''}
    - `base-effective.json`: readable selected original settings, package names
      and exact store identities, normal-user homes/groups, services and boot.
      This is reference only, never imported, and does not refresh after edits.
    - `flake.nix`: compiler and frozen image wiring; normally leave unchanged.

    Run `zenos-rebuild --show-generated` to check edits, then `zenos-rebuild` to apply.
    Removing an assignment restores inheritance; it does not disable that setting.
    This is a useful editable subset, not a full editable NixOS dump.

    ## Where inherited configuration comes from

    Read-only base source root: `${inputs.self.outPath}`.
    `hosts/installer-iso/image.nix` owns installation media, live filesystems,
    image packages and seeding. `hosts/installer-iso/system.nix` owns services,
    users, boot integration, session and Setup. `hosts/installer-iso/appearance.nix`
    owns the remaining appearance backend; `appearance.zcfg` is shared with the
    editable desktop copy. Upstream modules/packages come from the pinned
    `${inputs.zenpkgs.outPath}` and `${inputs.nixpkgs.outPath}` sources.
    These backend sources stay in the store, not editable Nix files under /Config.
    The live base is retained, including its forced login/media restrictions.

    Split sources may use the current DSL's `_import "file.zcfg";` syntax.
    User sources belong in `/Users/<user>/.private/Config/<name>.zcfg`, with
    matching absolute links at `hosts/${hostName}/users/<user>/<name>.zcfg`.
    Rebuild materializes these links into a private snapshot before Nix runs.
    Do not evaluate the editable flake directly when it contains external links.

    `zenos-rebuild --show-generated` checks and compiles without switching and
    prints the store path of the local ZCFG module. It is a generated view,
    not the complete image configuration and not an editable `host.nix`.
    The same derivation is exported as `packages.${system}.generated-host` and
    `nixosConfigurations.${hostName}.config.system.build.zenosGeneratedConfig`.
    The flake's pinned `zen-dsl` compiler owns generation, not a global `zcfg`.
    Raw Nix stays in store outputs or private temporary work directories.

    Local authored values use backend priority 90: they replace overlapping
    ordinary image values (100), but image `mkForce` restrictions (50) still win.
    Only local leaves are prioritized; unrelated image settings are retained.
    Conditional/merge wrappers and explicit backend override priorities survive.
    A local list replaces that setting's ordinary list, rather than appending.
    Font packages are the exception: the base's fonts and ordering are retained
    and newly selected fonts are added, so fallback fonts are not lost. Package
    selector trees merge with base selectors; local booleans win at authored paths.
    The generated view shows compiler output before this live-only priority rule.

    Rebuild logs are under `$XDG_STATE_HOME/zenos/rebuild-logs` (falling back to
    `$HOME/.local/state`). Canonical sources and their links are never rewritten.
    Source snapshots are retained in the built system closure for later rebuilds.
    These sources enter the Nix store; do not put secrets in ZCFG or JSON.

    Live edits are on the live filesystem and are not automatically persistent
    across a reboot. Setup uses its separate `/iso-config-template` contract to
    create installed configurations. Do not use this live flake as that template.
  '';
in
assert lib.assertMsg (
  builtins.match "[a-zA-Z0-9][a-zA-Z0-9_-]*" hostName != null
) "live-config hostName must be a simple host name";
{
  seed = pkgs.runCommand "zenos-live-config" { } ''
    mkdir -p "$out/hosts/${hostName}"
    cp ${flake} "$out/flake.nix"
    cp ${readme} "$out/README.md"
    cp ${snapshot} "$out/base-effective.json"
    cp ${tuningSource} "$out/hosts/${hostName}/system.zcfg"
    ${lib.optionalString (desktopSource != null) ''cp ${desktop} "$out/hosts/${hostName}/desktop.zcfg"''}
    cat > "$out/hosts/${hostName}/host.zcfg" <<'ZCFG'
    # Local additions to the frozen actual live image, using the current DSL.
    legacy.networking.hostName = ${builtins.toJSON hostName};
    _import "system.zcfg";
    ${lib.optionalString (desktopSource != null) ''_import "desktop.zcfg";''}
    ZCFG
  '';
  sources = lib.unique (
    [ inputs.self.outPath ]
    ++ lib.concatMap inputSources (builtins.attrValues (builtins.removeAttrs inputs [ "self" ]))
  );
}
