{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.francynox.auto-update.push;
  cfg-telegram = config.services.francynox.telegram-notify;

  triggerWebhook = pkgs.replaceVarsWith {
    src = ./scripts/trigger-webhook.sh;
    isExecutable = true;
    replacements = {
      inherit (pkgs) runtimeShell;
      path = lib.makeBinPath [
        pkgs.curl
        pkgs.coreutils
        pkgs.gnused
      ];
      inherit (cfg.webhook) tokenFile url;
      insecure = lib.boolToString cfg.webhook.insecure;
      inherit (config.networking) hostName;
    };
  };

  notifyFailureScript = pkgs.writeShellScript "nixos-upgrade-push-failure-notify" ''
    if [ "$SERVICE_RESULT" != "success" ]; then
      ${cfg-telegram.package}/bin/telegram-notify "❌ <b>Trigger upgrade failed</b>: ${config.networking.hostName}" || true
    fi
  '';

  pushDeployGuard = pkgs.replaceVarsWith {
    src = ./scripts/push-deploy-guard.sh;
    isExecutable = true;
    replacements = {
      inherit (pkgs) runtimeShell;
      path = lib.makeBinPath [
        pkgs.coreutils
        pkgs.systemd
        pkgs.nixos-rebuild
        pkgs.gawk
        pkgs.gnused
      ];
      autoRollback = lib.boolToString cfg.autoRollback;
      autoReboot = lib.boolToString cfg.autoReboot;
    };
  };
in
{
  options.services.francynox.auto-update.push = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable push-based auto-update.";
    };

    autoRollback = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatically rollback target host to previous generation if deployment or health check fails.";
    };

    webhook = {
      url = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Webhook URL on builder to trigger push.";
      };

      insecure = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Disable SSL verification for curl.";
      };

      tokenFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to file containing authorization token.";
      };
    };

    telegramNotify = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Send Telegram notifications if triggering push auto-update fails.";
    };

    autoReboot = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatically reboot target hosts after successful push deployment if reboot is needed.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.services.francynox.auto-update.pull.enable;
        message = "services.francynox.auto-update.pull.enable and services.francynox.auto-update.push.enable cannot be enabled at the same time.";
      }
      {
        assertion = cfg.webhook.url != "" && cfg.webhook.tokenFile != null;
        message = "services.francynox.auto-update.push: webhook.url and webhook.tokenFile must be set.";
      }
    ];

    system.autoUpgrade = {
      enable = true;
    };

    systemd.services.nixos-upgrade = {
      serviceConfig = {
        ExecStart = lib.mkForce triggerWebhook;
      }
      // lib.optionalAttrs (cfg.telegramNotify && cfg-telegram.enable) {
        ExecStopPost = "${notifyFailureScript}";
      };
    };

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "push-deploy-guard" ''
        exec ${pushDeployGuard} "$@"
      '')
    ];
  };
}
