#pragma once
#include <QObject>
#include <QElapsedTimer>
#include <atomic>

class HealthWorker : public QObject {
    Q_OBJECT
public:
    explicit HealthWorker(QObject *parent = nullptr);

    // Aufruf vom Main-Thread (frameSwapped Signal) — thread-safe
    void countFrame() noexcept {
        m_frameTicks.fetch_add(1, std::memory_order_relaxed);
        m_lastFrameMs.store(m_uptime.elapsed(), std::memory_order_relaxed);
    }

    void countSimTick() noexcept {
        m_simTicks.fetch_add(1, std::memory_order_relaxed);
    }

public slots:
    void start();

signals:
    void result(qint64 uptimeSecs, double cpuTemp, double gpuTemp,
                QString throttle, bool throttled,
                int memAvailMb, int memTotalMb,
                double simFps, double hudFps);
    void stalled();

private slots:
    void check();
    void checkStall();  // schnelle Prüfung alle 500ms

private:
    static double  readCpuTemp();
    static double  readGpuTemp();
    static QString readThrottle();
    static void    readMem(int &availMb, int &totalMb);  // /proc/meminfo

    static constexpr qint64 STALL_GRACE_MS  = 15000; // kein Check in den ersten 15s
    static constexpr qint64 STALL_TIMEOUT_MS = 2000; // kein Frame seit 2s → SIGTERM

    QElapsedTimer         m_uptime;
    std::atomic<int>      m_simTicks{0};
    std::atomic<int>      m_frameTicks{0};
    std::atomic<qint64>   m_lastFrameMs{-1};  // -1 = noch kein Frame gesehen
    bool                  m_sigtermSent = false;
    int                   m_stallCount  = 0;
};
