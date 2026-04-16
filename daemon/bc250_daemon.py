#!/usr/bin/env python3
"""
bc250_daemon.py — BC250 HUD Host-Daemon

Sammelt Systemmetriken und sendet sie per TCP an den Pi (10.10.5.2:5555).

Threads:
  SysfsCollector  (500 ms)  — sysfs + psutil → shared dict
  MangoHudReader  (FIFO)    — /tmp/mangohud_hud.fifo → fps-Daten
  SteamWatcher    (500 ms)  — gameprocess_log → Spielstart/-ende
  TCPSender       (100 ms)  — JSON-Pakete → Pi

Verwendung:
  python3 bc250_daemon.py          # normaler Betrieb
  python3 bc250_daemon.py --print  # Ausgabe auf stdout statt Pi
"""

import argparse
import base64
import collections
import json
import math
import os
import re
import signal
import socket
import sys
import threading
import time
from pathlib import Path

import psutil
from PIL import Image
import io

# ─── Konfiguration ────────────────────────────────────────────────────────────

PI_HOST    = "10.10.5.2"
PI_PORT    = 5555
SEND_INTERVAL_IDLE   = 0.200   # 5 Hz  — Sysfs aktualisiert nur alle 500 ms
SEND_INTERVAL_GAMING = 0.100   # 10 Hz — fps/frametime braucht schnelles Update
SYSFS_INTERVAL = 0.500
STEAM_INTERVAL = 0.500

MANGOHUD_OUT   = Path.home() / ".local/share/MangoHud/logs"
GAMEPROCESS_LOG = Path.home() / ".local/share/Steam/logs/gameprocess_log.txt"
STEAMAPPS_DIR   = Path.home() / ".local/share/Steam/steamapps"
LIBRARYCACHE    = Path.home() / ".local/share/Steam/appcache/librarycache"

# USB-Gadget-Interface zum Pi — ausschließen bei IP-Erkennung
GADGET_PREFIX = "10.10.5."

# FPS rolling window (600 Samples = 120s bei 5 Hz)
FPS_WINDOW_SIZE = 600

# ─── Hilfsfunktionen ──────────────────────────────────────────────────────────

def _find_hwmon(name: str) -> Path | None:
    """Findet hwmon-Verzeichnis anhand der 'name'-Datei."""
    base = Path("/sys/class/hwmon")
    if not base.exists():
        return None
    for d in base.iterdir():
        try:
            if (d / "name").read_text().strip() == name:
                return d
        except OSError:
            pass
    return None


def _read_sysfs_int(path: str | Path) -> int | None:
    try:
        return int(Path(path).read_text().strip())
    except (OSError, ValueError):
        return None


def _find_amdgpu_drm() -> Path | None:
    """Findet DRM-Geräteverzeichnis für amdgpu (gpu_busy_percent)."""
    drm = Path("/sys/class/drm")
    if not drm.exists():
        return None
    for card in sorted(drm.iterdir()):
        driver_link = card / "device" / "driver"
        try:
            if "amdgpu" in os.readlink(str(driver_link)):
                dev = card / "device"
                if (dev / "gpu_busy_percent").exists():
                    return dev
        except OSError:
            pass
    return None


def _local_ip() -> str:
    """Gibt die primäre lokale IP zurück (kein Loopback, kein USB-Gadget)."""
    for iface, addrs in psutil.net_if_addrs().items():
        for addr in addrs:
            if addr.family == socket.AF_INET:
                ip = addr.address
                if not ip.startswith("127.") and not ip.startswith(GADGET_PREFIX):
                    return ip
    return "0.0.0.0"


def _percentile(sorted_data: list[float], pct: float) -> float:
    if not sorted_data:
        return 0.0
    idx = max(0, int(len(sorted_data) * pct / 100.0) - 1)
    return sorted_data[idx]


# ─── SysfsCollector ───────────────────────────────────────────────────────────

