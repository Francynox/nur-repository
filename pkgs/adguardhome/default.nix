{
  stdenv,
  lib,
  fetchurl,
  autoPatchelfHook,
  nix-update-script,
}:
stdenv.mkDerivation rec {
  pname = "adguardhome";
  version = "1.0.0-b.1";

  src = fetchurl {
    url = "https://github.com/AdguardTeam/AdGuardHome/releases/download/v${version}/AdGuardHome_linux_amd64.tar.gz";
    hash = "sha256-Y4DLNZsTVnu48HQaUPONcC5clMIVnF2dgUSTOYDtOdQ=";
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
