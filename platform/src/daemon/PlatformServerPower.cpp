#include "PlatformServer.h"
#include "PowerProfilesBus.h"
#include "StatusPanelData.h"
#include "BatteryData.h"

#include <QDBusConnection>

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
    const QPointer<QLocalSocket> guarded(socket);
    const auto fallback = [this, guarded, request, writing, profile] {
        requestPowerProfiles(QDBusConnection::systemBus(), this,
            [this, guarded, request, writing](const PowerProfileSnapshot &snapshot) {
                if (snapshot.ok) {
                    respond(guarded.data(), request, true,
                            writing ? QJsonObject() : powerProfileObject(snapshot));
                } else {
                    const QString code = snapshot.timedOut ? QStringLiteral("command-timeout")
                        : writing ? QStringLiteral("command-failed")
                                  : QStringLiteral("command-unavailable");
                    respond(guarded.data(), request, false, {}, code,
                            QStringLiteral("Power profile request failed"), true);
                }
            }, writing ? profile : QString());
    };
    if (!powerProfilesCommandAvailable()) {
        fallback();
    } else if (reading) {
        runCommand(socket, request, QStringLiteral("powerprofilesctl"), {QStringLiteral("list")},
            [](const QByteArray &output, int) { return parsePowerProfiles(output); },
            3000, {}, 0, fallback);
    } else {
        runCommand(socket, request, QStringLiteral("powerprofilesctl"),
                   {QStringLiteral("set"), profile}, {}, 10000, {}, 0, fallback);
    }
    return true;
}
}
