{
  stdenv,
  lib,
  fetchurl,
  autoPatchelfHook,
  nix-update-script,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "adguardhome";
  version = "1.0.0-b.2";

  src = fetchurl {
    url = "https://github.com/AdguardTeam/AdGuardHome/releases/download/v${finalAttrs.version}/AdGuardHome_linux_amd64.tar.gz";
    hash = "sha256-ZUq6kxBv1t9LI9TndW46z58DwTMAYJlwZZvcRYvpwu0=";
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
})