class SysfsCollector(threading.Thread):
    """Liest alle Sysfs-Sensoren und psutil-Daten alle 500 ms."""

    def __init__(self, shared: dict, lock: threading.Lock):
        super().__init__(daemon=True, name="SysfsCollector")
        self._shared = shared
        self._lock   = lock
        self._hwmon_k10temp  = None
        self._hwmon_amdgpu   = None
        self._drm_amdgpu     = None
        self._disk_prev      = None
        self._disk_prev_time = None
        self._net_prev       = None
        self._net_prev_time  = None

    def run(self):
        # hwmon-Pfade einmalig ermitteln (können sich nach Modulneuladen ändern → retry)
        self._init_hwmon()
        while True:
            try:
                self._collect()
            except Exception as e:
                print(f"[SYSFS] Fehler: {e}")
            time.sleep(SYSFS_INTERVAL)

    def _init_hwmon(self):
        self._hwmon_k10temp = _find_hwmon("k10temp")
        self._hwmon_amdgpu  = _find_hwmon("amdgpu")
        self._drm_amdgpu    = _find_amdgpu_drm()

    def _collect(self):
        # CPU (psutil)
        cpu_pct   = psutil.cpu_percent(interval=None)
        cpu_cores = psutil.cpu_percent(interval=None, percpu=True)
        # Zen 2 SMT: 12 Logical → 6 Cores; je 2 logische Threads → Mittelwert
        cores6 = []
        for i in range(6):
            idx = i * 2
            if idx + 1 < len(cpu_cores):
                cores6.append((cpu_cores[idx] + cpu_cores[idx + 1]) / 2)
            elif idx < len(cpu_cores):
                cores6.append(cpu_cores[idx])
            else:
                cores6.append(0.0)

        cpu_freq = psutil.cpu_freq()
        cpu_freq_mhz = cpu_freq.current if cpu_freq else 0.0

        # CPU Temp (k10temp Tctl)
        cpu_temp = 0.0
        if self._hwmon_k10temp:
            v = _read_sysfs_int(self._hwmon_k10temp / "temp1_input")
            if v is not None:
                cpu_temp = v / 1000.0
        else:
            self._hwmon_k10temp = _find_hwmon("k10temp")

        # GPU
        gpu_pct  = 0.0
        gpu_temp = 0.0
        gpu_freq = 0.0
        gpu_power = 0.0
        vram_used  = 0.0
        vram_total = 0.0
        gpu_ok = False

        if self._hwmon_amdgpu:
            v = _read_sysfs_int(self._hwmon_amdgpu / "temp1_input")
            if v is not None:
                gpu_temp = v / 1000.0
                gpu_ok = True
            v = _read_sysfs_int(self._hwmon_amdgpu / "freq1_input")
            if v is not None:
                gpu_freq = v / 1e6
            v = _read_sysfs_int(self._hwmon_amdgpu / "power1_input")
            if v is not None:
                gpu_power = v / 1e6
        else:
            self._hwmon_amdgpu = _find_hwmon("amdgpu")

        if self._drm_amdgpu:
            v = _read_sysfs_int(self._drm_amdgpu / "gpu_busy_percent")
            if v is not None:
                gpu_pct = float(v)
            vu = _read_sysfs_int(self._drm_amdgpu / "mem_info_gtt_used")
            vt = _read_sysfs_int(self._drm_amdgpu / "mem_info_gtt_total")
            if vu is not None:
                vram_used  = vu / 1e9
            if vt is not None:
                vram_total = vt / 1e9
        else:
            self._drm_amdgpu = _find_amdgpu_drm()

        # RAM
        vm = psutil.virtual_memory()
        ram_pct   = vm.percent
        ram_used  = vm.used  / 1e9
        ram_total = vm.total / 1e9

        # Swap
        sw = psutil.swap_memory()
        swap_pct   = sw.percent
        swap_used  = sw.used  / 1e9
        swap_total = sw.total / 1e9

        # Storage (Haupt-Partition)
        # Bazzite/Silverblue: root ist overlayfs, psutil.disk_usage("/") kann 0 liefern.
        # Fallback-Kette: /var (beschreibbar, echte Partition) → /home → /
        stor_pct = stor_used = stor_total = 0.0
        for _stor_path in ("/var", "/home", "/"):
            try:
                du = psutil.disk_usage(_stor_path)
                if du.total > 1e9:   # min. 1 GB → echte Partition
                    stor_pct   = du.percent
                    stor_used  = du.used  / 1e9
                    stor_total = du.total / 1e9
                    break
            except OSError:
                continue

        # Disk I/O (Rate)
        disk_read_mbps = disk_write_mbps = 0.0
        try:
            dio = psutil.disk_io_counters()
            now = time.monotonic()
            if dio and self._disk_prev is not None:
                dt = now - self._disk_prev_time
                if dt > 0:
                    disk_read_mbps  = (dio.read_bytes  - self._disk_prev.read_bytes)  / dt / 1e6
                    disk_write_mbps = (dio.write_bytes - self._disk_prev.write_bytes) / dt / 1e6
            self._disk_prev      = dio
            self._disk_prev_time = now
        except Exception:
            pass

        # Netzwerk I/O (Rate, ohne Gadget-Interface)
        net_rx_mbps = net_tx_mbps = 0.0
        try:
            nio_all = psutil.net_io_counters(pernic=True)
            # Summiere alle Interfaces außer loopback und Gadget
            rx_bytes = tx_bytes = 0
            for iface, c in nio_all.items():
                addrs = psutil.net_if_addrs().get(iface, [])
                ip = next((a.address for a in addrs
                           if hasattr(a, 'family') and a.family == socket.AF_INET), "")
                if ip.startswith("127.") or ip.startswith(GADGET_PREFIX):
                    continue
                rx_bytes += c.bytes_recv
                tx_bytes += c.bytes_sent
            now = time.monotonic()
            if self._net_prev is not None:
                dt = now - self._net_prev_time
                if dt > 0:
                    net_rx_mbps = (rx_bytes - self._net_prev[0]) / dt / 1e6
                    net_tx_mbps = (tx_bytes - self._net_prev[1]) / dt / 1e6
            self._net_prev      = (rx_bytes, tx_bytes)
            self._net_prev_time = now
        except Exception:
            pass

        # Uptime
        uptime = int(time.monotonic() - psutil.boot_time() + psutil.boot_time() - psutil.boot_time())
        uptime = int(time.time() - psutil.boot_time())

        with self._lock:
            self._shared.update({
                "cpu_percent":        round(cpu_pct, 1),
                "cpu_core_pct":       [round(c, 1) for c in cores6],
                "cpu_temp":           round(cpu_temp, 1),
                "cpu_freq_mhz":       round(cpu_freq_mhz, 0),
                "cpu_package_w":      round(gpu_power, 1),  # PPT = kombiniert
                "gpu_percent":        round(gpu_pct, 1),
                "gpu_temp":           round(gpu_temp, 1),
                "gpu_freq_mhz":       round(gpu_freq, 0),
                "gpu_power_w":        round(gpu_power, 1),
                "gpu_available":      gpu_ok,
                "vram_used_gb":       round(vram_used,  2),
                "vram_total_gb":      round(vram_total, 2),
                "ram_percent":        round(ram_pct,  1),
                "ram_used_gb":        round(ram_used,  2),
                "ram_total_gb":       round(ram_total, 2),
                "swap_percent":       round(swap_pct,  1),
                "swap_used_gb":       round(swap_used,  2),
                "swap_total_gb":      round(swap_total, 2),
                "storage_percent":    round(stor_pct,  1),
                "storage_used_gb":    round(stor_used,  1),
                "storage_total_gb":   round(stor_total, 1),
                "disk_read_mbps":     round(max(0.0, disk_read_mbps),  2),
                "disk_write_mbps":    round(max(0.0, disk_write_mbps), 2),
                "net_rx_mbps":        round(max(0.0, net_rx_mbps),  3),
                "net_tx_mbps":        round(max(0.0, net_tx_mbps),  3),
                "net_local_ip":       _local_ip(),
                "uptime_seconds":     uptime,
                "hostname":           socket.gethostname(),
            })


