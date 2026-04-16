# BC250 HUD — Release-Paket

Vollständiges Installations- und Deploy-Paket für das BC250 HUD-System.

---

## Systemübersicht

| Komponente | Details |
|---|---|
| **Display-Controller** | Raspberry Pi Zero 2 W |
| **Host-PC** | BC250 (Bazzite Linux / Fedora) |
| **Display** | 480×1920 px, Hochformat, HDMI |
| **Verbindung** | USB-Gadget (Ethernet), Pi=10.10.5.2, Host=10.10.5.1 |
| **HUD-Binary** | Qt Quick / C++, `hudcw.service` (cage/Wayland) |
| **Kernel** | 6.18.6-drm-sched-v8+ (vc4 drm-scheduler fix) |

---

## Paket-Inhalt

```
Release/
├── README.md                          ← diese Datei
├── install.sh                         ← Pi-Installer (Neuinstallation)
├── host-setup.sh                      ← BC250 Host-Setup (USB-Gadget + Daemon)
├── deploy.sh                          ← Master-Deploy-Script (BC250 → Pi)
│
├── kernel/
│   ├── kernel8.img                    ← Custom Kernel 6.18.6-drm-sched-v8+
│   └── modules-6.18.6-drm-sched-v8+.tar.xz
│
├── dtbs/
│   ├── bcm2710-rpi-zero-2-w.dtb       ← Device Tree für Pi Zero 2 W
│   ├── *.dtb                          ← Weitere DTBs
│   └── overlays/                      ← Kernel-Overlays
│
├── hud/
│   ├── hudc_new                       ← HUD-Binary (arm64, Qt Quick)
│   ├── hud.qml                        ← HUD-UI (Qt Quick)
│   ├── hudcw.service                  ← Systemd-Service (cage/Wayland, aktiv)
│   └── hudc.service                   ← Systemd-Service (EGLFS, Fallback)
│
├── daemon/
│   ├── bc250_daemon.py                ← Host-Daemon (Metriken → Pi per TCP)
│   ├── bc250_daemon.service           ← Systemd-Service für BC250
│   └── bc250-sleep-hook.sh            ← Sleep/Wake-Hook
│
├── config/
│   ├── config.txt                     ← /boot/firmware/config.txt (Pi)
│   └── cpu-performance.service        ← CPU Governor = performance
│
└── src/                               ← Quellcode des HUD-Binaries
    ├── CMakeLists.txt
    ├── hud.qml
    └── src/
        ├── main.cpp
        ├── hudmodel.cpp / .h
        ├── daemonreceiver.cpp / .h
        ├── backlightcontroller.cpp / .h
        ├── healthworker.cpp / .h
        └── simulation.cpp / .h
```

---

## Neuinstallation (Fresh Pi Zero 2 W)

Voraussetzungen:
- Raspberry Pi OS **Bookworm Lite** (arm64, 64-bit) auf der SD-Karte
- Pi per USB-Gadget mit BC250 verbunden
- Pi hat während der Installation Internet-Zugang (für `apt`)

### Schritt 1 — Host vorbereiten (einmalig)

```bash
# Auf dem BC250-Host ausführen (als normaler User):
bash host-setup.sh
```

Richtet ein:
- NetworkManager-Verbindung `hud-usb-gadget` (10.10.5.1/30, autoconnect, never-default)
- `bc250_daemon.service` (Metriken-Daemon, autostart)
- Sleep/Wake-Hook

### Schritt 2 — Pi installieren

```bash
# Komplette Installation auf frischem Pi:
bash deploy.sh
```

Das Script:
1. Kopiert den gesamten Release-Ordner per rsync auf den Pi (`/home/pi/Release/`)
2. Startet `install.sh` auf dem Pi via SSH

`install.sh` erledigt dann auf dem Pi:
1. Pakete installieren (`cage`, `seatd`, `pigpiod`, `python3`, `rsync`)
2. Xwayland-Stub anlegen (cage benötigt das Binary)
3. User `pi` in Gruppen `seat`, `tty`, `video`, `render`
4. HUD-Binary, QML und Services nach `/home/pi/hudc/` und `/etc/systemd/system/`
5. Custom Kernel 6.18.6-drm-sched-v8+ installieren
6. USB-Gadget Netzwerk (usb0 → 10.10.5.2/30) als NetworkManager-Profil
7. `/boot/firmware/config.txt` installieren (Custom HDMI + USB-Gadget + vc4-kms-v3d)
8. CPU-Performance-Governor-Service installieren
9. Services aktivieren + Reboot

---

## Update (laufendes System)

Nur HUD-Binary, QML und Service aktualisieren — ohne Kernel-Neuinstall:

```bash
bash deploy.sh --update-only
```

Oder manuell:

```bash
PI="pi@10.10.5.2"
PASS="raspberry"

sshpass -p $PASS ssh $PI 'sudo systemctl stop hudcw.service'
sshpass -p $PASS scp hud/hudc_new $PI:/home/pi/hudc/hudc_new
sshpass -p $PASS scp hud/hud.qml  $PI:/home/pi/hudc/hud.qml
sshpass -p $PASS ssh $PI 'sudo systemctl start hudcw.service'
```

