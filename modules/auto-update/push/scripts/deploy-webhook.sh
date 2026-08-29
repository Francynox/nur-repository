#!@runtimeShell@
set -e -o pipefail
export PATH=@path@

HOST="$1"
REMOTE_ADDR="$2"
TOKEN="$3"

VALID_TOKEN=$(cat "@tokenFile@" | tr -d '\n\r ')
if [ "$TOKEN" != "$VALID_TOKEN" ]; then
  echo "Error: Unauthorized token."
  exit 1
fi

if [ -z "$REMOTE_ADDR" ]; then
  echo "Error: Remote client IP missing from request."
  exit 1
fi

# Strip :port and [ ] brackets for IPv4 and IPv6
CLEAN_IP="${REMOTE_ADDR%:*}"
CLEAN_IP="${CLEAN_IP#[}"
CLEAN_IP="${CLEAN_IP%]}"

echo "Triggering deploy for host $HOST (detected IP: $CLEAN_IP)..."

# Start deployment service using host@ip template instance
/run/wrappers/bin/sudo systemctl start --no-block "deploy-host@$HOST@$CLEAN_IP"

