{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.zenos.platform.refind;
  refindScript = ../../scripts/refind.py;
  refindResources = ../../assets/refind;
in
{
  options.zenos.platform.refind.enable = lib.mkEnableOption "the ZenOS rEFInd boot manager";

  config = lib.mkIf cfg.enable {
    boot = {
      consoleLogLevel = 0;
      initrd.verbose = false;
      kernelParams = [
        "quiet"
        "splash"
        "boot.shell_on_fail"
        "loglevel=3"
        "rd.systemd.show_status=false"
        "rd.udev.log_level=3"
        "udev.log_priority=3"
      ];
      loader = {
        timeout = 0;
        grub.enable = lib.mkForce false;
        refind.enable = lib.mkForce false;
        systemd-boot = {
          enable = true;
          configurationLimit = 10;
          extraInstallCommands = ''
            export PATH="${
              lib.makeBinPath [
                pkgs.coreutils
                pkgs.gptfdisk
                pkgs.gnused
                pkgs.gnugrep
              ]
            }:$PATH"

            if [ ! -f /boot/EFI/refind/refind_x64.efi ]; then
              echo "rEFInd not found. Performing unattended installation..."
              ${pkgs.refind}/bin/refind-install --yes
            fi

            echo "Deploying rEFInd resources..."
            cp -Lrf --no-preserve=mode ${refindResources}/. /boot/EFI/refind/

            echo "Syncing NixOS generations with rEFInd via Python script..."
            ${pkgs.python3}/bin/python3 ${refindScript}
          '';
        };
        efi = {
          canTouchEfiVariables = false;
          efiSysMountPoint = "/boot";
        };
      };
    };

    environment.systemPackages = [
      pkgs.refind
      pkgs.efibootmgr
      pkgs.python3
      pkgs.gptfdisk
      pkgs.gnused
    ];
  };
}
