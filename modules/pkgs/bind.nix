{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.francynox.bind;
in
{
  options.services.francynox.bind = {
    enable = lib.mkEnableOption "BIND DNS server (francynox NUR version)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.francynox.bind;
      defaultText = lib.literalExpression "pkgs.francynox.bind";
      description = "The BIND package (from francynox NUR) to use.";
    };

    configFile = lib.mkOption {
      type = lib.types.nullOr (lib.types.either lib.types.str lib.types.path);
      default = null;
      description = "Path to the main BIND configuration file (named.conf).";
      example = "/etc/bind/named.conf";
    };

    rndcKeyFile = lib.mkOption {
      type = lib.types.str;
      default = cfg.configDir + "/rndc.key";
      description = "Path to the rndc.key file.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "bind";
      description = "User account under which BIND runs.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "bind";
      description = "Group under which BIND runs.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/bind";
      description = "The working directory and data directory for BIND.";
    };

    configDir = lib.mkOption {
      type = lib.types.str;
      default = "/etc/bind";
      description = "The configuration directory for BIND.";
    };

    staticZoneFiles = lib.mkOption {
      type = lib.types.attrsOf (lib.types.either lib.types.str lib.types.path);
      default = { };
      description = ''
        An attribute set of static zone files to be forcefully copied into the zones directory
        on every restart. The attribute name will be the destination filename.
      '';
    };

    dynamicZoneFiles = lib.mkOption {
      type = lib.types.attrsOf (lib.types.either lib.types.str lib.types.path);
      default = { };
      description = ''
        An attribute set of dynamic zone templates (e.g. for DHCP/DDNS) to be copied into the zones
        directory ONLY if they do not already exist. 
        The attribute name will be the destination filename.
      '';
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
        message = "services.francynox.bind.configFile must be set when services.francynox.bind.enable is true.";
      }
    ];
    environment.systemPackages = [ cfg.package ];
    users.users.${cfg.user} = {
      isSystemUser = true;
      inherit (cfg) group;
    };
    users.groups.${cfg.group} = { };
    systemd.services.named = {
      description = "BIND Domain Name Server (francynox)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      preStart = ''
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (destName: srcPath: ''
            mkdir -p "$(dirname "${cfg.dataDir}/${destName}")"
            cp -f ${lib.escapeShellArg (toString srcPath)} "${cfg.dataDir}/${destName}"
          '') cfg.staticZoneFiles
        )}

        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (destName: srcPath: ''
            mkdir -p "$(dirname "${cfg.dataDir}/${destName}")"
            cp -n ${lib.escapeShellArg (toString srcPath)} "${cfg.dataDir}/${destName}"
          '') cfg.dynamicZoneFiles
        )}

        if [ ! -r ${lib.escapeShellArg cfg.rndcKeyFile} ]; then
          echo "${cfg.rndcKeyFile} file not found or not readable by user '${cfg.user}'. Cannot start bind service.";
          exit 1;
        fi

        ${cfg.package}/bin/named-checkconf ${cfg.configFile}
      '';
      restartTriggers = cfg.extraRestartTriggers;
      serviceConfig = {
        Type = "notify";
        ExecStart = "${cfg.package}/bin/named -f -c ${cfg.configFile} ${lib.escapeShellArgs cfg.extraArgs}";
        ExecReload = "${pkgs.writeShellScript "named-reload" ''
          set -e
          ${cfg.package}/bin/named-checkconf ${cfg.configFile}
          ${cfg.package}/bin/rndc -k ${cfg.rndcKeyFile} reload
        ''}";
        ExecStop = "${cfg.package}/bin/rndc -k ${cfg.rndcKeyFile} stop";
        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
        CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
        User = cfg.user;
        Group = cfg.group;
        ConfigurationDirectory = lib.mkIf (lib.hasPrefix "/etc/" cfg.configDir) (
          lib.removePrefix "/etc/" cfg.configDir
        );
        RuntimeDirectory = "named";
        RuntimeDirectoryPreserve = true;
        StateDirectory = lib.mkIf (lib.hasPrefix "/var/lib/" cfg.dataDir) (
          lib.removePrefix "/var/lib/" cfg.dataDir
        );
        StateDirectoryMode = "0700";
        CacheDirectory = "bind";
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
