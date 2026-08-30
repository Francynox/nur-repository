{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.francynox.mutable-configs;
  telegramNotifyScript = config.services.francynox.telegram-notify.package;

  pythonWithPyYaml = pkgs.python3.withPackages (p: [ p.pyyaml ]);

  yamlComparator = pkgs.writeShellScript "compare-yaml" ''
        ${pythonWithPyYaml}/bin/python3 -c '
    import sys
    import yaml

    try:
        with open(sys.argv[1], "r", encoding="utf-8") as f1, open(sys.argv[2], "r", encoding="utf-8") as f2:
            data1 = yaml.safe_load(f1)
            data2 = yaml.safe_load(f2)
            sys.exit(0 if data1 == data2 else 1)
    except Exception as e:
        print(f"Error parsing YAML: {e}", file=sys.stderr)
        sys.exit(1)
    ' "$1" "$2"
  '';

  jsonComparator = pkgs.writeShellScript "compare-json" ''
        ${pkgs.python3}/bin/python3 -c '
    import sys
    import json

    try:
        with open(sys.argv[1], "r", encoding="utf-8") as f1, open(sys.argv[2], "r", encoding="utf-8") as f2:
            data1 = json.load(f1)
            data2 = json.load(f2)
            sys.exit(0 if data1 == data2 else 1)
    except Exception as e:
        print(f"Error parsing JSON: {e}", file=sys.stderr)
        sys.exit(1)
    ' "$1" "$2"
  '';

  mutableConfigFileOptions = {
    options = {

      source = mkOption {
        type = types.path;
        description = "Path to the configuration file source (Nix store path or local path).";
      };

      mode = mkOption {
        type = types.str;
        default = "0644";
        description = "File mode (e.g. '0644').";
      };

      user = mkOption {
        type = types.str;
        default = "root";
        description = "User owner of the file.";
      };

      group = mkOption {
        type = types.str;
        default = "root";
        description = "Group owner of the file.";
      };

      notifyOnUpgrade = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to send a notification if the configuration has changed during an upgrade.";
      };

      stopAutoUpgrade = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to stop the auto-upgrade if the configuration has changed.";
      };

      pathToCheck = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Runtime path on the target system to check against the pristine copy. Defaults to the target file path if not set.";
      };

      format = mkOption {
        type = types.enum [
          "text"
          "yaml"
          "json"
        ];
        default = "text";
        description = "Format of the configuration file. 'yaml' and 'json' perform semantic comparison ignoring whitespace and key ordering.";
      };

      diffFlags = mkOption {
        type = types.listOf types.str;
        default = [
          "-q"
          "-b"
        ];
        description = "Flags passed to diff when format is 'text'.";
      };

      checkCommand = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Custom command or script to test for configuration drift. If set, overrides format and diffFlags. Available shell variables: $CHECK_FILE and $PRISTINE_FILE. Must exit 0 if configs match, non-zero if drifted.";
      };
    };
  };
in
{
  options.services.francynox.mutable-configs = mkOption {
    type = types.attrsOf (types.submodule mutableConfigFileOptions);
    default = { };
    description = ''
      Set of mutable configuration files. Each entry creates:
      1. A writable copy of the source at /etc/<path> (initially copied, never overwritten automatically).
      2. A read-only 'pristine' copy at /etc/<dir>/pristine/<filename>.
      3. A safety check in nixos-upgrade service to prevent overwrites or notify on changes.
    '';
  };

  config = mkIf (cfg != { }) {

    environment.etc = mkMerge (
      mapAttrsToList (
        name: conf:
        let
          d = dirOf name;
          pristineRelPath =
            if d == "." then "pristine/${baseNameOf name}" else "${d}/pristine/${baseNameOf name}";
        in
        {
          # Target Configuration File
          "${name}" = {
            inherit (conf)
              source
              mode
              user
              group
              ;
          };

          # Pristine File
          "${pristineRelPath}" = {
            inherit (conf) source;
          };
        }
      ) cfg
    );

    # Checks if local files have drifted from the pristine state.
    systemd.services.nixos-upgrade = {
      path = lib.mkAfter [
        pkgs.diffutils
        pkgs.coreutils
        pkgs.hostname
      ];
      preStart = ''
        echo "Checking mutable configs for local modifications..."
        EXIT_ON_CHANGE=0
        CHANGED_FILES=""

        ${concatStringsSep "\n" (
          mapAttrsToList (name: conf: ''
            TARGET_FILE="/etc/${name}"
            PRISTINE_DIR="$(dirname "$TARGET_FILE")/pristine"
            PRISTINE_FILE="$PRISTINE_DIR/$(basename "$TARGET_FILE")"

            # Determine which file to check against pristine
            CHECK_FILE=${if conf.pathToCheck != null then ''"${conf.pathToCheck}"'' else ''"$TARGET_FILE"''}

            if [ -f "$CHECK_FILE" ] && [ -f "$PRISTINE_FILE" ]; then
              if ! ${
                if conf.checkCommand != null then
                  conf.checkCommand
                else if conf.format == "yaml" then
                  "${yamlComparator} \"$CHECK_FILE\" \"$PRISTINE_FILE\""
                else if conf.format == "json" then
                  "${jsonComparator} \"$CHECK_FILE\" \"$PRISTINE_FILE\""
                else
                  "diff ${escapeShellArgs conf.diffFlags} \"$CHECK_FILE\" \"$PRISTINE_FILE\""
              }; then
                echo "  [!] Configuration drift detected: $CHECK_FILE differs from pristine."
                
                ${optionalString conf.notifyOnUpgrade ''
                  # Collect files that need notification
                  CHANGED_FILES="$CHANGED_FILES$CHECK_FILE\n"
                ''}

                ${optionalString conf.stopAutoUpgrade ''
                  echo "  [!!!] CRITICAL: Auto-upgrade stopped due to changes in $CHECK_FILE."
                  EXIT_ON_CHANGE=1
                ''}
              else
                 echo "  [i] $CHECK_FILE matches pristine."
              fi
            else
               echo "  [?] Warning: Could not check $CHECK_FILE or $PRISTINE_FILE (file missing)."
            fi
          '') cfg
        )}

        if [ -n "$CHANGED_FILES" ]; then
          if [ -x ${telegramNotifyScript}/bin/telegram-notify ]; then
            STATUS_MSG="Upgrade will proceed."
            if [ "$EXIT_ON_CHANGE" -eq 1 ]; then
              STATUS_MSG="Upgrade aborted!"
            fi
            ${telegramNotifyScript}/bin/telegram-notify "⚠️ <b>Configuration Drift Detected</b>\n\n<b>Status:</b> $STATUS_MSG\n\n<b>Files with changes:</b>\n<pre>$CHANGED_FILES</pre>" || true
          fi
        fi

        if [ "$EXIT_ON_CHANGE" -eq 1 ]; then
          echo "Aborting auto-upgrade."
          exit 1
        fi
      '';
    };
  };
}