# ─── MangoHudReader ───────────────────────────────────────────────────────────

class MangoHudReader(threading.Thread):
    """Liest MangoHud CSV-Output aus $HOME für fps/frametime-Metriken.

    MangoHud ignoriert output_folder/output_file innerhalb des pressure-vessel
    Containers und schreibt immer nach $HOME ({GameName}_{date}_{time}.csv).

    Spielende wird AUSSCHLIESSLICH vom SteamWatcher signalisiert (via game_appid
    im shared dict). MangoHudReader sendet nie selbst einen running-Cmd und
    bricht Gaming-Mode nicht bei Ladebildschirmen oder kurzen Freezes ab.
    """

    POLL_INTERVAL = 0.05   # s — 50ms für schnelle FPS-Aktualisierung

    def __init__(self, shared: dict, lock: threading.Lock,
                 pending_cmds: collections.deque, cmd_lock: threading.Lock):
        super().__init__(daemon=True, name="MangoHudReader")
        self._shared     = shared
        self._lock       = lock
        self._pending    = pending_cmds
        self._cmd_lock   = cmd_lock
        self._fps_window: list[float] = []
        self._cur_file:  Path | None = None
        self._file_pos   = 0
        self._col_fps    = 0
        self._col_ft     = 1
        self._header_ok  = False

    def run(self):
        MANGOHUD_OUT.mkdir(parents=True, exist_ok=True)
        self._cleanup_logs()
        while True:
            try:
                self._poll()
            except Exception as e:
                print(f"[MANGO] Fehler: {e}")
            time.sleep(self.POLL_INTERVAL)

    def _poll(self):
        # SteamWatcher ist Autorität für Spielstatus — game_appid fehlt → kein Spiel aktiv
        with self._lock:
            game_active = "game_appid" in self._shared

        if not game_active:
            # Internen Zustand zurücksetzen sobald das Spiel beendet wurde
            if self._cur_file is not None:
                self._cur_file  = None
                self._header_ok = False
                self._fps_window.clear()
                self._file_pos  = 0
            return

        now = time.time()
        # CSVs in output_folder + Fallback $HOME (output_folder wird in pressure-vessel manchmal ignoriert)
        candidates = list(MANGOHUD_OUT.glob("*.csv")) + list(Path.home().glob("*.csv"))
        csvs = [f for f in candidates
                if "_summary" not in f.name and now - f.stat().st_mtime < 60]
        if not csvs:
            return  # MangoHud schreibt noch nicht / Ladebildschirm — kein Spielende!

        newest = max(csvs, key=lambda f: f.stat().st_mtime)

        if newest != self._cur_file:
            self._cur_file  = newest
            self._header_ok = False
            self._col_fps   = 0
            self._col_ft    = 1
            # Header lesen, dann ans Ende springen — nur neue Zeilen verarbeiten
            try:
                with open(newest, "r", errors="replace") as f:
                    for line in f:
                        parts = line.strip().split(",")
                        if "fps" in parts:
                            self._col_fps   = parts.index("fps")
                            self._col_ft    = parts.index("frametime") if "frametime" in parts else self._col_fps + 1
                            self._header_ok = True
                            break
                    f.seek(0, 2)  # ans Ende
                    self._file_pos = f.tell()
            except OSError:
                self._file_pos = 0
            return  # Erst beim nächsten Poll neue Daten lesen

        if not self._header_ok:
            return

        try:
            with open(self._cur_file, "r", errors="replace") as f:
                f.seek(self._file_pos)
                lines = f.readlines()
                self._file_pos = f.tell()
        except OSError:
            return

        for line in lines:
            line = line.strip()
            if not line:
                continue
            self._parse_data(line.split(","))

    def _parse_data(self, parts: list[str]):
        try:
            fps = float(parts[self._col_fps])
            ft  = float(parts[self._col_ft])
        except (ValueError, IndexError):
            return

        self._fps_window.append(fps)
        if len(self._fps_window) > FPS_WINDOW_SIZE:
            self._fps_window.pop(0)

        sorted_fps = sorted(self._fps_window)
        n = len(sorted_fps)
        fps_1pct  = sorted_fps[max(0, int(n * 0.01) - 1)]
        fps_01pct = sorted_fps[max(0, int(n * 0.001) - 1)]

        with self._lock:
            self._shared.update({
                "fps":               round(fps, 1),
                "frametime_ms":      round(ft,  2),
                "fps_1pct_low":      round(fps_1pct,  1),
                "fps_point1pct_low": round(fps_01pct, 1),
            })

    def _cleanup_logs(self):
        for f in MANGOHUD_OUT.glob("*.csv"):
            try:
                f.unlink()
                print(f"[MANGO] Gelöscht: {f.name}")
            except OSError as e:
                print(f"[MANGO] Konnte {f.name} nicht löschen: {e}")


