#include "daemonreceiver.h"
#include <QTcpServer>
#include <QTcpSocket>
#include <QHostAddress>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDebug>

DaemonReceiver::DaemonReceiver(int port, QObject *parent)
    : QObject(parent), m_port(port) {}

void DaemonReceiver::start()
{
    m_server = new QTcpServer(this);
    connect(m_server, &QTcpServer::newConnection,
            this,     &DaemonReceiver::onNewConnection);

    if (!m_server->listen(QHostAddress::Any, m_port)) {
        qWarning("[DAEMON] Konnte nicht auf Port %d lauschen: %s",
                 m_port, qPrintable(m_server->errorString()));
        return;
    }
    qInfo("[DAEMON] Lausche auf Port %d", m_port);
}

void DaemonReceiver::onNewConnection()
{
    QTcpSocket *incoming = m_server->nextPendingConnection();
    if (!incoming) return;

    // Nur eine aktive Verbindung — alte ersetzen
    if (m_client) {
        qInfo("[DAEMON] Neue Verbindung ersetzt bestehende");
        m_client->disconnect();
        m_client->abort();
        m_client->deleteLater();
        m_buffer.clear();
    }

    m_client = incoming;
    connect(m_client, &QTcpSocket::readyRead,
            this,     &DaemonReceiver::onReadyRead);
    connect(m_client, &QTcpSocket::disconnected,
            this,     &DaemonReceiver::onClientDisconnected);

    qInfo("[DAEMON] Verbunden: %s", qPrintable(m_client->peerAddress().toString()));
    emit daemonConnected();
}

void DaemonReceiver::onReadyRead()
{
    m_buffer += m_client->readAll();

    // Zeilenweise JSON parsen
    while (true) {
        int nl = m_buffer.indexOf('\n');
        if (nl < 0) break;

        QByteArray line = m_buffer.left(nl).trimmed();
        m_buffer.remove(0, nl + 1);
        if (line.isEmpty()) continue;

        QJsonParseError err;
        QJsonDocument doc = QJsonDocument::fromJson(line, &err);
        if (err.error != QJsonParseError::NoError || !doc.isObject()) {
            qWarning("[DAEMON] Ungültiges JSON: %s", qPrintable(err.errorString()));
            continue;
        }

        QVariantMap map = doc.object().toVariantMap();
        if (map.contains(QStringLiteral("cmd"))) {
            const QString cmd = map.value(QStringLiteral("cmd")).toString();
            emit commandReceived(cmd);
            // Gaming-Cmd trägt game_name, game_appid, thumbnail_b64 — als Datenpaket weiterleiten
            if (cmd == QLatin1String("gaming"))
                emit dataReceived(map);
        } else {
            emit dataReceived(map);
        }
    }
}

void DaemonReceiver::onClientDisconnected()
{
    qInfo("[DAEMON] Verbindung getrennt");
    m_buffer.clear();
    if (m_client) {
        m_client->deleteLater();
        m_client = nullptr;
    }
    emit daemonDisconnected();
}
