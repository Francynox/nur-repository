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
    src = ./fetch-pat.sh;
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

  notifyScript = pkgs.writeShellScript "nixos-upgrade-notify" ''
    if [ "$SERVICE_RESULT" = "success" ]; then
      ${cfg-telegram.package}/bin/telegram-notify "✅ <b>Pull upgrade successful</b>: ${config.networking.hostName}" || true
    else
      ${cfg-telegram.package}/bin/telegram-notify "❌ <b>Pull upgrade failed</b>: ${config.networking.hostName}" || true
    fi
  '';
in
{
  options.services.francynox.auto-update.pull = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable pull-based auto-update.";
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
      type = lib.types.path;
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

    # Ensure nixos-upgrade uses the PAT and optionally notifies via Telegram
    systemd.services.nixos-upgrade = {
      environment.NIX_USER_CONF_FILES = "/run/nix-private-access.conf";
      serviceConfig = lib.mkIf (cfg.telegramNotify && cfg-telegram.enable) {
        ExecStopPost = "${notifyScript}";
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
