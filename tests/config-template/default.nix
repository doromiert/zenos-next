{
  configTemplate,
  pkgs,
}:

let
  fixture =
    pkgs.runCommand "zenos-config-template-fixture"
      {
        nativeBuildInputs = [ pkgs.nix ];
      }
      ''
        cp -R ${configTemplate}/. "$out"
        chmod -R u+w "$out"

        for host in final oobe; do
          mkdir -p "$out/hosts/$host"
          cat > "$out/hosts/$host/host.nix" <<'EOF'
        { pkgs }:
        {
           zenos.desktops.gnome.enable = true;
           zenos.gnomeProfile.enable = true;
           zenos.legacy = {
             users.users.contract = {
               isNormalUser = true;
               group = "users";
             };
           };
           zenfs.users.contract = {
             home = "/home/contract";
             group = "users";
           };
           disko.devices.disk.generated = {
             type = "disk";
             device = "/dev/vda";
             content = {
               type = "gpt";
               partitions = { };
             };
           };
           services.xserver.videoDrivers = [ "modesetting" ];
           environment.gnome.excludePackages = [ pkgs.gnome-extension-manager ];
           environment.systemPackages = [ pkgs.zenos.theming.icons.zenos-icons ];
        }
        EOF
        done
        for host in final oobe; do
          cat > "$out/hosts/$host/hardware-configuration.nix" <<'EOF'
        { ... }:
        {
          fileSystems."/" = {
            device = "/dev/disk/by-label/zenos-root";
            fsType = "ext4";
          };
        }
        EOF
        done
        touch "$out/hosts/oobe/oobe.json"

        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"
        nix --extra-experimental-features 'nix-command flakes' \
          flake lock --offline "$out"
      '';
  fixturePath = builtins.toString fixture;
  fixtureLock = builtins.readFile (fixturePath + "/flake.lock");
  fixtureHashFile =
    pkgs.runCommand "zenos-config-template-fixture-hash"
      {
        nativeBuildInputs = [ pkgs.nix ];
      }
      ''
        nix --extra-experimental-features nix-command hash path ${fixture} > "$out"
      '';
  fixtureHash = pkgs.lib.removeSuffix "\n" (builtins.readFile fixtureHashFile);
  rendered = builtins.seq fixtureLock (
    builtins.getFlake (
      "path:" + builtins.unsafeDiscardStringContext fixturePath + "?narHash=" + fixtureHash
    )
  );
  finalConfig = rendered.nixosConfigurations.final.config;
  oobeConfig = rendered.nixosConfigurations.oobe.config;
  finalPackageNames = map (
    package: package.pname or package.name
  ) finalConfig.environment.systemPackages;
  oobePackageNames = map (
    package: package.pname or package.name
  ) oobeConfig.environment.systemPackages;
  gdmDatabase = builtins.head (
    builtins.filter builtins.isAttrs finalConfig.programs.dconf.profiles.gdm.databases
  );
  lockClockDatabase = builtins.head (
    builtins.filter (
      database:
      builtins.isAttrs database
      && database.settings ? "org/gnome/shell/extensions/customize-clock-on-lockscreen"
    ) finalConfig.programs.dconf.profiles.user.databases
  );
in
assert !finalConfig.zenos.oobe.enable;
assert oobeConfig.zenos.oobe.enable;
assert finalConfig.services.displayManager.gdm.enable;
assert !oobeConfig.services.displayManager.gdm.enable;
assert finalConfig.system.stateVersion == "26.05";
assert finalConfig.fileSystems ? "/";
assert oobeConfig.fileSystems ? "/";
assert !finalConfig.boot.loader.refind.enable;
assert !finalConfig.boot.loader.grub.enable;
assert finalConfig.boot.loader.systemd-boot.enable;
assert pkgs.lib.hasInfix "refind-install --yes"
  finalConfig.boot.loader.systemd-boot.extraInstallCommands;
assert finalConfig.zenos.gnomeProfile.enable;
assert finalConfig.zenos.gnomeProfile.directionKeys == "vim";
assert finalConfig.zenos.gnomeProfile.actionKeys == "zenos";
assert gdmDatabase.settings."org/gnome/desktop/interface".accent-color == "purple";
assert pkgs.lib.hasSuffix "/share/pixmaps/zenos-gdm.png"
  gdmDatabase.settings."org/gnome/login-screen".logo;
assert
  lockClockDatabase.settings."org/gnome/shell/extensions/customize-clock-on-lockscreen".custom-time-text
  == "%H\n%M";
assert
  lockClockDatabase.settings."org/gnome/shell/extensions/customize-clock-on-lockscreen".custom-date-text
  == "%d.%m.%Y";
assert finalConfig.zenfs.enable;
assert finalConfig.zenfs.hierarchy.aliases."/Boot" == "/boot";
assert finalConfig.zenfs.hierarchy.aliases."/Config" == "/etc";
assert finalConfig.zenfs.hierarchy.aliases."/Packages" == "/nix";
assert builtins.elem "/Live" finalConfig.zenfs.hierarchy.directories;
assert finalConfig.zenfs.users.contract.home == "/home/contract";
assert oobeConfig.zenfs.users.zenos.home == "/home/zenos";
assert pkgs.lib.hasInfix "/Apps"
  finalConfig.systemd.services.zenos-app-index.serviceConfig.ExecStart;
assert finalConfig.nixpkgs.config.allowUnfree;
assert oobeConfig.nixpkgs.config.allowUnfree;
assert builtins.elem "zenos-icons" finalPackageNames;
assert builtins.elem "zenos-icons" oobePackageNames;
assert builtins.elem "zenos-nautilus-apps" finalPackageNames;
assert builtins.elem "zenos-nautilus-apps" oobePackageNames;
assert builtins.elem "zenos-setup" oobePackageNames;
assert builtins.elem "gnome-shell-extension-zenos-oobe-mode" oobePackageNames;
assert builtins.elem "zen-dsl" oobePackageNames;
assert builtins.elem "forge" finalPackageNames;
assert !builtins.elem "gnome-extension-manager" finalPackageNames;
assert !builtins.elem "zenos-setup" finalPackageNames;
assert !builtins.elem "gnome-shell-extension-zenos-oobe-mode" finalPackageNames;
assert !builtins.elem "zen-dsl" finalPackageNames;
assert builtins.length finalConfig.system.extraDependencies == 6;
pkgs.runCommand "zenos-config-template-check" { } ''
  test "$(find ${configTemplate} -mindepth 1 -maxdepth 1 -printf '%f\n')" = "flake.nix"
  ! grep -Eq '\./(modules|profiles)' ${configTemplate}/flake.nix
  test -f ${fixture}/flake.lock
  touch "$out"
''
