#include "PowerProfilesBus.h"

#include "PlatformDbus.h"

#include <QDBusConnection>
#include <QDBusPendingCallWatcher>
#include <QTimer>
#include <utility>
#include <iterator>
#include <QDBusMessage>
#include <QDBusVariant>
#include <QJsonArray>
#include <QStandardPaths>

namespace KosPlatform {
namespace {

struct Endpoint {
    const char *service;
    const char *path;
    const char *interface;
};

// Newer UPower name first. tuned-ppd and power-profiles-daemon each own one
// or both; the first name that answers is the one a later Set uses.
constexpr Endpoint kEndpoints[] = {
    {"org.freedesktop.UPower.PowerProfiles",
     "/org/freedesktop/UPower/PowerProfiles",
     "org.freedesktop.UPower.PowerProfiles"},
    {"net.hadess.PowerProfiles",
     "/net/hadess/PowerProfiles",
     "net.hadess.PowerProfiles"},
};

bool knownPowerProfile(const QString &profile)
{
    return profile == QLatin1String("power-saver")
        || profile == QLatin1String("balanced")
        || profile == QLatin1String("performance");
}

void appendKnown(const QString &name, QStringList *profiles)
{
    if (knownPowerProfile(name) && !profiles->contains(name))
        profiles->append(name);
}

bool decodeArgument(QDBusArgument argument, QStringList *profiles)
{
    if (argument.currentType() != QDBusArgument::ArrayType)
        return false;
    profiles->clear();
    argument.beginArray();
    while (!argument.atEnd()) {
        QVariantMap row;
        argument >> row;
        // a{sv} values arrive as QDBusVariant on some Qt builds and as the
        // inner string on others. unwrap is a no-op for a plain string.
        appendKnown(Detail::unwrapDbusValue(row.value(QStringLiteral("Profile"))).toString(),
                    profiles);
    }
    argument.endArray();
    return true;
}

} // namespace

bool powerProfilesCommandAvailable()
{
    return !QStandardPaths::findExecutable(QStringLiteral("powerprofilesctl")).isEmpty();
}

bool decodePowerProfileList(const QVariant &value, QStringList *profiles)
{
    if (!profiles)
        return false;
    const QVariant unwrapped = Detail::unwrapDbusValue(value);
    if (unwrapped.metaType() == QMetaType::fromType<QDBusArgument>())
        return decodeArgument(qvariant_cast<QDBusArgument>(unwrapped), profiles);
    // canConvert<QVariantList>() is true for unrelated types such as QString.
    if (unwrapped.metaType() != QMetaType::fromType<QVariantList>())
        return false;
    profiles->clear();
    for (const QVariant &entry : unwrapped.toList())
        appendKnown(Detail::variantMapFromDbusValue(entry).value(QStringLiteral("Profile")).toString(),
                    profiles);
    return true;
}

QString normalizePowerDegradation(const QString &value)
{
    const QString text = value.trimmed();
    return text.isEmpty() || text == QLatin1String("no") ? QString() : text;
}

QJsonObject powerProfileObject(const PowerProfileSnapshot &snapshot)
{
    QJsonArray profiles;
    for (const QString &name : snapshot.profiles)
        profiles.append(name);
    return {{QStringLiteral("profiles"), profiles},
            {QStringLiteral("activeProfile"), snapshot.activeProfile},
            {QStringLiteral("degraded"), snapshot.degraded}};
}

namespace {

class PowerProfileRequest final : public QObject {
public:
    PowerProfileRequest(const QDBusConnection &bus, QObject *context,
                        PowerProfileCompletion completion, const QString &profile)
        : QObject(context), m_bus(bus), m_completion(std::move(completion)), m_profile(profile)
    {
        m_deadline.setSingleShot(true);
        m_deadline.setTimerType(Qt::PreciseTimer);
        connect(&m_deadline, &QTimer::timeout, this, [this] {
            m_snapshot.ok = false;
            m_snapshot.timedOut = true;
            finish();
        });
    }

