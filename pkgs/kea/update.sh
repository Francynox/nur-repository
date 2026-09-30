version=$(curl -s --fail --connect-timeout 10 --max-time 30 https://www.isc.org/download/ | pup 'div#Kea td.download-version[title*="testing"] .download-version-text text{}' | tr -d '[:space:]')
if [ -z "$version" ]; then
  echo "Failed to fetch latest Kea testing version from isc.org" >&2
  exit 1
fi
echo "Latest Kea testing version: $version" >&2
exec nix-update --flake "$UPDATE_NIX_ATTR_PATH" --version "$version"
