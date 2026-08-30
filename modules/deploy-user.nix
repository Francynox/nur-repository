{
  config,
  lib,
  ...
}:
let
  cfg = config.services.francynox.deploy-user;
in
{
  options.services.francynox.deploy-user = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable generic deployment user.";
    };

    name = lib.mkOption {
      type = lib.types.str;
      default = "deploy";
      description = "The deploy username";
    };

    extraGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional groups for the deploy user.";
    };

    sshAuthorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "SSH authorized keys for the deploy user";
    };

    passwordlessSudo = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Allow the deploy user to run sudo without a password.";
    };

    trustedUser = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Add the deploy user to nix.settings.trusted-users.";
    };

    autologin = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable autologin for the deploy user";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.${cfg.name} = { };

    users.users.${cfg.name} = {
      isNormalUser = true;
      description = "Deployment User";
      group = lib.mkForce cfg.name;
      inherit (cfg) extraGroups;
      openssh.authorizedKeys.keys = cfg.sshAuthorizedKeys;
    };

    nix.settings.trusted-users = lib.mkIf cfg.trustedUser [ cfg.name ];

    security.sudo.extraRules = lib.mkIf cfg.passwordlessSudo [
      {
        users = [ cfg.name ];
        commands = [
          {
            command = "ALL";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    services.getty.autologinUser = lib.mkIf cfg.autologin cfg.name;
  };
}
