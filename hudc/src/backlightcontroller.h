#pragma once
#include <QObject>
#include <QTimer>
#include <QString>

// Steuert GPIO18 Hardware-PWM via pigpiod.
// Überwacht GPIO26 (Power-State-Pin des BC250) via Polling.
// Läuft in eigenem QThread — Timer unabhängig vom Render-Loop.
class BacklightController : public QObject {
    Q_OBJECT
public:
    explicit BacklightController(QObject *parent = nullptr);
    ~BacklightController();

    bool init();  // pigpiod verbinden; false wenn nicht erreichbar

signals:
    // HIGH = BC250 läuft, LOW = ausgeschaltet / abgestürzt
    void powerPinChanged(bool high);

public slots:
    // Fade-In beim App-Start — wird in blThread aufgerufen
    void start();
    // Sanfter Übergang zu target (0.0–1.0) über durationMs ms
    void fadeTo(double target, int durationMs, double gamma = 2.2);
    // Sofort setzen
    void setLevel(double level);
    // Auf HudModel::appStateChanged reagieren
    void onAppStateChanged(const QString &state);

private slots:
    void fadeStep();
    void pollPowerPin();

private:
    void applyPWM(double linearLevel);

    int     m_pi        = -1;
    double  m_current   =  0.0;
    double  m_target    =  0.0;
    double  m_delta     =  0.0;
    double  m_gamma     =  2.2;
    QString m_currentState;
    bool    m_lastPowerPin = true;  // Letzter bekannter Zustand GPIO26 (HIGH = an)
    QTimer *m_timer      = nullptr;  // in start() erzeugt → lebt in blThread
    QTimer *m_gpioTimer  = nullptr;  // GPIO-26-Polling, 200 ms

    static constexpr unsigned GPIO_BL   = 18;
    static constexpr unsigned GPIO_PWR  = 26;
    static constexpr unsigned PWM_FREQ  = 10000;  // 10 kHz — kein Flackern
    static constexpr int      STEP_MS   = 16;     // ~60 Hz Fade-Rate
    static constexpr int      GPIO_POLL = 250;    // Power-Pin-Polling alle 250 ms
    static constexpr double   STANDBY   = 0.30;
};
