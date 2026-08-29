{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.francynox.auto-update.pull;

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
in
{
  options.services.francynox.auto-update.pull = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable pull-based auto-update.";
    };

    auto-reboot = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable auto-reboot.";
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
      allowReboot = cfg.auto-reboot && !config.boot.isContainer;
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

    # Ensure nixos-upgrade uses the PAT
    systemd.services.nixos-upgrade.environment.NIX_USER_CONF_FILES = "/run/nix-private-access.conf";

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
