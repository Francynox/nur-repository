{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.francynox.unbound;
in
{
  options.services.francynox.unbound = {
    enable = lib.mkEnableOption "Unbound DNS recursor (francynox NUR version)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.francynox.unbound;
      defaultText = lib.literalExpression "pkgs.francynox.unbound";
      description = "The Unbound package (from francynox NUR) to use.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "unbound";
      description = "User account under which Unbound runs.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "unbound";
      description = "Group under which Unbound runs.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/unbound";
      description = "The working directory and data directory for Unbound.";
    };

    configDir = lib.mkOption {
      type = lib.types.str;
      default = "/etc/unbound";
      description = "The configuration directory for Unbound.";
    };

    configFile = lib.mkOption {
      type = lib.types.nullOr (lib.types.either lib.types.str lib.types.path);
      default = null;
      description = "Path to the main Unbound configuration file (unbound.conf).";
      example = "/etc/unbound/unbound.conf";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of additional command-line arguments to pass to the named daemon.";
    };

    extraRestartTriggers = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = "A list of extra derivations to trigger a service restart when changed.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.configFile != null;
        message = "services.francynox.unbound.configFile must be set when services.francynox.unbound.enable is true.";
      }
    ];
    environment.systemPackages = [ cfg.package ];
    users.users.${cfg.user} = {
      isSystemUser = true;
      inherit (cfg) group;
    };
    users.groups.${cfg.group} = { };
    systemd.services.unbound =
      let
        configFile = pkgs.writeText "unbound.conf" ''
          server:
            chroot: ""
            username: ""
            root-hints: "${pkgs.dns-root-data}/root.hints"

            remote-control:
              control-enable: yes
              control-interface: /run/unbound/unbound.ctl

            include: "${cfg.configFile}"
        '';
      in
      {
        description = "Unbound DNS recursor (francynox)";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        preStart = ''
          ${cfg.package}/bin/unbound-anchor
        '';
        restartTriggers = cfg.extraRestartTriggers;
        serviceConfig = {
          Type = "notify";
          ExecStart = "${cfg.package}/bin/unbound -d -p -c ${configFile} ${lib.escapeShellArgs cfg.extraArgs}";
          ExecReload = "${cfg.package}/bin/unbound-control -c ${configFile} reload";
          ExecStop = "${cfg.package}/bin/unbound-control -c ${configFile} stop";
          AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
          CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
          User = cfg.user;
          Group = cfg.group;
          ConfigurationDirectory = lib.mkIf (lib.hasPrefix "/etc/" cfg.configDir) (
            lib.removePrefix "/etc/" cfg.configDir
          );
          RuntimeDirectory = "unbound";
          RuntimeDirectoryPreserve = true;
          StateDirectory = lib.mkIf (lib.hasPrefix "/var/lib/" cfg.dataDir) (
            lib.removePrefix "/var/lib/" cfg.dataDir
          );
          StateDirectoryMode = "0700";
          CacheDirectory = "unbound";
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
          RestrictAddressFamilies = [ "AF_UNIX AF_INET AF_INET6 AF_NETLINK" ];
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          RestrictNamespaces = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = "~@clock @cpu-emulation @debug @module @mount @obsolete @privileged @raw-io @reboot @resources @swap";
        };
      };
  };
}
