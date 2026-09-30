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
    version = "3.3.2";

    src = fetchurl {
      url = "https://downloads.isc.org/isc/${pname}/${version}/${pname}-${version}.tar.xz";
      hash = "sha256-LHjkzVRLvkj/zfvSBnq77w9HCKFRd2sEC9FmEwBnmzM=";
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
