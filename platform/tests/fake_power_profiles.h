#pragma once

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusError>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusVariant>
#include <QDBusVirtualObject>
#include <QCoreApplication>
#include <QEventLoop>
#include <QTimer>
#include "../src/daemon/PowerProfilesBus.h"
#include <QMetaType>
#include <QStringList>
#include <QVariant>

// Synchronous adapters are test-only: production callers never spin an event loop.
namespace KosPlatform {
inline PowerProfileSnapshot readPowerProfiles(const QDBusConnection &bus)
{
    QEventLoop loop;
    PowerProfileSnapshot result;
    requestPowerProfiles(bus, &loop, [&](PowerProfileSnapshot snapshot) {
        result = snapshot;
        loop.quit();
    });
    loop.exec();
    return result;
}
inline bool writePowerProfile(const QDBusConnection &bus, const QString &profile)
{
    QEventLoop loop;
    bool ok = false;
    requestPowerProfiles(bus, &loop, [&](PowerProfileSnapshot snapshot) {
        ok = snapshot.ok;
        loop.quit();
    }, profile);
    loop.exec();
    return ok;
}
} // namespace KosPlatform

// One Profiles entry. Nesting a hand-built QDBusArgument in the
// Properties.Get variant crashes Qt 6.11's marshaller. A registered list
// of dicts is what produces the aa{sv} tuned-ppd sends.
struct FakePowerProfileRow {
    QString profile;
    QString driver;
};

inline QDBusArgument &operator<<(QDBusArgument &argument, const FakePowerProfileRow &row)
{
    argument.beginMap(QMetaType::fromType<QString>(), QMetaType::fromType<QDBusVariant>());
    argument.beginMapEntry();
    argument << QStringLiteral("Profile") << QDBusVariant(row.profile);
    argument.endMapEntry();
    argument.beginMapEntry();
    argument << QStringLiteral("Driver") << QDBusVariant(row.driver);
    argument.endMapEntry();
    argument.endMap();
    return argument;
}

inline const QDBusArgument &operator>>(const QDBusArgument &argument, FakePowerProfileRow &row)
{
    argument.beginMap();
    while (!argument.atEnd()) {
        QString key;
        QDBusVariant value;
        argument.beginMapEntry();
        argument >> key >> value;
        argument.endMapEntry();
        if (key == QLatin1String("Profile"))
            row.profile = value.variant().toString();
        else if (key == QLatin1String("Driver"))
            row.driver = value.variant().toString();
    }
    argument.endMap();
    return argument;
}

Q_DECLARE_METATYPE(FakePowerProfileRow)
Q_DECLARE_METATYPE(QList<FakePowerProfileRow>)

// No Q_OBJECT: the virtual-object hooks are enough, and the tests must not
// depend on moc seeing this header. Serve it from a child process so the
// read crosses dbus-daemon instead of Qt's same-process marshaller.
class FakePowerProfiles : public QDBusVirtualObject {
public:
    QStringList modes{QStringLiteral("power-saver"), QStringLiteral("custom"),
                      QStringLiteral("balanced"), QStringLiteral("performance")};
    QString active = QStringLiteral("balanced");
    QString degraded = QStringLiteral("no");
    QString reject;
    bool stick = false;

    QString introspect(const QString &) const override { return {}; }

    bool handleMessage(const QDBusMessage &message, const QDBusConnection &connection) override
    {
        if (qEnvironmentVariableIsSet("KOS_FAKE_HANG"))
            return true;
        const int delay = qEnvironmentVariableIntValue("KOS_FAKE_DELAY");
        if (delay > 0) {
            QTimer::singleShot(delay, this, [this, message, connection] {
                replyTo(message, connection);
            });
            return true;
        }
        return replyTo(message, connection);
    }

    bool replyTo(const QDBusMessage &message, const QDBusConnection &connection)
    {
        const QString member = message.member();
        const QList<QVariant> arguments = message.arguments();
        if (member == QLatin1String("Get") && arguments.size() >= 2) {
            const QString name = arguments.at(1).toString();
            QVariant value;
            if (name == QLatin1String("ActiveProfile"))
                value = active;
            else if (name == QLatin1String("PerformanceDegraded"))
                value = degraded;
            else if (name == QLatin1String("Profiles")) {
                QList<FakePowerProfileRow> rows;
                for (const QString &mode : modes)
                    rows.append(FakePowerProfileRow{mode, QStringLiteral("tuned")});
                value = QVariant::fromValue(rows);
            }
            else {
                connection.send(message.createErrorReply(QDBusError::UnknownProperty, name));
                return true;
            }
            QDBusMessage reply = message.createReply();
            reply << QVariant::fromValue(QDBusVariant(value));
            connection.send(reply);
            return true;
        }
        if (member == QLatin1String("Set") && arguments.size() >= 3) {
            const QString name = arguments.at(1).toString();
            if (name != QLatin1String("ActiveProfile")) {
                connection.send(message.createErrorReply(QDBusError::UnknownProperty, name));
                return true;
            }
            QVariant value = arguments.at(2);
            if (value.metaType() == QMetaType::fromType<QDBusVariant>())
                value = qvariant_cast<QDBusVariant>(value).variant();
            const QString next = value.toString();
            if (!reject.isEmpty() && next == reject) {
                connection.send(message.createErrorReply(QDBusError::NotSupported,
                                                         QStringLiteral("rejected")));
                return true;
            }
            if (!stick)
                active = next;
            connection.send(message.createReply());
            return true;
        }
        return false;
    }

    bool registerOn(QDBusConnection bus, const QString &service, const QString &path)
    {
        return bus.registerVirtualObject(path, this) && bus.registerService(service);
    }

    static int serve(const QString &which)
    {
        qDBusRegisterMetaType<FakePowerProfileRow>();
        qDBusRegisterMetaType<QList<FakePowerProfileRow>>();
        FakePowerProfiles fake;
        const QByteArray active = qgetenv("KOS_FAKE_ACTIVE");
        const QByteArray degraded = qgetenv("KOS_FAKE_DEGRADED");
        const QByteArray reject = qgetenv("KOS_FAKE_REJECT");
        if (!active.isEmpty())
            fake.active = QString::fromUtf8(active);
        if (!degraded.isNull())
            fake.degraded = QString::fromUtf8(degraded);
        if (!reject.isEmpty())
            fake.reject = QString::fromUtf8(reject);
        fake.stick = qEnvironmentVariableIntValue("KOS_FAKE_STICK") == 1;
        QDBusConnection bus = QDBusConnection::systemBus();
        const bool hadess = which == QLatin1String("hadess");
        const bool registered = hadess
            ? fake.registerOn(bus, QStringLiteral("net.hadess.PowerProfiles"),
                              QStringLiteral("/net/hadess/PowerProfiles"))
            : fake.registerOn(bus, QStringLiteral("org.freedesktop.UPower.PowerProfiles"),
                              QStringLiteral("/org/freedesktop/UPower/PowerProfiles"));
        if (!bus.isConnected() || !registered)
            return 2;
        return QCoreApplication::exec();
    }
};
