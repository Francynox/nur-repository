{
  stdenv,
  lib,
  fetchurl,
  autoPatchelfHook,
  nix-update-script,
}:
stdenv.mkDerivation rec {
  pname = "adguardhome";
  version = "0.108.0-b.91";

  src = fetchurl {
    url = "https://github.com/AdguardTeam/AdGuardHome/releases/download/v${version}/AdGuardHome_linux_amd64.tar.gz";
    hash = "sha256-Sgo4u96p6Bnwgro4pzsrOUW/fYdTMU35EEK2y8fGTFc=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -m755 -D ./AdGuardHome $out/bin/adguardhome

    runHook postInstall
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--version=unstable"
      "--use-github-releases"
    ];
  };

  meta = {
    homepage = "https://github.com/AdguardTeam/AdGuardHome";
    description = "Network-wide ads & trackers blocking DNS server";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "adguardhome";
  };
}
