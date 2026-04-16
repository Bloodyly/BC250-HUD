#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QTimer>
#include <QThread>
#include <QDebug>
#include <QFileInfo>
#include <QDateTime>
#include <memory>

#include "hudmodel.h"
#include "simulation.h"
#include "healthworker.h"
#include "daemonreceiver.h"
#include "backlightcontroller.h"

static SimData simDataFromMap(const QVariantMap &m)
{
    // Per-Core CPU (6 Kerne, Fallback: Gesamt-CPU für alle)
    std::array<double, 6> cores = {};
    const QVariantList coreList = m.value(QStringLiteral("cpu_core_pct")).toList();
    const double cpuFallback    = m.value(QStringLiteral("cpu_percent"), 0.0).toDouble();
    for (int i = 0; i < 6; ++i)
        cores[i] = (i < coreList.size()) ? coreList[i].toDouble() : cpuFallback;

    return SimData {
        .cpu             = cpuFallback,
        .cpuTemp         = m.value(QStringLiteral("cpu_temp"),          0.0  ).toDouble(),
        .gpu             = m.value(QStringLiteral("gpu_percent"),        0.0  ).toDouble(),
        .gpuTemp         = m.value(QStringLiteral("gpu_temp"),           0.0  ).toDouble(),
        .gpuAvailable    = m.value(QStringLiteral("gpu_available"),      false).toBool(),
        .ram             = m.value(QStringLiteral("ram_percent"),        0.0  ).toDouble(),
        .ramUsedGb       = m.value(QStringLiteral("ram_used_gb"),        0.0  ).toDouble(),
        .ramTotalGb      = m.value(QStringLiteral("ram_total_gb"),      15.53 ).toDouble(),
        .storage         = m.value(QStringLiteral("storage_percent"),    0.0  ).toDouble(),
        .storageUsedGb   = m.value(QStringLiteral("storage_used_gb"),    0.0  ).toDouble(),
        .storageTotalGb  = m.value(QStringLiteral("storage_total_gb"), 512.0  ).toDouble(),
        .uptimeSeconds   = m.value(QStringLiteral("uptime_seconds"),     0    ).toInt(),
        .hostname        = m.value(QStringLiteral("hostname"), QStringLiteral("BC250")).toString(),
        .cpuCorePct      = cores,
        .cpuFreqMhz      = m.value(QStringLiteral("cpu_freq_mhz"),       0.0  ).toDouble(),
        .cpuPackageW     = m.value(QStringLiteral("cpu_package_w"),       0.0  ).toDouble(),
        .gpuFreqMhz      = m.value(QStringLiteral("gpu_freq_mhz"),        0.0  ).toDouble(),
        .gpuPowerW       = m.value(QStringLiteral("gpu_power_w"),          0.0  ).toDouble(),
        .vramUsedGb      = m.value(QStringLiteral("vram_used_gb"),         0.0  ).toDouble(),
        .vramTotalGb     = m.value(QStringLiteral("vram_total_gb"),        7.54 ).toDouble(),
        .swapPercent     = m.value(QStringLiteral("swap_percent"),         0.0  ).toDouble(),
        .swapUsedGb      = m.value(QStringLiteral("swap_used_gb"),         0.0  ).toDouble(),
        .swapTotalGb     = m.value(QStringLiteral("swap_total_gb"),        7.55 ).toDouble(),
        .diskReadMbps    = m.value(QStringLiteral("disk_read_mbps"),       0.0  ).toDouble(),
        .diskWriteMbps   = m.value(QStringLiteral("disk_write_mbps"),      0.0  ).toDouble(),
        .netRxMbps       = m.value(QStringLiteral("net_rx_mbps"),          0.0  ).toDouble(),
        .netTxMbps       = m.value(QStringLiteral("net_tx_mbps"),          0.0  ).toDouble(),
        .netLocalIp      = m.value(QStringLiteral("net_local_ip"), QStringLiteral("0.0.0.0")).toString(),
        // Explizites gaming-Feld bevorzugen; Fallback: game_appid-Präsenz (Kompatibilität)
        .gaming          = m.value(QStringLiteral("gaming"),
                               m.contains(QStringLiteral("game_appid"))).toBool(),
        .fps             = m.value(QStringLiteral("fps"),                  0.0  ).toDouble(),
        .frametimeMs     = m.value(QStringLiteral("frametime_ms"),         0.0  ).toDouble(),
        .fps1PctLow      = m.value(QStringLiteral("fps_1pct_low"),         0.0  ).toDouble(),
        .fpsPoint1PctLow = m.value(QStringLiteral("fps_point1pct_low"),    0.0  ).toDouble(),
        .gameName        = m.value(QStringLiteral("game_name")).toString(),
        .thumbnailB64    = m.value(QStringLiteral("thumbnail_b64")).toString(),
        .hasThumbnail    = m.contains(QStringLiteral("thumbnail_b64")),
        .gameAppId       = m.value(QStringLiteral("game_appid"),            0    ).toInt(),
    };
}