# ─── SteamWatcher ─────────────────────────────────────────────────────────────

class SteamWatcher(threading.Thread):
    """Überwacht gameprocess_log für Spielstart/-ende."""

    GAME_START_COOLDOWN = 15.0  # s — Proton spawnt Cleanup-Prozesse mit gleicher AppID

    def __init__(self, shared: dict, lock: threading.Lock,
                 pending_cmds: collections.deque, cmd_lock: threading.Lock):
        super().__init__(daemon=True, name="SteamWatcher")
        self._shared   = shared
        self._lock     = lock
        self._pending  = pending_cmds
        self._cmd_lock = cmd_lock
        self._file_pos = 0
        self._active_appid: int | None = None
        self._active_pids: set[int] = set()
        self._last_start: dict[int, float] = {}  # appid → monotonic time

    def run(self):
        # Dateigröße ans Ende setzen (nur neue Events interessieren)
        try:
            self._file_pos = GAMEPROCESS_LOG.stat().st_size
        except OSError:
            self._file_pos = 0

        while True:
            try:
                self._check()
            except Exception as e:
                print(f"[STEAM] Fehler: {e}")
            time.sleep(STEAM_INTERVAL)

    def _check(self):
        if not GAMEPROCESS_LOG.exists():
            return
        try:
            with open(GAMEPROCESS_LOG, "r", errors="replace") as f:
                f.seek(self._file_pos)
                new_lines = f.readlines()
                self._file_pos = f.tell()
        except OSError:
            return

        for line in new_lines:
            # Spielstart: "AppID 1623730 adding PID 12345"
            m = re.search(r"AppID (\d+) adding PID (\d+)", line)
            if m:
                appid = int(m.group(1))
                pid   = int(m.group(2))
                if appid < 10:  # Steam-interne Prozesse ignorieren
                    continue
                self._active_pids.add(pid)
                if appid != self._active_appid:
                    self._active_appid = appid
                    now = time.monotonic()
                    if now - self._last_start.get(appid, 0) >= self.GAME_START_COOLDOWN:
                        self._last_start[appid] = now
                        self._on_game_start(appid)
                continue

            # Spielende: "AppID 1623730 no longer tracking PID 12345"
            m = re.search(r"AppID (\d+) no longer tracking PID (\d+)", line)
            if m:
                pid = int(m.group(2))
                self._active_pids.discard(pid)
                if not self._active_pids and self._active_appid is not None:
                    self._active_appid = None
                    with self._lock:
                        for key in ("game_name", "game_appid",
                                    "fps", "frametime_ms",
                                    "fps_1pct_low", "fps_point1pct_low"):
                            self._shared.pop(key, None)
                    # MangoHud-Logs aufräumen
                    for f in MANGOHUD_OUT.glob("*.csv"):
                        try:
                            f.unlink()
                        except OSError:
                            pass
                    with self._cmd_lock:
                        self._pending.append({"cmd": "running"})
                    print("[STEAM] Spiel beendet → cmd: running, CSVs gelöscht")

    def _on_game_start(self, appid: int):
        # Alte MangoHud-Logs aufräumen bevor das neue Spiel beginnt
        for f in MANGOHUD_OUT.glob("*.csv"):
            try:
                f.unlink()
            except OSError:
                pass

        name = self._get_game_name(appid)
        thumb_b64 = self._get_thumbnail_b64(appid)

        print(f"[STEAM] Spiel gestartet: {name} ({appid})")

        with self._lock:
            self._shared["game_name"]  = name
            self._shared["game_appid"] = appid

        cmd = {"cmd": "gaming", "game_name": name, "game_appid": appid,
               "thumbnail_b64": thumb_b64}

        with self._cmd_lock:
            self._pending.append(cmd)

    def _get_game_name(self, appid: int) -> str:
        acf = STEAMAPPS_DIR / f"appmanifest_{appid}.acf"
        try:
            content = acf.read_text(errors="replace")
            m = re.search(r'"name"\s+"([^"]+)"', content)
            if m:
                return m.group(1)
        except OSError:
            pass
        return f"App {appid}"

    def _get_thumbnail_b64(self, appid: int) -> str:
        subdir = LIBRARYCACHE / str(appid)
        if not subdir.is_dir():
            return ""

        # Alle zu durchsuchenden Verzeichnisse: appid-Ordner + direkte Unterordner
        dirs = [subdir] + sorted(d for d in subdir.iterdir() if d.is_dir())

        # Priorität: header → library_header → erstes brauchbares Bild
        priority_names = [
            "header.jpg", "header.png",
            "library_header.jpg", "library_header.png",
        ]
        for name in priority_names:
            for d in dirs:
                p = d / name
                if p.exists():
                    try:
                        return self._resize_and_encode(p)
                    except Exception as e:
                        print(f"[STEAM] Thumbnail-Fehler {p}: {e}")

        # Fallback: erstes brauchbares Bild (jpg/png) in allen Verzeichnissen, keine Logos
        for d in dirs:
            for p in sorted(d.glob("*")):
                if p.suffix.lower() in (".jpg", ".jpeg", ".png") and "logo" not in p.name.lower():
                    try:
                        return self._resize_and_encode(p)
                    except Exception as e:
                        print(f"[STEAM] Thumbnail-Fehler {p}: {e}")

        print(f"[STEAM] Kein Thumbnail für AppID {appid} gefunden")
        return ""

    @staticmethod
    def _resize_and_encode(path: Path) -> str:
        with Image.open(path) as img:
            if img.width < 200 or img.height < 80:
                raise ValueError(f"Bild zu klein ({img.width}×{img.height}), übersprungen")
            # PNG-Transparenz auf dunklem Hintergrund
            if img.mode in ("RGBA", "LA", "P"):
                img = img.convert("RGBA")
                bg = Image.new("RGB", img.size, (15, 15, 15))
                bg.paste(img, mask=img.split()[3])
                img = bg
            else:
                img = img.convert("RGB")
            # Aspect-Ratio erhalten, max 448×220
            img.thumbnail((448, 220), Image.LANCZOS)
            buf = io.BytesIO()
            img.save(buf, format="JPEG", quality=85)
            return base64.b64encode(buf.getvalue()).decode("ascii")


