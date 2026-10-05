{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.francynox.sparkyfitness;

  # Non-secret runtime environment derived from the module options. Secrets
  # (passwords, encryption key, auth secret) come from cfg.environmentFile.
  baseEnv = {
    NODE_ENV = "production";
    SPARKY_FITNESS_SERVER_PORT = toString cfg.port;
    SPARKY_FITNESS_DB_HOST = cfg.database.host;
    SPARKY_FITNESS_DB_PORT = toString cfg.database.port;
    SPARKY_FITNESS_DB_NAME = cfg.database.name;
    SPARKY_FITNESS_DB_USER = cfg.database.user;
    SPARKY_FITNESS_APP_DB_USER = cfg.database.appUser;
    SPARKY_FITNESS_FRONTEND_URL = cfg.frontendUrl;
    SPARKY_FITNESS_CUSTOM_UPLOADS_DIRECTORY = "${cfg.stateDir}/uploads";
    SPARKY_FITNESS_CUSTOM_BACKUP_DIRECTORY = "${cfg.stateDir}/backup";
    SPARKY_FITNESS_CUSTOM_TEMP_DIRECTORY = "${cfg.stateDir}/temp_uploads";
    SPARKY_FITNESS_LOG_LEVEL = cfg.logLevel;
  }
  // cfg.extraEnvironment;
in
{
  options.services.francynox.sparkyfitness = {
    enable = lib.mkEnableOption "the SparkyFitness self-hosted fitness tracker (francynox NUR version)";

    backendPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.francynox.sparkyfitness-server;
      defaultText = lib.literalExpression "pkgs.francynox.sparkyfitness-server";
      description = "The SparkyFitness backend server package (from francynox NUR) to use.";
    };

    frontendPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.francynox.sparkyfitness-frontend;
      defaultText = lib.literalExpression "pkgs.francynox.sparkyfitness-frontend";
      description = "The built SparkyFitness frontend static assets (from francynox NUR) to use.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "sparkyfitness";
      description = "User account under which the backend runs.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "sparkyfitness";
      description = "Group under which the backend runs.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/sparkyfitness";
      description = "Directory for persistent state (uploads and backups).";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3010;
      description = "Port the backend API listens on.";
    };

    frontendUrl = lib.mkOption {
      type = lib.types.str;
      example = "https://fitness.example.com";
      description = ''
        Public URL of the frontend. Used for CORS and Better Auth trusted
        origins. Must match how users reach the site.
      '';
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [
        "DEBUG"
        "INFO"
        "WARN"
        "ERROR"
        "SILENT"
      ];
      default = "INFO";
      description = "Backend log verbosity.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/sparkyfitness.env";
      description = ''
        Path to an EnvironmentFile (systemd format) holding secret values that
        should not live in the Nix store. At minimum this should set:

          SPARKY_FITNESS_DB_PASSWORD
          SPARKY_FITNESS_APP_DB_PASSWORD
          SPARKY_FITNESS_API_ENCRYPTION_KEY
          BETTER_AUTH_SECRET

        SPARKY_FITNESS_DB_PASSWORD is also used to provision the local
        PostgreSQL owner role.
      '';
    };

    extraEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        SPARKY_FITNESS_DISABLE_SIGNUP = "true";
      };
      description = "Additional environment variables passed to the backend.";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of additional command-line arguments to pass to the backend daemon.";
    };

    extraRestartTriggers = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = "A list of extra derivations to trigger a service restart when changed.";
    };

    database = {
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.postgresql_18;
        defaultText = lib.literalExpression "pkgs.postgresql_18";
        description = ''
          PostgreSQL package to use. Must be PostgreSQL 15 or newer:
          the migrations use `UNIQUE NULLS NOT DISTINCT`, which earlier
          versions reject with a syntax error near "NULLS".
        '';
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "/run/postgresql";
        description = "PostgreSQL host or Unix socket directory.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 5432;
        description = "PostgreSQL port.";
      };

      name = lib.mkOption {
        type = lib.types.str;
        default = "sparkyfitness_db";
        description = "Database name.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "sparky";
        description = ''
          Privileged database role used for migrations. It must be able to
          CREATE ROLE because the backend creates the application role on
          startup.
        '';
      };

      appUser = lib.mkOption {
        type = lib.types.str;
        default = "sparky_app";
        description = ''
          Limited application role. Created automatically by the backend at
          startup using SPARKY_FITNESS_APP_DB_PASSWORD.
        '';
      };
    };

    caddy = {
      virtualHost = lib.mkOption {
        type = lib.types.str;
        default =
          if lib.hasPrefix "https://" cfg.frontendUrl then
            lib.removePrefix "https://" cfg.frontendUrl
          else
            cfg.frontendUrl;
        defaultText = lib.literalExpression ''
          if lib.hasPrefix "https://" cfg.frontendUrl then
            lib.removePrefix "https://" cfg.frontendUrl
          else
            cfg.frontendUrl
        '';
        description = "Caddy virtual host name for the frontend.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.environmentFile != null;
        message = "services.francynox.sparkyfitness.environmentFile must be set with the required secrets.";
      }
    ];

    environment.systemPackages = [ cfg.backendPackage ];

    users.users = lib.optionalAttrs (cfg.user == "sparkyfitness") {
      sparkyfitness = {
        isSystemUser = true;
        inherit (cfg) group;
        home = cfg.stateDir;
      };
    };

    users.groups = lib.optionalAttrs (cfg.group == "sparkyfitness") {
      sparkyfitness = { };
    };

    # --- PostgreSQL -----------------------------------------------------------
    services.postgresql = {
      enable = lib.mkDefault true;
      # Pin the major version (>= 15 for `UNIQUE NULLS NOT DISTINCT`) instead of
      # the stateVersion-derived default, which can be too old. Override via
      # `services.francynox.sparkyfitness.database.package`.
      package = cfg.database.package;
      # The database itself is created by the sparkyfitness-db-init service so
      # it can be owned by the password-authenticated owner role. Using
      # `ensureDatabases` here would race with that service.
      authentication = lib.mkAfter ''
        # Allow SparkyFitness roles to connect over the local Unix socket with a password.
        local ${cfg.database.name} ${cfg.database.user} md5
        local ${cfg.database.name} ${cfg.database.appUser} md5

        # TCP fallback for loopback connections.
        host ${cfg.database.name} ${cfg.database.user} 127.0.0.1/32 md5
        host ${cfg.database.name} ${cfg.database.user} ::1/128 md5
        host ${cfg.database.name} ${cfg.database.appUser} 127.0.0.1/32 md5
        host ${cfg.database.name} ${cfg.database.appUser} ::1/128 md5
      '';
    };

    systemd.services = {
      # Provision the owner role + password and hand the database over to it.
      # The backend itself creates the limited application role at startup.
      sparkyfitness-db-init = {
        description = "SparkyFitness database initialisation (francynox)";
        after = [ "postgresql.service" ];
        requires = [ "postgresql.service" ];
        wantedBy = [ "multi-user.target" ];
        before = [ "sparkyfitness.service" ];
        restartTriggers = cfg.extraRestartTriggers;
        serviceConfig = {
          Type = "oneshot";
          User = "postgres";
          Group = "postgres";
          RemainAfterExit = true;
          EnvironmentFile = cfg.environmentFile;
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
        };
        path = [ config.services.postgresql.package ];
        script = ''
          set -euo pipefail
          psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${cfg.database.user}'" | grep -q 1 || psql -c 'CREATE ROLE "${cfg.database.user}"'
          psql -v passwd="$SPARKY_FITNESS_DB_PASSWORD" <<< "ALTER ROLE \"${cfg.database.user}\" WITH LOGIN CREATEROLE PASSWORD :'passwd';"

          psql -tAc "SELECT 1 FROM pg_database WHERE datname='${cfg.database.name}'" | grep -q 1 || psql -c 'CREATE DATABASE "${cfg.database.name}"'
          psql -c 'ALTER DATABASE "${cfg.database.name}" OWNER TO "${cfg.database.user}";'
          psql -d "${cfg.database.name}" -c 'ALTER SCHEMA public OWNER TO "${cfg.database.user}";'
        '';
      };

      # --- Backend service --------------------------------------------------
      sparkyfitness = {
        description = "SparkyFitness backend API server (francynox)";
        wantedBy = [ "multi-user.target" ];
        after = [
          "network.target"
          "postgresql.service"
          "sparkyfitness-db-init.service"
        ];
        requires = [
          "sparkyfitness-db-init.service"
        ];

        environment = baseEnv;

        restartTriggers = cfg.extraRestartTriggers;

        serviceConfig = {
          ExecStart = "${lib.getExe cfg.backendPackage} ${lib.escapeShellArgs cfg.extraArgs}";
          CapabilityBoundingSet = "";
          User = cfg.user;
          Group = cfg.group;
          EnvironmentFile = cfg.environmentFile;
          StateDirectory = lib.mkIf (lib.hasPrefix "/var/lib/" cfg.stateDir) (
            lib.removePrefix "/var/lib/" cfg.stateDir
          );
          StateDirectoryMode = "0750";
          WorkingDirectory = cfg.stateDir;
          Restart = "on-failure";
          RestartSec = 5;
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
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_INET"
            "AF_INET6"
            "AF_NETLINK"
          ];
          LockPersonality = true;
          # V8 JIT (node/tsx) needs writable+executable memory.
          MemoryDenyWriteExecute = false;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          RestrictNamespaces = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = "~@clock @cpu-emulation @debug @module @mount @obsolete @privileged @raw-io @reboot @resources @swap";
        };
      };
    };

    # --- Caddy frontend + reverse proxy --------------------------------------
    services.caddy = {
      enable = lib.mkDefault true;
      virtualHosts.${cfg.caddy.virtualHost} = {
        extraConfig = ''
          root * ${cfg.frontendPackage}
          encode zstd gzip

          # API & uploads
          handle /api/* {
            reverse_proxy http://127.0.0.1:${toString cfg.port}
          }

          handle /uploads/* {
            reverse_proxy http://127.0.0.1:${toString cfg.port}
          }

          # Mobile app /health-data endpoint rewrite
          handle_path /health-data* {
            rewrite * /api/health-data{uri}
            reverse_proxy http://127.0.0.1:${toString cfg.port}
          }

          # External MCP endpoint (streamed SSE responses)
          handle /mcp* {
            reverse_proxy http://127.0.0.1:${toString cfg.port} {
              flush_interval -1
            }
          }

          # Static assets (immutable long cache)
          @assets path /assets/*
          header @assets Cache-Control "public, no-transform, immutable, max-age=31536000"

          # SPA frontend fallback
          handle {
            header /index.html Cache-Control "no-cache, no-store, must-revalidate"
            try_files {path} /index.html
            file_server
          }
        '';
      };
    };
  };
}