    void start()
    {
        m_deadline.start(m_profile.isEmpty() ? 2000 : 12000);
        // Always complete asynchronously, including invalid input.
        QTimer::singleShot(0, this, [this] {
            if (!m_profile.isEmpty() && !knownPowerProfile(m_profile))
                finish();
            else
                nextEndpoint();
        });
    }

private:
    void finish()
    {
        if (m_done)
            return;
        m_done = true;
        m_deadline.stop();
        auto completion = std::move(m_completion);
        const auto snapshot = m_snapshot;
        deleteLater();
        completion(snapshot);
    }

    void call(const QString &method, const QList<QVariant> &arguments,
              std::function<void(const QDBusMessage &)> done)
    {
        auto message = QDBusMessage::createMethodCall(m_snapshot.service, m_snapshot.path,
            QStringLiteral("org.freedesktop.DBus.Properties"), method);
        message.setArguments(arguments);
        auto *watcher = new QDBusPendingCallWatcher(
            m_bus.asyncCall(message, qMax(1, m_deadline.remainingTime())), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this,
                [this, done = std::move(done)](QDBusPendingCallWatcher *watcher) {
            const auto reply = watcher->reply();
            watcher->deleteLater();
            if (!m_done) {
                if (reply.type() == QDBusMessage::ErrorMessage
                    && reply.errorName() == QLatin1String("org.freedesktop.DBus.Error.NoReply")) {
                    m_snapshot.timedOut = true;
                    finish();
                } else {
                    done(reply);
                }
            }
        });
    }

    void get(const QString &property, std::function<void(QVariant)> done)
    {
        call(QStringLiteral("Get"), {m_snapshot.interface, property},
             [done = std::move(done)](const QDBusMessage &reply) {
            done(reply.type() == QDBusMessage::ReplyMessage && reply.arguments().size() == 1
                ? Detail::unwrapDbusValue(reply.arguments().constFirst()) : QVariant());
        });
    }

    void nextEndpoint()
    {
        if (++m_endpoint >= int(std::size(kEndpoints))) {
            finish();
            return;
        }
        const auto &endpoint = kEndpoints[m_endpoint];
        m_snapshot = {};
        m_snapshot.service = QString::fromUtf8(endpoint.service);
        m_snapshot.path = QString::fromUtf8(endpoint.path);
        m_snapshot.interface = QString::fromUtf8(endpoint.interface);
        get(QStringLiteral("Profiles"), [this](const QVariant &value) {
            if (!decodePowerProfileList(value, &m_snapshot.profiles)) {
                nextEndpoint();
                return;
            }
            get(QStringLiteral("ActiveProfile"), [this](const QVariant &value) {
                if (!value.isValid()) {
                    nextEndpoint();
                    return;
                }
                m_snapshot.activeProfile = value.toString();
                get(QStringLiteral("PerformanceDegraded"), [this](const QVariant &value) {
                    m_snapshot.degraded = normalizePowerDegradation(value.toString());
                    if (m_profile.isEmpty()) {
                        m_snapshot.ok = true;
                        finish();
                        return;
                    }
                    // Reuse the endpoint selected above. A denied Set never
                    // falls back to another name or another transport.
                    call(QStringLiteral("Set"), {m_snapshot.interface,
                         QStringLiteral("ActiveProfile"),
                         QVariant::fromValue(QDBusVariant(m_profile))},
                         [this](const QDBusMessage &reply) {
                        m_snapshot.ok = reply.type() == QDBusMessage::ReplyMessage;
                        finish();
                    });
                });
            });
        });
    }

    QDBusConnection m_bus;
    PowerProfileCompletion m_completion;
    QString m_profile;
    QTimer m_deadline;
    PowerProfileSnapshot m_snapshot;
    int m_endpoint = -1;
    bool m_done = false;
};

} // namespace

void requestPowerProfiles(const QDBusConnection &bus, QObject *context,
                          PowerProfileCompletion completion, const QString &profile)
{
    (new PowerProfileRequest(bus, context, std::move(completion), profile))->start();
}

} // namespace KosPlatform
