{
  pkgs ? import <nixpkgs> { },
  package ? "",
}:

let
  nur-pkgs = import ../.. { inherit pkgs; };

  pkg =
    if builtins.hasAttr package nur-pkgs then
      nur-pkgs.${package}
    else
      throw "Package '${package}' not found in NUR repository.";

  updateScriptPath = pkg.passthru.updateScript or null;

  helperScript = ./update-helper.sh;

in
pkgs.writeShellApplication {
  name = "update-${package}";

  runtimeInputs = with pkgs; [
    nix-update
    curl
    jq
    pup
    findutils
    nix
    coreutils
  ];

  text = ''
    set -euo pipefail

    function finish {
      exit_code=$?
      echo ""
      if [ $exit_code -eq 0 ]; then
        echo "--------------------------------------------------------"
        echo "✅ SUCCESS: Update finished for ${package}"
        echo "--------------------------------------------------------"
      else
        echo "--------------------------------------------------------"
        echo "❌ ERROR: Update failed for ${package} with exit code $exit_code"
        echo "--------------------------------------------------------"
      fi
    }

    trap finish EXIT

    echo "--- Updating ${package} ---"

    export BASH_ENV="${helperScript}"

    ${
      if updateScriptPath != null then
        ''
          echo "Executing custom script: ${updateScriptPath}"
          bash "${updateScriptPath}"
        ''
      else
        ''
          echo "Using standard nix-update"
          nix-update "${package}"
        ''
    }
  '';
}
