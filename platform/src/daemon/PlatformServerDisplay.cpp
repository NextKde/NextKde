#include "PlatformServer.h"
#include "PlatformDbus.h"
#include "PlatformProcess.h"

#include <QByteArray>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QSettings>
#include <QStandardPaths>
#include <QStringList>
#include <memory>

namespace KosPlatform {
using namespace Detail;

namespace {

constexpr int kBrightnessCacheTtlMs = 10000;

constexpr int kNightLightCacheTtlMs = 10000;

std::unique_ptr<QDBusInterface> openScreenBrightness(QString &serviceName)
{
    for (const QString &candidate : {QStringLiteral("org.kde.ScreenBrightness"),
                                     QStringLiteral("org.kde.Solid.PowerManagement")}) {
        auto interface = std::make_unique<QDBusInterface>(
            candidate, QStringLiteral("/org/kde/ScreenBrightness"),
            QStringLiteral("org.kde.ScreenBrightness"), QDBusConnection::sessionBus());
        interface->setTimeout(kDbusCallTimeoutMs);
        if (interface->isValid()) {
            serviceName = candidate;
            return interface;
        }
    }
    return nullptr;
}

QString screenBrightnessPath(const QString &displayId)
{
    return QStringLiteral("/org/kde/ScreenBrightness/") + displayId;
}

QJsonObject readKdeBrightness(QString *serviceNameOut = nullptr,
                              QStringList *displayIdsOut = nullptr)
{
    QString serviceName;
    auto screenBrightness = openScreenBrightness(serviceName);
    if (!screenBrightness)
        return {{QStringLiteral("available"), false}};

    const QStringList displayIds = screenBrightness->property("DisplaysDBusNames").toStringList();
    if (serviceNameOut)
        *serviceNameOut = serviceName;
    if (displayIdsOut)
        *displayIdsOut = displayIds;
    QJsonArray displays;
    QJsonObject primary;
    for (const QString &displayId : displayIds) {
        if (displayId.isEmpty() || displayId.contains(QLatin1Char('/')))
            continue;
        QDBusInterface display(serviceName, screenBrightnessPath(displayId),
                               QStringLiteral("org.kde.ScreenBrightness.Display"),
                               QDBusConnection::sessionBus());
        display.setTimeout(kDbusCallTimeoutMs);
        if (!display.isValid())
            continue;
        const int maximum = display.property("MaxBrightness").toInt();
        if (maximum <= 0)
            continue;
        const int current = qBound(0, display.property("Brightness").toInt(), maximum);
        const bool internal = display.property("IsInternal").toBool();
        const QString label = display.property("Label").toString().trimmed();
        const QJsonObject item{
            {QStringLiteral("id"), displayId},
            {QStringLiteral("label"), label.isEmpty() ? displayId : label},
            {QStringLiteral("isInternal"), internal},
            {QStringLiteral("percent"), qRound(current * 100.0 / maximum)},
            {QStringLiteral("brightness"), current},
            {QStringLiteral("maximum"), maximum}
        };
        displays.append(item);
        if (primary.isEmpty() || (internal && !primary.value(QStringLiteral("isInternal")).toBool()))
            primary = item;
    }
    if (primary.isEmpty())
        return {{QStringLiteral("available"), false}};
    return {
        {QStringLiteral("available"), true},
        {QStringLiteral("percent"), primary.value(QStringLiteral("percent"))},
        {QStringLiteral("device"), primary.value(QStringLiteral("label"))},
        {QStringLiteral("displayId"), primary.value(QStringLiteral("id"))},
        {QStringLiteral("displays"), displays}
    };
}

bool setKdeDisplayBrightness(const QString &displayId, int percent)
{
    QString serviceName;
    auto screenBrightness = openScreenBrightness(serviceName);
    if (!screenBrightness)
        return false;
    const QStringList displayIds = screenBrightness->property("DisplaysDBusNames").toStringList();
    if (!displayIds.contains(displayId))
        return false;
    QDBusInterface display(serviceName, screenBrightnessPath(displayId),
                           QStringLiteral("org.kde.ScreenBrightness.Display"),
                           QDBusConnection::sessionBus());
    display.setTimeout(kDbusCallTimeoutMs);
    if (!display.isValid())
        return false;
    const int maximum = display.property("MaxBrightness").toInt();
    if (maximum <= 0)
        return false;
    const int target = qRound(qBound(0, percent, 100) * maximum / 100.0);
    const QDBusMessage reply = display.call(QStringLiteral("SetBrightness"), target,
                                            static_cast<uint>(0));
    return reply.type() == QDBusMessage::ReplyMessage;
}

QJsonObject readSysfsBrightness()
{
    const QDir backlights(QStringLiteral("/sys/class/backlight"));
    const QFileInfoList entries = backlights.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot,
                                                           QDir::Name);
    for (const QFileInfo &entry : entries) {
        QFile currentFile(entry.filePath() + QStringLiteral("/brightness"));
        QFile maximumFile(entry.filePath() + QStringLiteral("/max_brightness"));
        if (!currentFile.open(QIODevice::ReadOnly) || !maximumFile.open(QIODevice::ReadOnly))
            continue;
        bool currentOk = false;
        bool maximumOk = false;
        const int current = QString::fromUtf8(currentFile.readAll()).trimmed().toInt(&currentOk);
        const int maximum = QString::fromUtf8(maximumFile.readAll()).trimmed().toInt(&maximumOk);
        if (!currentOk || !maximumOk || maximum <= 0)
            continue;
        return QJsonObject{{QStringLiteral("available"), true},
                           {QStringLiteral("percent"), qRound(qBound(0.0,
                               current * 100.0 / maximum, 100.0))},
                           {QStringLiteral("device"), entry.fileName()},
                           {QStringLiteral("maximum"), maximum}};
    }
    return QJsonObject{{QStringLiteral("available"), false}};
}

QJsonObject parseBrightness(const QByteArray &output, int exitCode)
{
    if (exitCode != 0)
        return QJsonObject{{QStringLiteral("available"), false}};
    const QString text = QString::fromUtf8(output).trimmed();
    // brightnessctl -m: device,class,current,max,percentage
    const QStringList fields = text.split(QChar(','));
    if (fields.size() >= 5) {
        const auto match = QRegularExpression(QStringLiteral("(\\d+)%")).match(fields.at(4));
        if (match.hasMatch())
            return QJsonObject{{QStringLiteral("available"), true},
                               {QStringLiteral("percent"), match.captured(1).toInt()},
                               {QStringLiteral("device"), fields.at(0)}};
    }
    return QJsonObject{{QStringLiteral("available"), false}};
}

// 解析 kscreen-doctor -j 输出，提取屏幕输出列表及各屏幕的优先级 (Priority)
QJsonObject parseDisplayOutputs(const QByteArray &output, int exitCode)
{
    if (exitCode != 0)
        return QJsonObject{{QStringLiteral("available"), false}};
    QJsonParseError error{};
    const QJsonDocument doc = QJsonDocument::fromJson(output, &error);
    if (error.error != QJsonParseError::NoError || !doc.isObject())
        return QJsonObject{{QStringLiteral("available"), false}};

    const QJsonArray outputs = doc.object().value(QStringLiteral("outputs")).toArray();
    QJsonArray resultOutputs;
    for (const auto &val : outputs) {
        const QJsonObject item = val.toObject();
        if (!item.value(QStringLiteral("connected")).toBool() || !item.value(QStringLiteral("enabled")).toBool())
            continue;
        resultOutputs.append(QJsonObject{
            {QStringLiteral("name"), item.value(QStringLiteral("name")).toString()},
            {QStringLiteral("priority"), item.value(QStringLiteral("priority")).toInt()},
            {QStringLiteral("connected"), true},
            {QStringLiteral("enabled"), true}
        });
    }
    return QJsonObject{
        {QStringLiteral("available"), true},
        {QStringLiteral("outputs"), resultOutputs}
    };
}

} // namespace

