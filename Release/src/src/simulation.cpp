#include "simulation.h"

DemoSimulation::DemoSimulation()
    : _rng(std::random_device{}())
{}

double DemoSimulation::gauss(double stddev)
{
    return _ndist(_rng) * stddev;
}

double DemoSimulation::smooth(double val, double target, double alpha)
{
    return val + alpha * (target - val) + gauss(0.4);
}

SimData DemoSimulation::next()
{
    _t += 0.05;

    // CPU: Basislast ~30%, gelegentliche Spikes auf ~45%
    double cpuTarget = 30 + 12 * std::abs(std::sin(_t * 0.07))
                          +  8 * std::abs(std::sin(_t * 0.23));
    _cpu = std::max(18.0, std::min(52.0, smooth(_cpu, cpuTarget, 0.04)));

    // GPU: Gaming-Last ~52%, sanfte Wellen
    double gpuTarget = 52 + 14 * std::abs(std::sin(_t * 0.05))
                          +  6 * std::abs(std::sin(_t * 0.17));
    _gpu = std::max(38.0, std::min(72.0, smooth(_gpu, gpuTarget, 0.035)));

    // Per-Core CPU: jeder Kern weicht etwas vom Gesamt ab
    std::array<double, 6> cores;
    for (int i = 0; i < 6; ++i) {
        double coreTarget = _cpu + 8 * std::sin(_t * (0.11 + i * 0.07) + i);
        cores[i] = std::max(5.0, std::min(95.0, coreTarget + gauss(1.5)));
    }

    double cpuTemp  = 52 + 0.28 * _cpu + gauss(0.3);
    double gpuTemp  = 62 + 0.25 * _gpu + gauss(0.3);
    double cpuFreq  = 2600 + 400 * (_cpu / 50.0) + gauss(20.0);
    double cpuPkgW  = 8 + 0.35 * _cpu + 0.15 * _gpu + gauss(0.5);
    double gpuFreq  = 400 + 700 * (_gpu / 80.0) + gauss(15.0);
    double gpuPwrW  = cpuPkgW;   // PPT = combined SoC power

    double ramPct   = 61 + 3 * std::sin(_t * 0.04);
    double ramUsed  = RAM_TOTAL * ramPct / 100.0;
    double vramUsed = 0.5 + 0.4 * (_gpu / 70.0) + gauss(0.02);

    // Disk I/O: periodic read bursts
    double diskRTarget = 5 + 20 * std::abs(std::sin(_t * 0.12));
    _diskR = std::max(0.0, smooth(_diskR, diskRTarget, 0.08));
    double diskWTarget = 1 + 5 * std::abs(std::sin(_t * 0.09));
    _diskW = std::max(0.0, smooth(_diskW, diskWTarget, 0.06));

    // Network: small background traffic
    double netRxTarget = 0.5 + 1.5 * std::abs(std::sin(_t * 0.08));
    _netRx = std::max(0.0, smooth(_netRx, netRxTarget, 0.06));
    double netTxTarget = 0.05 + 0.3 * std::abs(std::sin(_t * 0.11));
    _netTx = std::max(0.0, smooth(_netTx, netTxTarget, 0.06));

    // FPS: simulate gaming at ~87fps
    double fpsTarget = 87 + 12 * std::sin(_t * 0.09);
    _fps = std::max(40.0, std::min(120.0, smooth(_fps, fpsTarget, 0.05)));
    double ft = 1000.0 / std::max(1.0, _fps);

    _uptime += 1;

    return SimData{
        .cpu             = std::round(_cpu   * 10) / 10,
        .cpuTemp         = std::round(cpuTemp * 10) / 10,
        .gpu             = std::round(_gpu   * 10) / 10,
        .gpuTemp         = std::round(gpuTemp * 10) / 10,
        .gpuAvailable    = true,
        .ram             = std::round(ramPct  * 10) / 10,
        .ramUsedGb       = std::round(ramUsed * 100) / 100,
        .ramTotalGb      = RAM_TOTAL,
        .storage         = 57.0,
        .storageUsedGb   = STOR_USED,
        .storageTotalGb  = STOR_TOTAL,
        .uptimeSeconds   = _uptime,
        .hostname        = QStringLiteral("BC250"),
        .cpuCorePct      = cores,
        .cpuFreqMhz      = std::round(cpuFreq),
        .cpuPackageW     = std::round(cpuPkgW * 10) / 10,
        .gpuFreqMhz      = std::round(gpuFreq),
        .gpuPowerW       = std::round(gpuPwrW * 10) / 10,
        .vramUsedGb      = std::round(vramUsed * 100) / 100,
        .vramTotalGb     = VRAM_TOTAL,
        .swapPercent     = 0.0,
        .swapUsedGb      = 0.0,
        .swapTotalGb     = SWAP_TOTAL,
        .diskReadMbps    = std::round(_diskR * 10) / 10,
        .diskWriteMbps   = std::round(_diskW * 10) / 10,
        .netRxMbps       = std::round(_netRx * 100) / 100,
        .netTxMbps       = std::round(_netTx * 100) / 100,
        .netLocalIp      = QStringLiteral("192.168.0.142"),
        .gaming          = true,
        .fps             = std::round(_fps * 10) / 10,
        .frametimeMs     = std::round(ft * 100) / 100,
        .fps1PctLow      = std::round((_fps * 0.72) * 10) / 10,
        .fpsPoint1PctLow = std::round((_fps * 0.55) * 10) / 10,
        .gameName        = QStringLiteral("Palworld"),
        .thumbnailB64    = {},
        .gameAppId       = 1623730,
    };
}
