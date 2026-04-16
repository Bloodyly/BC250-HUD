#include "hudmodel.h"

HudModel::HudModel(QObject *parent)
    : QObject(parent)
{}

// ── Helpers ──────────────────────────────────────────────────────────────────

double HudModel::ema(double old, double val, double alpha)
{
    return old + alpha * (val - old);
}

void HudModel::pushHist(QVector<double> &hist, double val, int maxLen)
{
    hist.append(val);
    if (hist.size() > maxLen)
        hist.removeFirst();
}

// ── Data update ───────────────────────────────────────────────────────────────

void HudModel::applySimData(const SimData &d)
{
    constexpr double a = EMA_FAST;

    // ── Basis ─────────────────────────────────────────────────────────────
    _cpu      = ema(_cpu,      d.cpu,     a);
    _cpuTemp  = ema(_cpuTemp,  d.cpuTemp, a);
    _gpu      = ema(_gpu,      d.gpu,     a);
    _gpuTemp  = ema(_gpuTemp,  d.gpuTemp, a);
    _gpuOk    = d.gpuAvailable;
    _ram      = ema(_ram,      d.ram,     a);
    _ramUsed  = d.ramUsedGb;
    _ramTotal = d.ramTotalGb;
    _storage  = ema(_storage,  d.storage, a);
    _storUsed  = d.storageUsedGb;
    _storTotal = d.storageTotalGb;
    _uptime   = d.uptimeSeconds;
    _hostname = d.hostname;

    pushHist(_cpuHist,  _cpu);
    pushHist(_gpuHist,  _gpu);
    pushHist(_loadHist, (_cpu + _gpu) / 2.0);

    // ── CPU erweitert ─────────────────────────────────────────────────────
    for (int i = 0; i < 6; ++i)
        _cpuCorePct[i] = ema(_cpuCorePct[i], d.cpuCorePct[i], a);
    _cpuFreqMhz  = ema(_cpuFreqMhz,  d.cpuFreqMhz,  a);
    _cpuPackageW = ema(_cpuPackageW, d.cpuPackageW, a);

    // ── GPU erweitert ─────────────────────────────────────────────────────
    _gpuFreqMhz = ema(_gpuFreqMhz, d.gpuFreqMhz, a);
    _gpuPowerW  = ema(_gpuPowerW,  d.gpuPowerW,  a);

    // ── VRAM (direkt, kein EMA) ───────────────────────────────────────────
    _vramUsed  = d.vramUsedGb;
    _vramTotal = d.vramTotalGb;

    // ── Swap ──────────────────────────────────────────────────────────────
    _swapPct   = ema(_swapPct, d.swapPercent, a);
    _swapUsed  = d.swapUsedGb;
    _swapTotal = d.swapTotalGb;

    // ── Disk I/O ─────────────────────────────────────────────────────────
    _diskRead  = ema(_diskRead,  d.diskReadMbps,  a);
    _diskWrite = ema(_diskWrite, d.diskWriteMbps, a);

    // ── Netzwerk ─────────────────────────────────────────────────────────
    _netRx = ema(_netRx, d.netRxMbps, a);
    _netTx = ema(_netTx, d.netTxMbps, a);
    _netIp = d.netLocalIp;

    // ── Gaming ───────────────────────────────────────────────────────────
    _gaming   = d.gaming;
    _gameName = d.gameName;
    _gameAppId = d.gameAppId;
    _fps1Pct  = d.fps1PctLow;
    _fps01Pct = d.fpsPoint1PctLow;

    if (_gaming) {
        _fps         = ema(_fps,         d.fps,         0.5);  // leichte Glättung, schnelle Reaktion
        _frametimeMs = ema(_frametimeMs, d.frametimeMs, 0.5);
    } else {
        _fps         = 0;
        _frametimeMs = 0;
    }

    // Thumbnail aktualisieren wenn Key explizit im Paket war (cmd-Paket beim Spielstart).
    // Leerer Wert = Spiel hat kein lokales Artwork → altes Bild löschen.
    if (d.hasThumbnail)
        _thumbnailB64 = d.thumbnailB64;

    emit changed();
}

// ── State ─────────────────────────────────────────────────────────────────────

void HudModel::setAppState(const QString &state)
{
    if (_appState == state)
        return;
    qDebug("[HUD] State: %s → %s",
           qPrintable(_appState), qPrintable(state));
    _appState = state;
    emit changed();
    emit appStateChanged(state);
}

void HudModel::setConnected(bool c)
{
    if (_connected == c)
        return;
    _connected = c;
    emit connectedChanged(c);
    emit changed();
}

// ── Backlight ─────────────────────────────────────────────────────────────────

void HudModel::setBacklightLevel(double level)
{
    // Klemme auf [0.1, 1.0] — Minimum damit Display nicht komplett dunkel wird
    level = qBound(0.1, level, 1.0);
    if (qFuzzyCompare(_backlightLevel, level))
        return;
    _backlightLevel = level;
    emit backlightLevelChanged(level);
    emit backlightRequested(level, 400);
}

// ── History / array getters ───────────────────────────────────────────────────

QVariantList HudModel::cpuHistory() const
{
    QVariantList out;
    out.reserve(_cpuHist.size());
    for (double v : _cpuHist) out.append(v);
    return out;
}

QVariantList HudModel::gpuHistory() const
{
    QVariantList out;
    out.reserve(_gpuHist.size());
    for (double v : _gpuHist) out.append(v);
    return out;
}

QVariantList HudModel::loadHistory() const
{
    QVariantList out;
    out.reserve(_loadHist.size());
    for (double v : _loadHist) out.append(v);
    return out;
}

QVariantList HudModel::cpuCorePct() const
{
    QVariantList out;
    out.reserve(6);
    for (double v : _cpuCorePct) out.append(v);
    return out;
}
