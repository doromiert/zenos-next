{
  pkgs,
  zenDsl,
}:

pkgs.testers.runNixOSTest {
  name = "zenos-dsl-vm";

  nodes.machine = {
    environment.systemPackages = [
      pkgs.jq
      zenDsl
    ];

    environment.etc."zen-dsl-valid/modules/programs/demo.zmdl".text = ''
      enable = enableOption {
        !! { genericRoute = true; };
        s!! {
          systemRoute = true;
          environment.systemPackages = with $pkgs.zenos.legacy; [ bash ];
        };
        u!! { userRoute = true; };
      };
    '';
    environment.etc."zen-dsl-invalid-id/modules/programs/demo.zmdl".text = ''
      _meta.id = "zenos.programs.demo";
      value = true;
    '';
    environment.etc."zen-dsl-invalid-with/bare.zpkg".text = ''
      value = with $pkgs; git;
    '';
    environment.etc."zen-dsl-invalid-with/lib.zpkg".text = ''
      value = with $pkgs.lib; id;
    '';
    environment.etc."zen-dsl-invalid-with/stdenv.zpkg".text = ''
      value = with $pkgs.stdenv; mkDerivation;
    '';
    environment.etc."zen-dsl-wrong-root/marker".text = "";
  };

  testScript = ''
    machine.start()
    machine.succeed(
      "zen-dsl compile /etc/zen-dsl-valid/modules/programs/demo.zmdl "
      "--root /etc/zen-dsl-valid -o /tmp/demo.nix"
    )
    machine.succeed("grep -F 'moduleIdentity = \"zenos.programs.demo\";' /tmp/demo.nix")
    machine.succeed("grep -F 'descriptorVersion = \"zenlang.semantic/2\";' /tmp/demo.nix")
    machine.succeed("grep -F 'genericRoute = true;' /tmp/demo.nix")
    machine.succeed("grep -F 'systemRoute = true;' /tmp/demo.nix")
    machine.succeed("grep -F 'home-manager.sharedModules' /tmp/demo.nix")
    machine.succeed("grep -F 'userRoute = true;' /tmp/demo.nix")
    machine.fail("grep -F 'compileTarget' /tmp/demo.nix")

    machine.succeed(
      "zen-dsl compile-tree --root /etc/zen-dsl-valid "
      "--output /tmp/bundle.json --mode interface"
    )
    machine.succeed(
      "jq -e '.bundleVersion == \"zenlang.bundle/2\" and "
      "all(.sources[]; .descriptor.descriptorVersion == \"zenlang.semantic/2\") and "
      ".modules == [{identity: \"zenos.programs.demo\", "
      "optionPath: [\"zenos\", \"programs\", \"demo\"], "
      "path: \"modules/programs/demo.zmdl\"}]' /tmp/bundle.json"
    )

    machine.fail(
      "zen-dsl compile /etc/zen-dsl-valid/modules/programs/demo.zmdl "
      "-o /tmp/missing-root.nix"
    )
    machine.fail(
      "zen-dsl compile /etc/zen-dsl-valid/modules/programs/demo.zmdl "
      "--root /etc/zen-dsl-wrong-root -o /tmp/wrong-root.nix"
    )
    machine.fail(
      "zen-dsl compile /etc/zen-dsl-valid/modules/programs/demo.zmdl "
      "--root /etc/zen-dsl-valid --option-path programs.demo"
    )
    machine.fail(
      "zen-dsl compile /etc/zen-dsl-invalid-id/modules/programs/demo.zmdl "
      "--root /etc/zen-dsl-invalid-id -o /tmp/authored-id.nix"
    )
    machine.fail("zen-dsl check-tree --root /etc/zen-dsl-invalid-id")

    machine.fail("zen-dsl check /etc/zen-dsl-invalid-with/bare.zpkg")
    machine.fail("zen-dsl check /etc/zen-dsl-invalid-with/lib.zpkg")
    machine.fail("zen-dsl check /etc/zen-dsl-invalid-with/stdenv.zpkg")
  '';
}