# ─── TCPSender ────────────────────────────────────────────────────────────────

class TCPSender(threading.Thread):
    """Sendet JSON-Pakete an den Pi. Auto-Reconnect alle 2s."""

    def __init__(self, shared: dict, lock: threading.Lock,
                 pending_cmds: collections.deque, cmd_lock: threading.Lock,
                 print_mode: bool = False):
        super().__init__(daemon=True, name="TCPSender")
        self._shared    = shared
        self._lock      = lock
        self._pending   = pending_cmds
        self._cmd_lock  = cmd_lock
        self._print_mode = print_mode
        self._sock: socket.socket | None = None

    def run(self):
        while True:
            try:
                if not self._print_mode:
                    self._connect()
                self._send_loop()
            except Exception as e:
                print(f"[TCP] Fehler: {e}")
                if self._sock:
                    try:
                        self._sock.close()
                    except OSError:
                        pass
                    self._sock = None
                time.sleep(2.0)

    def _connect(self):
        while True:
            try:
                s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                s.settimeout(3.0)
                s.connect((PI_HOST, PI_PORT))
                s.settimeout(None)
                self._sock = s
                print(f"[TCP] Verbunden mit {PI_HOST}:{PI_PORT}")
                return
            except OSError as e:
                print(f"[TCP] Verbindung fehlgeschlagen: {e} — Retry in 2s")
                time.sleep(2.0)

    def _send_loop(self):
        while True:
            # Zuerst ausstehende Cmds senden (z.B. gaming-cmd vor fps-Daten)
            with self._cmd_lock:
                while self._pending:
                    cmd = self._pending.popleft()
                    self._send(cmd)

            # Daten-Paket senden
            with self._lock:
                data = dict(self._shared)
                gaming = "game_appid" in data  # SteamWatcher ist Autorität; fps fehlt bei Ladebildschirmen
            # Explizites gaming-Flag in jedem Paket: Pi erkennt Spielstatus ohne
            # auf fps-Feld-Präsenz angewiesen zu sein; ermöglicht 5s Auto-Stop-Timer.
            data["gaming"] = gaming
            self._send(data)

            # Im Gaming-Mode fps-Daten schnell senden, sonst reicht 5 Hz
            interval = SEND_INTERVAL_GAMING if gaming else SEND_INTERVAL_IDLE
            time.sleep(interval)

    def _send(self, obj: dict):
        line = json.dumps(obj, separators=(",", ":")) + "\n"
        if self._print_mode:
            print(line, end="", flush=True)
            return
        try:
            self._sock.sendall(line.encode("utf-8"))
        except OSError:
            raise


