#!/usr/bin/env bash
# deploy.sh — Master-Deploy vom BC250-Host auf den Pi
#
# Kopiert den kompletten Release-Ordner auf den Pi und triggert install.sh.
# Gedacht für: Neuinstallation oder Update eines laufenden Pi.
#
# Aufruf: bash deploy.sh [--update-only]
#   --update-only: nur HUD-Binary + QML + Service neu deployen, kein Kernel-Install

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI_HOST="pi@10.10.5.2"
PI_PASS="raspberry"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[DEPLOY]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}   $*"; }
step() { echo -e "${CYAN}[STEP]${NC}   $*"; }

UPDATE_ONLY=false
[[ "${1:-}" == "--update-only" ]] && UPDATE_ONLY=true

# ── Pi erreichbar? ─────────────────────────────────────────────────────────────
sshpass -p "$PI_PASS" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
    "$PI_HOST" 'echo OK' > /dev/null 2>&1 \
    || { echo -e "${RED}[ERROR]${NC} Pi nicht erreichbar (10.10.5.2). USB-Gadget verbunden?"; exit 1; }

if $UPDATE_ONLY; then
    # ── Schnelles Update: nur HUD-Dateien ──────────────────────────────────────
    log "Update-Modus: Binary + QML + Service"
    sshpass -p "$PI_PASS" ssh "$PI_HOST" 'sudo systemctl stop hudcw.service'
    sshpass -p "$PI_PASS" scp "$SCRIPT_DIR/hud/hudc_new" "$PI_HOST:/home/pi/hudc/hudc_new"
    sshpass -p "$PI_PASS" scp "$SCRIPT_DIR/hud/hud.qml"  "$PI_HOST:/home/pi/hudc/hud.qml"
    sshpass -p "$PI_PASS" scp "$SCRIPT_DIR/hud/hudcw.service" "$PI_HOST:/tmp/hudcw.service"
    sshpass -p "$PI_PASS" ssh "$PI_HOST" '
        sudo cp /tmp/hudcw.service /etc/systemd/system/hudcw.service
        sudo systemctl daemon-reload
        sudo systemctl start hudcw.service
    '
    log "Update abgeschlossen."
    exit 0
fi

# ── Vollinstallation ────────────────────────────────────────────────────────────
step "1/2 Release-Ordner auf Pi kopieren (~60MB, dauert etwas)..."
rsync -av --progress \
    -e "sshpass -p $PI_PASS ssh -o StrictHostKeyChecking=no" \
    "$SCRIPT_DIR/" \
    "${PI_HOST}:/home/pi/Release/"

step "2/2 Installer auf Pi starten..."
sshpass -p "$PI_PASS" ssh "$PI_HOST" 'sudo bash /home/pi/Release/install.sh'
