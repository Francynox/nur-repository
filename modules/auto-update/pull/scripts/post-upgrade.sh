#!@runtimeShell@
set -e -o pipefail
export PATH=@path@

HOST_NAME="@hostName@"
TELEGRAM_NOTIFY="@telegramNotifyBin@"
AUTO_ROLLBACK="@autoRollback@"

notify() {
  local msg="$1"
  if [ -n "$TELEGRAM_NOTIFY" ] && [ -x "$TELEGRAM_NOTIFY" ]; then
    "$TELEGRAM_NOTIFY" "$msg" || true
  fi
}

ROLLBACK_STATUS=""

rollback_self() {
  if [ "$AUTO_ROLLBACK" != "true" ]; then
    echo "Auto-rollback is disabled. Leaving system in current state."
    ROLLBACK_STATUS="(auto-rollback disabled)"
    return
  fi

  echo "Rolling back to previous generation..."
  if nixos-rebuild switch --rollback; then
    ROLLBACK_STATUS="(rolled back to previous generation)"
  else
    echo "Warning: Rollback command failed!"
    ROLLBACK_STATUS="(rollback FAILED)"
  fi
}

PRE_SYSTEM=""
if [ -f /run/nixos-upgrade/pre-upgrade-system ]; then
  PRE_SYSTEM=$(cat /run/nixos-upgrade/pre-upgrade-system)
fi

PRE_FAILED_FILE="/run/nixos-upgrade/pre-failed-units"

if [ "$SERVICE_RESULT" != "success" ]; then
  echo "nixos-upgrade failed!"
  CURRENT_SYSTEM=$(readlink -f /nix/var/nix/profiles/system || true)

  if [ -n "$PRE_SYSTEM" ] && [ -n "$CURRENT_SYSTEM" ] && [ "$CURRENT_SYSTEM" = "$PRE_SYSTEM" ]; then
    echo "Upgrade failed before new generation was activated. Leaving system unchanged."
    notify "❌ <b>Pull upgrade failed</b>: $HOST_NAME (build/fetch failed, no changes applied)"
  else
    rollback_self
    notify "❌ <b>Pull upgrade failed</b>: $HOST_NAME $ROLLBACK_STATUS"
  fi
  rm -rf /run/nixos-upgrade
  exit 1
fi

# Post-activation health check
echo "Running post-upgrade health check..."
POST_FAILED=$(systemctl --failed --no-legend --plain | awk '{print $1}' | sort || true)

NEW_FAILED=""
if [ -f "$PRE_FAILED_FILE" ]; then
  NEW_FAILED=$(comm -13 "$PRE_FAILED_FILE" <(echo "$POST_FAILED") | tr '\n' ' ' | sed 's/[[:space:]]*$//')
else
  NEW_FAILED=$(echo "$POST_FAILED" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
fi

rm -rf /run/nixos-upgrade

if [ -n "$NEW_FAILED" ]; then
  echo "Health check failed! Found failed systemd units: $NEW_FAILED"
  rollback_self
  notify "❌ <b>Pull upgrade failed</b>: $HOST_NAME
<b>Reason:</b> Failed systemd units detected: $NEW_FAILED $ROLLBACK_STATUS"
  exit 1
fi

notify "✅ <b>Pull upgrade successful</b>: $HOST_NAME"
