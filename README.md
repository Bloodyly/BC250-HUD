# BC250 HUD

A system monitor HUD running on a Raspberry Pi Zero 2 W connected to a gaming PC (BC250) via USB Gadget Ethernet. Displays CPU, GPU, RAM, network stats and system state on a 480×1920 portrait HDMI display.

---

## Hardware

| Component | Details |
|---|---|
| Display controller | Raspberry Pi Zero 2 W |
| Host PC | BC250 (Bazzite Linux / Fedora) |
| Display | 480×1920 px, portrait, HDMI |
| Connection | USB Gadget Ethernet — Pi: `10.10.5.2`, Host: `10.10.5.1` |
| Backlight | GPIO18 (Hardware PWM via pigpio, 1 kHz) |
| Power signal | GPIO26 (Input, PUD_DOWN) — HIGH = host running |

---

## Repository Structure

```
repo/
├── hudc/                     Qt Quick HUD application (C++ + QML)
│   ├── src/                  C++ source (model, daemon receiver, backlight, health)
│   ├── hud.qml               UI definition — edit this for visual changes
│   ├── CMakeLists.txt        Build system
│   ├── Containerfile.builder Podman cross-compile container (arm64)
│   ├── hudcw.service         Active systemd service (cage/Wayland)
│   └── hudc.service          Fallback service (EGLFS, emergency only)
│
├── daemon/                   Host-side daemon (runs on BC250)
│   ├── bc250_daemon.py       Collects metrics, sends to Pi via TCP 5555
│   ├── bc250_daemon.service  systemd unit
│   └── bc250-sleep-hook.sh   Sends standby/wake commands on system sleep
│
├── kernel/                   Custom kernel build (vc4 drm-scheduler fix)
│   ├── build.sh              Clone + cross-compile kernel in Podman container
│   ├── Containerfile         Builder container definition
│   ├── deploy.sh             Flash compiled kernel to Pi
│   ├── pi-running.config     Kernel .config from the running Pi
│   └── PATCH.md              Details on the drm-scheduler patch
│
├── config/                   Pi configuration reference files
│   ├── config.txt            /boot/firmware/config.txt
│   ├── journald.conf         Limits journal size on the Pi SD card
│   └── kms.json              KMS config for EGLFS fallback (hudc.service)
│
├── system/                   Host-side udev rules
│   └── 70-pi-usb.rules       Gives the USB gadget NIC a stable name (pi-usb)
│
└── Release/                  Ready-to-deploy package (see Release/README.md)
    ├── install.sh            Full Pi installation from scratch
    ├── host-setup.sh         BC250 host configuration
    ├── deploy.sh             One-command deploy from BC250 to Pi
    ├── kernel/               Prebuilt kernel (Git LFS)
    ├── dtbs/                 Device tree blobs (Git LFS)
    ├── hud/                  Prebuilt HUD binary + QML + services (Git LFS)
    ├── daemon/               Daemon files
    ├── config/               Config files (config.txt, udev rules, etc.)
    └── src/                  Source snapshot for reference
```

---

## Quick Start

### Fresh Pi Installation

```bash
# From the BC250 host, with Pi booted and connected via USB:
cd Release/
bash deploy.sh
```

This runs `install.sh` on the Pi and configures the host automatically.

### Update HUD Only (no kernel reinstall)

```bash
cd Release/
bash deploy.sh --update-only
```

### Host Setup Only

```bash
cd Release/
bash host-setup.sh
```

---

## The QML UI File

All visual output is defined in a single file: **`hudc/hud.qml`** (on the Pi: `/home/pi/hudc/hud.qml`).