# ─── Main ─────────────────────────────────────────────────────────────────────

def _get_shutdown_type() -> str:
    """Erkennt anhand von systemd ob ein Reboot oder Shutdown geplant ist."""
    try:
        content = Path("/run/systemd/shutdown/scheduled").read_text()
        if "WHAT=reboot" in content or "WHAT=soft-reboot" in content:
            return "restart"
    except OSError:
        pass
    return "shutdown"


def _send_cmd_direct(cmd: str) -> None:
    """Sendet einen Befehl direkt an den Pi (neue TCP-Verbindung, kein Thread)."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(1.5)
        s.connect((PI_HOST, PI_PORT))
        s.sendall((json.dumps({"cmd": cmd}, separators=(",", ":")) + "\n").encode("utf-8"))
        time.sleep(0.3)  # kurz warten damit der Pi den Packet vollständig empfängt
        s.close()
        print(f"[DAEMON] SIGTERM: cmd '{cmd}' gesendet")
    except Exception as e:
        print(f"[DAEMON] SIGTERM: Konnte cmd '{cmd}' nicht senden: {e}")


def _sigterm_handler(signum, frame):
    """SIGTERM-Handler: sendet shutdown/restart nur bei echtem System-Shutdown/-Reboot.
    Bei Service-Restart (systemctl restart) kommt SIGTERM ohne geplanten Shutdown
    → kein Kommando senden, Pi bleibt im aktuellen Zustand."""
    shutdown_file = Path("/run/systemd/shutdown/scheduled")
    if not shutdown_file.exists():
        print("[DAEMON] SIGTERM empfangen (Service-Restart) → kein Cmd an Pi")
        sys.exit(0)
    cmd = _get_shutdown_type()
    print(f"[DAEMON] SIGTERM empfangen → sende '{cmd}'")
    _send_cmd_direct(cmd)
    sys.exit(0)


def main():
    parser = argparse.ArgumentParser(description="BC250 HUD Host-Daemon")
    parser.add_argument("--print", action="store_true",
                        help="JSON auf stdout ausgeben statt an Pi senden")
    args = parser.parse_args()

    # SIGTERM-Handler registrieren (systemd sendet SIGTERM bei stop/shutdown/reboot)
    signal.signal(signal.SIGTERM, _sigterm_handler)

    shared   = {}
    lock     = threading.Lock()
    pending  = collections.deque()
    cmd_lock = threading.Lock()

    threads = [
        SysfsCollector(shared, lock),
        MangoHudReader(shared, lock, pending, cmd_lock),
        SteamWatcher(shared, lock, pending, cmd_lock),
        TCPSender(shared, lock, pending, cmd_lock, print_mode=args.print),
    ]

    for t in threads:
        t.start()

    print(f"[DAEMON] BC250 HUD Daemon gestartet — Ziel: {PI_HOST}:{PI_PORT}")
    try:
        for t in threads:
            t.join()
    except KeyboardInterrupt:
        print("\n[DAEMON] Beendet durch Benutzer")


if __name__ == "__main__":
    main()
