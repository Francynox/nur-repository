{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.francynox.kea;

  commonServiceConfig = {
    User = cfg.user;
    Group = cfg.group;
    ConfigurationDirectory = lib.mkIf (lib.hasPrefix "/etc/" cfg.configDir) (
      lib.removePrefix "/etc/" cfg.configDir
    );
    RuntimeDirectory = "kea";
    RuntimeDirectoryPreserve = true;
    RuntimeDirectoryMode = "0750";
    StateDirectory = lib.mkIf (lib.hasPrefix "/var/lib/" cfg.dataDir) (
      lib.removePrefix "/var/lib/" cfg.dataDir
    );
    StateDirectoryMode = "0750";
    CacheDirectory = "kea";
    Restart = "on-failure";
    # Security
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    PrivateDevices = true;
    PrivateMounts = true;
    ProtectHostname = true;
    ProtectClock = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    ProtectProc = "invisible";
    ProcSubset = "pid";
    RemoveIPC = true;
    RestrictAddressFamilies = [ "AF_UNIX AF_INET AF_INET6 AF_NETLINK AF_PACKET" ];
    LockPersonality = true;
    MemoryDenyWriteExecute = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    RestrictNamespaces = true;
    SystemCallArchitectures = "native";
    SystemCallFilter = "~@clock @cpu-emulation @debug @module @mount @obsolete @privileged @raw-io @reboot @resources @swap";
  };

  mkKeaComponent =
    name: description:
    lib.mkOption {
      inherit description;
      default = { };
      type = lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "Kea ${name}";

          configFile = lib.mkOption {
            type = lib.types.nullOr (lib.types.either lib.types.str lib.types.path);
            default = null;
            description = "Path to the Kea ''${name} configuration file.";
          };

          extraArgs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Additional command-line arguments.";
          };

          extraRestartTriggers = lib.mkOption {
            type = lib.types.listOf lib.types.path;
            default = [ ];
            description = "Extra derivations to trigger a service restart.";
          };
        };
      };
    };

  mkKeaService =
    {
      componentName,
      binaryName,
      componentCfg,
      capabilities ? [ ],
    }:
    lib.mkIf componentCfg.enable {
      assertions = [
        {
          assertion = componentCfg.configFile != null;
          message = "services.francynox.kea.${componentName}.configFile must be set.";
        }
      ];

      systemd.services."kea-${componentName}" = {
        description = "Kea ${componentName} (francynox)";
        after = [
          "network-online.target"
          "time-sync.target"
        ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        environment = {
          KEA_PIDFILE_DIR = "/run/kea";
          KEA_LOCKFILE_DIR = "/run/kea";
        };

        preStart = ''
          ${cfg.package}/bin/${binaryName} -t ${componentCfg.configFile}
        '';

        restartTriggers = componentCfg.extraRestartTriggers;

        serviceConfig = commonServiceConfig // {
          ExecStart = "${cfg.package}/bin/${binaryName} -c ${componentCfg.configFile} ${lib.escapeShellArgs componentCfg.extraArgs}";
          ExecReload = "${pkgs.writeShellScript "kea-${componentName}-reload" ''
            set -e
            ${cfg.package}/bin/${binaryName} -t ${componentCfg.configFile}
            ${pkgs.coreutils}/bin/kill -HUP $MAINPID
          ''}";
          AmbientCapabilities = capabilities;
          CapabilityBoundingSet = capabilities;
        };
      };
    };

in
{
  options.services.francynox.kea = {
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.francynox.kea;
      defaultText = lib.literalExpression "pkgs.francynox.kea";
      description = "The Kea package (from francynox NUR) to use for all Kea services.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "kea";
      description = "User account under which Kea runs.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "kea";
      description = "Group under which Kea runs.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/kea";
      description = "The working directory and data directory for Kea.";
    };

    configDir = lib.mkOption {
      type = lib.types.str;
      default = "/etc/kea";
      description = "The configuration directory for Kea.";
    };

    ctrl-agent = mkKeaComponent "Control Agent" "Kea Control Agent configuration (francynox NUR version).";

    dhcp4 = mkKeaComponent "DHCPv4 Server" "Kea DHCPv4 Server configuration (francynox NUR version).";

    dhcp6 = mkKeaComponent "DHCPv6 Server" "Kea DHCPv6 Server configuration (francynox NUR version).";

    dhcp-ddns = mkKeaComponent "DHCP-DDNS Server" "Kea DHCP-DDNS module configuration (francynox NUR version).";
  };

  config =
    lib.mkIf
      (lib.any (c: c.enable) [
        cfg.ctrl-agent
        cfg.dhcp4
        cfg.dhcp6
        cfg.dhcp-ddns
      ])
      (
        lib.mkMerge [
          {
            environment.systemPackages = [ cfg.package ];

            users.users.${cfg.user} = {
              isSystemUser = true;
              inherit (cfg) group;
            };
            users.groups.${cfg.group} = { };
          }

          (mkKeaService {
            componentName = "ctrl-agent";
            binaryName = "kea-ctrl-agent";
            componentCfg = cfg.ctrl-agent;
          })

          (mkKeaService {
            componentName = "dhcp4";
            binaryName = "kea-dhcp4";
            componentCfg = cfg.dhcp4;
            capabilities = [
              "CAP_NET_BIND_SERVICE"
              "CAP_NET_RAW"
            ];
          })

          (mkKeaService {
            componentName = "dhcp6";
            binaryName = "kea-dhcp6";
            componentCfg = cfg.dhcp6;
            capabilities = [ "CAP_NET_BIND_SERVICE" ];
          })

          (mkKeaService {
            componentName = "dhcp-ddns";
            binaryName = "kea-dhcp-ddns";
            componentCfg = cfg.dhcp-ddns;
            capabilities = [ "CAP_NET_BIND_SERVICE" ];
          })
        ]
      );
}
