{
  config,
  lib,
  ...
}:
let
  cfg = config.services.francynox.auto-update;
in
{
  imports = [
    ./pull/pull.nix
    ./push/push.nix
    ./push/push-server.nix
  ];

  options.services.francynox.auto-update = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable generic auto-update.";
    };

    mode = lib.mkOption {
      type = lib.types.enum [
        "pull"
        "push"
      ];
      default = "pull";
      description = "Auto-update mode: pull (local builds) or push (remote builds via webhook)";
    };

    dates = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 03:00:00";
      description = "Cron expression for when to run auto-update.";
    };

    randomizedDelaySec = lib.mkOption {
      type = lib.types.str;
      default = "1h";
      description = "Randomized delay in seconds after the scheduled time.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.francynox.auto-update.pull.enable = cfg.mode == "pull";
    services.francynox.auto-update.push.enable = cfg.mode == "push";

    system.autoUpgrade = {
      enable = true;
      inherit (cfg) dates;
      inherit (cfg) randomizedDelaySec;
    };
  };
}
