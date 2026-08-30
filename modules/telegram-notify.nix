{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.services.francynox.telegram-notify;

  telegramNotifyScript = pkgs.writeShellScriptBin "telegram-notify" ''
    if [ "$#" -eq 1 ]; then
      MESSAGE="$1"
    elif [ "$#" -eq 0 ] && [ ! -t 0 ]; then
      MESSAGE="$(cat)"
    else
      echo "Usage: telegram-notify \"<message>\" or echo \"<message>\" | telegram-notify" >&2
      exit 1
    fi

    if [ -z "$MESSAGE" ]; then
      echo "Error: Empty message" >&2
      exit 1
    fi

    if ! ${pkgs.coreutils}/bin/printf "%b" "$MESSAGE" | ${pkgs.netcat-openbsd}/bin/nc -N -U /run/telegram-notify/notify.sock; then
      echo "Error: Failed to write to telegram-notify socket" >&2
      exit 1
    fi
  '';

  telegramNotifyServer = pkgs.writeShellScript "telegram-notify-server" ''
    MESSAGE=$(cat)

    if [ -z "$MESSAGE" ]; then
      echo "Error: Empty message received" >&2
      exit 1
    fi

    if [ ! -f "${cfg.botTokenFile}" ]; then
      echo "Error: Bot token file not found at ${cfg.botTokenFile}" >&2
      exit 1
    fi

    if [ ! -f "${cfg.chatIdFile}" ]; then
      echo "Error: Chat ID file not found at ${cfg.chatIdFile}" >&2
      exit 1
    fi

    BOT_TOKEN=$(cat "${cfg.botTokenFile}" | tr -d '\n\r ')
    CHAT_ID=$(cat "${cfg.chatIdFile}" | tr -d '\n\r ')

    TEXT=$(printf "🖥️ <b>${config.networking.hostName}</b>\n\n%s" "''${MESSAGE}")

    if [ "''${#TEXT}" -gt 4000 ]; then
      TEXT="''${TEXT:0:3900}

    ⚠️ [Message truncated: exceeded 4000 characters]"
    fi

    send_message() {
      local parse_mode="$1"
      local extra_args=()
      if [ -n "$parse_mode" ]; then
        extra_args+=(-d "parse_mode=$parse_mode")
      fi

      curl --fail-with-body -sS \
        --connect-timeout 10 \
        --max-time 30 \
        --retry 3 \
        --retry-delay 3 \
        --retry-connrefused \
        -X POST "https://api.telegram.org/bot''${BOT_TOKEN}/sendMessage" \
        -d chat_id="''${CHAT_ID}" \
        --data-urlencode "text=''${TEXT}" \
        "''${extra_args[@]}"
    }

    if ! send_message "HTML"; then
      echo "Warning: HTML parsing failed, retrying as plain text..." >&2
      if ! send_message ""; then
        echo "ERROR: Failed to send Telegram notification." >&2
        exit 1
      fi
    fi
  '';
in
{
  options.services.francynox.telegram-notify = {
    enable = mkEnableOption "Telegram notification service";

    botTokenFile = mkOption {
      type = types.str;
      description = "Path to the file containing the Telegram bot token.";
    };

    chatIdFile = mkOption {
      type = types.str;
      description = "Path to the file containing the Telegram chat ID.";
    };

    package = mkOption {
      type = types.package;
      internal = true;
      default = telegramNotifyScript;
      description = "Package containing the Telegram notification script.";
    };

    user = mkOption {
      type = types.str;
      default = "telegram-notify";
      description = "User to run the Telegram notification service as.";
    };

    group = mkOption {
      type = types.str;
      default = "telegram-notify";
      description = "Group to run the Telegram notification service as.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    users.users.${cfg.user} = {
      isSystemUser = true;
      inherit (cfg) group;
    };
    users.groups.${cfg.group} = { };

    systemd.sockets.telegram-notify = {
      description = "Telegram Notification Socket";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = "/run/telegram-notify/notify.sock";
        SocketMode = "0666";
        SocketUser = cfg.user;
        SocketGroup = cfg.group;
        DirectoryMode = "0755";
        Accept = true;
      };
    };

    systemd.services."telegram-notify@" = {
      description = "Send Telegram Message";
      requires = [ "telegram-notify.socket" ];
      path = [
        pkgs.curl
        pkgs.coreutils
      ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        StandardInput = "socket";
        ExecStart = telegramNotifyServer;

        # Security & Sandboxing
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        RestrictRealtime = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        ProtectKernelModules = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
      };
    };
  };
}
