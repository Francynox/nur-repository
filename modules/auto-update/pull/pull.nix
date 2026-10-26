{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.francynox.auto-update.pull;
  cfg-telegram = config.services.francynox.telegram-notify;

  postUpgradeScript = pkgs.replaceVarsWith {
    src = ./scripts/post-upgrade.sh;
    isExecutable = true;
    replacements = {
      inherit (pkgs) runtimeShell;
      path = lib.makeBinPath [
        pkgs.coreutils
        pkgs.nixos-rebuild
        pkgs.gawk
        pkgs.gnused
        pkgs.systemd
      ];
      inherit (config.networking) hostName;
      autoRollback = lib.boolToString cfg.autoRollback;
      telegramNotifyBin =
        if (cfg.telegramNotify && cfg-telegram.enable) then
          "${cfg-telegram.package}/bin/telegram-notify"
        else
          "";
    };
  };
in
{
  options.services.francynox.auto-update.pull = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable pull-based auto-update.";
    };

    autoRollback = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatically rollback to previous generation if upgrade or health check fails.";
    };

    autoReboot = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable auto-reboot.";
    };

    telegramNotify = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Send Telegram notifications on pull auto-update success/failure.";
    };

    flakeUrl = lib.mkOption {
      type = lib.types.str;
      description = "Target flake repository URL.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.services.francynox.auto-update.push.enable;
        message = "services.francynox.auto-update.push.enable and services.francynox.auto-update.pull.enable cannot be enabled at the same time.";
      }
    ];

    system.autoUpgrade = {
      enable = true;
      flake = cfg.flakeUrl;
      allowReboot = cfg.autoReboot && !config.boot.isContainer;
    };

    systemd.services.nixos-upgrade = {
      serviceConfig = {
        ExecStartPre = pkgs.writeShellScript "pre-upgrade-record" ''
          set -eu -o pipefail
          ${pkgs.coreutils}/bin/mkdir -p /run/nixos-upgrade
          ${pkgs.coreutils}/bin/readlink -f /nix/var/nix/profiles/system > /run/nixos-upgrade/pre-upgrade-system
          ${pkgs.systemd}/bin/systemctl --failed --no-legend --plain | ${pkgs.gawk}/bin/awk '{print $1}' | ${pkgs.coreutils}/bin/sort > /run/nixos-upgrade/pre-failed-units
        '';
        ExecStopPost = "${postUpgradeScript}";
      };
    };
  };
}
