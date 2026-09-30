qemu_version=$(git ls-remote --tags --refs --sort='-v:refname' https://github.com/proxmox/mirror_qemu.git 'v*.*.*' | grep -v -- '-' | head -n1 | awk -F'refs/tags/v' '{print $2}')
if [ -z "$qemu_version" ]; then
  echo "Failed to fetch latest QEMU version" >&2
  exit 1
fi
echo "Latest QEMU version: $qemu_version" >&2

patch_rev=$(git ls-remote https://github.com/proxmox/pve-qemu.git HEAD | cut -f1)
if [ -z "$patch_rev" ]; then
  echo "Failed to fetch latest pve-qemu rev" >&2
  exit 1
fi
echo "Latest pve-qemu rev: $patch_rev" >&2

pkg_attr="$UPDATE_NIX_ATTR_PATH"
nix-update --flake "$pkg_attr" --version "$qemu_version"
nix-update --flake "$pkg_attr.proxmoxPatchSrc" --version "$patch_rev"
