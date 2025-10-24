#!/usr/bin/env bash
set -euo pipefail

# Simple installer for server-updates
# Installs script to /usr/local/bin, systemd units, and logrotate config.

DEST_BIN=/usr/local/bin/update-server.sh
DEST_SERVICE=/etc/systemd/system/server-updates.service
DEST_TIMER=/etc/systemd/system/server-updates.timer
DEST_LOGROTATE=/etc/logrotate.d/server-updates

BASEDIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  cat <<EOF
Usage: $0 [--enable-timer]

Installs files and optionally enables and starts the systemd timer.
EOF
}

ENABLE_TIMER=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --enable-timer)
      ENABLE_TIMER=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root to install files." >&2
  exit 1
fi

echo "Installing update-server script to $DEST_BIN"
install -m 0755 "$BASEDIR/update-server.sh" "$DEST_BIN"

echo "Installing systemd units"
install -m 0644 "$BASEDIR/systemd/server-updates.service" "$DEST_SERVICE"
install -m 0644 "$BASEDIR/systemd/server-updates.timer" "$DEST_TIMER"

if [[ -f "$BASEDIR/logrotate/server-updates" ]]; then
  echo "Installing logrotate config to $DEST_LOGROTATE"
  install -m 0644 "$BASEDIR/logrotate/server-updates" "$DEST_LOGROTATE"
fi

# Copy sample config to /etc if it doesn't already exist
if [[ -f "$BASEDIR/etc/sample.conf" ]]; then
  if [[ -f /etc/server-updates.conf ]]; then
    echo "/etc/server-updates.conf already exists; not overwriting"
  else
    echo "Installing default config to /etc/server-updates.conf"
    install -m 0600 "$BASEDIR/etc/sample.conf" /etc/server-updates.conf
    chown root:root /etc/server-updates.conf || true
  fi
fi

echo "Reloading systemd daemon"
systemctl daemon-reload

if [[ $ENABLE_TIMER -eq 1 ]]; then
  echo "Enabling and starting server-updates.timer"
  systemctl enable --now server-updates.timer
else
  echo "Timer not enabled. To enable now: systemctl enable --now server-updates.timer"
fi

echo "Install complete. The update script is at: $DEST_BIN"
exit 0
