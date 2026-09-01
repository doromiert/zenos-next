#!/usr/bin/env python3
import glob
import os
import re


ESP_MOUNT = "/boot"
ENTRY_DIR = os.path.join(ESP_MOUNT, "loader/entries")
OUTPUT_FILE = os.path.join(ESP_MOUNT, "EFI/refind/zenos-entries.conf")
ICON_PATH = "/EFI/refind/themes/zenos-picker/icons/os_zenos.png"
FORCED_OPTIONS = "amd_iommu=on iommu=pt preempt=full threadirqs amd_pstate=active splash loglevel=4 lsm=landlock,yama,bpf"


def parse_systemd_entry(path):
    values = {}
    with open(path, encoding="utf-8") as entry_file:
        for raw_line in entry_file:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            key, separator, value = line.partition(" ")
            if separator:
                values[key] = value.strip()

    match = re.search(r"-generation-(\d+)(?:-|\.conf)", os.path.basename(path))
    if not match:
        raise RuntimeError(f"cannot determine generation from {path}")
    for key in ("linux", "initrd", "options"):
        if key not in values:
            raise RuntimeError(f"systemd-boot entry {path} has no {key} field")
    for key in ("linux", "initrd"):
        relative = values[key].lstrip("/")
        if not os.path.isfile(os.path.join(ESP_MOUNT, relative)):
            raise RuntimeError(f"systemd-boot entry {path} references missing {values[key]}")
    return {
        "generation": int(match.group(1)),
        "initrd": values["initrd"],
        "loader": values["linux"],
        "options": values["options"],
    }


def get_entries():
    paths = glob.glob(os.path.join(ENTRY_DIR, "nixos*-generation-*.conf"))
    paths = [path for path in paths if "-specialisation-" not in os.path.basename(path)]
    entries = [parse_systemd_entry(path) for path in paths]
    return sorted(entries, key=lambda entry: entry["generation"], reverse=True)[:5]


def generate_config():
    entries = get_entries()
    if not entries:
        raise RuntimeError(f"no NixOS systemd-boot entries found in {ENTRY_DIR}")

    print(f"Generating {OUTPUT_FILE} for {len(entries)} generations...")
    with open(OUTPUT_FILE, "w", encoding="utf-8") as output:
        output.write('menuentry "ZenOS" {\n')
        output.write(f"    icon {ICON_PATH}\n")

        for index, entry in enumerate(entries):
            options = f"{entry['options']} {FORCED_OPTIONS}"
            if index == 0:
                output.write(f"    loader {entry['loader']}\n")
                output.write(f"    initrd {entry['initrd']}\n")
                output.write(f'    options "{options}"\n')

            output.write(f'    submenuentry "Generation {entry["generation"]}" {{\n')
            output.write(f"        loader {entry['loader']}\n")
            output.write(f"        initrd {entry['initrd']}\n")
            output.write(f'        options "{options}"\n')
            output.write("    }\n")

        output.write("}\n")
    print("Done.")


if __name__ == "__main__":
    generate_config()
