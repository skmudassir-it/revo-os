#!/bin/busybox sh
# Revo OS v1.5.0 — Firewall Script (iptables)
#
# Default-deny policy with allowlists for essential services.
# Applied at boot by the init script.
#
# Ports:
#   2222  — SSH (Dropbear)
#   51820 — WireGuard (UDP)
#   6881  — revo-fs mesh (UDP + TCP)
#   24000 — Ornet API (optional)
#
# Usage: /etc/revo/firewall.sh [start|stop|status]

set -e

FIREWALL_LOG="/var/log/firewall.log"
SSH_PORT="${SSH_PORT:-2222}"
WG_PORT="${WG_PORT:-51820}"
MESH_PORT="${MESH_PORT:-6881}"

log() { echo "[firewall] $*" >> "$FIREWALL_LOG" 2>/dev/null; echo "[firewall] $*"; }

# ─── Start Firewall ───
fw_start() {
    log "Starting firewall (default-deny)..."
    
    # Flush existing rules
    iptables -F 2>/dev/null || true
    iptables -X 2>/dev/null || true
    iptables -t nat -F 2>/dev/null || true
    
    # ─── Default Policies ───
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT   # Allow all outbound (server can reach out)
    
    # ─── Allow loopback ───
    iptables -A INPUT -i lo -j ACCEPT
    
    # ─── Allow established/related ───
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    
    # ─── Allow SSH (Dropbear) ───
    iptables -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT
    log "  [OK] SSH: port $SSH_PORT"
    
    # ─── Allow WireGuard (UDP) ───
    iptables -A INPUT -p udp --dport "$WG_PORT" -j ACCEPT
    log "  [OK] WireGuard: port $WG_PORT (UDP)"
    
    # ─── Allow revo-fs mesh ───
    iptables -A INPUT -p tcp --dport "$MESH_PORT" -j ACCEPT
    iptables -A INPUT -p udp --dport "$MESH_PORT" -j ACCEPT
    log "  [OK] revo-fs mesh: port $MESH_PORT"
    
    # ─── Allow ping (optional, for monitoring) ───
    iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/second -j ACCEPT
    log "  [OK] ICMP: rate-limited ping"
    
    # ─── Log dropped packets (rate-limited) ───
    iptables -A INPUT -m limit --limit 5/minute -j LOG --log-prefix "FW-DROP: " --log-level 4
    
    log "Firewall active — $(iptables -L INPUT -n | grep -c ACCEPT) allow rules"
}

# ─── Stop Firewall ───
fw_stop() {
    log "Stopping firewall (allow-all)..."
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -F
    iptables -X
    log "Firewall disabled"
}

# ─── Status ───
fw_status() {
    echo "Firewall Status"
    echo "==============="
    echo ""
    
    local policy=$(iptables -L INPUT -n 2>/dev/null | head -1 | awk '{print $4}')
    echo "Default policy: ${policy:-UNKNOWN}"
    echo ""
    
    echo "Allow rules:"
    iptables -L INPUT -n --line-numbers 2>/dev/null | grep ACCEPT | while read -r line; do
        echo "  $line"
    done
}

# ─── Main ───
case "${1:-start}" in
    start)  fw_start ;;
    stop)   fw_stop ;;
    status) fw_status ;;
    *)      echo "Usage: $0 [start|stop|status]"; exit 1 ;;
esac
