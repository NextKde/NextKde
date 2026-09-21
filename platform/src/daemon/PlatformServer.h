#pragma once

#include <QObject>
#include <QDBusObjectPath>
#include <QHash>
#include <QJsonObject>
#include <QLocalServer>
#include <QLocalSocket>
#include <QPointer>
#include <QProcess>
#include <QSet>
#include <QThreadPool>
#include <QVariantMap>

#include <optional>

namespace KosPlatform {

// One connect request: the settings dict already carries every secret, so the
// runner treats this as opaque data. The map never lands in a log or an argv
// -- it goes straight into AddConnection.
struct NmConnectRequest {
    QString device;
    QString savedProfileUuid;
    QVariantMap settings;
    QString replaceProfileId;
};

class PlatformServer final : public QObject {
    Q_OBJECT

public:
    explicit PlatformServer(QObject *parent = nullptr);
    ~PlatformServer() override;
    bool listen();
    QString socketPath() const { return m_socketPath; }

public slots:
    void broadcastKWinEvent(const QJsonObject &event);

private slots:
    void acceptConnections();
    void readClient();
    void clientDisconnected();
    // Every D-Bus property watch below funnels into reply-cache
    // invalidation: a change notification means the next request for that
    // domain must observe fresh state instead of the cached snapshot.
    void nmPropertiesChanged(const QString &interface, const QVariantMap &changed,
                             const QStringList &invalidated);
    void bluezPropertiesChanged(const QString &interface, const QVariantMap &changed,
                                const QStringList &invalidated);
    void bluezInterfacesAdded(const QDBusObjectPath &path, const QVariantMap &interfaces);
    void bluezInterfacesRemoved(const QDBusObjectPath &path, const QStringList &interfaces);
    void brightnessPropertiesChanged(const QString &interface, const QVariantMap &changed,
                                     const QStringList &invalidated);
    void nightLightPropertiesChanged(const QString &interface, const QVariantMap &changed,
                                     const QStringList &invalidated);

private:
    void handleRequest(QLocalSocket *socket, const QJsonObject &request);
    void respond(QLocalSocket *socket, const QJsonObject &request,
                 bool ok, const QJsonObject &result = {},
                 const QString &code = {}, const QString &message = {},
                 bool retryable = false);
    void runCommand(QLocalSocket *socket, const QJsonObject &request,
                    const QString &program, const QStringList &arguments,
                    std::function<QJsonObject(const QByteArray &, int)> parser = {},
                    int timeoutMs = -1,
                    const QString &cacheKey = QString(), int cacheTtlMs = 0);
    void applySystemTheme(QLocalSocket *socket, const QJsonObject &request,
                          bool dark);
    void runNetworkRefresh(QLocalSocket *socket, const QJsonObject &request);
    void runNetworkDetails(QLocalSocket *socket, const QJsonObject &request,
                           const QString &device);
    void runNetworkConnect(QLocalSocket *socket, const QJsonObject &request,
                           const NmConnectRequest &connect);
    void runBluetoothList(QLocalSocket *socket, const QJsonObject &request);
    void sendEvent(QLocalSocket *socket, const QJsonObject &event);
    QString requestId(const QJsonObject &request) const;
    QString operation(const QJsonObject &request) const;

    // Reply cache shared by the periodically polled read operations. Entries
    // are keyed by operation (plus device for network.details) and expire on
    // a TTL or on a matching D-Bus change notification, whichever comes
    // first. Writes invalidate their domain's keys before spawning so the
    // settle-polling the Shell does after a toggle never reads stale state.
    struct CachedReply {
        bool ok = false;
        QJsonObject result;
        QString code;
        QString message;
        bool retryable = true;
        qint64 expiresAt = 0;
    };
    struct PendingReply {
        QPointer<QLocalSocket> socket;
        QJsonObject request;
    };
    bool serveCachedReply(QLocalSocket *socket, const QJsonObject &request,
                          const QString &key);
    void storeReply(const QString &key, int ttlMs, bool ok,
                    const QJsonObject &result = {}, const QString &code = {},
                    const QString &message = {}, bool retryable = false);
    void invalidateReplies(const QString &keyPrefix);
    // Returns true when a fetch for `key` is already running and this request
    // was queued onto it; false means the caller must start the fetch itself
    // and finish it with completeInFlight().
    bool queueIfInFlight(const QString &key, QLocalSocket *socket,
                         const QJsonObject &request);
    void completeInFlight(const QString &key, bool ok,
                          const QJsonObject &result = {},
                          const QString &code = {}, const QString &message = {},
                          bool retryable = false, int ttlMs = 0);
    void watchNmPath(const QString &path);
    void watchBluezManager();
    void watchBluezPath(const QString &path);
    void watchBrightnessPath(const QString &service, const QString &path);
    void watchNightLight();
    void startAudioEventWatcher(const QString &pactl);

