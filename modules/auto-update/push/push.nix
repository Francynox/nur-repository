{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.francynox.auto-update.push;

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

  pushRebootDetector = pkgs.replaceVarsWith {
    src = ./scripts/push-reboot-detector.sh;
    isExecutable = true;
    replacements = {
      inherit (pkgs) runtimeShell;
      path = lib.makeBinPath [
        pkgs.coreutils
        pkgs.systemd
      ];
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
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to file containing authorization token.";
      };
    };

    autoReboot = lib.mkOption {
      type = lib.types.bool;
      default = false;
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
      path = lib.mkAfter [
        pkgs.curl
        pkgs.coreutils
      ];

      serviceConfig.ExecStart = lib.mkForce triggerWebhook;
    };

    systemd.services.push-reboot-detector = {
      description = "Check if reboot is required and reboot if needed";
      path = [
        pkgs.coreutils
        pkgs.systemd
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pushRebootDetector;
      };
    };
  };
}
