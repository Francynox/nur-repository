#!@runtimeShell@
set -e -o pipefail
export PATH=@path@

ACTION="$1"
WATCHDOG_TIMEOUT="${2:-180s}"
AUTO_ROLLBACK="@autoRollback@"
AUTO_REBOOT="@autoReboot@"

STATE_DIR="/run/push-deploy"

disarm() {
  systemctl stop nixos-deploy-watchdog.timer 2>/dev/null || true
  systemctl reset-failed nixos-deploy-watchdog.timer 2>/dev/null || true
  rm -rf "$STATE_DIR"
  echo "Rollback watchdog disarmed."
}

rollback() {
  systemctl stop nixos-deploy-watchdog.timer 2>/dev/null || true
  systemctl reset-failed nixos-deploy-watchdog.timer 2>/dev/null || true

  if [ "$AUTO_ROLLBACK" = "true" ]; then
    echo "Rolling back target host to previous generation..."
    if nixos-rebuild switch --rollback; then
      echo "(rolled back to previous generation)"
      rm -rf "$STATE_DIR"
      echo "Rollback watchdog disarmed."
    else
      echo "(rollback FAILED)"
      exit 1
    fi
  else
    echo "(auto-rollback disabled)"
    rm -rf "$STATE_DIR"
  fi
}

rollback_if_changed() {
  local current_system
  current_system=$(readlink -f /nix/var/nix/profiles/system || true)
  local pre_system=""
  if [ -f "$STATE_DIR/pre-deploy-system" ]; then
    pre_system=$(cat "$STATE_DIR/pre-deploy-system")
  fi

  if [ -n "$pre_system" ] && [ -n "$current_system" ] && [ "$current_system" = "$pre_system" ]; then
    echo "System generation unchanged; disarming watchdog without rollback."
    disarm
  else
    echo "System generation changed or activation failed; rolling back..."
    rollback
  fi
}

arm() {
  if [ "$AUTO_ROLLBACK" != "true" ]; then
    echo "Auto-rollback is disabled. Skipping watchdog arming."
    return 0
  fi

  mkdir -p "$STATE_DIR"
  readlink -f /nix/var/nix/profiles/system > "$STATE_DIR/pre-deploy-system" || true
  systemctl --failed --no-legend --plain | awk '{print $1}' | sort > "$STATE_DIR/pre-failed-units" || true

  systemctl stop nixos-deploy-watchdog.timer 2>/dev/null || true
  systemctl reset-failed nixos-deploy-watchdog.timer 2>/dev/null || true

  systemd-run --unit=nixos-deploy-watchdog \
    --on-active="$WATCHDOG_TIMEOUT" \
    --description="Push deploy auto-rollback watchdog" \
    /run/current-system/sw/bin/push-deploy-guard rollback

  echo "Rollback watchdog armed (timeout: $WATCHDOG_TIMEOUT)."
}

confirm() {
  echo "Running post-deploy health checks..."
  local post_failed
  post_failed=$(systemctl --failed --no-legend --plain | awk '{print $1}' | sort || true)

  local new_failed=""
  if [ -f "$STATE_DIR/pre-failed-units" ]; then
    new_failed=$(comm -13 "$STATE_DIR/pre-failed-units" <(echo "$post_failed") | tr '\n' ' ' | sed 's/[[:space:]]*$//')
  else
    new_failed=$(echo "$post_failed" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
  fi

  if [ -n "$new_failed" ]; then
    echo "Health check failed! Newly failed units: $new_failed"
    rollback
    exit 1
  fi

  echo "Health checks passed."
  disarm

  echo "Checking reboot requirements..."
  if ! detect_reboot; then
    if [ "$AUTO_REBOOT" = "true" ]; then
      echo "Scheduling reboot in 2s..."
      systemctl stop push-deploy-reboot.timer push-deploy-reboot.service 2>/dev/null || true
      systemctl reset-failed push-deploy-reboot.timer push-deploy-reboot.service 2>/dev/null || true
      systemd-run --unit=push-deploy-reboot \
        --on-active=2s \
        --description="Push deploy auto-reboot" \
        systemctl reboot || true
    else
      echo "Auto-reboot is disabled; not scheduling reboot."
    fi
  fi
}

detect_reboot() {
  local booted_kernel current_kernel booted_initrd current_initrd booted_systemd current_systemd
  local reboot_needed=false

  booted_kernel=$(readlink -f /run/booted-system/kernel || true)
  current_kernel=$(readlink -f /run/current-system/kernel || true)
  booted_initrd=$(readlink -f /run/booted-system/initrd || true)
  current_initrd=$(readlink -f /run/current-system/initrd || true)
  booted_systemd=$(readlink -f /run/booted-system/systemd || true)
  current_systemd=$(readlink -f /run/current-system/systemd || true)

  if [ "$booted_kernel" != "$current_kernel" ]; then
    echo "STATUS: Kernel changed (booted: $booted_kernel, current: $current_kernel)."
    reboot_needed=true
  fi
  if [ "$booted_initrd" != "$current_initrd" ] && [ -n "$booted_initrd" ]; then
    echo "STATUS: Initrd changed (booted: $booted_initrd, current: $current_initrd)."
    reboot_needed=true
  fi
  if [ "$booted_systemd" != "$current_systemd" ] && [ -n "$booted_systemd" ]; then
    echo "STATUS: Systemd changed (booted: $booted_systemd, current: $current_systemd)."
    reboot_needed=true
  fi

  if [ "$reboot_needed" = "true" ]; then
    echo "STATUS: Reboot needed."
    return 1
  fi

  echo "STATUS: No reboot needed."
  return 0
}

case "$ACTION" in
  arm)
    arm
    ;;
  disarm)
    disarm
    ;;
  confirm)
    confirm
    ;;
  rollback)
    rollback
    ;;
  rollback-if-changed)
    rollback_if_changed
    ;;
  check-reboot)
    detect_reboot
    ;;
  *)
    echo "Usage: push-deploy-guard {arm|disarm|confirm|rollback|rollback-if-changed|check-reboot}" >&2
    exit 1
    ;;
esac

