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
        exit 0
      '';
      openssh = final.writeShellScriptBin "ssh" ''
        echo "MOCK ssh: $@" >> /var/log/deploy/deploy.log
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

    # Start the nixos-upgrade service on client which triggers the webhook curl call
    client.succeed("systemctl start nixos-upgrade.service")

    # Wait for builder to receive and execute the deploy service oneshot
    builder.wait_until_succeeds("grep -q 'MOCK rebuild' /var/log/deploy/deploy.log")
    builder.wait_until_succeeds("grep -q 'MOCK telegram-notify' /var/log/deploy/telegram.log")

    # Verify rebuild log contents on builder
    deploy_log = builder.succeed("cat /var/log/deploy/deploy.log")
    builder.log(f"Deploy log content:\\n{deploy_log}")
    assert "MOCK rebuild" in deploy_log
    # In trigger-webhook.sh, client sends its hostname (which is "client")
    assert "client" in deploy_log
    assert "MOCK ssh" in deploy_log
    assert "push-reboot-detector" in deploy_log

    # Verify telegram log contents on builder
    telegram_log = builder.succeed("cat /var/log/deploy/telegram.log")
    builder.log(f"Telegram log content:\\n{telegram_log}")
    assert "MOCK telegram-notify" in telegram_log
    assert "Deploy successful" in telegram_log
    assert "client" in telegram_log
  '';
}
