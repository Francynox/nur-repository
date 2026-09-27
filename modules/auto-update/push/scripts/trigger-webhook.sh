#!@runtimeShell@
set -eu -o pipefail
export PATH=@path@

TOKEN=$(tr -d '\n\r ' < "@tokenFile@")

INSECURE_ARGS=()
if [ "@insecure@" = "true" ]; then
  INSECURE_ARGS=("-k")
fi

BODY_FILE=$(mktemp)
trap 'rm -f "$BODY_FILE"' EXIT

echo "Triggering remote configuration deployment on builder via webhook..."

HTTP_STATUS=$(printf 'header = "X-Deploy-Token: %s"\n' \
  "$TOKEN" | curl --config - \
  "${INSECURE_ARGS[@]}" \
  -sS \
  -o "$BODY_FILE" \
  -w "%{http_code}" \
  --connect-timeout 10 \
  --retry 3 \
  --retry-delay 5 \
  --retry-connrefused \
  --json "{\"host\": \"@hostName@\"}" \
  "@url@"
)

if [ "$HTTP_STATUS" -lt 200 ] || [ "$HTTP_STATUS" -ge 300 ]; then
  echo "Error: Webhook returned HTTP status $HTTP_STATUS"
  echo "Response body:"
  cat "$BODY_FILE"
  exit 1
fi

echo "Webhook trigger successful. Status: $HTTP_STATUS"