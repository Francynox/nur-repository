#!@runtimeShell@
set -e -o pipefail
export PATH=@path@

TOKEN=$(cat "@tokenFile@" | tr -d '\n\r ')

INSECURE_FLAG=""
if [ "@insecure@" = "true" ]; then
  INSECURE_FLAG="-k"
fi

echo "Triggering remote configuration deployment on builder via webhook..."
RESPONSE=$(curl $INSECURE_FLAG -sS -w "\n%{http_code}" -X POST \
  --connect-timeout 10 \
  --retry 3 \
  --retry-delay 5 \
  --retry-connrefused \
  -H "Content-Type: application/json" \
  -H "X-Deploy-Token: $TOKEN" \
  -d "{\"host\": \"@hostName@\"}" \
  "@url@" 2>&1) || {
    echo "Error: Failed to connect to webhook server:"
    echo "$RESPONSE"
    exit 1
}

HTTP_STATUS=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_STATUS" -lt 200 ] || [ "$HTTP_STATUS" -ge 300 ]; then
  echo "Error: Webhook returned HTTP status $HTTP_STATUS"
  echo "Response body: $BODY"
  exit 1
fi

echo "Webhook trigger successful. Status: $HTTP_STATUS"

