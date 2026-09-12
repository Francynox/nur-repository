{
  lib,
  fetchFromGitHub,
  fetchurl,
  qemu_kvm,
  # build time
  perl,
  python3Packages,
  # runtime
  libuuid,
  ...
}:
let
  proxmoxPatchSrc = fetchFromGitHub rec {
    pname = "pve-qemu-src";
    version = "fa71af3c796c51f68679fa835eeeff2e7094e5e5";

    owner = "proxmox";
    repo = "pve-qemu";
    rev = version;
    hash = "sha256-PxXMYCnJVwQynifn6Y0+zDNXbDEanB5Y5GVH2XZJ2bY=";
  };

  # Disable unneeded features to reduce build time
  minimalQemu = qemu_kvm.override {
    alsaSupport = false;
    pulseSupport = false;
    sdlSupport = false;
    jackSupport = false;
    gtkSupport = false;
    vncSupport = false;
    smartcardSupport = false;
    spiceSupport = false;
    ncursesSupport = false;
    libiscsiSupport = false;
    tpmSupport = false;
    numaSupport = false;
    seccompSupport = false;
    guestAgentSupport = false;
  };
in
minimalQemu.overrideAttrs (super: rec {
  pname = "proxmox-vma";
  version = "11.1.1";

  src = fetchurl {
    url = "https://download.qemu.org/qemu-${version}.tar.xz";
    hash = "sha256-B5/7/4pxEbvIkCIQfLq/O7/WFNX8nXzGdZkRlqyhJII=";
  };

  outputs = [ "out" ];
  separateDebugInfo = false;

  patches = [
    "${proxmoxPatchSrc}/debian/patches/pve/0026-PVE-Backup-add-vma-backup-format-code.patch"
  ];

  nativeBuildInputs = super.nativeBuildInputs ++ [
    perl
    python3Packages.qemu-qmp
    python3Packages.setuptools
    python3Packages.wheel
  ];
  buildInputs = super.buildInputs ++ [ libuuid ];

  postInstall = ''
    # Delete standard QEMU binaries to reduce closure size
    find $out/bin -type f -not -name 'vma' -delete

    # Cleanup artifacts
    rm -rf $out/share $out/libexec $out/include

    if [ ! -e "$out/bin/vma" ]; then
        echo "Error: vma binary was not built!"
        exit 1
    fi
  '';

  passthru = {
    updateScript = ./update.sh;
    inherit proxmoxPatchSrc;
  };

  meta = {
    description = "Proxmox VMA (Virtual Machine Archive) tool patched into QEMU";
    homepage = "https://git.proxmox.com/?p=pve-qemu.git";
    license = lib.licenses.gpl2Plus;
    platforms = [ "x86_64-linux" ];
  };
})
