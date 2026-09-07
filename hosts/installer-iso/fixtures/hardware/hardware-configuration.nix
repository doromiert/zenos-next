{ ... }:
{
  # Evaluation fixture only. It is never installed or used for disk operations.
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/fixture-root";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/fixture-esp";
    fsType = "vfat";
  };
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_blk"
  ];
}
