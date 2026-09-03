{
  pkgs,
  modules,
  ...
}:
pkgs.testers.runNixOSTest {
  name = "lxc-wipe-on-boot";

  nodes = {
    machine =
      { config, ... }:
      {
        imports = modules;

        networking.hostName = "test-lxc";

        services.francynox.lxc-wipe-on-boot.enable = true;

        # Provide init-wipe and install-bootloader as commands for easy invocation in the test
        environment.systemPackages = [
          (pkgs.writeShellScriptBin "init-wipe" "${config.system.build.init-wipe}")
          (pkgs.writeShellScriptBin "install-bootloader" ''
            ${config.system.build.installBootLoader} /run/current-system
          '')
        ];
      };
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    with subtest("Bootloader installation & wrapper creation"):
        # Run installBootLoader
        machine.succeed("install-bootloader")

        # Verify /sbin/init exists, is executable, and points to the toplevel init
        machine.succeed("test -x /sbin/init")
        init_content = machine.succeed("cat /sbin/init")
        machine.log(f"/sbin/init content:\n{init_content}")
        assert "init-wipe.sh" in init_content
        assert "exec /run/current-system/init" in init_content

        # Verify /boot/generations-commands.txt was created
        gen_content = machine.succeed("cat /boot/generations-commands.txt")
        machine.log(f"/boot/generations-commands.txt content:\n{gen_content}")
        assert "Run these commands to manually switch to a specific generation" in gen_content

    with subtest("Generational rollback commands in /boot"):
        # Create mock profile generations in /nix/var/nix/profiles
        machine.succeed("mkdir -p /nix/var/nix/profiles")
        machine.succeed("ln -sfn /run/current-system /nix/var/nix/profiles/system-1-link")
        machine.succeed("ln -sfn /run/current-system /nix/var/nix/profiles/system-2-link")
        machine.succeed("install-bootloader")

        gen_content = machine.succeed("cat /boot/generations-commands.txt")
        machine.log(f"Updated /boot/generations-commands.txt content:\n{gen_content}")
        assert "Generation 1" in gen_content
        assert "Generation 2" in gen_content

    with subtest("Root wipe execution"):
        # Create mutable test files across /etc, /var, /tmp, /root
        machine.succeed("touch /etc/ephemeral-test.txt /var/ephemeral-test.txt /tmp/ephemeral-test.txt /root/ephemeral-test.txt")

        # Create persistent test file in /nix/persist
        machine.succeed("mkdir -p /nix/persist && echo 'keep-me' > /nix/persist/persistent-test.txt")

        # Execute the init-wipe script
        machine.succeed("init-wipe")

        # Verify ephemeral files were wiped
        machine.fail("test -e /etc/ephemeral-test.txt || test -e /var/ephemeral-test.txt || test -e /tmp/ephemeral-test.txt || test -e /root/ephemeral-test.txt")

        # Verify persistent file was kept
        kept_text = machine.succeed("cat /nix/persist/persistent-test.txt").strip()
        assert kept_text == "keep-me"

        # Verify logging to /nix/persist/init-wipe.log
        wipe_log = machine.succeed("cat /nix/persist/init-wipe.log")
        machine.log(f"Init wipe log content:\n{wipe_log}")
        assert "LXC Init Script Started" in wipe_log
        assert "Wiping root for impermanence..." in wipe_log
        assert "System wiped. Returning to wrapper..." in wipe_log

        # Verify /etc/hostname and /etc/systemd/network were recreated
        hostname = machine.succeed("cat /etc/hostname").strip()
        assert hostname == "test-lxc"
        machine.succeed("test -d /etc/systemd/network")

        # Verify /sbin/init and /boot were not wiped
        machine.succeed("test -x /sbin/init && test -f /boot/generations-commands.txt")
  '';
}
