#!/usr/bin/env bash
# build.sh — Baut den vc4-drm-scheduler Kernel für den Pi Zero 2 W
#
# Ablauf:
#   1. Kernel-Source klonen (mairacanal/linux-rpi, Branch vc4/downstream/drm-scheduler)
#   2. Laufende Kernel-Config vom Pi holen
#   3. Build-Container bauen (falls nicht vorhanden)
#   4. Kernel, Module und DTBs im Container cross-compilieren
#   5. Output in repo/kernel/output/ ablegen
#
# Aufruf: ./build.sh [--rebuild-container]
#
# Voraussetzungen: podman, sshpass
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_IMAGE="hud-kernel-builder"
BRANCH="vc4/downstream/drm-scheduler"
REPO_URL="https://github.com/mairacanal/linux-rpi.git"
SRC_DIR="$SCRIPT_DIR/linux-rpi"
OUTPUT_DIR="$SCRIPT_DIR/output"
PI_HOST="pi@10.10.5.2"
PI_PASS="raspberry"
LOCALVERSION="-drm-sched-v8"
JOBS=$(nproc)

# Laufende Kernel-Version vom Pi dynamisch ermitteln (für Config-Download)
PI_KERNEL_VER=$(sshpass -p "$PI_PASS" ssh "$PI_HOST" 'uname -r' 2>/dev/null) \
    || { warn "Pi nicht erreichbar — PI_KERNEL_VER auf letzten bekannten Wert gesetzt."; PI_KERNEL_VER="6.12.75+rpt-rpi-v8"; }

# Farben für Log
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[BUILD]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── 1. Kernel-Source ─────────────────────────────────────────────────────────
if [ ! -d "$SRC_DIR/.git" ]; then
    log "Klone Kernel-Source (Branch: $BRANCH)..."
    log "Achtung: shallow clone (~500 MB), dauert einige Minuten."
    git clone --depth=1 --branch "$BRANCH" "$REPO_URL" "$SRC_DIR"
else
    log "Kernel-Source bereits vorhanden: $SRC_DIR"
    log "Prüfe ob Branch korrekt ist..."
    cd "$SRC_DIR"
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    if [ "$CURRENT_BRANCH" != "$BRANCH" ]; then
        warn "Branch ist '$CURRENT_BRANCH', erwartet '$BRANCH'."
        warn "Führe 'git fetch && git checkout $BRANCH' manuell aus oder lösche linux-rpi/ und starte neu."
    fi
    cd "$SCRIPT_DIR"
fi

# ── 2. Laufende Kernel-Config vom Pi holen ───────────────────────────────────
CONFIG_SRC="$SCRIPT_DIR/pi-running.config"
log "Hole Kernel-Config vom Pi (/boot/config-$PI_KERNEL_VER)..."
sshpass -p "$PI_PASS" scp \
    "${PI_HOST}:/boot/config-${PI_KERNEL_VER}" \
    "$CONFIG_SRC" \
    || err "Config-Download fehlgeschlagen. Pi erreichbar? (sshpass -p $PI_PASS ssh $PI_HOST)"

# LOCALVERSION anpassen — erzeugt 6.12.75-drm-sched-v8 statt 6.12.75+rpt-v8
sed -i "s|^CONFIG_LOCALVERSION=.*|CONFIG_LOCALVERSION=\"$LOCALVERSION\"|" "$CONFIG_SRC"
# Sicherheitshalber: kein Auto-Append aus git describe
sed -i 's|^CONFIG_LOCALVERSION_AUTO=.*|# CONFIG_LOCALVERSION_AUTO is not set|' "$CONFIG_SRC"

log "LOCALVERSION gesetzt auf: $LOCALVERSION"

# ── 3. Build-Container ───────────────────────────────────────────────────────
REBUILD_CONTAINER=false
if [[ "${1:-}" == "--rebuild-container" ]]; then
    REBUILD_CONTAINER=true
fi

if ! podman image exists "$CONTAINER_IMAGE" 2>/dev/null || $REBUILD_CONTAINER; then
    log "Baue Build-Container '$CONTAINER_IMAGE'..."
    podman build -t "$CONTAINER_IMAGE" "$SCRIPT_DIR"
else
    log "Build-Container '$CONTAINER_IMAGE' bereits vorhanden."
fi

# ── 4. Output-Verzeichnisse ──────────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR/modules"
mkdir -p "$OUTPUT_DIR/dtbs/overlays"

# ── 5. Kernel-Build im Container ─────────────────────────────────────────────
log "Starte Kernel-Build im Container (Threads: $JOBS)..."
log "Erwartete Dauer: 15–40 Minuten je nach CPU."

podman run --rm \
    --volume "$SCRIPT_DIR:/work:z" \
    "$CONTAINER_IMAGE" \
    bash -euo pipefail -c "
        set -euo pipefail
        cd /work/linux-rpi

        echo '[BUILD] Kernel-Config kopieren und bereinigen...'
        cp /work/pi-running.config .config
        make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig

        echo '[BUILD] Kernel-Version:'
        make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- kernelversion

        echo '[BUILD] Baue Kernel, Module und DTBs...'
        make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
            -j${JOBS} \
            Image modules dtbs \
            2>&1 | tee /work/build.log

        echo '[BUILD] Installiere Module nach output/modules/...'
        make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
            INSTALL_MOD_PATH=/work/output/modules \
            modules_install

        echo '[BUILD] Kopiere Kernel-Image...'
        cp arch/arm64/boot/Image /work/output/kernel8.img

        echo '[BUILD] Kopiere DTBs...'
        rsync -a --include='bcm271*.dtb' --exclude='*' \
            arch/arm64/boot/dts/broadcom/ /work/output/dtbs/
        rsync -a arch/arm64/boot/dts/overlays/*.dtbo \
                 arch/arm64/boot/dts/overlays/*.dtb \
                 arch/arm64/boot/dts/overlays/README \
                 /work/output/dtbs/overlays/ 2>/dev/null || true

        echo '[BUILD] Fertig.'
        echo '[BUILD] Kernel-Image: '\$(ls -lh /work/output/kernel8.img)
        echo '[BUILD] Module-Version: '\$(ls /work/output/modules/lib/modules/)
    "

# ── 6. Ergebnis ──────────────────────────────────────────────────────────────
KVER=$(ls "$OUTPUT_DIR/modules/lib/modules/" 2>/dev/null | head -1)
log ""
log "════════════════════════════════════════════"
log " Build erfolgreich!"
log " Kernel-Image : output/kernel8.img ($(ls -lh "$OUTPUT_DIR/kernel8.img" | awk '{print $5}'))"
log " Kernel-Version: $KVER"
log " DTBs         : output/dtbs/"
log " Module       : output/modules/lib/modules/$KVER/"
log ""
log " Nächster Schritt: ./deploy.sh"
log "════════════════════════════════════════════"
