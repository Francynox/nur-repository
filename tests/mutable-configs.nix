{
  pkgs,
  modules,
  ...
}:
pkgs.testers.runNixOSTest {
  name = "mutable-configs";

  nodes = {
    machine =
      { pkgs, lib, ... }:
      {
        imports = modules;

        # Mock telegram-notify package
        services.francynox.telegram-notify = {
          enable = true;
          botTokenFile = "/etc/telegram-token";
          chatIdFile = "/etc/telegram-chat-id";
          package = pkgs.writeShellScriptBin "telegram-notify" ''
            echo "MOCK telegram-notify: $@" >> /tmp/telegram.log
            exit 0
          '';
        };

        # Mock the ExecStart of nixos-upgrade to do nothing
        systemd.services.nixos-upgrade.serviceConfig.ExecStart = lib.mkForce (
          pkgs.writeShellScript "mock-upgrade-exec" "echo MOCK UPGRADE EXEC; exit 0"
        );

        # Enable autoUpgrade so nixos-upgrade.service is generated
        system.autoUpgrade.enable = true;

        # Configure mock credentials
        environment.etc = {
          "telegram-token".text = "mock-telegram-token";
          "telegram-chat-id".text = "mock-telegram-chat-id";
        };

        # Enable mutable configs (text and yaml)
        services.francynox.mutable-configs."test.conf" = {
          source = pkgs.writeText "test-source" "original-content\n";
          notifyOnUpgrade = true;
          stopAutoUpgrade = true;
        };

        services.francynox.mutable-configs."test.yaml" = {
          source = pkgs.writeText "test-yaml-source" ''
            server:
              port: 8080
              host: "0.0.0.0"
            rules:
              - id: 1
                enabled: true
          '';
          format = "yaml";
          notifyOnUpgrade = true;
          stopAutoUpgrade = true;
        };
      };
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # TEST CASE 1: No configuration drift
    # Target files match pristine copies
    machine.succeed("systemctl start nixos-upgrade.service")

    # TEST CASE 2: YAML formatting changes (different indentation / key ordering)
    # This simulates self-formatting daemons like AdGuard Home
    reformatted_yaml = (
        'server:\n'
        '    host: "0.0.0.0"\n'
        '    port: 8080\n'
        'rules:\n'
        '  - enabled: true\n'
        '    id: 1\n'
    )
    machine.succeed(f"printf '%s' '{reformatted_yaml}' > /etc/test.yaml")
    # YAML semantic comparison should recognize identical content and SUCCEED
    machine.succeed("systemctl start nixos-upgrade.service")

    # TEST CASE 3: Actual semantic change in YAML file
    drifted_yaml = (
        'server:\n'
        '    host: "127.0.0.1"\n'
        '    port: 9090\n'
        'rules:\n'
        '  - enabled: false\n'
        '    id: 1\n'
    )
    machine.succeed(f"printf '%s' '{drifted_yaml}' > /etc/test.yaml")
    # nixos-upgrade.service should now FAIL because port and host values changed
    machine.fail("systemctl start nixos-upgrade.service")

    telegram_log = machine.succeed("cat /tmp/telegram.log")
    machine.log(f"Telegram log content after YAML drift:\n{telegram_log}")
    assert "Configuration Drift Detected" in telegram_log
    assert "test.yaml" in telegram_log
    assert "Upgrade aborted" in telegram_log

    # Reset YAML to pristine
    machine.succeed("cp /etc/pristine/test.yaml /etc/test.yaml")
    machine.succeed("rm -f /tmp/telegram.log")

    # TEST CASE 4: Plain text configuration drift
    machine.succeed("echo 'local-modification' > /etc/test.conf")
    machine.fail("systemctl start nixos-upgrade.service")

    telegram_log = machine.succeed("cat /tmp/telegram.log")
    machine.log(f"Telegram log content after text drift:\n{telegram_log}")
    assert "Configuration Drift Detected" in telegram_log
    assert "test.conf" in telegram_log
    assert "Upgrade aborted" in telegram_log
  '';
}
