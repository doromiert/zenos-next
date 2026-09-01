{ modulesPath, ... }:
{
  imports = [
    "${modulesPath}/profiles/qemu-guest.nix"
    "${modulesPath}/virtualisation/qemu-vm.nix"
  ];

  virtualisation = {
    cores = 4;
    diskSize = 32768;
    graphics = true;
    memorySize = 6144;
    qemu.options = [ "-vga virtio" ];
    resolution = {
      x = 1280;
      y = 800;
    };
  };

  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  users.users.zenos.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH4+fQMTy7FaLwqDOumL1y3uW+WMWpoc12MEeQXeF+VF zenos-next-vm-debug"
  ];

  virtualisation.forwardPorts = [
    {
      from = "host";
      host = {
        address = "127.0.0.1";
        port = 2222;
      };
      guest.port = 22;
    }
  ];
}
