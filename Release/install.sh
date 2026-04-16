#!/usr/bin/env bash
# install.sh — BC250 HUD Installer für Raspberry Pi Zero 2 W
#
# Voraussetzung:
#   - Raspberry Pi OS Bookworm Lite (arm64, kernel8)
#   - Internet-Zugang auf dem Pi für apt
#   - Dieser Release-Ordner liegt auf dem Pi unter /home/pi/Release
#   - Als root oder mit sudo ausführen
#
# Aufruf:
#   cd /home/pi/Release && sudo bash install.sh
#
# Was dieser Installer tut:
#   1. Benötigte Pakete installieren (cage, seatd, pigpiod, python3)
#   2. Xwayland-Stub anlegen (cage braucht das Binary, nutzt es nie)
#   3. Benutzer pi in seat/tty/video/render Gruppen
#   4. HUD-Binary, QML und Services installieren
#   5. Custom Kernel (6.18.6 + vc4 drm-scheduler Fix) installieren
#   6. USB-Gadget Netzwerk auf Pi-Seite konfigurieren (10.10.5.2/30)
#   7. CPU Governor auf performance setzen
#   8. config.txt auf /boot/firmware kopieren (Custom HDMI + USB-Gadget)
#   9. Alle Services aktivieren und Reboot

set -euo pipefail

RELEASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KVER="6.18.6-drm-sched-v8+"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[INSTALL]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}   $*"; }
step() { echo -e "${CYAN}[STEP]${NC}   $*"; }
err()  { echo -e "${RED}[ERROR]${NC}  $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || err "Als root oder mit sudo ausführen."
[ -f "$RELEASE_DIR/hud/hudc_new" ] || err "Falschews Verzeichnis? hudc_new nicht gefunden."

log "BC250 HUD Installer — Raspberry Pi Zero 2 W"
log "Release-Verzeichnis: $RELEASE_DIR"
echo ""

# ── 1. Pakete ─────────────────────────────────────────────────────────────────
step "1/9 Pakete installieren..."
apt-get update -qq
apt-get install -y --no-install-recommends \
    cage seatd \
    pigpiod python3 python3-pigpio \
    rsync
log "Pakete installiert."

# ── 2. Xwayland-Stub ──────────────────────────────────────────────────────────
step "2/9 Xwayland-Stub anlegen..."
printf '#!/bin/sh\nexec sleep infinity\n' > /usr/bin/Xwayland
chmod +x /usr/bin/Xwayland
log "Xwayland-Stub: /usr/bin/Xwayland"

# ── 3. Gruppen ────────────────────────────────────────────────────────────────
step "3/9 Benutzer pi in Gruppen seat/tty/video/render..."
usermod -aG seat,tty,video,render pi
log "Gruppen gesetzt."

# ── 4. HUD-Dateien ────────────────────────────────────────────────────────────
step "4/9 HUD-Dateien installieren..."
mkdir -p /home/pi/hudc
cp "$RELEASE_DIR/hud/hudc_new" /home/pi/hudc/hudc_new
cp "$RELEASE_DIR/hud/hud.qml"  /home/pi/hudc/hud.qml
chmod +x /home/pi/hudc/hudc_new
chown -R pi:pi /home/pi/hudc
cp "$RELEASE_DIR/hud/hudcw.service" /etc/systemd/system/
cp "$RELEASE_DIR/hud/hudc.service"  /etc/systemd/system/
log "HUD installiert: /home/pi/hudc/"

# ── 5. Custom Kernel ──────────────────────────────────────────────────────────
step "5/9 Custom Kernel installieren ($KVER)..."

# Backup des aktuellen Kernels
cp /boot/firmware/kernel8.img /boot/firmware/kernel8.img.bak
log "Backup: /boot/firmware/kernel8.img.bak"

# Kernel-Image
cp "$RELEASE_DIR/kernel/kernel8.img" /boot/firmware/kernel8.img
log "Kernel-Image installiert."

# Module entpacken
MODULES_TAR="$RELEASE_DIR/kernel/modules-${KVER}.tar.xz"
[ -f "$MODULES_TAR" ] || err "Module-Archiv nicht gefunden: $MODULES_TAR"
mkdir -p /lib/modules
tar -xJf "$MODULES_TAR" -C /
depmod "$KVER"
log "Module installiert: /lib/modules/$KVER"

# DTBs
cp "$RELEASE_DIR/dtbs/"*.dtb /boot/firmware/ 2>/dev/null || true
# Overlays (FAT: kein chown)
rsync -rl --no-perms --no-owner --no-group \
    "$RELEASE_DIR/dtbs/overlays/" /boot/firmware/overlays/
log "DTBs und Overlays installiert."

# ── 6. USB-Gadget Netzwerk (Pi-Seite) ─────────────────────────────────────────
step "6/9 USB-Gadget Netzwerk konfigurieren (Pi: 10.10.5.2/30)..."

# NetworkManager-Profil für usb0 (USB Gadget Interface auf Pi-Seite)
mkdir -p /etc/NetworkManager/system-connections
cat > /etc/NetworkManager/system-connections/usb-gadget.nmconnection << 'NMEOF'
[connection]
id=usb-gadget
uuid=a1b2c3d4-e5f6-7890-abcd-ef1234567890
type=ethernet
interface-name=usb0
autoconnect=true
autoconnect-priority=5

[ethernet]
duplex=full

[ipv4]
method=manual
address1=10.10.5.2/30
gateway=10.10.5.1
dns=10.10.5.1;

[ipv6]
method=disabled
NMEOF

chmod 600 /etc/NetworkManager/system-connections/usb-gadget.nmconnection
log "USB-Gadget Netzwerk-Profil erstellt (usb0 → 10.10.5.2/30)."

# ── 7. config.txt ─────────────────────────────────────────────────────────────
step "7/9 /boot/firmware/config.txt installieren..."
cp /boot/firmware/config.txt /boot/firmware/config.txt.bak
cp "$RELEASE_DIR/config/config.txt" /boot/firmware/config.txt
log "config.txt installiert (Backup: config.txt.bak)."

# ── 8. CPU Performance Governor ───────────────────────────────────────────────
step "8/9 CPU Governor Service installieren..."
cp "$RELEASE_DIR/config/cpu-performance.service" /etc/systemd/system/
log "cpu-performance.service installiert."

# ── 9. Services aktivieren ────────────────────────────────────────────────────
step "9/9 Services aktivieren..."
systemctl daemon-reload
systemctl enable pigpiod.service
systemctl enable seatd.service
systemctl enable hudcw.service
systemctl enable cpu-performance.service
# systemd-udev-settle maskieren (3-Min-Timeout-Bug)
systemctl mask systemd-udev-settle.service 2>/dev/null || true
log "Services aktiviert."

# ── Abschluss ─────────────────────────────────────────────────────────────────
echo ""
log "════════════════════════════════════════════"
log " Installation abgeschlossen!"
log ""
log " Kernel  : $KVER (vc4 drm-scheduler Fix)"
log " HUD     : /home/pi/hudc/"
log " Service : hudcw.service (cage/Wayland)"
log ""
warn "WICHTIG: Für den BC250-Host (Bazzite/PC) muss noch"
warn "  release/host-setup.sh ausgeführt werden, um die"
warn "  USB-Gadget-Verbindung auf dem PC zu konfigurieren."
echo ""
read -rp "Jetzt neu starten? [J/n] " yn
if [[ "${yn,,}" != "n" ]]; then
    log "Starte neu..."
    reboot
fi
