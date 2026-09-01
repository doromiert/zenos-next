{
  lib,
  pkgs,
}:

let
  recovery = pkgs.zenos.apps.recovery;

  detect = pkgs.writeShellApplication {
    name = "zen-recovery-detect";
    runtimeInputs = [
      recovery.jq
      recovery.util-linux
    ];
    text = ''
      output="''${1:-/run/zenos-recovery/devices.json}"
      mkdir -p "$(dirname "$output")"
      temporary="$(mktemp "''${output}.XXXXXX")"
      lsblk --json --output-all > "$temporary"
      jq --arg generated "$(date --iso-8601=seconds)" \
        '{schema: 1, generated: $generated, blockDevices: .blockdevices}' \
        "$temporary" > "''${temporary}.json"
      mv "''${temporary}.json" "$output"
      rm -f "$temporary"
      printf '%s\n' "$output"
    '';
  };

  mount = pkgs.writeShellApplication {
    name = "zen-recovery-mount";
    runtimeInputs = [ recovery.util-linux ];
    text = ''
      read_write=0
      if [[ "''${1:-}" == "--read-write" ]]; then
        read_write=1
        shift
      fi
      if [[ $# -lt 1 || $# -gt 2 ]]; then
        echo "usage: zen-recovery-mount [--read-write] DEVICE [TARGET]" >&2
        exit 2
      fi
      device=$1
      [[ "$device" == /dev/* ]] || { echo "DEVICE must be under /dev" >&2; exit 2; }
      name="$(basename "$device")"
      target="''${2:-/mnt/recovery/$name}"
      [[ "$target" == /mnt/recovery/* ]] || { echo "TARGET must be under /mnt/recovery" >&2; exit 2; }
      options="nosuid,nodev,noexec"
      if (( read_write )); then
        echo "Mounting read-write: $device -> $target" >&2
      else
        options="ro,$options"
        echo "Mounting read-only: $device -> $target" >&2
      fi
      sudo -n install -d -m 0755 "$target"
      sudo -n mount -o "$options" -- "$device" "$target"
      printf '%s\n' "$target"
    '';
  };

  diagnostics = pkgs.writeShellApplication {
    name = "zen-recovery-diagnostics";
    runtimeInputs = [
      recovery.dmidecode
      recovery.iproute2
      recovery.jq
      recovery.lshw
      recovery.nvme-cli
      recovery.pciutils
      recovery.smartmontools
      recovery.usbutils
      recovery.util-linux
    ];
    text = ''
      output="''${1:-/run/zenos-recovery/report}"
      mkdir -p "$output"
      lsblk --json --output-all > "$output/lsblk.json"
      lspci -nnk > "$output/lspci.txt"
      lsusb > "$output/lsusb.txt"
      ip -details address > "$output/network.txt"
      # Keep report files owned by the live user while elevating hardware inspection.
      # shellcheck disable=SC2024
      sudo -n dmidecode > "$output/dmidecode.txt" 2>&1 || true
      # shellcheck disable=SC2024
      sudo -n nvme list -o json > "$output/nvme.json" 2>/dev/null || true
      # shellcheck disable=SC2024
      sudo -n lshw -json > "$output/lshw.json" 2>/dev/null || true
      journalctl -b --no-pager > "$output/journal.txt"
      printf '%s\n' "$output"
    '';
  };

  repair =
    target:
    pkgs.writeShellApplication {
      name = "zen-recover-${target}";
      runtimeInputs = [
        recovery.arch-install-scripts
        recovery.nixos-install-tools
        recovery.util-linux
      ];
      text = ''
        apply=0
        if [[ "''${1:-}" == "--apply" ]]; then
          apply=1
          shift
        fi
        root="''${1:-}"
        if [[ -z "$root" || "$root" != /* || ! -d "$root" ]]; then
          echo "usage: zen-recover-${target} [--apply] MOUNTED_ROOT" >&2
          exit 2
        fi

        # shellcheck disable=SC2194
        case ${lib.escapeShellArg target} in
          nixos|zenos)
            command=(sudo -n nixos-enter --root "$root")
            hint="Inside the target: inspect the flake, then run nixos-rebuild boot --flake PATH#HOST"
            ;;
          arch)
            command=(sudo -n arch-chroot "$root")
            hint="Inside the target: inspect mkinitcpio and the configured bootloader before applying changes"
            ;;
          ubuntu|fedora)
            command=(sudo -n chroot "$root" /bin/bash)
            hint="Bind /dev, /proc, /sys and /run only when needed; inspect initramfs and bootloader configuration first"
            ;;
          windows)
            echo "Windows recovery is instruction-only from Linux. Keep NTFS read-only." >&2
            echo "Use WinRE for chkdsk, offline DISM/SFC, and bcdboot." >&2
            exit 0
            ;;
        esac

        echo "$hint"
        printf 'Proposed command:'
        printf ' %q' "''${command[@]}"
        printf '\n'
        if (( ! apply )); then
          echo "Re-run with --apply to enter the target."
          exit 0
        fi
        exec "''${command[@]}"
      '';
    };
in
pkgs.symlinkJoin {
  name = "zenos-recovery-tools-0.1.0";
  paths = [
    detect
    diagnostics
    mount
    (repair "zenos")
    (repair "nixos")
    (repair "arch")
    (repair "ubuntu")
    (repair "fedora")
    (repair "windows")
  ];
  meta = {
    description = "Conservative cross-distribution recovery helpers for ZenOS live media";
    license = lib.licenses.napalm;
    platforms = lib.platforms.linux;
  };
}
