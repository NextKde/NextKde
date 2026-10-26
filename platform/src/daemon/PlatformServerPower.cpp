#include "PlatformServer.h"
#include "StatusPanelData.h"
#include "BatteryData.h"

namespace KosPlatform {
bool PlatformServer::handlePowerOperation(QLocalSocket *socket, const QJsonObject &request)
{
    const QString op = operation(request);
    if (op == QStringLiteral("power.battery")) {
        // Bounded local sysfs reads, requested only while the popup is open.
        // No helper process, persistent watch, or caller-supplied file path.
        respond(socket, request, true, readBatteryDetails());
        return true;
    }
    if (op == QStringLiteral("power.profiles")) {
        runCommand(socket, request, QStringLiteral("powerprofilesctl"), {QStringLiteral("list")},
            [](const QByteArray &output, int) { return parsePowerProfiles(output); }, 3000);
        return true;
    }
    if (op != QStringLiteral("power.profile.set")) return false;
    const QString profile = request.value(QStringLiteral("payload")).toObject().value(QStringLiteral("profile")).toString();
    if (profile != QStringLiteral("power-saver") && profile != QStringLiteral("balanced")
        && profile != QStringLiteral("performance")) {
        respond(socket, request, false, {}, QStringLiteral("invalid-profile"),
            QStringLiteral("Unsupported power profile"), false);
        return true;
    }
    runCommand(socket, request, QStringLiteral("powerprofilesctl"), {QStringLiteral("set"), profile}, {}, 10000);
    return true;
}
}
