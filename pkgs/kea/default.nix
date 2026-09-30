{
  fetchurl,
  kea,
  lib,
  writeShellApplication,
  curl,
  pup,
  nix-update,
}:
(kea.override {
  withKrb5 = false;
  withMysql = false;
  withPostgresql = false;
}).overrideAttrs
  (prevAttrs: rec {
    pname = "kea";
    version = "3.3.1";

    src = fetchurl {
      url = "https://downloads.isc.org/isc/${pname}/${version}/${pname}-${version}.tar.xz";
      hash = "sha256-C1nVPdieF1se2zXBAEjt7IZWl1EcpzwqQ0fQE3KnmB8=";
    };

    patches = [
      ./dont-create-system-paths.patch
    ];

    passthru = (prevAttrs.passthru or { }) // {
      updateScript = lib.getExe (writeShellApplication {
        name = "update-kea";
        runtimeInputs = [
          curl
          pup
          nix-update
        ];
        text = builtins.readFile ./update.sh;
      });
    };
  })
