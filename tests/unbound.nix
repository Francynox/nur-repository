{
  pkgs,
  modules,
  ...
}:
let
  unboundConf = pkgs.writeText "unbound.conf" ''
    server:
      private-domain: "example.com"
      local-zone: "ns1.example.com" static
      local-data: "ns1.example.com A 127.0.0.1"
  '';
in
pkgs.testers.runNixOSTest {
  name = "unbound";

  nodes.unbound =
    { pkgs, ... }:
    {
      imports = modules;

      environment.systemPackages = [ pkgs.francynox.bind ];

      environment.etc."unbound/user-unbound.conf".source = unboundConf;

      services.francynox.unbound = {
        enable = true;
        configFile = "/etc/unbound/user-unbound.conf";
      };
    };

  testScript = ''
    import re

    def run_checks():
      unbound.wait_for_unit("unbound.service")
      unbound.wait_for_open_port(53)

      unbound.succeed("test -f /var/lib/unbound/root.key")

      unbound.succeed("test -S /run/unbound/unbound.ctl")

      unbound.succeed("dig @localhost ns1.example.com +short | grep 127.0.0.1")

    def security_score():
      out = unbound.succeed("systemd-analyze security unbound.service --no-pager")
      unbound.log(f"Security Analysis:\n{out}")

      match = re.search(r"Overall exposure level.*:\s+([0-9]+\.[0-9]+)", out)
      if not match:
        raise Exception("Failed to extract numeric security score from systemd-analyze output!")

      score = float(match.group(1))
      threshold = 2.0
      if score > threshold:
        raise Exception(f"Security regression: score {score} exceeds limit {threshold}!")

    with subtest("Run Basic Checks"):
      run_checks()

    with subtest("Verify hardening"):
      security_score()

    with subtest("Verify Service Reload"):
      unbound.succeed("systemctl reload unbound.service")
      run_checks()

    with subtest("Verify Service Restart"):
      unbound.succeed("systemctl restart unbound.service")
      run_checks()

    with subtest("Verify preStart safeguard on restart with broken config"):
      unbound.succeed("rm -f /etc/unbound/user-unbound.conf && echo 'server: broken syntax: [invalid' > /etc/unbound/user-unbound.conf")
      unbound.fail("systemctl restart unbound.service")
      unbound.fail("systemctl is-active unbound.service")

      unbound.succeed("cp -f ${unboundConf} /etc/unbound/user-unbound.conf")
      unbound.succeed("systemctl restart unbound.service")
      run_checks()

    with subtest("Verify reload safeguard with broken config"):
      unbound.succeed("rm -f /etc/unbound/user-unbound.conf && echo 'server: broken syntax: [invalid' > /etc/unbound/user-unbound.conf")
      unbound.fail("systemctl reload unbound.service")
      unbound.succeed("systemctl is-active unbound.service")
      unbound.succeed("dig @localhost ns1.example.com +short | grep 127.0.0.1")

      unbound.succeed("cp -f ${unboundConf} /etc/unbound/user-unbound.conf")
      unbound.succeed("systemctl reload unbound.service")
      run_checks()
  '';
}
