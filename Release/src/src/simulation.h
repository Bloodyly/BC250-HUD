#pragma once

#include <QString>
#include <array>
#include <random>
#include <cmath>

struct SimData {
    // ── Basis ──────────────────────────────────────────────────────────────
    double cpu, cpuTemp;
    double gpu, gpuTemp;
    bool   gpuAvailable;
    double ram, ramUsedGb, ramTotalGb;
    double storage, storageUsedGb, storageTotalGb;
    int    uptimeSeconds;
    QString hostname;

    // ── CPU erweitert ──────────────────────────────────────────────────────
    std::array<double, 6> cpuCorePct = {};
    double cpuFreqMhz  = 0;
    double cpuPackageW = 0;

    // ── GPU erweitert ──────────────────────────────────────────────────────
    double gpuFreqMhz = 0;
    double gpuPowerW  = 0;

    // ── VRAM (GTT) ─────────────────────────────────────────────────────────
    double vramUsedGb  = 0;
    double vramTotalGb = 8.1;

    // ── Swap ───────────────────────────────────────────────────────────────
    double swapPercent = 0;
    double swapUsedGb  = 0;
    double swapTotalGb = 8.1;

    // ── Disk I/O ───────────────────────────────────────────────────────────
    double diskReadMbps  = 0;
    double diskWriteMbps = 0;

    // ── Netzwerk ───────────────────────────────────────────────────────────
    double  netRxMbps  = 0;
    double  netTxMbps  = 0;
    QString netLocalIp = QStringLiteral("0.0.0.0");

    // ── Gaming ─────────────────────────────────────────────────────────────
    bool    gaming          = false;
    double  fps             = 0;
    double  frametimeMs     = 0;
    double  fps1PctLow      = 0;
    double  fpsPoint1PctLow = 0;
    QString gameName;
    QString thumbnailB64;
    bool    hasThumbnail    = false;   // true wenn thumbnail_b64 Key im Paket war
    int     gameAppId = 0;
};

class DemoSimulation {
public:
    DemoSimulation();
    SimData next();

private:
    double smooth(double val, double target, double alpha);
    double gauss(double stddev);

    double _t      = 0.0;
    double _cpu    = 32.0;
    double _gpu    = 55.0;
    double _fps    = 85.0;
    double _diskR  = 8.0;
    double _diskW  = 2.0;
    double _netRx  = 0.8;
    double _netTx  = 0.15;
    int    _uptime = 7320;

    std::mt19937 _rng;
    std::normal_distribution<double> _ndist{0.0, 1.0};

    static constexpr double RAM_TOTAL  = 15.53;
    static constexpr double VRAM_TOTAL =  7.54;
    static constexpr double SWAP_TOTAL =  7.55;
    static constexpr double STOR_TOTAL = 512.0;
    static constexpr double STOR_USED  = 292.0;
};
