#pragma once

#include <QObject>
#include <QVariantList>
#include <QVector>
#include <QString>
#include <array>
#include "simulation.h"

class HudModel : public QObject {
    Q_OBJECT

    // ── Bestehende Properties ──────────────────────────────────────────────
    Q_PROPERTY(double       cpu             READ cpu             NOTIFY changed)
    Q_PROPERTY(double       cpuTemp         READ cpuTemp         NOTIFY changed)
    Q_PROPERTY(double       gpu             READ gpu             NOTIFY changed)
    Q_PROPERTY(double       gpuTemp         READ gpuTemp         NOTIFY changed)
    Q_PROPERTY(bool         gpuAvailable    READ gpuAvailable    NOTIFY changed)
    Q_PROPERTY(double       ram             READ ram             NOTIFY changed)
    Q_PROPERTY(double       ramUsedGb       READ ramUsedGb       NOTIFY changed)
    Q_PROPERTY(double       ramTotalGb      READ ramTotalGb      NOTIFY changed)
    Q_PROPERTY(double       storage         READ storage         NOTIFY changed)
    Q_PROPERTY(double       storageUsedGb   READ storageUsedGb   NOTIFY changed)
    Q_PROPERTY(double       storageTotalGb  READ storageTotalGb  NOTIFY changed)
    Q_PROPERTY(int          uptimeSeconds   READ uptimeSeconds   NOTIFY changed)
    Q_PROPERTY(QString      hostname        READ hostname        NOTIFY changed)
    Q_PROPERTY(bool         connected       READ connected       NOTIFY changed)
    Q_PROPERTY(QVariantList cpuHistory      READ cpuHistory      NOTIFY changed)
    Q_PROPERTY(QVariantList gpuHistory      READ gpuHistory      NOTIFY changed)
    Q_PROPERTY(QVariantList loadHistory     READ loadHistory     NOTIFY changed)
    Q_PROPERTY(QString      appState        READ appState        NOTIFY changed)

    // ── CPU erweitert ──────────────────────────────────────────────────────
    Q_PROPERTY(QVariantList cpuCorePct      READ cpuCorePct      NOTIFY changed)
    Q_PROPERTY(double       cpuFreqMhz      READ cpuFreqMhz      NOTIFY changed)
    Q_PROPERTY(double       cpuPackageW     READ cpuPackageW     NOTIFY changed)

    // ── GPU erweitert ──────────────────────────────────────────────────────
    Q_PROPERTY(double       gpuFreqMhz      READ gpuFreqMhz      NOTIFY changed)
    Q_PROPERTY(double       gpuPowerW       READ gpuPowerW       NOTIFY changed)

    // ── VRAM (GTT, unified memory) ─────────────────────────────────────────
    Q_PROPERTY(double       vramUsedGb      READ vramUsedGb      NOTIFY changed)
    Q_PROPERTY(double       vramTotalGb     READ vramTotalGb     NOTIFY changed)

    // ── Swap ───────────────────────────────────────────────────────────────
    Q_PROPERTY(double       swapPercent     READ swapPercent     NOTIFY changed)
    Q_PROPERTY(double       swapUsedGb      READ swapUsedGb      NOTIFY changed)
    Q_PROPERTY(double       swapTotalGb     READ swapTotalGb     NOTIFY changed)

    // ── Disk I/O ───────────────────────────────────────────────────────────
    Q_PROPERTY(double       diskReadMbps    READ diskReadMbps    NOTIFY changed)
    Q_PROPERTY(double       diskWriteMbps   READ diskWriteMbps   NOTIFY changed)

    // ── Netzwerk ───────────────────────────────────────────────────────────
    Q_PROPERTY(double       netRxMbps       READ netRxMbps       NOTIFY changed)
    Q_PROPERTY(double       netTxMbps       READ netTxMbps       NOTIFY changed)
    Q_PROPERTY(QString      netLocalIp      READ netLocalIp      NOTIFY changed)

    // ── Gaming (MangoHud) ──────────────────────────────────────────────────
    Q_PROPERTY(bool         gaming          READ gaming          NOTIFY changed)
    Q_PROPERTY(double       fps             READ fps             NOTIFY changed)
    Q_PROPERTY(double       frametimeMs     READ frametimeMs     NOTIFY changed)
    Q_PROPERTY(double       fps1PctLow      READ fps1PctLow      NOTIFY changed)
    Q_PROPERTY(double       fpsPoint1PctLow READ fpsPoint1PctLow NOTIFY changed)
    Q_PROPERTY(QString      gameName        READ gameName        NOTIFY changed)
    Q_PROPERTY(int          gameAppId       READ gameAppId       NOTIFY changed)
    Q_PROPERTY(QString      thumbnailB64    READ thumbnailB64    NOTIFY changed)

