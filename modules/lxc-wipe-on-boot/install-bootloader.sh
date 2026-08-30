#!@runtimeShell@
set -e -o pipefail
export PATH=@path@

defaultConfig="$1"
echo "Updating /sbin/init wrapper to point to $defaultConfig"

# Function to generate wrapper content
generate_wrapper() {
  local path="$1"
  cat <<EOF
#!@runtimeShell@
@initWipe@
exec $path/init "\$@"
EOF
}

# Update the main init wrapper
mkdir -p /sbin
generate_wrapper "$defaultConfig" > /sbin/init.new
chmod +x /sbin/init.new
mv /sbin/init.new /sbin/init

# Create a record of all generations in /boot
mkdir -p /boot
targetOther="/boot/generations-commands.txt"
echo "# Run these commands to manually switch to a specific generation" > "$targetOther"
echo "" >> "$targetOther"

for generation in $(
    (cd /nix/var/nix/profiles && ls -d system-*-link 2>/dev/null) \
    | sed 's/system-\([0-9]\+\)-link/\1/' \
    | sort -n -r); do
    link=/nix/var/nix/profiles/system-$generation-link
    date=$(stat --printf="%y" $link 2>/dev/null || echo "unknown date")
    
    echo "Generation $generation ($date):" >> "$targetOther"
    echo "  # Wrapper script content:" >> "$targetOther"
    generate_wrapper "$link" | sed 's/^/  /' >> "$targetOther"
    echo "" >> "$targetOther"
    echo "  # To run directly:" >> "$targetOther"
    echo "  @initWipe@; exec $link/init" >> "$targetOther"
    echo "------------------------------------------------" >> "$targetOther"
done
