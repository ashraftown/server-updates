
#!/usr/bin/env bash
# Ensure this script is running under bash (some sudo executions use /bin/sh)
# Use POSIX [ ] test so /bin/sh can parse this section and re-exec to bash.
if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  else
    echo "This script requires bash. Please install bash or run under bash." >&2
    exit 1
  fi
fi
# Note: we intentionally do NOT set -e so the script can continue and
# report a summary even if individual steps fail.
set -uo pipefail

# Server update script — improved output formatting and verbose logging
# Modes: update-only | security | full

LOCK=/var/lock/server-updates.lock
MODE=full
DRY_RUN=0
LOG=/var/log/server-updates.log
VERBOSE_LOG=/var/log/server-updates_verbose.log
FAIL_ON_ERROR=0
CONFIG_FILE=/etc/server-updates.conf
SLACK_WEBHOOK_URL=""
SLACK_USERNAME="server-updates"
SLACK_ICON=":package:"
NO_NOTIFY=0
SLACK_CHANNEL=""

usage() {
  cat <<EOF
Usage: $0 [--mode update-only|full|security] [--dry-run] [--log /path/to/log] [--verbose-log /path]

EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE=${2:-}
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --log)
      LOG=$2
      shift 2
      ;;
    --verbose-log)
      VERBOSE_LOG=$2
      shift 2
      ;;
    --fail-on-error)
      FAIL_ON_ERROR=1
      shift
      ;;
    --config)
      CONFIG_FILE=$2
      shift 2
      ;;
    --no-notify)
      NO_NOTIFY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

# Load config file if present (simple KEY=VALUE pairs)
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

# Ensure log directories exist (create after config in case LOG was set there)
mkdir -p "$(dirname "$LOG")" || true
mkdir -p "$(dirname "$VERBOSE_LOG")" || true

# Choose whether to use sudo for commands
if [[ $EUID -eq 0 ]]; then
  SUDO=""
else
  SUDO="sudo"
fi

send_slack() {
  # usage: send_slack <type> <short_text> <details-json-or-text>
  # types: start | failure | complete
  local msgtype="$1"
  local short="$2"
  local details="$3"

  # don't attempt network calls during dry-run; write payload to verbose log
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '\n[slack-dry-run] type=%s text=%s details=%s\n' "$msgtype" "$short" "$details" >> "$VERBOSE_LOG"
    return 0
  fi

  if [[ -z "${SLACK_WEBHOOK_URL:-}" || $NO_NOTIFY -eq 1 ]]; then
    # nothing to do
    return 0
  fi

  # build attachment color based on type
  local color
  case "$msgtype" in
    start) color="#439FE0" ;; # blue
    failure) color="#ff0000" ;; # red
    complete)
      if [[ $failed_steps -eq 0 ]]; then
        color="#36a64f" # green
      else
        color="#ffae42" # orange
      fi
      ;;
    *) color="#439FE0" ;;
  esac

  # escape JSON for safe payload construction
  esc() { printf '%s' "$1" | sed 's/"/\\"/g' | sed ':a;N;s/\n/\\n/g;ta'; }

  local host esc_host esc_short esc_details esc_mode esc_log
  host=$(hostname)
  esc_host=$(esc "$host")
  esc_short=$(esc "$short")
  esc_details=$(esc "$details")
  esc_mode=$(esc "$MODE")
  esc_log=$(esc "$VERBOSE_LOG")

  # Build attachment with fields safely using a heredoc (values are already escaped)
  local attachments
  attachments=$(cat <<JSON
[{"color":"$color","author_name":"$SLACK_USERNAME","title":"$esc_short","fields":[{"title":"host","value":"$esc_host","short":true},{"title":"mode","value":"$esc_mode","short":true},{"title":"details","value":"$esc_details","short":false},{"title":"verbose_log","value":"$esc_log","short":false}],"ts":$(date +%s)}]
JSON
)

  # channel override if configured
  local channelpart=""
  if [[ -n "${SLACK_CHANNEL:-}" ]]; then
    channelpart=",\"channel\": \"$(esc "$SLACK_CHANNEL")\""
  fi

  local payload
  payload="{\"username\": \"$(esc "$SLACK_USERNAME")\", \"icon_emoji\": \"$(esc "$SLACK_ICON")\"$channelpart, \"attachments\": $attachments}"

  # post and ignore errors but log them
  curl -s -X POST -H 'Content-type: application/json' --data "$payload" "$SLACK_WEBHOOK_URL" >> "$VERBOSE_LOG" 2>&1 || \
    printf '\n[slack-fail] failed to send notification\n' >> "$VERBOSE_LOG"
}

# Create lock and prevent concurrent runs
mkdir -p "$(dirname "$LOCK")" || true
exec 9>"$LOCK" || exit 1
if ! flock -n 9; then
  echo "Another instance appears to be running (lock: $LOCK). Exiting." >&2
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive

# Counters for the summary
total_steps=0
success_steps=0
failed_steps=0

timestamp() { date -u '+%a %b %d %T %Z %Y'; }