int main(int argc, char *argv[])
{
    qputenv("QT_AUTO_SCREEN_SCALE_FACTOR", "0");
    qputenv("QT_SCALE_FACTOR", "1");

    QGuiApplication app(argc, argv);
    app.setApplicationName("BC250 HUD C++");

    HudModel       model;
    DemoSimulation sim;

    // ══ BacklightController — eigener Thread ══════════════════════════════════
    auto *blThread  = new QThread(&app);
    auto *backlight = new BacklightController;
    backlight->moveToThread(blThread);

    QObject::connect(blThread, &QThread::started, [backlight]() {
        if (backlight->init())
            backlight->start();
    });
    QObject::connect(&app,     &QCoreApplication::aboutToQuit, blThread, &QThread::quit);
    QObject::connect(blThread, &QThread::finished, backlight, &QObject::deleteLater);
    QObject::connect(&model, &HudModel::appStateChanged,
                     backlight, &BacklightController::onAppStateChanged);

    // GPIO 26: Power-State-Pin des BC250
    // Wird auch beim Start einmalig emittiert (Initialzustand).
    // HIGH: BC250 läuft → booting starten (aus "off" oder nach shutdown)
    // LOW:  BC250 aus  → nur shutdown wenn wir bereits aktiv waren, nicht aus "off"
    QObject::connect(backlight, &BacklightController::powerPinChanged, &app,
        [&model](bool high) {
            const QString st = model.appState();
            if (high) {
                qInfo("[GPIO] Power HIGH → booting (war: %s)", qPrintable(st));
                if (st == QLatin1String("off") ||
                    st == QLatin1String("shutdown"))
                    model.setAppState(QStringLiteral("booting"));
                // Alle anderen States: BC250 ist sowieso schon aktiv, ignorieren
            } else {
                // LOW: nur reagieren wenn wir nicht bereits im "aus"-Zustand sind
                if (st != QLatin1String("off")       &&
                    st != QLatin1String("shutdown")  &&
                    st != QLatin1String("restarting")) {
                    qInfo("[GPIO] Power LOW → shutdown (war: %s)", qPrintable(st));
                    model.setConnected(false);
                    model.setAppState(QStringLiteral("shutdown"));
                }
            }
        });

    blThread->start();

    // ══ HealthWorker — eigener Thread ════════════════════════════════════════
    auto *healthThread = new QThread(&app);
    auto *health       = new HealthWorker;
    health->moveToThread(healthThread);

    QObject::connect(healthThread, &QThread::started,
                     health, &HealthWorker::start);
    QObject::connect(&app, &QCoreApplication::aboutToQuit,
                     healthThread, &QThread::quit);
    QObject::connect(healthThread, &QThread::finished,
                     health, &QObject::deleteLater);

    QObject::connect(health, &HealthWorker::result,
        [](qint64 up, double cpu, double gpu,
           const QString &throttle, bool throttled,
           int memAvail, int memTotal, double simFps, double hudFps) {
        const QString gpuStr = (gpu > 0)
            ? QString::number(gpu, 'f', 1) + QStringLiteral("\xc2\xb0""C")
            : QStringLiteral("N/A");
        qInfo("[HEALTH] uptime=%llds  cpu=%.1f\xc2\xb0""C  gpu=%s  %s%s"
              "  mem=%d/%dMB  sim_fps=%.0f  hud_fps=%.1f",
              up, cpu, qPrintable(gpuStr), qPrintable(throttle),
              throttled ? "  *** THROTTLED ***" : "",
              memAvail, memTotal, simFps, hudFps);
    });

    // Stall-Signal: Render-Loop ist eingefroren → sauber beenden, systemd startet neu
    QObject::connect(health, &HealthWorker::stalled, &app, []() {
        qCritical("[HUD] Render-Stall → exit(2) für systemd-Neustart");
        QCoreApplication::exit(2);
    });

    healthThread->start();

    // ══ Disconnect-Timer: 5s Verzögerung bevor "disconnected" angezeigt wird ══
    // Kurze Verbindungsabbrüche (z.B. USB-Neuverbindung) sollen kein Flackern erzeugen.
    auto *disconnectTimer = new QTimer(&app);
    disconnectTimer->setSingleShot(true);
    disconnectTimer->setInterval(5000);
    QObject::connect(disconnectTimer, &QTimer::timeout, &app, [&model]() {
        const QString st = model.appState();
        if (st == QLatin1String("idle") || st == QLatin1String("gaming")) {
            qInfo("[HUD] Disconnect-Timeout (5s) → disconnected");
            model.setAppState(QStringLiteral("disconnected"));
        }
    });

    // ══ Gaming-Stop-Timer: 5s nach letztem Gaming-Paket → idle ═══════════════
    // Spiel beendet: Daemon schickt {"cmd":"running"} oder hört auf gaming-Pakete zu senden.
    auto *gamingStopTimer = new QTimer(&app);
    gamingStopTimer->setSingleShot(true);
    gamingStopTimer->setInterval(5000);
    QObject::connect(gamingStopTimer, &QTimer::timeout, &app, [&model]() {
        if (model.appState() == QLatin1String("gaming")) {
            qInfo("[HUD] Gaming-Stop-Timeout (5s) → idle");
            model.setAppState(QStringLiteral("idle"));
        }
    });

    // ══ DaemonReceiver — eigener Thread ══════════════════════════════════════
    auto *daemonThread = new QThread(&app);
    auto *daemon       = new DaemonReceiver(5555);
    daemon->moveToThread(daemonThread);

    QObject::connect(daemonThread, &QThread::started,
                     daemon, &DaemonReceiver::start);
    QObject::connect(&app, &QCoreApplication::aboutToQuit,
                     daemonThread, &QThread::quit);
    QObject::connect(daemonThread, &QThread::finished,
                     daemon, &QObject::deleteLater);

    QObject::connect(daemon, &DaemonReceiver::daemonConnected, &app,
        [&model, disconnectTimer]() {
            qInfo("[HUD] Daemon verbunden → idle");
            disconnectTimer->stop();
            model.setConnected(true);
            const QString st = model.appState();
            // Von Boot, Trennung oder Neustart zurück in idle
            if (st == QLatin1String("booting")       ||
                st == QLatin1String("disconnected")  ||
                st == QLatin1String("restarting"))
                model.setAppState(QStringLiteral("idle"));
        });

    QObject::connect(daemon, &DaemonReceiver::daemonDisconnected, &app,
        [&model, disconnectTimer, gamingStopTimer]() {
            qInfo("[HUD] Daemon getrennt — starte 5s Disconnect-Timer");
            model.setConnected(false);
            gamingStopTimer->stop();
            const QString st = model.appState();
            // Nur im aktiven HUD-Betrieb Timer starten
            // standby/shutdown/restarting sind erwartete Trennungen
            if (st == QLatin1String("idle") || st == QLatin1String("gaming"))
                disconnectTimer->start();
        });

    QObject::connect(daemon, &DaemonReceiver::dataReceived, &app,
        [&model, gamingStopTimer](const QVariantMap &map) {
            const SimData d = simDataFromMap(map);
            model.applySimData(d);

            // ── Auto-Gaming-Erkennung via Datenpakete ─────────────────────
            // Daemon sendet gaming:true mit jedem Paket solange ein Spiel läuft.
            // Nach 5s ohne gaming-Paket → zurück zu idle.
            const QString st = model.appState();
            if (d.gaming) {
                if (st == QLatin1String("idle"))
                    model.setAppState(QStringLiteral("gaming"));
                // 5s-Timer bei jedem Gaming-Paket zurücksetzen
                gamingStopTimer->start();
            } else if (st == QLatin1String("gaming")) {
                // Kein Gaming-Flag mehr → Countdown starten wenn noch nicht aktiv
                if (!gamingStopTimer->isActive())
                    gamingStopTimer->start();
            }
        });

    QObject::connect(daemon, &DaemonReceiver::commandReceived, &app,
        [&model, gamingStopTimer](const QString &cmd) {
            qInfo("[DAEMON] cmd=%s", qPrintable(cmd));
            const QString st = model.appState();
            if (cmd == QLatin1String("standby") &&
                    (st == QLatin1String("idle") || st == QLatin1String("gaming"))) {
                gamingStopTimer->stop();
                model.setAppState(QStringLiteral("standby"));
            } else if (cmd == QLatin1String("wake") &&
                       st == QLatin1String("standby")) {
                model.setAppState(QStringLiteral("idle"));
            } else if (cmd == QLatin1String("gaming") &&
                       st == QLatin1String("idle")) {
                model.setAppState(QStringLiteral("gaming"));
                gamingStopTimer->start();  // Fallback-Timer starten
            } else if (cmd == QLatin1String("running") &&
                       (st == QLatin1String("gaming") || st == QLatin1String("idle"))) {
                gamingStopTimer->stop();
                model.setAppState(QStringLiteral("idle"));
            } else if (cmd == QLatin1String("restart") &&
                       (st == QLatin1String("idle") || st == QLatin1String("gaming"))) {
                gamingStopTimer->stop();
                model.setAppState(QStringLiteral("restarting"));
            } else if (cmd == QLatin1String("shutdown") &&
                       (st == QLatin1String("idle")    ||
                        st == QLatin1String("gaming")  ||
                        st == QLatin1String("standby"))) {
                gamingStopTimer->stop();
                model.setAppState(QStringLiteral("shutdown"));
            }
        });

    daemonThread->start();

    // ══ Simulations-Timer ════════════════════════════════════════════════════
    QTimer simTimer;
    simTimer.setInterval(100);
    QObject::connect(&simTimer, &QTimer::timeout, [&]() {
        if (!model.connected())
            model.applySimData(sim.next());
        health->countSimTick();
    });
    simTimer.start();

    // ══ QML laden ════════════════════════════════════════════════════════════
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("hud"), &model);
    const QString qmlPath = QCoreApplication::applicationDirPath()
                            + QStringLiteral("/hud.qml");
    engine.load(QUrl::fromLocalFile(qmlPath));
    if (engine.rootObjects().isEmpty()) {
        qCritical("[HUD] QML laden fehlgeschlagen: %s", qPrintable(qmlPath));
        return 1;
    }

    // ══ Backlight: erst nach erstem gerenderten Frame hochfaden ══════════════
    auto *win = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    if (win) {
        // FPS-Zähler: jedes gerenderte Frame inkrementiert den Atomic-Counter
        QObject::connect(win, &QQuickWindow::frameSwapped,
                         health, &HealthWorker::countFrame);

        QObject::connect(win, &QQuickWindow::frameSwapped, backlight,
            [backlight, &model]() {
                static bool fired = false;
                if (fired) return;
                fired = true;
                // Backlight erstmals einschalten: aktuellen State anwenden statt
                // hardcoded 0.6 — verhindert Race wenn Daemon schon verbunden ist.
                QMetaObject::invokeMethod(backlight, "onAppStateChanged",
                    Qt::QueuedConnection,
                    Q_ARG(QString, model.appState()));
            });
    } else {
        qWarning("[HUD] Root-Objekt ist kein QQuickWindow — Backlight startet sofort");
        QMetaObject::invokeMethod(backlight, "fadeTo", Qt::QueuedConnection,
            Q_ARG(double, 1.0), Q_ARG(int, 1500), Q_ARG(double, 2.2));
    }

    // ══ QML Hot-Reload: alle 5 s auf Dateiänderung prüfen ════════════════════
    // Nützlich während der Entwicklung: hud.qml auf dem Pi ersetzen →
    // HUD lädt automatisch neu ohne Service-Neustart.
    // qmlLastMod via shared_ptr — vermeidet read-only Capture-Problem mit Lambda.
    auto qmlLastMod = std::make_shared<QDateTime>(QFileInfo(qmlPath).lastModified());

    auto *reloadTimer = new QTimer(&app);
    reloadTimer->setInterval(5000);
    QObject::connect(reloadTimer, &QTimer::timeout, &app,
        [&engine, qmlLastMod, qmlPath, health]() {
            const QDateTime mod = QFileInfo(qmlPath).lastModified();
            if (mod == *qmlLastMod)
                return;
            *qmlLastMod = mod;

            qInfo("[HOT-RELOAD] hud.qml geändert — lade neu");
            qDeleteAll(engine.rootObjects());
            engine.clearComponentCache();
            engine.load(QUrl::fromLocalFile(qmlPath));

            if (engine.rootObjects().isEmpty()) {
                qCritical("[HOT-RELOAD] QML-Reload fehlgeschlagen");
                return;
            }
            if (auto *w = qobject_cast<QQuickWindow *>(engine.rootObjects().first()))
                QObject::connect(w, &QQuickWindow::frameSwapped,
                                 health, &HealthWorker::countFrame);
        });
    reloadTimer->start();

    return app.exec();
}
