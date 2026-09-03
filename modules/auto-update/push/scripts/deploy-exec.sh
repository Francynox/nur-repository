#!@runtimeShell@
set -e -o pipefail
export PATH=@path@

INSTANCE="$1"
HOST="${INSTANCE%%@*}"
IP="${INSTANCE##*@}"

TARGET_USER="@targetUser@"
TELEGRAM_NOTIFY="@telegramNotifyBin@"
AUTO_ROLLBACK="@autoRollback@"
WATCHDOG_TIMEOUT="@watchdogTimeout@"

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
FAILURE_REASON=""

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
    if [ -n "$FAILURE_REASON" ]; then
      notify "❌ <b>Deploy failed</b>: $HOST
<b>Reason:</b> $FAILURE_REASON (after $DURATION_STR)"
    else
      notify "❌ <b>Deploy failed</b>: $HOST (after $DURATION_STR)"
    fi
  fi
}
trap handle_exit EXIT

export NIX_SSHOPTS="-i @sshKeyFile@ -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/run/deploy-webhook/known_hosts"

SUDO_PREFIX=""
SUDO_FLAG=""
if [ "$TARGET_USER" != "root" ]; then
  SUDO_PREFIX="sudo "
  SUDO_FLAG="--sudo"
fi

remote_exec() {
  ssh $NIX_SSHOPTS "$TARGET_USER@$IP" "${SUDO_PREFIX}$*"
}

# Arm target watchdog if auto-rollback is enabled
if [ "$AUTO_ROLLBACK" = "true" ]; then
  echo "Arming rollback watchdog on $HOST..."
  remote_exec push-deploy-guard arm "$WATCHDOG_TIMEOUT" || echo "Warning: push-deploy-guard arm failed or not available on target; continuing."
fi

# Build and deploy
echo "Building and deploying configuration to attribute #$HOST at IP $IP as user $TARGET_USER..."
if ! nixos-rebuild switch \
  --target-host "$TARGET_USER@$IP" \
  $SUDO_FLAG \
  --flake "@flakePath@#$HOST"; then
  echo "Error: nixos-rebuild switch failed on $HOST!"
  if [ "$AUTO_ROLLBACK" = "true" ]; then
    remote_exec push-deploy-guard rollback-if-changed || true
  fi
  FAILURE_REASON="nixos-rebuild switch failed"
  exit 1
fi

# Confirm health on target (runs health check, disarms watchdog, handles reboot)
echo "Confirming deployment health on target $HOST..."
if ! CONFIRM_OUTPUT=$(remote_exec push-deploy-guard confirm); then
  echo "Error: Target confirmation failed on $HOST!"
  echo "$CONFIRM_OUTPUT"
  FAILURE_REASON="Health check failed on target: ${CONFIRM_OUTPUT:-target unreachable; watchdog armed for auto-rollback}"
  exit 1
fi

echo "Deployment and target verification completed successfully for $HOST."

