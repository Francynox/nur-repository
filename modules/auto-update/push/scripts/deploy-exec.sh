#!@runtimeShell@
set -e -o pipefail
export PATH=@path@

INSTANCE="$1"
HOST="${INSTANCE%%@*}"
IP="${INSTANCE##*@}"

TARGET_USER="@targetUser@"
TELEGRAM_NOTIFY="@telegramNotifyBin@"

# Per-host lock to prevent concurrent deploys
LOCK_FILE="/run/deploy-webhook/deploy-${HOST}.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  echo "Error: Deploy already in progress for host $HOST. Skipping."
  exit 1
fi

notify() {
  local msg="$1"
  if [ -n "$TELEGRAM_NOTIFY" ] && [ -x "$TELEGRAM_NOTIFY" ]; then
    "$TELEGRAM_NOTIFY" "$msg" || true
  fi
}

START_TIME=$(date +%s)

handle_exit() {
  exit_code=$?
  DURATION=$(( $(date +%s) - START_TIME ))
  DURATION_STR="${DURATION}s"
  if [ "$DURATION" -ge 60 ]; then
    DURATION_STR="$(( DURATION / 60 ))m $(( DURATION % 60 ))s"
  fi

  if [ $exit_code -eq 0 ]; then
    notify "✅ <b>Deploy successful</b>: $HOST (took $DURATION_STR)"
  else
    notify "❌ <b>Deploy failed</b>: $HOST (after $DURATION_STR)"
  fi
}
trap handle_exit EXIT

export NIX_SSHOPTS="-i @sshKeyFile@ -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/run/deploy-webhook/known_hosts"

SUDO_FLAG=""
if [ "$TARGET_USER" != "root" ]; then
  SUDO_FLAG="--sudo"
fi

echo "Building and deploying configuration to attribute #$HOST at IP $IP as user $TARGET_USER..."
nixos-rebuild switch \
  --target-host "$TARGET_USER@$IP" \
  $SUDO_FLAG \
  --flake "@flakePath@#$HOST"

echo "Triggering reboot check on target host $HOST at IP $IP..."
if [ "$TARGET_USER" = "root" ]; then
  ssh $NIX_SSHOPTS "$TARGET_USER@$IP" "systemctl start --no-block push-reboot-detector"
else
  ssh $NIX_SSHOPTS "$TARGET_USER@$IP" "sudo systemctl start --no-block push-reboot-detector"
fi
