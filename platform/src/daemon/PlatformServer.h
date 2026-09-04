#pragma once

#include <QObject>
#include <QHash>
#include <QJsonObject>
#include <QLocalServer>
#include <QLocalSocket>
#include <QPointer>
#include <QProcess>
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
    void applySystemTheme(QLocalSocket *socket, const QJsonObject &request,
                          bool dark);
    void runNetworkRefresh(QLocalSocket *socket, const QJsonObject &request);
    void runBluetoothList(QLocalSocket *socket, const QJsonObject &request);
    void sendEvent(QLocalSocket *socket, const QJsonObject &event);
    QString requestId(const QJsonObject &request) const;
    QString operation(const QJsonObject &request) const;

    bool handleClipboard(QLocalSocket *socket, const QJsonObject &request);
    bool handleFileOperation(QLocalSocket *socket, const QJsonObject &request);
    bool handleKWin(QLocalSocket *socket, const QJsonObject &request);
    bool handleAppMenu(QLocalSocket *socket, const QJsonObject &request);
    bool handleSystemOperation(QLocalSocket *socket, const QJsonObject &request);
    void startClipboardHistoryWatcher(QProcess *&watcher,
                                      const QStringList &arguments);
    void runClipboardDecode(QLocalSocket *socket, const QJsonObject &request,
                            const QString &record);
    void runClipboardDelete(QLocalSocket *socket, const QJsonObject &request,
                            const QString &record);

    QLocalServer m_server;
    QString m_socketPath;
    QHash<QLocalSocket *, QByteArray> m_buffers;
    QSet<QLocalSocket *> m_windowSubscribers;
    // A Shell can reconnect after Quickshell reloads while KWin has no new
    // window event to broadcast. Retain the authoritative last snapshot so a
    // new subscriber never has to wait for unrelated window activity.
    QJsonObject m_latestWindowSnapshot;
    QJsonObject m_latestDesktopSnapshot;
    QProcess *m_textHistoryWatcher = nullptr;
    QProcess *m_imageHistoryWatcher = nullptr;
    bool m_watchImages = true;
};

} // namespace KosPlatform