    bool handleClipboard(QLocalSocket *socket, const QJsonObject &request);
    bool handleApplication(QLocalSocket *socket, const QJsonObject &request);
    bool handleFileOperation(QLocalSocket *socket, const QJsonObject &request);
    bool handleKWin(QLocalSocket *socket, const QJsonObject &request);
    bool handleAppMenu(QLocalSocket *socket, const QJsonObject &request);
    bool handleInput(QLocalSocket *socket, const QJsonObject &request);
    bool handleSystemOperation(QLocalSocket *socket, const QJsonObject &request);
    bool handleStateOperation(QLocalSocket *socket, const QJsonObject &request);
    void startClipboardHistoryWatcher(QProcess *&watcher,
                                      const QStringList &arguments);
    void runClipboardDecode(QLocalSocket *socket, const QJsonObject &request,
                            const QString &record);
    void runClipboardDelete(QLocalSocket *socket, const QJsonObject &request,
                            const QString &record);
    // Runs `cliphist decode <record>` and hands the raw bytes back. Shared by
    // the thumbnail renderer and the pin store, which both need the decoded
    // payload rather than a copy into the clipboard.
    void runCliphistDecode(const QString &record,
                           std::function<void(bool, const QByteArray &)> done);
    void runWlCopy(const QByteArray &payload, std::function<void(bool)> done);
    void runClipboardThumb(QLocalSocket *socket, const QJsonObject &request,
                           const QString &record);
    void runClipboardPinnedList(QLocalSocket *socket, const QJsonObject &request);
    void runClipboardPinnedAdd(QLocalSocket *socket, const QJsonObject &request,
                               const QString &record, const QString &preview);
    void runClipboardPinnedRemove(QLocalSocket *socket, const QJsonObject &request,
                                  const QString &pinId);
    void runClipboardPinnedCopy(QLocalSocket *socket, const QJsonObject &request,
                                const QString &pinId);

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
    // Used together with KWin's persistent Active setting: the setting keeps
    // the choice across login, while the cookie applies it immediately in the
    // current compositor session (KWin does not hot-reload NightColor Active).
    std::optional<quint32> m_nightLightInhibitionCookie;
    bool m_watchImages = true;
    // clipboard.history.list rides the reply cache; these track the last
    // cliphist output hash + prune time so the thumbs sweep runs only on real
    // changes, not on every panel refresh.
    QByteArray m_lastClipboardListHash;
    qint64 m_lastClipboardPruneMs = 0;
    QHash<QString, CachedReply> m_replyCache;
    QHash<QString, QList<PendingReply>> m_inFlightReplies;
    QSet<QString> m_nmWatchedPaths;
    QSet<QString> m_bluezWatchedPaths;
    // "service path" pairs: the KDE brightness service name differs between
    // powerdevil generations, so the watch key carries the resolved service.
    QSet<QString> m_brightnessWatched;
    bool m_bluezManagerWatched = false;
    bool m_nightLightWatched = false;
    QProcess *m_audioEventWatcher = nullptr;
    // file.copy work runs here so a multi-GB copy cannot stall the socket
    // event loop. Declared last so it is destroyed first: ~QThreadPool waits
    // for in-flight copies (bounded file IO) before members go away.
    QThreadPool m_copyPool;
    // Synchronous NM/BlueZ-class D-Bus walks (network.refresh/details) run
    // here off the socket event loop. Declared last so ~QThreadPool waits for
    // in-flight workers (bounded calls) before members go away.
    QThreadPool m_dbusPool;
};

} // namespace KosPlatform
