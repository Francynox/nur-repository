{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.francynox.auto-update.pull;
  cfg-telegram = config.services.francynox.telegram-notify;

  fetchPatScript = pkgs.replaceVarsWith {
    src = ./scripts/fetch-pat.sh;
    isExecutable = true;
    replacements = {
      inherit (pkgs) runtimeShell;
      path = lib.makeBinPath [
        pkgs.coreutils
        pkgs.curl
        pkgs.sops
        pkgs.ssh-to-age
      ];
      inherit (cfg) sopsKeyPath;
      remoteSecretsUrl = cfg.secretsUrl;
    };
  };

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

    secretsUrl = lib.mkOption {
      type = lib.types.str;
      description = "Secrets repository or URL.";
    };

    sopsKeyPath = lib.mkOption {
      type = lib.types.str;
      default = "/etc/ssh/ssh_host_ed25519_key";
      description = "Path to SOPS key file.";
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

    # Oneshot service to fetch and decrypt the GitHub PAT on boot
    systemd.services.fetch-github-pat = {
      description = "Fetch and decrypt GitHub PAT for private repo access";
      wantedBy = [ "multi-user.target" ];
      before = [ "nixos-upgrade.service" ];
      requiredBy = [ "nixos-upgrade.service" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = fetchPatScript;
        RemainAfterExit = true;
      };
    };

    # Ensure nixos-upgrade uses the PAT, runs health check / rollback, and notifies
    systemd.services.nixos-upgrade = {
      environment.NIX_USER_CONF_FILES = "/run/nix-private-access.conf";
      serviceConfig = {
        ExecStartPre = pkgs.writeShellScript "pre-upgrade-record" ''
          mkdir -p /run/nixos-upgrade
          readlink -f /nix/var/nix/profiles/system > /run/nixos-upgrade/pre-upgrade-system || true
          systemctl --failed --no-legend --plain | awk '{print $1}' | sort > /run/nixos-upgrade/pre-failed-units || true
        '';
        ExecStopPost = "${postUpgradeScript}";
      };
    };

    # For standard user terminals running 'sudo nixos-rebuild switch' or 'nix'
    environment.shellAliases = {
      nixos-rebuild = "sudo NIX_USER_CONF_FILES=/run/nix-private-access.conf nixos-rebuild";
      nix = "sudo NIX_USER_CONF_FILES=/run/nix-private-access.conf nix";
    };

    # For root shells (e.g., sudo -i or direct root login)
    environment.extraInit = ''
      if [ "$USER" = "root" ] || [ "$UID" -eq 0 ]; then
        export NIX_USER_CONF_FILES="/run/nix-private-access.conf"
      fi
    '';

    # Expose the fetch script for manual use
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "fetch-pat" ''
        exec ${fetchPatScript}
      '')
    ];
  };
}
