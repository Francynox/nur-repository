{
  lib,
  fetchFromGitHub,
  nodejs_24,
  pnpm_10,
  pnpm_10_latest ? pnpm_10,
  fetchPnpmDeps,
  pnpmConfigHook,
  writeShellApplication,
  nix-update,
  nix,
}:
let
  version = "1.8.0";

  src = fetchFromGitHub {
    owner = "CodeWithCJ";
    repo = "SparkyFitness";
    rev = "v${version}";
    hash = "sha256-MoSfL7W2IgxFpbDZ3xKSldGMSHtM6wzMrQzhlpvJ71s=";
  };

  nodejs = nodejs_24;
  # pnpm 10 required: upstream uses package.json 'pnpm' overrides ignored by pnpm 11.
  # Prefer pnpm_10_latest when available (nixos-26.05 keeps pnpm_10 at insecure 10.34.0).
  pnpm = pnpm_10_latest;

  fetchPnpmDeps' = fetchPnpmDeps.override { inherit pnpm; };
  pnpmConfigHook' = pnpmConfigHook.override { inherit pnpm; };

  updateScript = lib.getExe (writeShellApplication {
    name = "update-sparkyfitness";
    runtimeInputs = [
      nix-update
      nix
    ];
    text = builtins.readFile ./update.sh;
  });
in
{
  inherit
    version
    src
    nodejs
    pnpm
    fetchPnpmDeps'
    pnpmConfigHook'
    updateScript
    ;

  meta = {
    homepage = "https://github.com/CodeWithCJ/SparkyFitness";
    # Upstream LICENSE restricts use to non-commercial purposes only.
    license = lib.licenses.unfree;
    platforms = lib.platforms.linux;
  };
}
