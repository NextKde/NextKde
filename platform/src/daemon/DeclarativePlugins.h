#pragma once

#include <QJsonObject>
#include <QObject>
#include <QPointer>
#include <QLocalSocket>
#include <QHash>
#include <QElapsedTimer>
#include <functional>
#include <memory>
#include <atomic>

namespace KosPlatform {

// Trusted frontend adapter for data packages. Never a generic plugin IPC bridge.
class DeclarativePlugins final : public QObject {
public:
    using Reply = std::function<void(bool, const QJsonObject &, const QString &, const QString &)>;
    explicit DeclarativePlugins(QObject *parent = nullptr);
    ~DeclarativePlugins() override;
    void request(QLocalSocket *peer, const QString &operation, const QJsonObject &payload, Reply reply);

private:
    struct Store;
    std::shared_ptr<Store> m_store;
    bool m_busy = false;
    QElapsedTimer m_clock;
    QHash<QLocalSocket *, qint64> m_lastRequest;
    QHash<QString, std::shared_ptr<std::atomic_bool>> m_connections;
};

} // namespace KosPlatform
