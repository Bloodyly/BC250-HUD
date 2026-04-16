#!/bin/bash
# bc250-sleep-hook.sh — systemd-sleep-Hook für BC250 HUD
#
# Deploy auf dem BC250-Host:
#   sudo cp bc250-sleep-hook.sh /lib/systemd/system-sleep/bc250-hud.sh
#   sudo chmod +x /lib/systemd/system-sleep/bc250-hud.sh
#
# Wird von systemd mit Argumenten aufgerufen:
#   $1 = pre|post
#   $2 = suspend|hibernate|hybrid-sleep|suspend-then-hibernate

PI_IP="10.10.5.2"
PI_PORT="5555"

send_cmd() {
    local cmd="$1"
    printf '{"cmd":"%s"}\n' "$cmd" | timeout 1 nc -q1 "$PI_IP" "$PI_PORT" 2>/dev/null || \
    printf '{"cmd":"%s"}\n' "$cmd" | timeout 1 nc -w1 "$PI_IP" "$PI_PORT" 2>/dev/null || true
    echo "[bc250-hud] Sleep-Hook: cmd '$cmd' gesendet (${1}/${2})"
}

case "$1/$2" in
    pre/suspend|pre/hibernate|pre/hybrid-sleep|pre/suspend-then-hibernate)
        send_cmd "standby"
        ;;
    post/suspend|post/hibernate|post/hybrid-sleep|post/suspend-then-hibernate)
        send_cmd "wake"
        ;;
esac
