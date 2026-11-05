#include "PlatformServer.h"
#include "PlatformDbus.h"
#include "PlatformProcess.h"

#include <QByteArray>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingCall>
#include <functional>
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

    if (screenBrightness) {
        const QStringList displayIds = screenBrightness->property("DisplaysDBusNames").toStringList();
        if (serviceNameOut)
            *serviceNameOut = serviceName;
        if (displayIdsOut)
            *displayIdsOut = displayIds;
        QJsonArray displays;
        QJsonObject primary;
        const QString currentSeat = qEnvironmentVariable("XDG_SEAT").trimmed();
        const bool preferExternal = (!currentSeat.isEmpty() && currentSeat != QStringLiteral("seat0"));

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
            if (primary.isEmpty()) {
                primary = item;
            } else if (preferExternal && !internal && primary.value(QStringLiteral("isInternal")).toBool()) {
                primary = item;
            } else if (!preferExternal && internal && !primary.value(QStringLiteral("isInternal")).toBool()) {
                primary = item;
            }
        }
        if (!primary.isEmpty()) {
            return {
                {QStringLiteral("available"), true},
                {QStringLiteral("percent"), primary.value(QStringLiteral("percent"))},
                {QStringLiteral("device"), primary.value(QStringLiteral("label"))},
                {QStringLiteral("displayId"), primary.value(QStringLiteral("id"))},
                {QStringLiteral("displays"), displays}
            };
        }
    }

    // Fall back to single-display / internal panel interface: org.kde.Solid.PowerManagement.Actions.BrightnessControl
    QDBusInterface kde(QStringLiteral("org.kde.Solid.PowerManagement"),
                       QStringLiteral("/org/kde/Solid/PowerManagement/Actions/BrightnessControl"),
                       QStringLiteral("org.kde.Solid.PowerManagement.Actions.BrightnessControl"),
                       QDBusConnection::sessionBus());
    kde.setTimeout(kDbusCallTimeoutMs);
    if (kde.isValid()) {
        const QDBusReply<int> maxReply = kde.call(QStringLiteral("brightnessMax"));
        if (maxReply.isValid() && maxReply.value() > 0) {
            const int maximum = maxReply.value();
            const QDBusReply<int> curReply = kde.call(QStringLiteral("brightness"));
            if (curReply.isValid()) {
                const int current = curReply.value();
                const int percent = qRound(qBound(0.0, current * 100.0 / maximum, 100.0));
                return {
                    {QStringLiteral("available"), true},
                    {QStringLiteral("percent"), percent},
                    {QStringLiteral("device"), QStringLiteral("kde-solid")},
                    {QStringLiteral("maximum"), maximum}
                };
            }
        }
    }

    return {{QStringLiteral("available"), false}};
}

// One request owns its watchers. Discover once, then write displays in parallel;
// no QDBusInterface construction/introspection or synchronous calls on this path.
class BrightnessWrite final : public QObject {
public:
    using Done = std::function<void(bool, bool, QJsonObject, QString)>;
    BrightnessWrite(QObject *owner, QString id, int percent, Done done)
        : QObject(owner), m_id(std::move(id)), m_percent(percent), m_done(std::move(done)) {}

    void start() { discover(0); }

private:
    void call(const QString &service, const QString &path, const QString &interface,
              const QString &method, const QVariantList &args,
              std::function<void(const QDBusMessage &)> done)
    {
        auto message = QDBusMessage::createMethodCall(service, path, interface, method);
        message.setArguments(args);
        auto *watcher = new QDBusPendingCallWatcher(
            QDBusConnection::sessionBus().asyncCall(message, kDbusCallTimeoutMs), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this,
                [watcher, done = std::move(done)] {
            const auto reply = watcher->reply();
            watcher->deleteLater();
            done(reply);
        });
    }

    void property(const QString &service, const QString &path, const QString &interface,
                  const QString &name, std::function<void(const QDBusMessage &)> done)
    {
        call(service, path, QStringLiteral("org.freedesktop.DBus.Properties"),
             QStringLiteral("Get"), {interface, name}, std::move(done));
    }

