#pragma once

#include <QObject>
#include <QHash>
#include <QJsonObject>
#include <QLocalServer>
#include <QLocalSocket>
#include <QSet>

namespace KosPlatform {

class PlatformServer final : public QObject {
    Q_OBJECT

public:
    explicit PlatformServer(QObject *parent = nullptr);
    bool listen();
    QString socketPath() const { return m_socketPath; }

public slots:
    void broadcastKWinEvent(const QJsonObject &event);

private slots:
    void acceptConnections();
    void readClient();
    void clientDisconnected();

private:
    void handleRequest(QLocalSocket *socket, const QJsonObject &request);
    void respond(QLocalSocket *socket, const QJsonObject &request,
                 bool ok, const QJsonObject &result = {},
                 const QString &code = {}, const QString &message = {},
                 bool retryable = false);
    void runCommand(QLocalSocket *socket, const QJsonObject &request,
                    const QString &program, const QStringList &arguments,
                    std::function<QJsonObject(const QByteArray &, int)> parser = {});
    void sendEvent(QLocalSocket *socket, const QJsonObject &event);
    QString requestId(const QJsonObject &request) const;
    QString operation(const QJsonObject &request) const;

    bool handleClipboard(QLocalSocket *socket, const QJsonObject &request);
    bool handleFileOperation(QLocalSocket *socket, const QJsonObject &request);
    bool handleKWin(QLocalSocket *socket, const QJsonObject &request);
    bool handleSystemOperation(QLocalSocket *socket, const QJsonObject &request);

    QLocalServer m_server;
    QString m_socketPath;
    QHash<QLocalSocket *, QByteArray> m_buffers;
    QSet<QLocalSocket *> m_windowSubscribers;
};

} // namespace KosPlatform
