{
  lib,
  fetchurl,
  unbound,
  systemdLibs,
}:
(unbound.override {
  withSystemd = true;
  systemd = systemdLibs;
  withSlimLib = false;
  withTFO = true;
  withDoH = true;
}).overrideAttrs
  (prevAttrs: rec {
    pname = "unbound";
    version = "1.26.1";

    src = fetchurl {
      url = "https://nlnetlabs.nl/downloads/unbound/unbound-${version}.tar.gz";
      hash = "sha256-NabcDkJakoLDQm2aMEMUQBG/BTSu1Lc6tixSruCvFQM=";
    };

    configureFlags =
      (builtins.filter (flag: !lib.hasPrefix "--with-rootkey-file=" flag) prevAttrs.configureFlags)
      ++ [ "--with-rootkey-file=/var/lib/unbound/root.key" ];

    passthru = (prevAttrs.passthru or { }) // {
      updateScript = ./update.sh;
    };
  })
