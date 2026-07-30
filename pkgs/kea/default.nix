{
  stdenv,
  lib,
  fetchurl,
  # build time
  pkg-config,
  meson,
  ninja,
  python3,
  # runtime
  boost,
  log4cplus,
  openssl,
}:
stdenv.mkDerivation rec {
  pname = "kea";
  version = "3.3.0";

  src = fetchurl {
    url = "https://downloads.isc.org/isc/${pname}/${version}/${pname}-${version}.tar.xz";
    hash = "sha256-26m3Rorm4LiwGMoSlvPBeOFMgxoig9w82ERq8y6eIJc=";
  };

  patches = [
    ./dont-create-system-paths.patch
  ];

  postPatch = ''
    patchShebangs scripts/grabber.py

    substituteInPlace ./src/hooks/dhcp/radius/meson.build --replace-fail 'install_dir: SYSCONFDIR' "install_dir: '$out/etc'"
    substituteInPlace ./src/bin/keactrl/meson.build --replace-fail "kea_configfiles_destdir = SYSCONFDIR" "kea_configfiles_destdir = '$out/etc'"
  '';

  mesonFlags = [
    (lib.mesonOption "crypto" "openssl")
    (lib.mesonEnable "krb5" false)
    (lib.mesonEnable "mysql" false)
    (lib.mesonEnable "netconf" false)
    (lib.mesonEnable "postgresql" false)
    (lib.mesonOption "localstatedir" "/var")
    (lib.mesonOption "runstatedir" "/run")
    (lib.mesonOption "sysconfdir" "/etc/kea")
  ];

  postConfigure = ''
    # Mangle embedded paths to dev-only inputs.
    for file in config.report meson-info/intro*.json; do
      sed -e "s|$NIX_STORE/[a-z0-9]\{32\}-|$NIX_STORE/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee-|g" -i "$file"
    done
  '';

  nativeBuildInputs = [
    pkg-config
    meson
    ninja
    python3
  ];

  buildInputs = [
    boost
    log4cplus
    openssl
  ];

  passthru.updateScript = ./update.sh;

  meta = {
    homepage = "https://kea.isc.org/";
    description = "ISC KEA - DHCP server";
    license = lib.licenses.mpl20;
    platforms = [ "x86_64-linux" ];
  };
}
