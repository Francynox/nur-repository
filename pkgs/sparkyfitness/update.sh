# Both packages share this updater; run only once from sparkyfitness-server
if [ -n "${UPDATE_NIX_ATTR_PATH:-}" ] && [ "$UPDATE_NIX_ATTR_PATH" != "sparkyfitness-server" ]; then
  echo "sparkyfitness updates are driven via sparkyfitness-server (shared version stream); nothing to do here." >&2
  exit 0
fi

nix-update --flake "sparkyfitness-server" --override-filename "pkgs/sparkyfitness/common.nix" || exit 1

nix-update --flake "sparkyfitness-frontend" --version skip || exit 1
nix-update --flake "sparkyfitness-server" --version skip || exit 1
