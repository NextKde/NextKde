#include "LockScreenNotifications.h"

#include <QDBusMessage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QSet>
#include <cmath>
#include <sys/socket.h>
#include <unistd.h>

namespace KosPlatform {
namespace {
const auto service = QStringLiteral("org.kos.LockScreen");
const auto path = QStringLiteral("/org/kos/LockScreen");
const auto interface = QStringLiteral("org.kos.LockScreen1");

bool sameUser(QLocalSocket *socket)
{
    if (!socket || socket->state() != QLocalSocket::ConnectedState) return false;
    struct ucred credentials {};
    socklen_t size = sizeof(credentials);
    return ::getsockopt(socket->socketDescriptor(), SOL_SOCKET, SO_PEERCRED,
                        &credentials, &size) == 0
        && size == sizeof(credentials) && credentials.uid == ::geteuid();
}

bool validPayload(const QJsonObject &payload)
{
    if (payload.size() != 1 || !payload.value("notifications").isArray()) return false;
    const auto rows = payload.value("notifications").toArray();
    if (rows.size() > 4) return false;
    static const QRegularExpression iconName(QStringLiteral("\\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\\z"));
    static const QRegularExpression controls(QStringLiteral("[\\x{0000}-\\x{001f}\\x{007f}]"));
    QSet<QString> ids;
    for (const auto &value : rows) {
        if (!value.isObject()) return false;
        const auto row = value.toObject();
        if (row.size() != 6) return false;
        for (const auto &key : {"id", "appName", "appIcon", "summary", "body"})
            if (!row.value(QLatin1String(key)).isString()) return false;
        const auto id = row.value("id").toString();
        const auto name = row.value("appName").toString();
        const auto icon = row.value("appIcon").toString();
        const auto time = row.value("createdAt");
        if (id.isEmpty() || id.size() > 64 || ids.contains(id) || controls.match(id).hasMatch()
            || name.size() > 256 || controls.match(name).hasMatch()
            || (!icon.isEmpty() && !iconName.match(icon).hasMatch())
            || !row.value("summary").toString().isEmpty() || !row.value("body").toString().isEmpty()
            || !time.isDouble() || !std::isfinite(time.toDouble()) || time.toDouble() <= 0
            || time.toDouble() > 9007199254740991.0 || std::floor(time.toDouble()) != time.toDouble())
            return false;
        ids.insert(id);
    }
    return true;
}
} // namespace

LockScreenNotifications::LockScreenNotifications(QObject *parent)
    : QObject(parent), m_bus(QDBusConnection::sessionBus())
{
    m_expiry.setSingleShot(true);
    m_expiry.setInterval(leaseMs);
    connect(&m_expiry, &QTimer::timeout, this, &LockScreenNotifications::clear);
}

LockScreenNotifications::~LockScreenNotifications()
{
    if (m_exported) {
        m_bus.unregisterObject(path);
        m_bus.unregisterService(service);
    }
}

bool LockScreenNotifications::ensureExported()
{
    if (m_exported) return true;
    // Default registration neither queues nor replaces an existing owner.
    if (!m_bus.registerService(service)) return false;
    if (!m_bus.registerObject(path, this, QDBusConnection::ExportScriptableSlots
                             | QDBusConnection::ExportScriptableProperties)) {
        m_bus.unregisterService(service);
        return false;
    }
    m_exported = true;
    return true;
}

QString LockScreenNotifications::publish(QLocalSocket *publisher, const QJsonObject &payload)
{
    if (!sameUser(publisher)) return QStringLiteral("lockscreen-publisher-denied");
    if (!validPayload(payload)) return QStringLiteral("invalid-lockscreen-notifications");
    if (m_publisher && m_publisher != publisher) return QStringLiteral("lockscreen-publisher-busy");
    if (!ensureExported()) return QStringLiteral("lockscreen-bridge-unavailable");
    if (!m_publisher) {
        m_publisher = publisher;
        m_disconnect = connect(publisher, &QLocalSocket::disconnected, this, &LockScreenNotifications::clear);
    }
    setJson(QString::fromUtf8(QJsonDocument(payload.value("notifications").toArray()).toJson(QJsonDocument::Compact)));
    m_expiry.start();
    return {};
}

void LockScreenNotifications::clear()
{
    disconnect(m_disconnect);
    m_publisher.clear();
    m_expiry.stop();
    setJson(QStringLiteral("[]"));
}

void LockScreenNotifications::setJson(const QString &json)
{
    if (json == m_json) return;
    m_json = json;
    auto signal = QDBusMessage::createSignal(path, QStringLiteral("org.freedesktop.DBus.Properties"),
                                           QStringLiteral("PropertiesChanged"));
    signal << interface << QVariantMap{{QStringLiteral("NotificationsJson"), m_json}} << QStringList{};
    m_bus.send(signal);
}
} // namespace KosPlatform
