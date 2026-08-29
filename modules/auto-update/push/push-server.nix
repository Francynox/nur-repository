{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.francynox.auto-update.push-server;
  cfg-webhook = config.services.webhook;
  cfg-telegram = config.services.francynox.telegram-notify.package;

  deployWebhookScript = pkgs.replaceVarsWith {
    src = ./scripts/deploy-webhook.sh;
    isExecutable = true;
    replacements = {
      inherit (pkgs) runtimeShell;
      path = lib.makeBinPath [
        pkgs.coreutils
        pkgs.systemd
      ];
      inherit (cfg) tokenFile;
    };
  };

  deployScript = pkgs.replaceVarsWith {
    src = ./scripts/deploy-exec.sh;
    isExecutable = true;
    replacements = {
      inherit (pkgs) runtimeShell;
      path = lib.makeBinPath [
        pkgs.coreutils
        pkgs.nixos-rebuild
        pkgs.util-linux
        pkgs.openssh
      ];
      inherit (cfg) targetUser flakePath sshKeyFile;
      telegramNotifyBin = if cfg.telegramNotify then "${cfg-telegram}/bin/telegram-notify" else "";
    };
  };
in
{
  options.services.francynox.auto-update.push-server = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable deploy-webhook service for push-based deployments.";
    };

    flakePath = lib.mkOption {
      type = lib.types.str;
      description = "Flake URI or path to the flake repository.";
    };

    targetUser = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "SSH user to log into target hosts during deploy.";
    };

    tokenFile = lib.mkOption {
      type = lib.types.str;
      description = "Path to the decrypted SOPS token file.";
    };

    sshKeyFile = lib.mkOption {
      type = lib.types.str;
      description = "Path to the decrypted SOPS SSH private key file used to deploy.";
    };

    githubPatFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to the decrypted SOPS GitHub Personal Access Token file.";
    };

    telegramNotify = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Send Telegram notifications on deploy success/failure.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9000;
      description = "Port for the webhook listener.";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = [
      cfg.port
    ];

    systemd.services."deploy-host@" = {
      description = "Deploy configuration to %I";
      path = [
        pkgs.nixos-rebuild
        pkgs.git
        pkgs.openssh
        pkgs.util-linux
      ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg-webhook.user;
        Group = cfg-webhook.group;

        RuntimeDirectory = "deploy-webhook";

        Environment = [
          "HOME=/run/deploy-webhook"
        ]
        ++ lib.optionals (cfg.githubPatFile != null) [
          "NIX_USER_CONF_FILES=/run/deploy-webhook/nix-access-tokens.conf"
        ];

        ExecStartPre = lib.mkIf (cfg.githubPatFile != null) (
          pkgs.writeShellScript "deploy-pre-script" ''
            set -euo pipefail
            PAT=$(cat "${cfg.githubPatFile}" | tr -d '\n\r ')
            echo "access-tokens = github.com=$PAT" > /run/deploy-webhook/nix-access-tokens.conf
            chmod 600 /run/deploy-webhook/nix-access-tokens.conf
          ''
        );

        ExecStart = "${deployScript} %i";
        TimeoutStartSec = "30m";
      };
    };

    security.sudo.extraRules = [
      {
        users = [ cfg-webhook.user ];
        commands = [
          {
            command = "${pkgs.systemd}/bin/systemctl start --no-block deploy-host@*";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    services.webhook = {
      enable = true;
      inherit (cfg) port;
      hooks = {
        deploy = {
          execute-command = "${deployWebhookScript}";
          command-working-directory = "/tmp";
          pass-arguments-to-command = [
            {
              source = "payload";
              name = "host";
            }
            {
              source = "request";
              name = "remote-addr";
            }
            {
              source = "header";
              name = "X-Deploy-Token";
            }
          ];
          trigger-rule-mismatch-http-response-code = 400;
          trigger-rule = {
            and = [
              {
                match = {
                  type = "regex";
                  regex = "^[a-zA-Z0-9.-]+$";
                  parameter = {
                    source = "payload";
                    name = "host";
                  };
                };
              }
              {
                match = {
                  type = "regex";
                  regex = "^.+$";
                  parameter = {
                    source = "header";
                    name = "X-Deploy-Token";
                  };
                };
              }
            ];
          };
        };
      };
    };
  };
}
