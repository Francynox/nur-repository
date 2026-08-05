{
  stdenv,
  lib,
  fetchurl,
  # build time
  pkg-config,
  flex,
  bison,
  makeWrapper,
  symlinkJoin,
  # runtime
  openssl,
  expat,
  nghttp2,
  systemdLibs,
  libsodium,
  libevent,
}:
stdenv.mkDerivation rec {
  pname = "unbound";
  version = "1.26.0";

  src = fetchurl {
    url = "https://nlnetlabs.nl/downloads/unbound/unbound-${version}.tar.gz";
    hash = "sha256-d0WKcVbidcC3sX+ryzV8sSRF2Vz8sm+5u31ey6ReC2M=";
  };

  configureFlags = [
    "--localstatedir=/var"
    "--sysconfdir=/etc"
    "--sbindir=\${out}/bin"
    "--enable-pie"
    "--enable-relro-now"
    "--enable-systemd"
    "--enable-dnscrypt"
    "--enable-tfo-client"
    "--enable-tfo-server"
    "--with-ssl=${openssl.dev}"
    "--with-libexpat=${expat.dev}"
    "--with-libevent=${libevent.dev}"
    "--with-libnghttp2=${nghttp2.dev}"
    "--with-libsodium=${
      symlinkJoin {
        name = "libsodium-full";
        paths = [
          libsodium.dev
          libsodium
        ];
      }
    }"
    "--with-rootkey-file=/var/lib/unbound/root.key"
  ];

  nativeBuildInputs = [
    pkg-config
    flex
    bison
    makeWrapper
  ];

  buildInputs = [
    openssl
    expat
    nghttp2
    systemdLibs
    libsodium
    libevent
  ];

  postConfigure = ''
    sed -E '/CONFCMDLINE/ s;${builtins.storeDir}/[a-z0-9]{32}-;${builtins.storeDir}/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee-;g' -i config.h
  '';

  installFlags = [ "configfile=\${out}/etc/unbound/unbound.conf" ];

  postInstall = ''
    make unbound-event-install

    wrapProgram $out/bin/unbound-control-setup \
      --prefix PATH : ${lib.makeBinPath [ openssl ]}
  '';

  enableParallelBuilding = true;

  passthru.updateScript = ./update.sh;

  meta = {
    homepage = "https://nlnetlabs.nl/projects/unbound/about/";
    description = "UNBOUND - validating, recursive, caching DNS resolver";
    license = lib.licenses.bsd3;
    platforms = [ "x86_64-linux" ];
    mainProgram = "unbound";
  };
}
