#pragma once

#include <QDBusConnection>
#include <QJsonObject>
#include <QLocalSocket>
#include <QObject>
#include <QPointer>
#include <QTimer>

namespace KosPlatform {

// No D-Bus setters, actions or notification-server interface. Publication is
// only accepted from an authenticated, connected platform JSONL socket.
class LockScreenNotifications final : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kos.LockScreen1")
    Q_PROPERTY(QString NotificationsJson READ notificationsJson)

public:
    explicit LockScreenNotifications(QObject *parent = nullptr);
    ~LockScreenNotifications() override;
    QString notificationsJson() const { return m_json; }
    // Empty result means success; otherwise a stable protocol error code.
    QString publish(QLocalSocket *publisher, const QJsonObject &payload);
    static constexpr int leaseMs = 30000;

public slots:
    Q_SCRIPTABLE QString GetNotifications() const { return m_json; }

private:
    bool ensureExported();
    void clear();
    void setJson(const QString &json);
    QDBusConnection m_bus;
    bool m_exported = false;
    QString m_json = QStringLiteral("[]");
    QPointer<QLocalSocket> m_publisher;
    QMetaObject::Connection m_disconnect;
    QTimer m_expiry;
};

} // namespace KosPlatform
