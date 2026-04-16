#include "healthworker.h"
#include <QProcess>
#include <QFile>
#include <cstdio>
#include <QTimer>
#include <QDebug>
#include <QCoreApplication>
#include <csignal>
#include <unistd.h>


HealthWorker::HealthWorker(QObject *parent) : QObject(parent) {}

void HealthWorker::start()
{
    m_uptime.start();

    // Health-Report alle 5s (verzögert nach 10s)
    QTimer::singleShot(10000, this, &HealthWorker::check);
    auto *t = new QTimer(this);
    t->setInterval(5000);
    connect(t, &QTimer::timeout, this, &HealthWorker::check);
    t->start();

    // Schnelle Stall-Erkennung alle 500ms
    auto *stallTimer = new QTimer(this);
    stallTimer->setInterval(500);
    connect(stallTimer, &QTimer::timeout, this, &HealthWorker::checkStall);
    stallTimer->start();
}

void HealthWorker::check()
{
    double  cpuTemp  = readCpuTemp();
    double  gpuTemp  = readGpuTemp();
    QString throttle = readThrottle();
    int     memAvail = 0, memTotal = 0;
    readMem(memAvail, memTotal);

    int ticks     = m_simTicks.exchange(0, std::memory_order_relaxed);
    int frameTicks = m_frameTicks.exchange(0, std::memory_order_relaxed);
    double simFps  = ticks     / 5.0 * 10.0;
    double hudFps  = frameTicks / 5.0;   // frames in 5s interval → fps

    // Stall-Erkennung läuft separat in checkStall() — hier nur Logging
    if (hudFps < 1.0)
        m_stallCount++;
    else
        m_stallCount = 0;

    bool throttled = false;
    if (throttle.contains(QLatin1Char('='))) {
        bool ok;
        uint val = throttle.section(QLatin1Char('='), 1).trimmed().toUInt(&ok, 16);
        throttled = ok && (val & 0xFu) != 0u;
    }

    emit result(m_uptime.elapsed() / 1000, cpuTemp, gpuTemp,
                throttle, throttled, memAvail, memTotal, simFps, hudFps);
}

double HealthWorker::readCpuTemp()
{
    QFile f(QStringLiteral("/sys/class/thermal/thermal_zone0/temp"));
    if (!f.open(QIODevice::ReadOnly)) return -1.0;
    return f.readAll().trimmed().toDouble() / 1000.0;
}

double HealthWorker::readGpuTemp()
{
    QFile f(QStringLiteral("/sys/class/thermal/thermal_zone1/temp"));
    if (!f.open(QIODevice::ReadOnly)) return -1.0;
    return f.readAll().trimmed().toDouble() / 1000.0;
}

QString HealthWorker::readThrottle()
{
    QProcess proc;
    proc.start(QStringLiteral("vcgencmd"), {QStringLiteral("get_throttled")});
    if (!proc.waitForFinished(800)) {
        proc.kill();
        proc.waitForFinished(300);
        return QStringLiteral("throttled=N/A");
    }
    return proc.readAllStandardOutput().trimmed();
}

void HealthWorker::checkStall()
{
    if (m_sigtermSent) return;

    const qint64 now       = m_uptime.elapsed();
    const qint64 lastFrame = m_lastFrameMs.load(std::memory_order_relaxed);

    // Kein Check in der Startup-Gracefrist oder bevor der erste Frame kam
    if (now < STALL_GRACE_MS || lastFrame < 0) return;

    const qint64 stalledMs = now - lastFrame;
    if (stalledMs > STALL_TIMEOUT_MS) {
        m_sigtermSent = true;
        qCritical("[HEALTH] Kein Frame seit %lldms — SIGTERM", (long long)stalledMs);
        emit stalled();
        ::kill(::getpid(), SIGTERM);
    }
}

void HealthWorker::readMem(int &availMb, int &totalMb)
{
    FILE *f = fopen("/proc/meminfo", "r");
    if (!f) return;
    char line[128];
    int val = 0;
    while (fgets(line, sizeof(line), f)) {
        if (sscanf(line, "MemTotal: %d", &val) == 1)
            totalMb = val / 1024;
        else if (sscanf(line, "MemAvailable: %d", &val) == 1)
            availMb = val / 1024;
    }
    fclose(f);
}