    // ── Backlight (QML-steuerbar) ──────────────────────────────────────────
    // Lesen: aktuell gespeicherter Nutzerwert (0.0–1.0)
    // Schreiben: löst backlightRequested() aus → BacklightController
    Q_PROPERTY(double backlightLevel
               READ  backlightLevel
               WRITE setBacklightLevel
               NOTIFY backlightLevelChanged)

public:
    explicit HudModel(QObject *parent = nullptr);

    // ── Getter bestehend ───────────────────────────────────────────────────
    double       cpu()            const { return _cpu; }
    double       cpuTemp()        const { return _cpuTemp; }
    double       gpu()            const { return _gpu; }
    double       gpuTemp()        const { return _gpuTemp; }
    bool         gpuAvailable()   const { return _gpuOk; }
    double       ram()            const { return _ram; }
    double       ramUsedGb()      const { return _ramUsed; }
    double       ramTotalGb()     const { return _ramTotal; }
    double       storage()        const { return _storage; }
    double       storageUsedGb()  const { return _storUsed; }
    double       storageTotalGb() const { return _storTotal; }
    int          uptimeSeconds()  const { return _uptime; }
    QString      hostname()       const { return _hostname; }
    bool         connected()      const { return _connected; }
    QVariantList cpuHistory()     const;
    QVariantList gpuHistory()     const;
    QVariantList loadHistory()    const;
    QString      appState()       const { return _appState; }

    // ── Getter neu ─────────────────────────────────────────────────────────
    QVariantList cpuCorePct()     const;
    double  cpuFreqMhz()          const { return _cpuFreqMhz; }
    double  cpuPackageW()         const { return _cpuPackageW; }
    double  gpuFreqMhz()          const { return _gpuFreqMhz; }
    double  gpuPowerW()           const { return _gpuPowerW; }
    double  vramUsedGb()          const { return _vramUsed; }
    double  vramTotalGb()         const { return _vramTotal; }
    double  swapPercent()         const { return _swapPct; }
    double  swapUsedGb()          const { return _swapUsed; }
    double  swapTotalGb()         const { return _swapTotal; }
    double  diskReadMbps()        const { return _diskRead; }
    double  diskWriteMbps()       const { return _diskWrite; }
    double  netRxMbps()           const { return _netRx; }
    double  netTxMbps()           const { return _netTx; }
    QString netLocalIp()          const { return _netIp; }
    bool    gaming()              const { return _gaming; }
    double  fps()                 const { return _fps; }
    double  frametimeMs()         const { return _frametimeMs; }
    double  fps1PctLow()          const { return _fps1Pct; }
    double  fpsPoint1PctLow()     const { return _fps01Pct; }
    QString gameName()            const { return _gameName; }
    int     gameAppId()           const { return _gameAppId; }
    QString thumbnailB64()        const { return _thumbnailB64; }
    double  backlightLevel()      const { return _backlightLevel; }

    // ── Steuerung ──────────────────────────────────────────────────────────
    void applySimData(const SimData &d);
    void setAppState(const QString &state);
    void setConnected(bool c);
    // Aus QML aufgerufen (0.0–1.0); klemmt auf [0.1, 1.0]
    void setBacklightLevel(double level);

signals:
    void changed();
    void appStateChanged(const QString &state);
    void stateCommandReceived(const QString &cmd);
    void connectedChanged(bool connected);
    // Backlight: BacklightController hört hier zu
    void backlightRequested(double level, int durationMs);
    void backlightLevelChanged(double level);

private:
    static double ema(double old, double val, double alpha);
    static void   pushHist(QVector<double> &hist, double val, int maxLen = 60);

    // ── Member bestehend ───────────────────────────────────────────────────
    double  _cpu = 0,    _cpuTemp = 0;
    double  _gpu = 0,    _gpuTemp = 0;
    bool    _gpuOk = false;
    double  _ram = 0,    _ramUsed = 0,   _ramTotal = 34.0;
    double  _storage = 0, _storUsed = 0, _storTotal = 512.0;
    int     _uptime = 0;
    QString _hostname  = QStringLiteral("BC250");
    bool    _connected = false;
    QString _appState  = QStringLiteral("off");
    QVector<double> _cpuHist, _gpuHist, _loadHist;

    // ── Member neu ─────────────────────────────────────────────────────────
    std::array<double, 6> _cpuCorePct = {};
    double _cpuFreqMhz = 0, _cpuPackageW = 0;
    double _gpuFreqMhz = 0, _gpuPowerW   = 0;
    double _vramUsed   = 0, _vramTotal   = 8.1;
    double _swapPct    = 0, _swapUsed    = 0,   _swapTotal = 8.1;
    double _diskRead   = 0, _diskWrite   = 0;
    double _netRx      = 0, _netTx       = 0;
    QString _netIp     = QStringLiteral("0.0.0.0");
    bool    _gaming    = false;
    double  _fps = 0, _frametimeMs = 0, _fps1Pct = 0, _fps01Pct = 0;
    QString _gameName, _thumbnailB64;
    int     _gameAppId = 0;
    double  _backlightLevel = 1.0;  // Nutzerpräferenz, default 100%

    static constexpr double EMA_FAST = 0.15;
};
