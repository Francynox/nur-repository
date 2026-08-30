#!@runtimeShell@
set -e -o pipefail
export PATH=@path@

# Enable logging to /nix/persist/init-wipe.log (overwritten on each boot)
mkdir -p /nix/persist
echo > /nix/persist/init-wipe.log
exec > >(tee -a /nix/persist/init-wipe.log > /dev/console) 2>&1

echo "------------------------------------------------"
echo "LXC Init Script Started at $(date || echo ' ')"
echo "------------------------------------------------"

echo "Wiping root for impermanence..."

# Find and delete everything in / excluding specific paths
# Preserving /nix (store), /dev, /proc, /sys, /run (runtime), and kernel mounts
find / -xdev -mindepth 1 -maxdepth 1 \
  ! -name 'nix' \
  ! -name 'dev' \
  ! -name 'proc' \
  ! -name 'sys' \
  ! -name 'run' \
  ! -name 'sbin' \
  ! -name 'boot' \
  ! -name 'nix-path-registration' \
  -exec rm -rf --one-file-system {} + || true

# Recreate necessary directories
mkdir -p /etc/systemd/network

# Restore hostname for systemd
echo "@hostName@" > /etc/hostname

echo "System wiped. Returning to wrapper..."

# Ensure all writes are flushed before handover
sync