bool PlatformServer::handleDisplayOperation(QLocalSocket *socket, const QJsonObject &request)
{
    const QString op = operation(request);
    const QJsonObject payload = request.value(QStringLiteral("payload")).toObject();
    if (op == QStringLiteral("nightlight.get")) {
        const QString key = QStringLiteral("nightlight.get");
        if (serveCachedReply(socket, request, key))
            return true;
        watchNightLight();
        QDBusInterface nightLight(QStringLiteral("org.kde.KWin"),
                                  QStringLiteral("/org/kde/KWin/NightLight"),
                                  QStringLiteral("org.kde.KWin.NightLight"),
                                  QDBusConnection::sessionBus());
        nightLight.setTimeout(kDbusCallTimeoutMs);
        if (!nightLight.isValid()) {
            const QString code = QStringLiteral("nightlight-unavailable");
            const QString message = QStringLiteral("夜灯服务不可用");
            respond(socket, request, false, {}, code, message, true);
            storeReply(key, kNightLightCacheTtlMs, false, {}, code, message, true);
            return true;
        }
        const bool available = nightLight.property("available").toBool();
        const bool runtimeEnabled = nightLight.property("enabled").toBool();
        const QString configPath = QStandardPaths::writableLocation(
            QStandardPaths::ConfigLocation) + QStringLiteral("/kwinrc");
        QSettings settings(configPath, QSettings::IniFormat);
        const bool enabled = settings.value(
            QStringLiteral("NightColor/Active"), runtimeEnabled).toBool();
        if (!enabled && runtimeEnabled && !m_nightLightInhibitionCookie.has_value()) {
            const QDBusMessage reply = nightLight.call(QStringLiteral("inhibit"));
            if (reply.type() != QDBusMessage::ErrorMessage && !reply.arguments().isEmpty())
                m_nightLightInhibitionCookie = reply.arguments().constFirst().toUInt();
        }
        const bool running = nightLight.property("running").toBool();
        const bool inhibited = m_nightLightInhibitionCookie.has_value()
            || nightLight.property("inhibited").toBool();
        const uint mode = nightLight.property("mode").toUInt();
        const uint targetTemp = nightLight.property("targetTemperature").toUInt();
        const uint currentTemp = nightLight.property("currentTemperature").toUInt();

        const bool isWarm = enabled && running && !inhibited;

        QJsonObject result{
            {QStringLiteral("available"), available},
            {QStringLiteral("enabled"), enabled},
            {QStringLiteral("running"), isWarm},
            {QStringLiteral("inhibited"), inhibited},
            {QStringLiteral("mode"), static_cast<int>(mode)},
            {QStringLiteral("targetTemperature"), static_cast<int>(targetTemp)},
            {QStringLiteral("currentTemperature"), static_cast<int>(currentTemp)}
        };
        respond(socket, request, true, result);
        storeReply(key, kNightLightCacheTtlMs, true, result);
        return true;
    }
    if (op == QStringLiteral("nightlight.toggle")) {
        invalidateReplies(QStringLiteral("nightlight."));
        QDBusInterface nightLight(QStringLiteral("org.kde.KWin"),
                                  QStringLiteral("/org/kde/KWin/NightLight"),
                                  QStringLiteral("org.kde.KWin.NightLight"),
                                  QDBusConnection::sessionBus());
        nightLight.setTimeout(kDbusCallTimeoutMs);
        if (!nightLight.isValid()
            || !nightLight.property("available").toBool()) {
            respond(socket, request, false, {}, QStringLiteral("nightlight-unavailable"),
                    QStringLiteral("夜灯服务不可用"), true);
            return true;
        }

        const QString configPath = QStandardPaths::writableLocation(
            QStandardPaths::ConfigLocation) + QStringLiteral("/kwinrc");
        QSettings settings(configPath, QSettings::IniFormat);
        const bool currentEnabled = settings.value(
            QStringLiteral("NightColor/Active"),
            nightLight.property("enabled").toBool()).toBool();
        const bool requestedEnabled = payload.contains(QStringLiteral("enabled"))
            ? payload.value(QStringLiteral("enabled")).toBool()
            : !currentEnabled;

        // Active is KWin's persistent master switch. Change only this key so
        // the user's mode, schedule, location, and temperature remain intact.
        settings.setValue(QStringLiteral("NightColor/Active"), requestedEnabled);
        settings.sync();
        if (settings.status() != QSettings::NoError) {
            respond(socket, request, false, {}, QStringLiteral("nightlight-config-failed"),
                    QStringLiteral("无法保存夜灯开关状态"), true);
            return true;
        }

        // The config write already committed, so any failure past this point
        // is partial application, not a failed toggle: the requested state is
        // persisted and KWin will converge on it at the next reconfigure.
        // Report ok with applied:false (and a warning string) so the Shell
        // aligns its UI to the persisted state instead of rolling back to a
        // value that no longer matches kwinrc.
        bool applied = true;
        QString warning;
        if (requestedEnabled && m_nightLightInhibitionCookie.has_value()) {
            const QDBusMessage reply = nightLight.call(
                QStringLiteral("uninhibit"), *m_nightLightInhibitionCookie);
            if (reply.type() == QDBusMessage::ErrorMessage) {
                applied = false;
                warning = QStringLiteral("夜灯已启用，但未能立即恢复");
            } else {
                m_nightLightInhibitionCookie.reset();
            }
        } else if (!requestedEnabled && !m_nightLightInhibitionCookie.has_value()) {
            const QDBusMessage reply = nightLight.call(QStringLiteral("inhibit"));
            if (reply.type() == QDBusMessage::ErrorMessage || reply.arguments().isEmpty()) {
                applied = false;
                warning = QStringLiteral("夜灯已关闭，但未能立即暂停当前效果");
            } else {
                m_nightLightInhibitionCookie = reply.arguments().constFirst().toUInt();
            }
        }

        QDBusInterface kwin(QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"),
                            QStringLiteral("org.kde.KWin"), QDBusConnection::sessionBus());
        kwin.setTimeout(kDbusCallTimeoutMs);
        const QDBusMessage reconfigureReply = kwin.call(QStringLiteral("reconfigure"));
        if (reconfigureReply.type() == QDBusMessage::ErrorMessage) {
            applied = false;
            warning = QStringLiteral("夜灯状态已保存，但 KWin 未能立即应用");
        }

        const bool available = nightLight.property("available").toBool();
        const bool running = nightLight.property("running").toBool();
        const bool inhibited = m_nightLightInhibitionCookie.has_value()
            || nightLight.property("inhibited").toBool();

        QJsonObject result{
            {QStringLiteral("available"), available},
            {QStringLiteral("enabled"), requestedEnabled},
            {QStringLiteral("running"), requestedEnabled && running && !inhibited},
            {QStringLiteral("inhibited"), inhibited},
            {QStringLiteral("applied"), applied}
        };
        if (!warning.isEmpty())
            result.insert(QStringLiteral("warning"), warning);
        respond(socket, request, true, result);
        return true;
    }
    if (op == QStringLiteral("display.outputs.get")) {
        const QString key = QStringLiteral("display.outputs.get");
        if (serveCachedReply(socket, request, key))
            return true;
        const QString kscreenDoctor = QStandardPaths::findExecutable(QStringLiteral("kscreen-doctor"));
        if (!kscreenDoctor.isEmpty()) {
            runCommand(socket, request, kscreenDoctor, {QStringLiteral("-j")},
                       parseDisplayOutputs, kDefaultCommandTimeoutMs,
                       key, 1000);
            return true;
        }
        respond(socket, request, false, {}, QStringLiteral("kscreen-doctor-unavailable"),
                QStringLiteral("kscreen-doctor 不可用"), false);
        return true;
    }
    if (op == QStringLiteral("display.brightness.get")) {
        const QString key = QStringLiteral("display.brightness.get");
        if (serveCachedReply(socket, request, key))
            return true;
        QString brightnessService;
        QStringList displayIds;
        const QJsonObject kdeBrightness = readKdeBrightness(&brightnessService, &displayIds);
        if (kdeBrightness.value(QStringLiteral("available")).toBool()) {
            watchBrightnessPath(brightnessService,
                                QStringLiteral("/org/kde/ScreenBrightness"));
            for (const QString &displayId : displayIds)
                watchBrightnessPath(brightnessService, screenBrightnessPath(displayId));
            // The brightness poll doubles as the aging heartbeat: even in a
            // session that never opens the network popup, stale watches are
            // still dropped.
            pruneStaleDbusWatches();
            respond(socket, request, true, kdeBrightness);
            storeReply(key, kBrightnessCacheTtlMs, true, kdeBrightness);
            return true;
        }
        const QString brightnessctl = QStandardPaths::findExecutable(QStringLiteral("brightnessctl"));
        if (!brightnessctl.isEmpty()) {
            runCommand(socket, request, brightnessctl, {QStringLiteral("-m")},
                       parseBrightness, kDefaultCommandTimeoutMs,
                       key, kBrightnessCacheTtlMs);
        } else {
            const QJsonObject sysfs = readSysfsBrightness();
            respond(socket, request, true, sysfs);
            storeReply(key, kBrightnessCacheTtlMs, true, sysfs);
        }
        return true;
    }
    if (op == QStringLiteral("display.brightness.set")) {
        invalidateReplies(QStringLiteral("display.brightness."));
        const int value = qBound(0, payload.value(QStringLiteral("percent")).toInt(), 100);
        const QString displayId = payload.value(QStringLiteral("displayId")).toString();
        if (!displayId.isEmpty()) {
            if (!setKdeDisplayBrightness(displayId, value)) {
                respond(socket, request, false, {}, QStringLiteral("brightness-display-set-failed"),
                        QStringLiteral("无法设置指定显示器亮度"), true);
                return true;
            }
            respond(socket, request, true, {
                {QStringLiteral("displayId"), displayId},
                {QStringLiteral("percent"), value}
            });
            return true;
        }
        const QString brightnessctl = QStandardPaths::findExecutable(QStringLiteral("brightnessctl"));
        if (!brightnessctl.isEmpty()) {
            runCommand(socket, request, brightnessctl,
                       {QStringLiteral("set"), QStringLiteral("%1%").arg(value)});
            return true;
        }
        const QJsonObject backlight = readSysfsBrightness();
        if (!backlight.value(QStringLiteral("available")).toBool()) {
            respond(socket, request, false, {}, QStringLiteral("brightness-unavailable"),
                    QStringLiteral("亮度控制不可用"), false);
            return true;
        }
        const quint32 rawValue = qRound(value * backlight.value(QStringLiteral("maximum")).toInt() / 100.0);
        QDBusInterface session(QStringLiteral("org.freedesktop.login1"),
                               QStringLiteral("/org/freedesktop/login1/session/auto"),
                               QStringLiteral("org.freedesktop.login1.Session"),
                               QDBusConnection::systemBus());
        session.setTimeout(kDbusCallTimeoutMs);
        const QDBusMessage reply = session.call(QStringLiteral("SetBrightness"),
                                                QStringLiteral("backlight"),
                                                backlight.value(QStringLiteral("device")).toString(), rawValue);
        if (reply.type() == QDBusMessage::ErrorMessage)
            respond(socket, request, false, {}, QStringLiteral("brightness-set-failed"),
                    QStringLiteral("无法设置显示亮度"), true);
        else
            respond(socket, request, true, QJsonObject{{QStringLiteral("percent"), value}});
        return true;
    }
    return false;
}

} // namespace KosPlatform