    static QVariant value(const QDBusMessage &reply)
    {
        if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty())
            return {};
        return unwrapDbusValue(reply.arguments().first());
    }

    void finish(bool handled, bool ok, QJsonObject result = {}, QString error = {})
    {
        m_done(handled, ok, result, error);
        deleteLater();
    }

    void discover(int index)
    {
        const QStringList services{QStringLiteral("org.kde.ScreenBrightness"),
                                   QStringLiteral("org.kde.Solid.PowerManagement")};
        if (index == services.size()) {
            if (!m_id.isEmpty())
                finish(true, false, {}, QStringLiteral("brightness-display-set-failed"));
            else
                solid();
            return;
        }
        const QString service = services.at(index);
        property(service, QStringLiteral("/org/kde/ScreenBrightness"),
                 QStringLiteral("org.kde.ScreenBrightness"), QStringLiteral("DisplaysDBusNames"),
                 [this, service, index](const QDBusMessage &reply) {
            QStringList ids = qdbus_cast<QStringList>(value(reply));
            ids.removeDuplicates();
            ids.removeIf([](const QString &id) {
                static const QRegularExpression segment(QStringLiteral("^[A-Za-z0-9_]+$"));
                return !segment.match(id).hasMatch();
            });
            if (ids.isEmpty()) {
                discover(index + 1);
                return;
            }
            if (!m_id.isEmpty()) {
                if (!ids.contains(m_id)) {
                    finish(true, false, {}, QStringLiteral("brightness-display-set-failed"));
                    return;
                }
                ids = {m_id};
            }
            m_pending = ids.size();
            for (const auto &id : ids)
                writeDisplay(service, id);
        });
    }

    void writeDisplay(const QString &service, const QString &id)
    {
        property(service, screenBrightnessPath(id), QStringLiteral("org.kde.ScreenBrightness.Display"),
                 QStringLiteral("MaxBrightness"), [this, service, id](const QDBusMessage &reply) {
            bool valid = false;
            const int maximum = value(reply).toInt(&valid);
            if (!valid || maximum <= 0) {
                displayDone(id, false);
                return;
            }
            const int target = qRound(m_percent * (maximum / 100.0));
            call(service, screenBrightnessPath(id), QStringLiteral("org.kde.ScreenBrightness.Display"),
                 QStringLiteral("SetBrightness"), {target, uint(0)},
                 [this, id](const QDBusMessage &written) {
                displayDone(id, written.type() == QDBusMessage::ReplyMessage);
            });
        });
    }

    void displayDone(const QString &id, bool ok)
    {
        m_results.append(QJsonObject{{QStringLiteral("displayId"), id}, {QStringLiteral("ok"), ok}});
        if (ok) ++m_succeeded;
        if (--m_pending != 0) return;
        const bool all = m_succeeded == m_results.size();
        QJsonObject result{{QStringLiteral("displays"), m_results}};
        if (!m_id.isEmpty()) result.insert(QStringLiteral("displayId"), m_id);
        if (all) result.insert(QStringLiteral("percent"), m_percent);
        // An advertised display that fails is not replaced by a write to some
        // other backend/device, even if every display failed.
        finish(true, all, result, all ? QString() : m_succeeded > 0
            ? QStringLiteral("brightness-partial-failure")
            : QStringLiteral("brightness-display-set-failed"));
    }

    void solid()
    {
        const QString service = QStringLiteral("org.kde.Solid.PowerManagement");
        const QString path = QStringLiteral("/org/kde/Solid/PowerManagement/Actions/BrightnessControl");
        const QString interface = QStringLiteral("org.kde.Solid.PowerManagement.Actions.BrightnessControl");
        call(service, path, interface, QStringLiteral("brightnessMax"), {},
             [this, service, path, interface](const QDBusMessage &reply) {
            bool valid = false;
            const int maximum = value(reply).toInt(&valid);
            if (!valid || maximum <= 0) {
                finish(false, false); // No KDE backend: permit the legacy fallback.
                return;
            }
            const int target = qRound(m_percent * (maximum / 100.0));
            call(service, path, interface, QStringLiteral("setBrightness"), {target},
                 [this](const QDBusMessage &written) {
                const bool ok = written.type() == QDBusMessage::ReplyMessage;
                finish(true, ok, ok ? QJsonObject{{QStringLiteral("percent"), m_percent}} : QJsonObject{},
                       ok ? QString() : QStringLiteral("brightness-set-failed"));
            });
        });
    }

    QString m_id;
    int m_percent;
    Done m_done;
    int m_pending = 0;
    int m_succeeded = 0;
    QJsonArray m_results;
};

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
        int percent = 0;
        if (payload.contains(QStringLiteral("percent")))
            percent = payload.value(QStringLiteral("percent")).toInt();
        else if (request.contains(QStringLiteral("percent")))
            percent = request.value(QStringLiteral("percent")).toInt();
        const int value = qBound(0, percent, 100);
        const QString displayId = payload.value(QStringLiteral("displayId")).toString();
        const QPointer<QLocalSocket> guarded(socket);
        auto *write = new BrightnessWrite(this, displayId, value,
            [this, guarded, request, value](bool handled, bool ok, QJsonObject result, QString error) {
            invalidateReplies(QStringLiteral("display.brightness."));
            if (handled) {
                respond(guarded.data(), request, ok, result, error,
                        ok ? QString() : QStringLiteral("部分或全部显示器亮度设置失败"), !ok, result);
                return;
            }
            QLocalSocket *socket = guarded.data();
            if (!socket) return;
            const QString brightnessctl = QStandardPaths::findExecutable(QStringLiteral("brightnessctl"));
            if (!brightnessctl.isEmpty()) {
                runCommand(socket, request, brightnessctl,
                           {QStringLiteral("set"), QStringLiteral("%1%").arg(value)});
                return;
            }
            const QJsonObject backlight = readSysfsBrightness();
            if (!backlight.value(QStringLiteral("available")).toBool()) {
                respond(socket, request, false, {}, QStringLiteral("brightness-unavailable"),
                        QStringLiteral("亮度控制不可用"), false);
                return;
            }
            const quint32 rawValue = qRound(value * backlight.value(QStringLiteral("maximum")).toInt() / 100.0);
            auto message = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.login1"),
                QStringLiteral("/org/freedesktop/login1/session/auto"),
                QStringLiteral("org.freedesktop.login1.Session"), QStringLiteral("SetBrightness"));
            message.setArguments({QStringLiteral("backlight"), backlight.value(QStringLiteral("device")).toString(), rawValue});
            auto *watcher = new QDBusPendingCallWatcher(
                QDBusConnection::systemBus().asyncCall(message, kDbusCallTimeoutMs), this);
            connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, guarded, request, value, watcher] {
                const bool ok = watcher->reply().type() == QDBusMessage::ReplyMessage;
                watcher->deleteLater();
                invalidateReplies(QStringLiteral("display.brightness."));
                respond(guarded.data(), request, ok, ok ? QJsonObject{{QStringLiteral("percent"), value}} : QJsonObject{},
                        ok ? QString() : QStringLiteral("brightness-set-failed"),
                        ok ? QString() : QStringLiteral("无法设置显示亮度"), !ok);
            });
        });
        write->start();
        return true;
    }
    return false;
}

} // namespace KosPlatform
