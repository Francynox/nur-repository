{
  pkgs,
  modules,
  ...
}:
let
  mockCurl = pkgs.writeShellScriptBin "curl" ''
    echo "MOCK curl: $@" >> /var/log/telegram-mock.log
    echo '{"ok":true}'
    exit 0
  '';
in
pkgs.testers.runNixOSTest {
  name = "telegram-notify";

  nodes = {
    machine =
      { ... }:
      {
        imports = modules;

        users.users.testuser = {
          isNormalUser = true;
          uid = 1000;
        };

        systemd.tmpfiles.rules = [
          "d /var/log 0777 root root -"
        ];

        environment.etc = {
          "telegram-token".text = "mock-bot-token";
          "telegram-chat-id".text = "mock-chat-id";
        };

        services.francynox.telegram-notify = {
          enable = true;
          botTokenFile = "/etc/telegram-token";
          chatIdFile = "/etc/telegram-chat-id";
        };

        systemd.services."telegram-notify@" = {
          path = [ mockCurl ];
          serviceConfig.ReadWritePaths = [ "/var/log" ];
        };
      };
  };

  testScript = ''
    # Wait for the socket to be listening
    machine.wait_for_unit("telegram-notify.socket")

    # Verify socket file exists and has correct permissions (0666)
    machine.succeed("stat -c '%a' /run/telegram-notify/notify.sock | grep -q '666'")

    # Send message as non-root user
    machine.succeed("su - testuser -c 'telegram-notify \"hello from testuser\"'")

    # Wait for systemd services to finish processing
    machine.wait_until_succeeds("grep -q 'hello from testuser' /var/log/telegram-mock.log")

    # Send message via stdin pipe as non-root user
    machine.succeed("su - testuser -c 'echo \"hello via pipe\" | telegram-notify'")

    # Wait for systemd services to finish processing
    machine.wait_until_succeeds("grep -q 'hello via pipe' /var/log/telegram-mock.log")

    # Assert curl request payload containing token and chat id
    curl_log = machine.succeed("cat /var/log/telegram-mock.log")
    machine.log(f"Curl invocation: {curl_log}")
    assert "mock-bot-token" in curl_log
    assert "mock-chat-id" in curl_log
  '';
}
