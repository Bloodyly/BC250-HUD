#!/usr/bin/env bash
# host-setup.sh — BC250 Host Setup (Bazzite/Fedora)
#
# Konfiguriert auf dem BC250-PC:
#   1. NetworkManager-Verbindung für das USB-Gadget Interface (10.10.5.1/30)
#      - autoconnect, nie als Default-Route
#   2. bc250_daemon.service (HUD-Daemon) installieren und aktivieren
#   3. Sleep/Wake-Hook installieren
#
# Aufruf (auf dem BC250-PC, als normaler User):
#   bash host-setup.sh
#
# Voraussetzung:
#   - Bazzite / Fedora Linux
#   - NetworkManager aktiv
#   - Pi per USB-Gadget verbunden

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[HOST-SETUP]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}       $*"; }
step() { echo -e "${CYAN}[STEP]${NC}       $*"; }
err()  { echo -e "${RED}[ERROR]${NC}      $*" >&2; exit 1; }

# ── Voraussetzungen ────────────────────────────────────────────────────────────
command -v nmcli  >/dev/null || err "nmcli nicht gefunden — NetworkManager installiert?"
command -v python3 >/dev/null || err "python3 nicht gefunden."

log "BC250 HUD Host-Setup"
echo ""

# ── 0. udev-Regel für stabilen Interface-Namen installieren ───────────────────
UDEV_RULE="$SCRIPT_DIR/config/70-pi-usb.rules"
if [ -f "$UDEV_RULE" ]; then
    sudo install -m 644 "$UDEV_RULE" /etc/udev/rules.d/70-pi-usb.rules
    sudo udevadm control --reload-rules
    sudo udevadm trigger --subsystem-match=net --action=change
    log "udev-Regel installiert: Pi USB-Gadget Interface → 'pi-usb'"
    log "Hinweis: Interface-Umbenennung gilt ab nächstem Plug/Reboot vollständig."
fi

# ── 1. USB-Gadget Interface finden ────────────────────────────────────────────
step "1/4 USB-Gadget Interface erkennen..."

# Suche nach Interface mit cdc_ether-Treiber (USB Gadget Ethernet)
CDC_IF=""
for iface in $(nmcli -t -f DEVICE,TYPE dev | grep ":ethernet" | cut -d: -f1); do
    DRIVER=$(readlink /sys/class/net/"$iface"/device/driver 2>/dev/null | xargs basename 2>/dev/null || true)
    if [[ "$DRIVER" == "cdc_ether" || "$DRIVER" == "rndis_host" ]]; then
        CDC_IF="$iface"
        break
    fi
done

if [ -z "$CDC_IF" ]; then
    warn "USB-Gadget Interface nicht automatisch erkannt."
    warn "Pi verbunden und eingeschaltet?"
    echo ""
    echo "Verfügbare Ethernet-Interfaces:"
    nmcli -t -f DEVICE,TYPE,STATE dev | grep ":ethernet"
    echo ""
    read -rp "Interface-Name manuell eingeben (z.B. enp0s19f2u1u1): " CDC_IF
    [ -n "$CDC_IF" ] || err "Kein Interface angegeben."
fi

log "USB-Gadget Interface: $CDC_IF"

# ── 2. NetworkManager-Verbindung erstellen ─────────────────────────────────────
step "2/4 NetworkManager-Verbindung konfigurieren..."

# Alte Verbindung löschen falls vorhanden
nmcli connection delete "hud-usb-gadget" 2>/dev/null || true

nmcli connection add \
    type ethernet \
    con-name "hud-usb-gadget" \
    ifname "$CDC_IF" \
    ipv4.method manual \
    ipv4.addresses "10.10.5.1/30" \
    ipv4.never-default true \
    ipv6.method disabled \
    connection.autoconnect true \
    connection.autoconnect-priority 10

log "Verbindung 'hud-usb-gadget' erstellt: 10.10.5.1/30 auf $CDC_IF"
log "Verbindung aktivieren..."
nmcli connection up "hud-usb-gadget" || warn "Aktivierung fehlgeschlagen — Pi verbunden?"

# ── 3. bc250_daemon installieren ──────────────────────────────────────────────
step "3/4 bc250_daemon installieren..."

sudo install -m 755 "$SCRIPT_DIR/daemon/bc250_daemon.py" /opt/hud/bc250_daemon.py 2>/dev/null || {
    sudo mkdir -p /opt/hud
    sudo install -m 755 "$SCRIPT_DIR/daemon/bc250_daemon.py" /opt/hud/bc250_daemon.py
}

# Service-Datei anpassen: User auf aktuellen User setzen
CURRENT_USER=$(id -un)
sed "s/^User=.*/User=${CURRENT_USER}/" "$SCRIPT_DIR/daemon/bc250_daemon.service" \
    | sudo tee /etc/systemd/system/bc250_daemon.service > /dev/null

# Sleep/Wake-Hook
if [ -d /lib/systemd/system-sleep ]; then
    sudo install -m 755 "$SCRIPT_DIR/daemon/bc250-sleep-hook.sh" \
        /lib/systemd/system-sleep/bc250-sleep-hook.sh
    log "Sleep-Hook installiert."
fi

sudo systemctl daemon-reload
sudo systemctl enable --now bc250_daemon.service
log "bc250_daemon.service aktiviert."

# ── 4/4 systemd-udev-settle maskieren (3-Min-Boot-Timeout) ─────────────────────
if systemctl is-enabled systemd-udev-settle.service 2>/dev/null | grep -qv "masked"; then
    warn "systemd-udev-settle wird maskiert (verhindert 3-Min-Boot-Delay)..."
    sudo systemctl mask systemd-udev-settle.service
fi

# ── Ergebnis ─────────────────────────────────────────────────────────────────
echo ""
log "════════════════════════════════════════════"
log " Host-Setup abgeschlossen!"
log ""
log " USB-Gadget  : $CDC_IF → 10.10.5.1/30"
log " NM-Profil   : hud-usb-gadget (autoconnect, never-default)"
log " Daemon      : /opt/hud/bc250_daemon.py"
log " Service     : bc250_daemon.service (aktiv)"
log ""
log " Pi erreichbar unter: 10.10.5.2"
log " Test: ssh pi@10.10.5.2"
log "════════════════════════════════════════════"
