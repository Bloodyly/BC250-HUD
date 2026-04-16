#!/usr/bin/env bash
# deploy.sh — Deployt den gebauten Kernel auf den Pi Zero 2 W
#
# Was passiert:
#   1. Backup des aktuellen Kernels auf dem Pi (/boot/firmware/kernel8.img.bak)
#   2. Neues kernel8.img übertragen
#   3. Module nach /lib/modules/<version>/ rsync-en
#   4. DTBs und Overlays übertragen
#   5. Pi neu starten
#
# Rollback falls kaputt:
#   sshpass -p raspberry ssh pi@10.10.5.2 \
#     'sudo cp /boot/firmware/kernel8.img.bak /boot/firmware/kernel8.img && sudo reboot'
#
# Aufruf: ./deploy.sh [--no-reboot]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/output"
PI_HOST="pi@10.10.5.2"
PI_PASS="raspberry"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[DEPLOY]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}   $*"; }
err()  { echo -e "${RED}[ERROR]${NC}  $*" >&2; exit 1; }
step() { echo -e "${CYAN}[STEP]${NC}   $*"; }

NO_REBOOT=false
if [[ "${1:-}" == "--no-reboot" ]]; then NO_REBOOT=true; fi

# ── Voraussetzungen ───────────────────────────────────────────────────────────
[ -f "$OUTPUT_DIR/kernel8.img" ] \
    || err "kernel8.img nicht gefunden. Erst build.sh ausführen."

KVER=$(ls "$OUTPUT_DIR/modules/lib/modules/" 2>/dev/null | head -1)
[ -n "$KVER" ] \
    || err "Keine Module in output/modules/lib/modules/. Build vollständig?"

log "Kernel-Version: $KVER"
log "Pi: $PI_HOST"
echo ""
warn "Dieser Schritt überschreibt den laufenden Kernel auf dem Pi."
warn "Ein Backup wird als kernel8.img.bak gespeichert."
echo ""
read -rp "Fortfahren? [j/N] " CONFIRM
[[ "${CONFIRM,,}" == "j" ]] || { log "Abgebrochen."; exit 0; }

# ── 1. Backup des aktuellen Kernels ──────────────────────────────────────────
step "1/5 Backup des aktuellen Kernels..."
sshpass -p "$PI_PASS" ssh "$PI_HOST" \
    'sudo cp /boot/firmware/kernel8.img /boot/firmware/kernel8.img.bak'
log "Backup: /boot/firmware/kernel8.img.bak"

# ── 2. Neues Kernel-Image ─────────────────────────────────────────────────────
step "2/5 Übertrage kernel8.img ($(ls -lh "$OUTPUT_DIR/kernel8.img" | awk '{print $5}'))..."
sshpass -p "$PI_PASS" scp \
    "$OUTPUT_DIR/kernel8.img" \
    "${PI_HOST}:/tmp/kernel8.img"
sshpass -p "$PI_PASS" ssh "$PI_HOST" \
    'sudo cp /tmp/kernel8.img /boot/firmware/kernel8.img'
log "kernel8.img installiert."

# ── 3. Module ────────────────────────────────────────────────────────────────
step "3/5 Übertrage Kernel-Module ($KVER)..."
# Zuerst Verzeichnis anlegen
sshpass -p "$PI_PASS" ssh "$PI_HOST" \
    "sudo mkdir -p /lib/modules/$KVER && sudo chown -R pi:pi /lib/modules/$KVER"
# Module rsync-en
rsync -av --progress \
    --exclude=build --exclude=source \
    -e "sshpass -p $PI_PASS ssh -o StrictHostKeyChecking=no" \
    "$OUTPUT_DIR/modules/lib/modules/$KVER/" \
    "${PI_HOST}:/lib/modules/$KVER/"
# Eigentümer zurücksetzen
sshpass -p "$PI_PASS" ssh "$PI_HOST" \
    "sudo chown -R root:root /lib/modules/$KVER"
log "Module installiert: /lib/modules/$KVER"

# ── 4. DTBs und Overlays ─────────────────────────────────────────────────────
step "4/5 Übertrage DTBs..."
# Broadcom DTBs
for dtb in "$OUTPUT_DIR/dtbs/"*.dtb; do
    [ -f "$dtb" ] || continue
    BASE=$(basename "$dtb")
    sshpass -p "$PI_PASS" scp "$dtb" "${PI_HOST}:/tmp/$BASE"
    sshpass -p "$PI_PASS" ssh "$PI_HOST" "sudo cp /tmp/$BASE /boot/firmware/$BASE"
done

# Overlays (rsync in temp, dann sudo-move)
if [ -d "$OUTPUT_DIR/dtbs/overlays" ] && [ "$(ls -A "$OUTPUT_DIR/dtbs/overlays")" ]; then
    sshpass -p "$PI_PASS" ssh "$PI_HOST" 'mkdir -p /tmp/overlays-new'
    rsync -av \
        -e "sshpass -p $PI_PASS ssh -o StrictHostKeyChecking=no" \
        "$OUTPUT_DIR/dtbs/overlays/" \
        "${PI_HOST}:/tmp/overlays-new/"
    sshpass -p "$PI_PASS" ssh "$PI_HOST" \
        'sudo rsync -rl --no-perms --no-owner --no-group /tmp/overlays-new/ /boot/firmware/overlays/ && rm -rf /tmp/overlays-new'
fi
log "DTBs und Overlays installiert."

# ── 5. depmod ────────────────────────────────────────────────────────────────
step "5/5 depmod..."
sshpass -p "$PI_PASS" ssh "$PI_HOST" "sudo depmod $KVER"
log "Modul-Abhängigkeiten aktualisiert."

# ── Zusammenfassung ───────────────────────────────────────────────────────────
echo ""
log "════════════════════════════════════════════"
log " Deploy erfolgreich!"
log ""
log " Neuer Kernel : $KVER"
log " Backup       : /boot/firmware/kernel8.img.bak"
log ""
log " Rollback falls kaputt:"
log "   sshpass -p raspberry ssh pi@10.10.5.2 \\"
log "   'sudo cp /boot/firmware/kernel8.img.bak \\"
log "    /boot/firmware/kernel8.img && sudo reboot'"
log "════════════════════════════════════════════"
echo ""

if $NO_REBOOT; then
    warn "Kein Reboot (--no-reboot). Manuell neu starten wenn bereit."
else
    log "Starte Pi neu..."
    sshpass -p "$PI_PASS" ssh "$PI_HOST" 'sudo reboot' || true
    log "Pi startet neu — warte ~30s dann prüfen mit:"
    log "  sshpass -p raspberry ssh pi@10.10.5.2 'uname -r'"
fi
