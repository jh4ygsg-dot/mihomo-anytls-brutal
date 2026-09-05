#!/usr/bin/env bash
set -euo pipefail

SERVICE="brutal-anytls-watch.service"
WATCH_SCRIPT="/usr/local/bin/brutal-anytls-watch.sh"
SERVICE_FILE="/etc/systemd/system/${SERVICE}"
STATE_DIR="/var/lib/brutal-anytls"
IP_FILE="${STATE_DIR}/clients"

log() { printf '[uninstall] %s\n' "$*"; }
die() { printf '[uninstall] ERROR: %s\n' "$*" >&2; exit 1; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "please run as root"

if [[ -f "$IP_FILE" ]] && command -v brutalctl >/dev/null 2>&1; then
    log "removing Brutal rules recorded by this project"
    while IFS= read -r ip; do
        [[ -n "$ip" ]] || continue
        brutalctl del "${ip}/32" 2>/dev/null || true
    done < "$IP_FILE"
fi

systemctl disable --now "$SERVICE" 2>/dev/null || true
rm -f "$SERVICE_FILE" "$WATCH_SCRIPT"
rm -rf "$STATE_DIR"
systemctl daemon-reload
systemctl reset-failed "$SERVICE" 2>/dev/null || true

log "uninstalled"
log "TCP Brutal itself and Mihomo configuration were left untouched"
