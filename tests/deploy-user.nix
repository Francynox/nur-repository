{
  pkgs,
  modules,
  ...
}:
let
  testKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGt7xUjV2+pD79Ww99GfWp4W062Lz2J/1X0rN7M3K8z9 test@deploy";
in
pkgs.testers.runNixOSTest {
  name = "deploy-user";

  nodes = {
    machine =
      { ... }:
      {
        imports = modules;

        users.groups.customgroup = { };

        services.openssh.enable = true;

        services.francynox.deploy-user = {
          enable = true;
          name = "deploy";
          extraGroups = [ "customgroup" ];
          sshAuthorizedKeys = [ testKey ];
          passwordlessSudo = true;
        };
      };
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # Verify user existence and group memberships
    groups = machine.succeed("id -Gn deploy").strip().split()
    assert set(groups) == {"deploy", "customgroup"}, f"Expected groups to be {{'deploy', 'customgroup'}}, got: {groups}"

    # Verify nix trusted-users contains deploy
    machine.succeed("grep -E '^trusted-users = .*\\bdeploy\\b' /etc/nix/nix.conf")

    # Verify authorized keys
    auth_keys = machine.succeed("cat /etc/ssh/authorized_keys.d/deploy")
    assert "test@deploy" in auth_keys, "Expected test@deploy key in authorized keys"

    # Verify passwordless sudo
    whoami = machine.succeed("su - deploy -c 'sudo whoami'").strip()
    assert whoami == "root", f"Expected sudo whoami to be root, got {whoami}"
  '';
}
