#include "PlatformServer.h"
#include "PowerProfilesBus.h"
#include "StatusPanelData.h"
#include "BatteryData.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusVariant>

namespace KosPlatform {
namespace {

bool knownPowerProfile(const QString &profile)
{
    return profile == QLatin1String("power-saver")
        || profile == QLatin1String("balanced")
        || profile == QLatin1String("performance");
}

} // namespace

bool PlatformServer::handlePowerOperation(QLocalSocket *socket, const QJsonObject &request)
{
    const QString op = operation(request);
    if (op == QStringLiteral("power.battery")) {
        // Bounded local sysfs reads, requested only while the popup is open.
        // No helper process, persistent watch, or caller-supplied file path.
        respond(socket, request, true, readBatteryDetails());
        return true;
    }
    const bool reading = op == QStringLiteral("power.profiles");
    const bool writing = op == QStringLiteral("power.profile.set");
    if (!reading && !writing)
        return false;
    const QString profile = request.value(QStringLiteral("payload")).toObject()
        .value(QStringLiteral("profile")).toString();
    if (writing && !knownPowerProfile(profile)) {
        respond(socket, request, false, {}, QStringLiteral("invalid-profile"),
                QStringLiteral("Unsupported power profile"), false);
        return true;
    }
    // Keep the helper wherever it is installed. Distributions that ship only
    // the PowerProfiles bus service (Fedora tuned-ppd) never have it on PATH.
    if (powerProfilesCommandAvailable()) {
        if (reading) {
            runCommand(socket, request, QStringLiteral("powerprofilesctl"), {QStringLiteral("list")},
                [](const QByteArray &output, int) { return parsePowerProfiles(output); }, 3000);
        } else {
            runCommand(socket, request, QStringLiteral("powerprofilesctl"),
                {QStringLiteral("set"), profile}, {}, 10000);
        }
        return true;
    }
    const QDBusConnection bus = QDBusConnection::systemBus();
    if (reading) {
        const PowerProfileSnapshot snapshot = readPowerProfiles(bus);
        if (!snapshot.ok) {
            respond(socket, request, false, {}, QStringLiteral("command-unavailable"),
                    QStringLiteral("平台命令不可用"), true);
        } else {
            respond(socket, request, true, powerProfileObject(snapshot));
        }
        return true;
    }
    // Property reads are short. Set can wait on a policy agent, so it must
    // not block the daemon thread. Ten seconds stays inside the shell
    // client's 15s budget for power.profile.set and matches the helper.
    const PowerProfileSnapshot snapshot = readPowerProfiles(bus);
    if (!snapshot.ok) {
        respond(socket, request, false, {}, QStringLiteral("command-failed"),
                QStringLiteral("平台命令执行失败"), true);
        return true;
    }
    QDBusMessage call = QDBusMessage::createMethodCall(
        snapshot.service, snapshot.path, QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("Set"));
    call.setArguments({snapshot.interface, QStringLiteral("ActiveProfile"),
                       QVariant::fromValue(QDBusVariant(profile))});
    auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(call, 10000), this);
    const QPointer<QLocalSocket> guarded(socket);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, guarded, request](QDBusPendingCallWatcher *completed) {
        const bool ok = completed->reply().type() == QDBusMessage::ReplyMessage;
        if (ok)
            respond(guarded.data(), request, true, {});
        else
            respond(guarded.data(), request, false, {}, QStringLiteral("command-failed"),
                    QStringLiteral("平台命令执行失败"), true);
        completed->deleteLater();
    });
    return true;
}
}
