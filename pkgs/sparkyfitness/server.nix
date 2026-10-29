{
  lib,
  stdenv,
  callPackage,
  common ? callPackage ./common.nix { },
  makeWrapper,
  postgresql,
  gnutar,
  gzip,
}:
let
  pname = "sparkyfitness-server";

  pnpmWorkspaces = [
    "sparkyfitnessserver"
    "@workspace/shared"
  ];

  pnpmHash = "sha256-qGik2SOG9zkSRR/WZ0Vz5KVVvJOIGK7J/szzWF96lkU=";
in
stdenv.mkDerivation (finalAttrs: {
  inherit pname;
  inherit (common) version src;
  inherit pnpmWorkspaces;

  pnpmDeps = common.fetchPnpmDeps' {
    inherit (finalAttrs)
      pname
      version
      src
      pnpmWorkspaces
      ;
    fetcherVersion = 3;
    hash = pnpmHash;
  };

  nativeBuildInputs = [
    common.nodejs
    common.pnpm
    common.pnpmConfigHook'
    makeWrapper
  ];

  dontBuild = true;

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    pnpm --filter sparkyfitnessserver run validate
    pnpm --filter sparkyfitnessserver test
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    appDir="$out/libexec/sparkyfitness"
    mkdir -p "$appDir"
    cp -r . "$appDir/"

    makeWrapper "${common.nodejs}/bin/node" "$out/bin/sparkyfitness-server" \
      --chdir "$appDir/SparkyFitnessServer" \
      --add-flags "--import tsx index.ts" \
      --prefix PATH : ${
        lib.makeBinPath [
          common.nodejs
          postgresql # pg_dump / psql used by the backup service
          gnutar
          gzip
        ]
      }

    runHook postInstall
  '';

  passthru.updateScript = common.updateScript;

  meta = common.meta // {
    description = "SparkyFitness backend API server (Express + PostgreSQL)";
    mainProgram = "sparkyfitness-server";
  };
})