sep() { printf '%s\n' "==========================================="; }

log_verbose() {
  # Prepend timestamp header for each command section
  printf '\n===== %s =====\n' "$(date -u --rfc-3339=seconds) $1" >> "$VERBOSE_LOG"
  # Append command output
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '+ %s\n' "$2" >> "$VERBOSE_LOG"
  else
    # Run the command, capture exit status
    bash -c "$2" >> "$VERBOSE_LOG" 2>&1 || true
  fi
}

run_step() {
  local label="$1"
  local cmd="$2"

  total_steps=$((total_steps + 1))

  printf '\nRunning: %s\n' "$label"

  if [[ $DRY_RUN -eq 1 ]]; then
    printf '+ %s\n' "$cmd"
    printf '✓ Success: %s\n' "$label"
    success_steps=$((success_steps + 1))
    # still log the dry-run to verbose log
    log_verbose "$label (dry-run)" "$cmd"
    return 0
  fi

  # write header to verbose log and run
  # prefix command with sudo when needed
  local fullcmd
  fullcmd="$SUDO $cmd"
  log_verbose "$label" "$fullcmd"

  # actually run the command and capture exit code
  bash -c "$fullcmd"
  local rc=$?
  if [[ $rc -eq 0 ]]; then
    printf '✓ Success: %s\n' "$label"
    success_steps=$((success_steps + 1))
  else
    printf '✗ Failure: %s (exit %d)\n' "$label" "$rc"
    failed_steps=$((failed_steps + 1))
    # notify Slack about the failure
    if [[ $NO_NOTIFY -eq 0 ]]; then
      send_slack "failure" "Failure: $label" "exit=$rc on $(hostname) — $(timestamp)"
    fi
  fi
  return $rc
}

echo
sep
echo "Ubuntu System Update Script"
sep
echo "Starting system update at $(timestamp)"
sep

echo "Verbose output will be written to: $VERBOSE_LOG" >> "$LOG" 2>/dev/null || true

# send start notification (logged in dry-run)
if [[ $NO_NOTIFY -eq 0 ]]; then
  send_slack "start" "Starting system update" "mode=$MODE on $(hostname) — $(timestamp)"
fi

# Steps differ by mode
if [[ "$MODE" == "update-only" ]]; then
  run_step "Update package lists" "apt-get update"

elif [[ "$MODE" == "security" ]]; then
  # Prefer unattended-upgrade
  if command -v unattended-upgrade >/dev/null 2>&1; then
    run_step "Run unattended-upgrades (security)" "unattended-upgrade -v"
  else
    run_step "Update package lists" "apt-get update"
    run_step "Upgrade installed packages" "apt-get -y upgrade"
  fi

else
  # full mode: run a sequence of standard maintenance commands
  run_step "Update package lists" "apt-get update"
  run_step "Upgrade installed packages" "apt-get -y upgrade"
  run_step "Remove unnecessary packages" "apt-get -y autoremove"

  # snap refresh if available
  if command -v snap >/dev/null 2>&1; then
    run_step "Update snap packages" "snap refresh"
  else
    printf '\nRunning: Update snap packages\n'
    printf '✓ Skipped: snap not installed\n'
  fi

  run_step "Full system upgrade (handles dependencies)" "apt-get -y full-upgrade"
  run_step "Clean package cache" "apt-get -y autoclean"
fi

# Check for reboot requirement
if [[ $DRY_RUN -eq 1 ]]; then
  reboot_required=0
else
  if [[ -f /var/run/reboot-required ]]; then
    reboot_required=1
  else
    reboot_required=0
  fi
fi

echo
if [[ $reboot_required -eq 1 ]]; then
  printf '\n✗ Reboot required\n'
else
  printf '\n✓ No reboot required\n'
fi

sep
echo "UPDATE SUMMARY"
sep

if [[ $failed_steps -eq 0 ]]; then
  printf '✓ All updates completed successfully!\n'
else
  printf '✗ Some steps failed. See verbose log for details.\n'
fi

printf '✓ %d/%d commands executed without errors\n' "$success_steps" "$total_steps"
printf 'Verbose output saved to: %s\n' "$VERBOSE_LOG"
echo "Completed: $(timestamp)"
sep

# send completion notification (logged in dry-run)
if [[ $NO_NOTIFY -eq 0 ]]; then
  if [[ $failed_steps -eq 0 ]]; then
    send_slack "complete" "Completed: all updates succeeded" "$success_steps/$total_steps on $(hostname) — $(timestamp)"
  else
    send_slack "complete" "Completed: failures" "$success_steps/$total_steps (failed=$failed_steps) on $(hostname) — $(timestamp)"
  fi
fi

# Optionally fail the run if any step failed
if [[ $FAIL_ON_ERROR -eq 1 && $failed_steps -gt 0 ]]; then
  echo "One or more steps failed (failed_steps=$failed_steps). Exiting with error." >&2
  exit 1
fi

# release lock (file descriptor will close on exit)
exit 0
