{
  pkgs,
  modules,
  ...
}:
let
  adguardHomeConfig = pkgs.writeText "AdGuardHome.yaml" ''
    http:
      address: 0.0.0.0:80
    dns:
      bootstrap_dns:
        - 1.1.1.1
    filtering:
      rewrites:
        - domain: test.home.arpa
          answer: 10.10.10.10
    schema_version: 29
  '';
in
pkgs.testers.runNixOSTest {
  name = "adguardhome";

  nodes = {
    adguardhome =
      { pkgs, ... }:
      {
        imports = modules;

        environment.systemPackages = [ pkgs.francynox.bind ];

        environment.etc."AdGuardHome.yaml".source = adguardHomeConfig;

        services.francynox.adguardhome = {
          enable = true;
          configFile = "/etc/AdGuardHome.yaml";
        };
      };
  };
  testScript = ''
    def run_checks():
      adguardhome.wait_for_unit("adguardhome.service")
      adguardhome.wait_for_open_port(80, timeout = 15)
      adguardhome.wait_for_open_port(53, timeout = 15)

      adguardhome.succeed("curl --fail -s http://localhost:80/ | grep 'AdGuard Home'")

      adguardhome.succeed("dig @localhost test.home.arpa +short | grep 10.10.10.10")

    def security_score():
      security_score = adguardhome.succeed("systemd-analyze security adguardhome.service --no-pager")
      adguardhome.log(f"Security Analysis:\n{security_score}")
      if "UNSAFE" in security_score:
        raise Exception("AdGuardHome service security level is UNSAFE!")

    start_all()

    with subtest("Run Basic Checks"):
      run_checks()

    with subtest("Verify hardening"):
      security_score()

    with subtest("Verify Service Restart"):
      adguardhome.systemctl("restart adguardhome.service")
      run_checks()

    with subtest("Verify preStart safeguard on restart with broken config"):
      adguardhome.succeed("rm -f /etc/AdGuardHome.yaml && echo 'broken: yaml: [invalid' > /etc/AdGuardHome.yaml")
      adguardhome.fail("systemctl restart adguardhome.service")
      adguardhome.fail("systemctl is-active adguardhome.service")
      adguardhome.fail("pgrep adguardhome")

      adguardhome.succeed("cp -f ${adguardHomeConfig} /etc/AdGuardHome.yaml")
      adguardhome.succeed("systemctl restart adguardhome.service")
      adguardhome.succeed("systemctl is-active adguardhome.service")
      run_checks()
  '';
}
