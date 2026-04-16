#include "backlightcontroller.h"
#include <pigpiod_if2.h>
#include <QDebug>
#include <cmath>

BacklightController::BacklightController(QObject *parent)
    : QObject(parent)
{
    // Kein Timer-Setup hier — Objekt lebt noch im Haupt-Thread.
    // Timer wird in start() erzeugt, das aus blThread aufgerufen wird.
}

BacklightController::~BacklightController()
{
    if (m_pi >= 0) {
        hardware_PWM(m_pi, GPIO_BL, 0, 0);
        pigpio_stop(m_pi);
    }
}

bool BacklightController::init()
{
    m_pi = pigpio_start(nullptr, nullptr);
    if (m_pi < 0) {
        qWarning("[BL] pigpiod nicht erreichbar (Code %d)", m_pi);
        return false;
    }
    hardware_PWM(m_pi, GPIO_BL, PWM_FREQ, 0);
    qInfo("[BL] pigpiod verbunden, GPIO%u @ %u Hz", GPIO_BL, PWM_FREQ);
    return true;
}

void BacklightController::start()
{
    // In blThread aufgerufen → Timer wird hier im richtigen Thread erzeugt
    m_timer = new QTimer(this);
    m_timer->setInterval(STEP_MS);
    connect(m_timer, &QTimer::timeout, this, &BacklightController::fadeStep);
    // Backlight bleibt bei 0 — Fade startet erst nach dem ersten gerenderten Frame
    // (wird von main.cpp via frameSwapped-Signal ausgelöst)

    // GPIO 26 (Power-State-Pin) als Input mit Pull-Down konfigurieren
    if (m_pi >= 0) {
        set_mode(m_pi, GPIO_PWR, PI_INPUT);
        set_pull_up_down(m_pi, GPIO_PWR, PI_PUD_DOWN);
        // Initialzustand einlesen und sofort emittieren, damit main.cpp reagieren kann
        m_lastPowerPin = (gpio_read(m_pi, GPIO_PWR) == PI_HIGH);
        qInfo("[GPIO] Power-Pin GPIO%u Initialzustand: %s",
              GPIO_PWR, m_lastPowerPin ? "HIGH" : "LOW");

        m_gpioTimer = new QTimer(this);
        m_gpioTimer->setInterval(GPIO_POLL);
        connect(m_gpioTimer, &QTimer::timeout, this, &BacklightController::pollPowerPin);
        m_gpioTimer->start();

        // Initialzustand jetzt emittieren — main.cpp reagiert darauf:
        // HIGH → booting, LOW → in "off" bleiben (kein shutdown)
        emit powerPinChanged(m_lastPowerPin);
    }
}

void BacklightController::fadeTo(double target, int durationMs, double gamma)
{
    if (m_pi < 0 || !m_timer) return;
    target   = qBound(0.0, target, 1.0);
    m_target = target;
    m_gamma  = gamma;
    int steps = qMax(1, durationMs / STEP_MS);
    m_delta   = (target - m_current) / steps;
    if (!m_timer->isActive())
        m_timer->start();
}

void BacklightController::setLevel(double level)
{
    if (m_pi < 0 || !m_timer) return;
    m_timer->stop();
    m_current = qBound(0.0, level, 1.0);
    m_target  = m_current;
    applyPWM(m_current);
}

void BacklightController::onAppStateChanged(const QString &state)
{
    m_currentState = state;
    if      (state == QLatin1String("idle") || state == QLatin1String("gaming"))
        fadeTo(1.0, 1200, 2.2);   // 100 % — HUD aktiv
    else if (state == QLatin1String("booting")      ||
             state == QLatin1String("standby")       ||
             state == QLatin1String("disconnected")  ||
             state == QLatin1String("restarting"))
        fadeTo(0.6, 1200, 2.2);   // 60 % — Zwischenzustand
    else if (state == QLatin1String("shutdown"))
        fadeTo(0.0, 1500, 2.2);   // 0 % — Display aus
    // "off": kein Fade — Backlight bleibt bei 0 (Pi wartet auf BC250)
}

void BacklightController::pollPowerPin()
{
    if (m_pi < 0) return;
    bool high = (gpio_read(m_pi, GPIO_PWR) == PI_HIGH);
    if (high != m_lastPowerPin) {
        m_lastPowerPin = high;
        qInfo("[GPIO] Power-Pin GPIO%u: %s", GPIO_PWR, high ? "HIGH" : "LOW");
        emit powerPinChanged(high);
    }
}

void BacklightController::fadeStep()
{
    m_current += m_delta;
    if ((m_delta >= 0.0 && m_current >= m_target) ||
        (m_delta <  0.0 && m_current <= m_target)) {
        m_current = m_target;
        m_timer->stop();
    }
    applyPWM(m_current);
}

void BacklightController::applyPWM(double linear)
{
    double corrected = std::pow(qBound(0.0, linear, 1.0), m_gamma);
    unsigned duty    = static_cast<unsigned>(corrected * 1'000'000.0);
    hardware_PWM(m_pi, GPIO_BL, PWM_FREQ, duty);
}
