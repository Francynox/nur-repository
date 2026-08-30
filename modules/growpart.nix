{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.francynox.growpart;
in
{
  options.services.francynox.growpart = lib.mkOption {
    description = "Configure partitions to be grown on boot";
    default = { };
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          device = lib.mkOption {
            type = lib.types.str;
            description = "The device path (e.g. /dev/sda)";
          };
          partition = lib.mkOption {
            type = lib.types.int;
            description = "The partition number to grow";
          };
          before = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "List of systemd services this should run before";
          };
          after = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "List of systemd services this should run after";
          };
        };
      }
    );
  };

  config = lib.mkIf (cfg != { }) {
    systemd.services = lib.mapAttrs' (
      name: opts:
      lib.nameValuePair "growpart-${name}" {
        description = "Grow partition ${toString opts.partition} on ${opts.device}";
        wantedBy = [ "local-fs-pre.target" ];
        inherit (opts) after;
        before = opts.before ++ [
          "local-fs-pre.target"
          "shutdown.target"
        ];
        conflicts = [ "shutdown.target" ];
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutSec = "infinity";
          SuccessExitStatus = "0 1";
        };
        script = ''
          echo "Expanding partition layout for ${opts.device} (part ${toString opts.partition})..."
          "${pkgs.cloud-utils.guest}/bin/growpart" "${opts.device}" "${toString opts.partition}"

          echo "Settling kernel udev events..."
          ${pkgs.systemd}/bin/udevadm settle
        '';
      }
    ) cfg;
  };
}
