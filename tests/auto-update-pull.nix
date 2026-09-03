{
  pkgs,
  modules,
  ...
}:
let
  testPkgs = pkgs.extend (
    final: _prev: {
      sops = final.writeShellScriptBin "sops" ''
        echo "my-github-pat"
        exit 0
      '';
      ssh-to-age = final.writeShellScriptBin "ssh-to-age" ''
        echo "dummy-age-key"
        exit 0
      '';
      nixos-rebuild = final.writeShellScriptBin "nixos-rebuild" ''
        echo "MOCK rebuild: $@" >> /tmp/rebuild.log
        exit 0
      '';
    }
  );
in
testPkgs.testers.runNixOSTest {
  name = "auto-update-pull";

  nodes = {
    machine =
      { pkgs, lib, ... }:
      {
        imports = modules;

        # Ensure SSH host key exists for the fetch script check
        environment.etc = {
          "ssh/ssh_host_ed25519_key".text = "mock-private-key";
          "mock-secrets.yaml".text = "mock-encrypted-sops-data";
          "telegram-token".text = "mock-telegram-token";
          "telegram-chat-id".text = "mock-telegram-chat-id";
        };

        services.francynox.telegram-notify = {
          enable = true;
          botTokenFile = "/etc/telegram-token";
          chatIdFile = "/etc/telegram-chat-id";
          package = pkgs.writeShellScriptBin "telegram-notify" ''
            echo "MOCK telegram-notify: $@" >> /tmp/telegram.log
            exit 0
          '';
        };

        services.francynox.auto-update = {
          enable = true;
          mode = "pull";
          pull = {
            flakeUrl = "github:my-org/my-private-repo/main";
            secretsUrl = "file:///etc/mock-secrets.yaml";
            sopsKeyPath = "/etc/ssh/ssh_host_ed25519_key";
            telegramNotify = true;
          };
        };

        # Directly mock the ExecStart command of nixos-upgrade service
        systemd.services.nixos-upgrade.serviceConfig.ExecStart = lib.mkForce (
          pkgs.writeShellScript "mock-nixos-upgrade" ''
            if [ -f /tmp/mock-upgrade-fail ]; then
              ln -sfn /nix/store/mock-new-system /nix/var/nix/profiles/system
              echo "MOCK nixos-rebuild failing..." >> /tmp/upgrade.log
              exit 1
            fi
            echo "MOCK nixos-rebuild: --flake github:my-org/my-private-repo/main" >> /tmp/upgrade.log
            echo "NIX_USER_CONF_FILES: $NIX_USER_CONF_FILES" >> /tmp/upgrade.log
            exit 0
          ''
        );
      };
  };

  testScript = ''
    # Wait for the PAT fetching service to complete and write the configuration file
    machine.wait_until_succeeds("cat /run/nix-private-access.conf | grep -q 'my-github-pat'")

    # Verify that NIX_USER_CONF_FILES was written correctly with decrypted PAT
    pat_conf = machine.succeed("cat /run/nix-private-access.conf")
    machine.log(f"PAT conf content:\n{pat_conf}")
    assert "access-tokens = github.com=my-github-pat" in pat_conf

    with subtest("Successful pull upgrade"):
        # Start the nixos-upgrade service manually to trigger pull update
        machine.succeed("systemctl start nixos-upgrade.service")

        # Wait for upgrade log to be written by the upgrade runner
        machine.wait_until_succeeds("grep -q 'MOCK nixos-rebuild' /tmp/upgrade.log")
        machine.wait_until_succeeds("grep -q 'Pull upgrade successful' /tmp/telegram.log")

        # Read upgrade log to verify nixos-rebuild was called with correct environment
        upgrade_log = machine.succeed("cat /tmp/upgrade.log")
        machine.log(f"Upgrade log content:\n{upgrade_log}")
        assert "MOCK nixos-rebuild" in upgrade_log
        assert "github:my-org/my-private-repo/main" in upgrade_log
        assert "NIX_USER_CONF_FILES: /run/nix-private-access.conf" in upgrade_log

        telegram_log = machine.succeed("cat /tmp/telegram.log")
        assert "Pull upgrade successful" in telegram_log

    with subtest("Failed upgrade execution triggers rollback"):
        machine.succeed("rm -f /tmp/upgrade.log /tmp/telegram.log /tmp/rebuild.log")
        machine.succeed("touch /tmp/mock-upgrade-fail")

        machine.fail("systemctl restart nixos-upgrade.service")

        machine.wait_until_succeeds("grep -q 'switch --rollback' /tmp/rebuild.log")
        machine.wait_until_succeeds("grep -q 'Pull upgrade failed' /tmp/telegram.log")

        rebuild_log = machine.succeed("cat /tmp/rebuild.log")
        assert "switch --rollback" in rebuild_log

        telegram_log = machine.succeed("cat /tmp/telegram.log")
        assert "Pull upgrade failed" in telegram_log
        assert "rolled back" in telegram_log
  '';
}