### QML-Hot-Reload (ohne Service-Neustart)

Während der Entwicklung: HUD lädt hud.qml automatisch neu wenn sich die Datei ändert (alle 5s geprüft):

```bash
# Nur QML deployen → Auto-Reload in ≤5s
sshpass -p raspberry scp hud/hud.qml pi@10.10.5.2:/home/pi/hudc/hud.qml
```

---

## Daemon deployen (BC250 Host)

```bash
sudo cp daemon/bc250_daemon.py /opt/hud/bc250_daemon.py
sudo systemctl restart bc250_daemon.service
```

---

## Binary neu bauen (Cross-Compile)

Das HUD-Binary muss auf dem BC250-Host cross-compiled werden (Pi Zero 2 W hat zu wenig RAM für native Compilation).

```bash
cd ~/Dokumente/hud/repo/hudc

# Builder-Image einmalig bauen (falls noch nicht vorhanden):
podman build -t hudc-builder .

# Cross-compile für arm64:
podman run --platform linux/arm64 --rm \
  -v "$(pwd)":/src:z \
  -v /tmp/hudc-build:/build:z \
  localhost/hudc-builder

# → hudc_new liegt danach in repo/hudc/
# Dann ins Release-Paket kopieren:
cp repo/hudc/hudc_new Release/hud/hudc_new
```

---

## Kernel-Details

### Warum Custom Kernel?

Der Standard-Raspberry Pi Kernel enthält einen Bug im vc4 DRM-Treiber:

Der `hangcheck.timer` ruft bei einem GPU-Timeout `vc4_cancel_bin_job()` auf. Diese Funktion verschiebt den hängenden Job zurück in die Queue, **signalisiert aber den DMA-Fence nicht**. Jeder Prozess der auf diesen Fence wartet (z.B. cages `drmModeAtomicCommit`) geht in den `TASK_UNINTERRUPTIBLE`-Zustand — immun gegen SIGKILL. Der DRM-Mutex bleibt gehalten. Der Pi ist dauerhaft blockiert und nur durch Hard-Reset rettbar.

### Fix: drm-scheduler

Der Custom Kernel (`6.18.6-drm-sched-v8+`) basiert auf dem Branch `vc4/downstream/drm-scheduler` von Maíra Canal (Igalia). Er ersetzt vc4's proprietäres Job-Queuing (`bin_job_list`, `render_job_list`, `hangcheck.timer`) durch das Standard-DRM-Scheduler-Framework (`drm_sched`).

Bei einem Job-Timeout werden alle wartenden Fences mit einem Fehler signalisiert → kein D-State möglich → kein permanenter Deadlock.

### Kernel bauen

```bash
cd repo/kernel

# Container-Image bauen:
podman build -t kernel-builder .

# Kernel bauen (lädt automatisch Config vom Pi):
bash build.sh

# Kernel deployen:
bash deploy.sh
```

---

## Service-Management (Pi)

```bash
# Status HUD-Service
systemctl status hudcw.service

# Neustart
sudo systemctl restart hudcw.service

# Logs live
journalctl -u hudcw.service -f

# Fallback auf EGLFS (Notfall)
sudo systemctl stop hudcw.service
sudo systemctl start hudc.service
```

## Service-Management (BC250 Host)

```bash
# Daemon Status
systemctl status bc250_daemon.service

# Daemon Logs live
journalctl -u bc250_daemon.service -f

# Daemon neu starten
sudo systemctl restart bc250_daemon.service
```

---

## Netzwerk

| | IP | Interface |
|---|---|---|
| **Host (BC250)** | `10.10.5.1/30` | `enp0s19f2u1u1` (USB-Gadget, cdc_ether) |
| **Pi** | `10.10.5.2` | `usb0` (dwc2 USB-Gadget) |

```bash
# SSH-Zugang zum Pi
sshpass -p raspberry ssh pi@10.10.5.2

# Pi erreichbar?
ping -c1 10.10.5.2
```

---

## HUD State Machine

```
[Pi boot]
    │
    ▼
initialising ──(Power Pin HIGH)──► booting ──(Daemon verbunden)──► running ⇄ gaming
    │                                                                  │
    │ (4s, Power Pin noch LOW)                                    standby
    ▼
  Backlight 0%

Jeder State + Power Pin LOW ──► shutdown
```

### Backlight-Helligkeiten

| State | Helligkeit |
|---|---|
| `running`, `gaming` | 100% |
| `booting`, `standby`, `disconnected`, `restarting` | 60% |
| `shutdown` | 0% |
| `initialising` | kein Fade (bleibt bei 0%) |

---

## GPIO-Pinbelegung (Pi)

| GPIO | Funktion |
|---|---|
| GPIO18 | Backlight PWM (Hardware-PWM via pigpio, 1kHz) |
| GPIO26 | Power-Signal vom BC250 (Input, PUD_DOWN; HIGH = BC250 läuft) |
