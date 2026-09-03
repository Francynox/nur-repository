{
  pkgs,
  modules,
  ...
}:
let
  testPkgs = pkgs.extend (
    final: _prev: {
      nixos-rebuild = final.writeShellScriptBin "nixos-rebuild" ''
        echo "MOCK rebuild: $@" >> /var/log/deploy/deploy.log
        if [ -f /tmp/mock-rebuild-fail ]; then
          exit 1
        fi
        touch /tmp/rebuild-done
        exit 0
      '';
      openssh = final.writeShellScriptBin "ssh" ''
        echo "MOCK ssh: $@" >> /var/log/deploy/deploy.log
        if [ -f /tmp/mock-ssh-broken ] && [ -f /tmp/rebuild-done ]; then
          exit 255
        fi
        if [[ "$*" == *"push-deploy-guard confirm"* ]]; then
          if [ -f /tmp/mock-service-failed ]; then
            echo "Health check failed! Newly failed units: mock-broken.service (rolled back to previous generation)"
            echo "switch --rollback" >> /var/log/deploy/deploy.log
            exit 1
          fi
          exit 0
        fi
        exit 0
      '';
    }
  );
in
testPkgs.testers.runNixOSTest {
  name = "auto-update-push";

  nodes = {
    builder =
      { pkgs, ... }:
      {
        imports = modules;

        systemd.tmpfiles.rules = [
          "d /var/log/deploy 0777 webhook webhook -"
        ];

        environment.etc = {
          "deploy-token".text = "my-secret-token";
          "ssh-key".text = "mock-ssh-key";
          "telegram-token".text = "mock-telegram-token";
          "telegram-chat-id".text = "mock-telegram-chat-id";
        };

        services.francynox.telegram-notify = {
          enable = true;
          botTokenFile = "/etc/telegram-token";
          chatIdFile = "/etc/telegram-chat-id";
          package = pkgs.writeShellScriptBin "telegram-notify" ''
            echo "MOCK telegram-notify: $@" >> /var/log/deploy/telegram.log
            exit 0
          '';
        };

        services.francynox.auto-update.push-server = {
          enable = true;
          flakePath = "/etc/nixos";
          tokenFile = "/etc/deploy-token";
          sshKeyFile = "/etc/ssh-key";
          telegramNotify = true;
        };
      };

    client =
      { ... }:
      {
        imports = modules;

        environment.etc = {
          "deploy-token".text = "my-secret-token";
        };

        services.francynox.auto-update.push = {
          enable = true;
          webhook = {
            url = "http://builder:9000/hooks/deploy";
            tokenFile = "/etc/deploy-token";
          };
          autoReboot = true;
        };
      };
  };

  testScript = ''
    # Wait for the webhook server on builder to be ready
    builder.wait_for_unit("webhook.service")
    builder.wait_for_open_port(9000)

    # Wait for the client node to boot
    client.wait_for_unit("multi-user.target")

    with subtest("Successful deployment"):
        # Start the nixos-upgrade service on client which triggers the webhook curl call
        client.succeed("systemctl start nixos-upgrade.service")

        # Wait for builder to receive and execute the deploy service oneshot
        builder.wait_until_succeeds("grep -q 'MOCK rebuild' /var/log/deploy/deploy.log")
        builder.wait_until_succeeds("grep -q 'MOCK telegram-notify' /var/log/deploy/telegram.log")

        # Verify rebuild log contents on builder
        deploy_log = builder.succeed("cat /var/log/deploy/deploy.log")
        builder.log(f"Deploy log content:\n{deploy_log}")
        assert "MOCK rebuild" in deploy_log
        assert "client" in deploy_log
        assert "MOCK ssh" in deploy_log
        assert "push-deploy-guard" in deploy_log

        # Verify telegram log contents on builder
        telegram_log = builder.succeed("cat /var/log/deploy/telegram.log")
        builder.log(f"Telegram log content:\n{telegram_log}")
        assert "MOCK telegram-notify" in telegram_log
        assert "Deploy successful" in telegram_log
        assert "client" in telegram_log

    with subtest("Failed health check triggers automatic rollback"):
        # Clear previous logs and simulate a failed unit on the target
        builder.succeed("rm -f /var/log/deploy/deploy.log /var/log/deploy/telegram.log /tmp/rebuild-done /tmp/mock-ssh-broken")
        builder.succeed("echo 'mock-broken.service failed' > /tmp/mock-service-failed")

        # Trigger upgrade again
        client.succeed("systemctl restart nixos-upgrade.service")

        # Wait for builder to process deployment and fail healthcheck
        builder.wait_until_succeeds("grep -q 'switch --rollback' /var/log/deploy/deploy.log")
        builder.wait_until_succeeds("grep -q 'Deploy failed' /var/log/deploy/telegram.log")

        deploy_log = builder.succeed("cat /var/log/deploy/deploy.log")
        builder.log(f"Deploy log after failure:\n{deploy_log}")
        assert "switch --rollback" in deploy_log

        telegram_log = builder.succeed("cat /var/log/deploy/telegram.log")
        builder.log(f"Telegram log after failure:\n{telegram_log}")
        assert "Deploy failed" in telegram_log
        assert "mock-broken.service" in telegram_log
        assert "rolled back" in telegram_log

    with subtest("Target watchdog remains armed when SSH fails during health check"):
        builder.succeed("rm -f /var/log/deploy/deploy.log /var/log/deploy/telegram.log /tmp/rebuild-done /tmp/mock-service-failed")
        builder.succeed("touch /tmp/mock-ssh-broken")

        client.succeed("systemctl restart nixos-upgrade.service")

        builder.wait_until_succeeds("grep -q 'Deploy failed' /var/log/deploy/telegram.log")
        telegram_log = builder.succeed("cat /var/log/deploy/telegram.log")
        builder.log(f"Telegram log with broken SSH:\n{telegram_log}")
        assert "Deploy failed" in telegram_log
        assert "watchdog armed for auto-rollback" in telegram_log
  '';
}