This is a [Qt Quick](https://doc.qt.io/qt-6/qtquick-index.html) file — a declarative UI language. It describes the layout, animations, colours and data bindings of the HUD. No C++ knowledge is needed to change colours, font sizes, labels, panel positions or animations.

The C++ binary (`hudc_new`) watches this file and **automatically reloads it every 5 seconds** after a change is detected — no service restart needed. Changes appear on the display within seconds of saving.

### Live-Editing via SSH

```bash
# Connect to Pi
ssh pi@10.10.5.2          # password: raspberry

# Edit the UI file directly
nano /home/pi/hudc/hud.qml
```

Save with `Ctrl+O`, exit with `Ctrl+X`. The HUD updates itself on the next 5-second poll cycle.

For larger edits, edit locally and push to the Pi:

```bash
# Edit locally, then deploy (no restart needed)
sshpass -p raspberry scp hudc/hud.qml pi@10.10.5.2:/home/pi/hudc/hud.qml
```

---

## Adapting to a Different Display

Three things need to match for a different display: the HDMI signal, the Qt window size, and the layout.

### 1. HDMI Mode — `/boot/firmware/config.txt`

The relevant lines (see [config/config.txt](config/config.txt)):

```ini
hdmi_group=2
hdmi_mode=87
hdmi_cvt=1920 480 60 6 0 0 0   # W H fps aspect
hdmi_force_hotplug=1
```

`hdmi_cvt` format: `<width> <height> <refresh> <aspect> <margins> <interlace> <rb>`

Common values:

| Display | hdmi_cvt line |
|---|---|
| 480×1920 portrait (current) | `hdmi_cvt=1920 480 60 6 0 0 0` |
| 1920×480 landscape | `hdmi_cvt=1920 480 60 6 0 0 0` (same signal, layout differs) |
| 720×1280 portrait | `hdmi_cvt=1280 720 60 6 0 0 0` |
| 1080×1920 portrait | `hdmi_cvt=1920 1080 60 6 0 0 0` |
| 800×480 landscape | `hdmi_cvt=800 480 60 6 0 0 0` |

> Note: `hdmi_cvt` always takes **width first, then height** — regardless of physical orientation. After editing, copy to Pi and reboot:
> ```bash
> sshpass -p raspberry scp config/config.txt pi@10.10.5.2:/boot/firmware/config.txt
> sshpass -p raspberry ssh pi@10.10.5.2 'sudo reboot'
> ```

### 2. Qt Window Size — `hud.qml`

At the top of `hud.qml`, the window dimensions must match the display resolution:

```qml
Window {
    id: root
    width:  480    // ← physical pixel width of your display
    height: 1920   // ← physical pixel height of your display
    ...
}
```

Change both values to match your display, then save. The hot-reload will pick it up within 5 seconds, or restart the service for an immediate effect.

### 3. Layout

The current layout is designed for a tall portrait panel (480×1920). Most elements use `root.width` and `root.height` for positioning so they scale with the window, but the panel arrangement is inherently vertical.

For a **different portrait resolution** (e.g. 720×1280): update width/height as above, then tweak font sizes and panel heights to taste — the overall structure stays the same.

For a **landscape orientation** (e.g. 1920×480 or 800×480): the panel order needs to change from vertical stacking to horizontal. This requires rearranging the main panels (`panelCPU`, `gpuGauge`, `ramPanel`, `timePanel`) from top-to-bottom to left-to-right in the QML.

For a **display without PWM backlight control**: the backlight GPIO calls in `backlightcontroller.cpp` can be disabled, or pigpiod can simply be left running harmlessly.

---

## Architecture

### Display Stack

```
hudcw.service
  └─ cage (Wayland compositor)
       └─ hudc_new (Qt Quick app, QT_QPA_PLATFORM=wayland)
            └─ hud.qml (UI)
```

**Why cage/Wayland instead of direct EGLFS?**
The vc4 DRM driver has a race in its custom job queue: when the hangcheck timer fires during a bin job, `vc4_cancel_bin_job()` fails to signal the DMA fence. The atomic commit waiter in cage (`drmModeAtomicCommit`) then enters `TASK_UNINTERRUPTIBLE` waiting for that fence and becomes immune to SIGKILL, permanently blocking the display pipeline.

The fix is the custom kernel below. Additionally, routing rendering through cage/Wayland avoids direct vc4 DRM fence exposure from Qt's render thread, which provides additional isolation.

### State Machine

```
off → booting (GPIO26 HIGH) → idle (daemon connected) ↔ gaming (auto, 5 s timeout)
 ↑                                    ↓ (5 s delay)
 └───────── shutdown (GPIO26 LOW) ← disconnected
                                      ↑
                                   standby (cmd)
```

| State | Backlight | Trigger |
|---|---|---|
| `off` | 0% | Startup / after shutdown |
| `booting` | 60% | GPIO26 HIGH |
| `idle` | 100% | Daemon connected |
| `gaming` | 100% | `gaming:true` in data packet |
| `disconnected` | 60% | 5 s after daemon disconnect |
| `standby` | 30% | `{"cmd":"standby"}` |
| `shutdown` | 0% | GPIO26 LOW or `{"cmd":"shutdown"}` |

### Daemon Protocol

TCP port 5555, newline-delimited JSON, 10 Hz:

```json
{
  "cpu_percent": 42.0, "cpu_temp": 61.5,
  "gpu_percent": 58.0, "gpu_temp": 72.1,
  "gpu_available": true,
  "ram_percent": 61.4, "ram_used_gb": 20.9, "ram_total_gb": 34.0,
  "storage_percent": 57.0, "storage_used_gb": 292.0, "storage_total_gb": 512.0,
  "net_rx_mbps": 0.5, "net_tx_mbps": 0.1, "net_local_ip": "192.168.x.x",
  "uptime_seconds": 7320,
  "hostname": "BC250",
  "gaming": false
}
```

Commands: `{"cmd": "standby"}` · `{"cmd": "wake"}` · `{"cmd": "gaming"}` · `{"cmd": "running"}` · `{"cmd": "restart"}` · `{"cmd": "shutdown"}`

---

## Building

### HUD Binary (cross-compile for arm64)

```bash
# Build cross-compile container (once)
podman build -t hudc-builder -f hudc/Containerfile.builder .

# Cross-compile
podman run --rm --platform linux/arm64 \
  -v "$(pwd)/hudc:/src" \
  -v "$(pwd)/hudc/build_output:/out" \
  hudc-builder

# Deploy binary and QML
sshpass -p raspberry scp hudc/build_output/hudc_new pi@10.10.5.2:/home/pi/hudc/hudc_new
sshpass -p raspberry scp hudc/hud.qml pi@10.10.5.2:/home/pi/hudc/hud.qml
sshpass -p raspberry ssh pi@10.10.5.2 'sudo systemctl restart hudcw.service'
```

### QML Only (no recompile, no restart needed)

The binary watches `hud.qml` and reloads it automatically within 5 seconds of a change.

```bash
sshpass -p raspberry scp hudc/hud.qml pi@10.10.5.2:/home/pi/hudc/hud.qml
# HUD updates itself — no restart required
```

Force an immediate reload (optional):
```bash
sshpass -p raspberry ssh pi@10.10.5.2 'sudo systemctl restart hudcw.service'
```

### Custom Kernel

See [kernel/PATCH.md](kernel/PATCH.md) and [kernel/build.sh](kernel/build.sh).

```bash
cd kernel/
bash build.sh          # clone + compile (takes ~15 min)
bash deploy.sh         # flash to Pi + reboot
```

---

## Pi Service Management

```bash
# Status
systemctl status hudcw.service

# Restart
sudo systemctl restart hudcw.service

# Live logs
journalctl -u hudcw.service -f

# Emergency fallback (EGLFS, no cage)
sudo systemctl stop hudcw.service
sudo systemctl start hudc.service
```

## Host Daemon Management

```bash
systemctl status bc250_daemon.service
journalctl -u bc250_daemon.service -f
sudo systemctl restart bc250_daemon.service
```

---

## Pi System Image (Release Asset)

The prebuilt system image is available as a GitHub Release asset.

**Image specs:** Raspberry Pi Zero 2 W, Raspberry Pi OS Lite (arm64), kernel 6.18.6-drm-sched-v8+, all services pre-configured.

### Creating a New Image

```bash
# 1. Power off Pi cleanly
sshpass -p raspberry ssh pi@10.10.5.2 'sudo poweroff'

# 2. Remove SD card, image it on another machine
sudo dd if=/dev/sdX of=pi-hud-raw.img bs=4M status=progress

# 3. Shrink with PiShrink
wget https://raw.githubusercontent.com/Drewsif/PiShrink/master/pishrink.sh
sudo bash pishrink.sh -a pi-hud-raw.img pi-hud.img

# 4. Compress
xz -T0 -9 pi-hud.img
# Result: ~1.2 GB, upload as GitHub Release asset
```

### Flashing the Image

```bash
# Linux
xzcat pi-hud.img.xz | sudo dd of=/dev/sdX bs=4M status=progress

# Or use Raspberry Pi Imager with the .img.xz file directly
```

---

## Pi Hardware Configuration

Custom HDMI mode (480×1920 portrait), USB Gadget, vc4-kms-v3d, 1.2 GHz overclock — see [config/config.txt](config/config.txt).

GPIO:
- **GPIO18** — Backlight PWM (Hardware PWM0, pigpiod, 1 kHz, 0–1,000,000 duty)
- **GPIO26** — Power signal from host (Input, PUD_DOWN; HIGH = host on)
