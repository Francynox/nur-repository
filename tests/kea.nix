{
  pkgs,
  modules,
  ...
}:
let
  keaDhcp4Config = pkgs.writeText "kea-dhcp4-test.conf" ''
    {
      "Dhcp4": {
        "interfaces-config": {
          "dhcp-socket-type": "raw",
          "interfaces": [ "eth1" ]
        },
        "lease-database": {
          "type": "memfile",
          "persist": true,
          "name": "/var/lib/kea/dhcp4.leases"
        },
        "control-sockets": [
          {
            "socket-type": "unix",
            "socket-name": "/run/kea/dhcp4.sock"
          }
        ],
        "valid-lifetime": 3600,
        "renew-timer": 900,
        "rebind-timer": 1800,
        "subnet4": [
          {
            "id": 1,
            "subnet": "10.0.0.0/29",
            "interface": "eth1",
            "pools": [
              {
                "pool": "10.0.0.3 - 10.0.0.3"
              }
            ]
          }
        ],
        "dhcp-ddns": {
          "enable-updates": true
        },
        "ddns-send-updates": true,
        "ddns-qualifying-suffix": "lan.nixos.test."
      }
    }
  '';

  keaDdnsConfig = pkgs.writeText "kea-ddns-test.conf" ''
    {
      "DhcpDdns": {
        "forward-ddns": {
          "ddns-domains": [
            {
              "name": "lan.nixos.test.",
              "key-name": "",
              "dns-servers": [
                {
                  "ip-address": "10.0.0.2",
                  "port": 53
                }
              ]
            }
          ]
        }
      }
    }
  '';
in
pkgs.testers.runNixOSTest {
  name = "kea";

  nodes = {
    router =
      { ... }:
      {
        imports = modules;

        virtualisation.vlans = [ 1 ];

        networking = {
          useNetworkd = true;
          useDHCP = false;
          firewall.allowedUDPPorts = [ 67 ];
        };

        systemd.network = {
          enable = true;
          networks = {
            "01-eth1" = {
              name = "eth1";
              networkConfig = {
                Address = "10.0.0.1/29";
              };
            };
          };
        };

        environment.etc."kea/kea-dhcp4.conf".source = keaDhcp4Config;

        services.francynox.kea.dhcp4 = {
          enable = true;
          configFile = "/etc/kea/kea-dhcp4.conf";
        };

        services.francynox.kea.dhcp-ddns = {
          enable = true;
          configFile = keaDdnsConfig;
        };
      };

    nameserver =
      { pkgs, ... }:
      {
        imports = modules;

        virtualisation.vlans = [ 1 ];

        networking = {
          useNetworkd = true;
          useDHCP = false;
          firewall.allowedUDPPorts = [ 53 ];
        };

        systemd.network = {
          enable = true;
          networks = {
            "01-eth1" = {
              name = "eth1";
              networkConfig = {
                Address = "10.0.0.2/29";
              };
            };
          };
        };

        services.resolved.enable = false;

        environment.etc."bind/rndc.key" = {
          source = pkgs.runCommand "rndc.key" { } ''
            ${pkgs.bind}/bin/rndc-confgen -a -c $out
          '';
          mode = "0640";
          group = "bind";
        };

        services.francynox.bind =
          let
            zoneFile = pkgs.writeText "lan.nixos.test" ''
              $TTL 1D
              @       IN      SOA     ns1.nixos.test. root.nixos.test. (
                                      2024010101 ; Serial
                                      1D         ; Refresh
                                      1H         ; Retry
                                      1W         ; Expire
                                      3H )       ; Negative Cache TTL
              ;
                      IN      NS      ns1.nixos.test.
              nameserver     IN      A       10.0.0.3
              router         IN      A       10.0.0.1
            '';

            namedConfFile = pkgs.writeText "named-test.conf" ''
              options {
                directory "/var/cache/bind";
                empty-zones-enable no;
              };
              zone "lan.nixos.test" {
                type master;
                file "${zoneFile}";
                journal "/var/lib/bind/db.lan.nixos.test.jnl";
                allow-update { 10.0.0.1; };
              };
            '';
          in
          {
            enable = true;
            configFile = namedConfFile;
          };
      };

    client = {
      virtualisation.vlans = [ 1 ];
      systemd.services.systemd-networkd.environment.SYSTEMD_LOG_LEVEL = "debug";
      networking = {
        useNetworkd = true;
        useDHCP = false;
        firewall.enable = false;
        interfaces.eth1.useDHCP = true;
      };
    };
  };
  testScript = ''
    import re

    def run_checks():
      nameserver.wait_for_unit("named.service")
      router.wait_for_unit("kea-dhcp4.service")
      router.wait_for_unit("kea-dhcp-ddns.service")

      client.succeed("systemctl start systemd-networkd-wait-online.service")

      client.wait_until_succeeds("ping -c 1 10.0.0.1", timeout = 60)
      router.wait_until_succeeds("ping -c 1 10.0.0.3", timeout = 60)

      nameserver.wait_until_succeeds("dig +short client.lan.nixos.test @10.0.0.2 | grep -q 10.0.0.3", timeout = 60)

    def security_score(service):
      out = router.succeed(f"systemd-analyze security {service}.service --no-pager")
      router.log(f"Security Analysis:\n{out}")

      match = re.search(r"Overall exposure level.*:\s+([0-9]+\.[0-9]+)", out)
      if not match:
        raise Exception("Failed to extract numeric security score from systemd-analyze output!")

      score = float(match.group(1))
      threshold = 2.0
      if score > threshold:
        raise Exception(f"Security regression: score {score} for {service} exceeds limit {threshold}!")

    with subtest("Run Basic Checks"):
      run_checks()

    with subtest("Verify hardening"):
      security_score("kea-dhcp4")
      security_score("kea-dhcp-ddns")

    with subtest("Verify Service Restart"):
      router.succeed("systemctl restart kea-dhcp4.service")
      router.succeed("systemctl restart kea-dhcp-ddns.service")
      run_checks()

    with subtest("Verify Service Reload"):
      router.succeed("systemctl reload kea-dhcp4.service")
      router.succeed("systemctl reload kea-dhcp-ddns.service")
      run_checks()

    with subtest("Verify preStart safeguard on restart with broken config"):
      router.succeed("rm -f /etc/kea/kea-dhcp4.conf && echo '{\"Dhcp4\": { broken json' > /etc/kea/kea-dhcp4.conf")
      router.fail("systemctl restart kea-dhcp4.service")
      router.fail("systemctl is-active kea-dhcp4.service")

      router.succeed("cp -f ${keaDhcp4Config} /etc/kea/kea-dhcp4.conf")
      router.succeed("systemctl restart kea-dhcp4.service")
      run_checks()

    with subtest("Verify reload safeguard with broken config"):
      router.succeed("rm -f /etc/kea/kea-dhcp4.conf && echo '{\"Dhcp4\": { broken json' > /etc/kea/kea-dhcp4.conf")
      router.fail("systemctl reload kea-dhcp4.service")
      router.succeed("systemctl is-active kea-dhcp4.service")

      router.succeed("cp -f ${keaDhcp4Config} /etc/kea/kea-dhcp4.conf")
      router.succeed("systemctl reload kea-dhcp4.service")
      run_checks()
  '';
}
