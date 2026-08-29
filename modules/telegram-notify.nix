{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.francynox.telegram-notify;

  telegramNotifyScript = pkgs.writeShellScriptBin "telegram-notify" ''
    if [ "$#" -ne 1 ]; then
      echo "Usage: telegram-notify \"<message>\""
      exit 1
    fi

    if ! ${pkgs.coreutils}/bin/printf "%b" "$1" | ${pkgs.netcat-openbsd}/bin/nc -N -U /run/telegram-notify/notify.sock; then
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

    if ! curl --fail-with-body -s \
      --connect-timeout 10 \
      --max-time 30 \
      --retry 3 \
      --retry-delay 3 \
      --retry-connrefused \
      -X POST "https://api.telegram.org/bot''${BOT_TOKEN}/sendMessage" \
      -d chat_id="''${CHAT_ID}" \
      --data-urlencode "text=''${TEXT}" \
      -d parse_mode="HTML"; then

      echo "ERROR: Telegram API rejected the notification payload." >&2
      exit 1
    fi
  '';
in
{
  options.services.francynox.telegram-notify = {
    enable = mkEnableOption "Telegram notification service";

    botTokenFile = mkOption {
      type = types.path;
      description = "Path to the file containing the Telegram bot token.";
    };

    chatIdFile = mkOption {
      type = types.path;
      description = "Path to the file containing the Telegram chat ID.";
    };

    package = mkOption {
      type = types.package;
      internal = true;
      default = telegramNotifyScript;
      description = "Package containing the Telegram notification script.";
    };

    user = mkOption {
      type = lib.types.str;
      default = "telegram-notify";
      description = "User to run the Telegram notification service as.";
    };

    group = mkOption {
      type = lib.types.str;
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
      path = [ pkgs.curl ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        StandardInput = "socket";
        ExecStart = telegramNotifyServer;
      };
    };
  };
}
