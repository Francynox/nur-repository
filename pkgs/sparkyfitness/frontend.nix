{
  stdenv,
  callPackage,
  common ? callPackage ./common.nix { },
}:
let
  pname = "sparkyfitness-frontend";

  pnpmWorkspaces = [
    "sparkyfitnessfrontend"
    "@workspace/shared"
  ];

  pnpmHash = "sha256-loAIs7JVvXHUVX1HMV9CcIb8Wz3XidPRY05GdeIKV2U=";
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
  ];

  buildPhase = ''
    runHook preBuild
    pnpm --filter sparkyfitnessfrontend exec vite build
    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    pnpm --filter sparkyfitnessfrontend run validate
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    cp -r SparkyFitnessFrontend/dist "$out"
    runHook postInstall
  '';

  passthru.updateScript = common.updateScript;

  meta = common.meta // {
    description = "SparkyFitness web frontend (static build)";
  };
})
