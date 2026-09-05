#!/usr/bin/env bash
set -euo pipefail

RATE_MBPS="${RATE_MBPS:-500}"
MAX_IPS="${MAX_IPS:-20}"
MIHOMO_UNIT="${MIHOMO_UNIT:-mihomo.service}"
ANYTLS_PORT="${ANYTLS_PORT:-443}"

WATCH_SCRIPT="/usr/local/bin/brutal-anytls-watch.sh"
SERVICE_FILE="/etc/systemd/system/brutal-anytls-watch.service"
STATE_DIR="/var/lib/brutal-anytls"

log() { printf '[install] %s\n' "$*"; }
die() { printf '[install] ERROR: %s\n' "$*" >&2; exit 1; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "please run as root"
command -v systemctl >/dev/null 2>&1 || die "systemd/systemctl is required"
command -v journalctl >/dev/null 2>&1 || die "journalctl is required"
command -v ss >/dev/null 2>&1 || die "ss (iproute2) is required"

[[ "$RATE_MBPS" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "RATE_MBPS must be a positive number"
[[ "$MAX_IPS" =~ ^[0-9]+$ ]] && (( MAX_IPS > 0 )) || die "MAX_IPS must be a positive integer"
[[ "$ANYTLS_PORT" =~ ^[0-9]+$ ]] && (( ANYTLS_PORT >= 1 && ANYTLS_PORT <= 65535 )) || die "ANYTLS_PORT must be 1..65535"

if ! systemctl cat "$MIHOMO_UNIT" >/dev/null 2>&1; then
    die "cannot find systemd unit: $MIHOMO_UNIT"
fi

if ! command -v brutalctl >/dev/null 2>&1; then
    log "brutalctl not found; installing TCP Brutal using the official installer"
    command -v curl >/dev/null 2>&1 || die "curl is required to install TCP Brutal"
    bash <(curl -fsSL https://tcp.hy2.sh/)
fi

command -v brutalctl >/dev/null 2>&1 || die "brutalctl is still unavailable after installation"

log "installing watcher: rate=${RATE_MBPS}Mbps, max_ips=${MAX_IPS}, port=${ANYTLS_PORT}, mihomo_unit=${MIHOMO_UNIT}"

install -d -m 0755 "$STATE_DIR"

cat >"$WATCH_SCRIPT" <<EOF
#!/usr/bin/env bash
set -u

RATE_MBPS="${RATE_MBPS}"
MAX_IPS="${MAX_IPS}"
MIHOMO_UNIT="${MIHOMO_UNIT}"
ANYTLS_PORT="${ANYTLS_PORT}"
STATE_DIR="${STATE_DIR}"
IP_FILE="\${STATE_DIR}/clients"

mkdir -p "\$STATE_DIR"
touch "\$IP_FILE"

log() {
    echo "[brutal-anytls] \$*"
}

has_rule() {
    local ip="\$1"
    brutalctl list 2>/dev/null | grep -qE "^\${ip//./\\.}/32([[:space:]]|\$)"
}

remember_ip() {
    local ip="\$1" tmp
    tmp="\$(mktemp)"
    grep -vxF "\$ip" "\$IP_FILE" >"\$tmp" || true
    echo "\$ip" >>"\$tmp"
    mv "\$tmp" "\$IP_FILE"
}

cleanup_old_ips() {
    local count old_ip
    count="\$(wc -l <"\$IP_FILE")"
    while [ "\$count" -gt "\$MAX_IPS" ]; do
        old_ip="\$(head -n 1 "\$IP_FILE")"
        if [ -n "\$old_ip" ]; then
            log "removing old client: \${old_ip}/32"
            brutalctl del "\${old_ip}/32" 2>/dev/null || true
        fi
        sed -i '1d' "\$IP_FILE"
        count="\$(wc -l <"\$IP_FILE")"
    done
}

add_rule() {
    local ip="\$1"
    remember_ip "\$ip"
    cleanup_old_ips

    if has_rule "\$ip"; then
        return 1
    fi

    log "new client IP detected: \$ip"
    log "adding Brutal rule: \${ip}/32 @ \${RATE_MBPS} Mbps"

    if brutalctl add "\${ip}/32" "\$RATE_MBPS"; then
        log "Brutal rule added successfully"
        return 0
    fi

    log "failed to add Brutal rule for \$ip"
    return 1
}

kick_connections() {
    local ip="\$1"
    log "closing existing AnyTLS TCP connections for \$ip"
    ss -K "sport = :\${ANYTLS_PORT}" "dst \${ip}" 2>/dev/null || true
    log "client should now reconnect using TCP Brutal"
}

log "starting"
log "rate=\${RATE_MBPS} Mbps, max_ips=\${MAX_IPS}, AnyTLS port=\${ANYTLS_PORT}"

journalctl -u "\$MIHOMO_UNIT" -f -n 0 -o cat |
while IFS= read -r line; do
    ip="\$(printf '%s\\n' "\$line" | sed -nE 's/.*\\[TCP\\] ([0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+):[0-9]+ -->.*/\\1/p')"
    [ -z "\$ip" ] && continue

    case "\$ip" in
        127.*|0.*|169.254.*)
            continue
            ;;
    esac

    if add_rule "\$ip"; then
        sleep 0.2
        kick_connections "\$ip"
    fi
done
EOF

chmod 0755 "$WATCH_SCRIPT"

cat >"$SERVICE_FILE" <<EOF
[Unit]
Description=TCP Brutal v2 auto rule for Mihomo AnyTLS
After=network-online.target ${MIHOMO_UNIT}
Wants=network-online.target
Requires=${MIHOMO_UNIT}

[Service]
Type=simple
ExecStart=${WATCH_SCRIPT}
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now brutal-anytls-watch.service

log "installation complete"
log "service status: systemctl status brutal-anytls-watch"
log "watch logs:     journalctl -u brutal-anytls-watch -f"
log "Brutal rules:   brutalctl list"
