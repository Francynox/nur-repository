#!@runtimeShell@
set -e -o pipefail
export PATH=@path@

SOPS_KEY_FILE="@sopsKeyPath@"
SECRETS_URL="@remoteSecretsUrl@"
OUTPUT_FILE="/run/nix-private-access.conf"

echo "[fetch-pat] Fetching encrypted secrets from public repo..."

if [ ! -f "$SOPS_KEY_FILE" ]; then
  echo "[fetch-pat] ERROR: Host key not found at $SOPS_KEY_FILE"
  echo "[fetch-pat] Skipping PAT setup — private repo access will not work."
  exit 0
fi

TEMP_FILE=$(mktemp /tmp/secrets.XXXXXX.yaml)
trap 'rm -f "$TEMP_FILE"' EXIT

if ! curl --connect-timeout 10 --max-time 60 --retry 5 --retry-delay 10 --retry-all-errors -sS -f -o "$TEMP_FILE" "$SECRETS_URL"; then
  echo "[fetch-pat] ERROR: Failed to download secrets from $SECRETS_URL after multiple attempts"
  exit 1
fi
AGE_KEY=$(ssh-to-age -private-key -i "$SOPS_KEY_FILE")
PAT=$(SOPS_AGE_KEY="$AGE_KEY" sops -d --extract '["github-pat"]' "$TEMP_FILE")
(
  umask 077
  echo "access-tokens = github.com=$PAT" > "$OUTPUT_FILE"
)

echo "[fetch-pat] PAT configured successfully."
