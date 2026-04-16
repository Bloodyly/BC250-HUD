#pragma once
#include <QObject>
#include <QVariantMap>

class QTcpServer;
class QTcpSocket;

// Lauscht auf TCP-Port 5555 auf JSON-Zeilen vom BC250-Daemon.
// Läuft in eigenem QThread — blockiert nie den Main/Render-Thread.
class DaemonReceiver : public QObject {
    Q_OBJECT
public:
    explicit DaemonReceiver(int port = 5555, QObject *parent = nullptr);

public slots:
    void start();   // via QThread::started

signals:
    void daemonConnected();
    void daemonDisconnected();
    // Datenpakete (kein "cmd"-Feld): rohe Map, Main-Thread parsed
    void dataReceived(QVariantMap data);
    // Steuerbefehle: "standby", "wake", "gaming", "running"
    void commandReceived(QString cmd);

private slots:
    void onNewConnection();
    void onReadyRead();
    void onClientDisconnected();

private:
    int          m_port;
    QTcpServer  *m_server = nullptr;
    QTcpSocket  *m_client = nullptr;
    QByteArray   m_buffer;
};
