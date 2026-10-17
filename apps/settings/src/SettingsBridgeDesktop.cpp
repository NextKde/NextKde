#include "SettingsBridge.h"

#include <QDBusArgument>
#include <QDBusError>
#include <QDBusMetaType>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusInterface>
#include <QDBusVariant>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDateTime>
#include <QThread>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>

void SettingsBridge::launchSystemSettings()
{
    callShell(QStringLiteral("app-launch"),
        { QStringLiteral("open"), QStringLiteral("org.kde.systemsettings.desktop") },
        QStringLiteral("Unable to open KDE system settings"), RequestKind::OpenApp);
}

void SettingsBridge::dockSnapshot() { callDock({ QStringLiteral("snapshot") }); }

void SettingsBridge::updateDockLayout(double height)
{
    callDock({ QStringLiteral("updateLayout"), QString::number(height, 'f', 2) });
}

void SettingsBridge::updateDockPosition(const QString& position)
{
    callDock({ QStringLiteral("updatePosition"), position });
}

void SettingsBridge::updateDockBuiltinVisibility(const QString& id, bool visible)
{
    callShell(QStringLiteral("dock-settings"),
        { QStringLiteral("updateBuiltinVisibility"), id,
            visible ? QStringLiteral("true") : QStringLiteral("false") },
        QStringLiteral("Dock icon display request failed"), RequestKind::DockBuiltinVisibility);
}

void SettingsBridge::notificationSnapshot()
{
    callShell(QStringLiteral("notification-settings"), { QStringLiteral("snapshot") },
        QStringLiteral("无法读取通知设置"), RequestKind::Notifications);
}

void SettingsBridge::setNotificationPreference(const QString& key, bool value)
{
    callShell(QStringLiteral("notification-settings"),
        { QStringLiteral("setPreference"), key,
            value ? QStringLiteral("true") : QStringLiteral("false") },
        QStringLiteral("通知设置更新失败"), RequestKind::Notifications);
}

void SettingsBridge::setNotificationBlocked(const QString& key, bool blocked)
{
    callShell(QStringLiteral("notification-settings"),
        { QStringLiteral("setBlocked"), key,
            blocked ? QStringLiteral("true") : QStringLiteral("false") },
        QStringLiteral("应用通知设置更新失败"), RequestKind::Notifications);
}

void SettingsBridge::updateDockNotificationBadgeVisibility(bool visible)
{
    callShell(QStringLiteral("dock-settings"),
        { QStringLiteral("updateNotificationBadgeVisibility"),
            visible ? QStringLiteral("true") : QStringLiteral("false") },
        QStringLiteral("Dock notification badge request failed"),
        RequestKind::DockNotificationBadgeVisibility);
}

void SettingsBridge::updateDockRevealIndicatorVisibility(bool visible)
{
    callShell(QStringLiteral("dock-settings"),
        { QStringLiteral("updateRevealIndicatorVisibility"),
            visible ? QStringLiteral("true") : QStringLiteral("false") },
        QStringLiteral("Dock hide hint bar request failed"),
        RequestKind::DockRevealIndicatorVisibility);
}

void SettingsBridge::updateDockContentStyle(const QString& style)
{
    callDock({ QStringLiteral("updateContentStyle"), style });
}

void SettingsBridge::updateDockStyle(const QString& style)
{
    callDock({ QStringLiteral("updateDockStyle"), style });
}

void SettingsBridge::updateDockHoverScale(double scale)
{
    callDock({ QStringLiteral("updateHoverScale"), QString::number(scale, 'f', 4) });
}

void SettingsBridge::updateDockCornerRadius(double ratio)
{
    callDock({ QStringLiteral("updateCornerRadiusRatio"), QString::number(ratio, 'f', 4) });
}

void SettingsBridge::updateDockIconMode(const QString& mode)
{
    callDock({ QStringLiteral("updateIconMode"), mode });
}

void SettingsBridge::updateDockIconOpacity(double opacity)
{
    callDock({ QStringLiteral("updateIconOpacity"), QString::number(opacity, 'f', 2) });
}

void SettingsBridge::updateDockIconTintColor(const QString& color)
{
    callDock({ QStringLiteral("updateIconTintColor"), color });
}

void SettingsBridge::updateDockVisibilityMode(const QString& mode)
{
    callDock({ QStringLiteral("updateVisibilityMode"), mode });
}

void SettingsBridge::updateDockWindowGrouping(const QString& mode)
{
    callDock({ QStringLiteral("updateWindowGrouping"), mode });
}

void SettingsBridge::launcherSnapshot() { callLauncher({ QStringLiteral("snapshot") }); }

void SettingsBridge::shortcutsSnapshot() { callShortcuts({ QStringLiteral("snapshot") }); }

void SettingsBridge::updateShortcut(const QString& id, const QString& combo)
{
    callShortcuts({ QStringLiteral("updateShortcut"), id, combo });
}

void SettingsBridge::resetShortcut(const QString& id)
{
    callShortcuts({ QStringLiteral("resetShortcut"), id });
}

void SettingsBridge::updateLauncherDisplayMode(const QString& mode)
{
    callLauncher({ QStringLiteral("updateDisplayMode"), mode });
}

void SettingsBridge::updateLauncherProfileIconSize(const QString& mode, const QString& size)
{
    callLauncher({ QStringLiteral("updateProfileIconSize"), mode, size });
}

void SettingsBridge::updateLauncherProfileDensity(const QString& mode, const QString& density)
{
    callLauncher({ QStringLiteral("updateProfileDensity"), mode, density });
}

void SettingsBridge::updateLauncherProfileFontWeight(const QString& mode, const QString& weight)
{
    callLauncher({ QStringLiteral("updateProfileFontWeight"), mode, weight });
}

void SettingsBridge::resetLauncherLayoutProfile(const QString& mode)
{
    callLauncher({ QStringLiteral("resetProfile"), mode });
}

void SettingsBridge::integrationSnapshot()
{
    if (m_integrationPending)
        return;
    m_integrationPending = true;
    callShell(QStringLiteral("integration-status"), { QStringLiteral("snapshot") },
        QStringLiteral("Integration status request failed"), RequestKind::Integration);
}

void SettingsBridge::i18nSnapshot() { callI18n({ QStringLiteral("snapshot") }); }

void SettingsBridge::updateLanguage(const QString& language)
{
    callI18n({ QStringLiteral("updateLanguage"), language });
}

QVariantMap SettingsBridge::notificationSnapshotFromReply(const QString& payload)
{
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &error);
    const QJsonObject object = document.object();
    if (error.error != QJsonParseError::NoError || !document.isObject()
        || !object.value(QStringLiteral("ready")).isBool()
        || !object.value(QStringLiteral("sources")).isArray()
        || !object.value(QStringLiteral("blockedKeys")).isArray()) {
        setLastError(QStringLiteral("桌面环境返回了无效的通知设置"));
        return { };
    }
    setLastError({ });
    return object.toVariantMap();
}

QVariantMap SettingsBridge::snapshotFromReply(const QString& payload)
{
    if (payload.isEmpty())
        return { };

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        setLastError(
            QStringLiteral("The desktop environment returned an invalid Dock configuration"));
        return { };
    }

    const QJsonObject object = document.object();
    if (!object.contains(QStringLiteral("baseHeight"))
        || !object.contains(QStringLiteral("windowGrouping"))) {
        setLastError(
            QStringLiteral("The Dock configuration from the desktop environment is incomplete"));
        return { };
    }

    setLastError({ });
    return {
        { QStringLiteral("baseHeight"), object.value(QStringLiteral("baseHeight")).toDouble() },
        { QStringLiteral("position"), object.value(QStringLiteral("position")).toString() },
        // contentStyle/dockStyle are read straight back by the dock page's
        // applyState; without them the two pickers snap back to index 0 on
        // every snapshot refresh.
        { QStringLiteral("contentStyle"), object.value(QStringLiteral("contentStyle")).toString() },
        { QStringLiteral("dockStyle"), object.value(QStringLiteral("dockStyle")).toString() },
        // Hover magnification. The shell sends the effective values, so an
        // untouched profile opens on exactly what the Dock is drawing; the
        // fallbacks match the macOS defaults the page starts with.
        { QStringLiteral("hoverScale"), object.value(QStringLiteral("hoverScale")).toDouble(1.19) },
        // Dock corner rounding as a fraction of dock height. Defaults to 0.5
        // (half-circle cap), the pre-setting behaviour when no value is stored.
        { QStringLiteral("cornerRadiusRatio"), object.value(QStringLiteral("cornerRadiusRatio")).toDouble(0.5) },
        { QStringLiteral("iconMode"), object.value(QStringLiteral("iconMode")).toString() },
        { QStringLiteral("iconOpacity"), object.value(QStringLiteral("iconOpacity")).toDouble() },
        { QStringLiteral("iconTintColor"),
            object.value(QStringLiteral("iconTintColor")).toString() },
        { QStringLiteral("visibilityMode"),
            object.value(QStringLiteral("visibilityMode")).toString() },
        { QStringLiteral("windowGrouping"),
            object.value(QStringLiteral("windowGrouping")).toString() },
        { QStringLiteral("showLauncher"),
            object.value(QStringLiteral("showLauncher")).toBool(true) },
        { QStringLiteral("showTrash"), object.value(QStringLiteral("showTrash")).toBool(true) },
        { QStringLiteral("showNotificationBadges"),
            object.value(QStringLiteral("showNotificationBadges")).toBool(true) },
        { QStringLiteral("showRevealIndicator"),
            object.value(QStringLiteral("showRevealIndicator")).toBool(true) },
    };
}

QVariantMap SettingsBridge::i18nSnapshotFromReply(const QString& payload)
{
    if (payload.isEmpty())
        return { };

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        setLastError(
            QStringLiteral("The desktop environment returned an invalid language configuration"));
        return { };
    }

    const QJsonObject object = document.object();
    setLastError({ });
    return {
        { QStringLiteral("language"),
            object.value(QStringLiteral("language")).toString(QStringLiteral("zh-CN")) },
    };
}

QVariantMap SettingsBridge::launcherSnapshotFromReply(const QString& payload)
{
    if (payload.isEmpty())
        return { };

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        setLastError(
            QStringLiteral("The desktop environment returned an invalid launcher configuration"));
        return { };
    }

    const QJsonObject object = document.object();
    if (!object.contains(QStringLiteral("displayMode"))) {
        setLastError(QStringLiteral(
            "The launcher configuration from the desktop environment is incomplete"));
        return { };
    }

    setLastError({ });
    return {
        { QStringLiteral("displayMode"), object.value(QStringLiteral("displayMode")).toString() },
        { QStringLiteral("layoutProfiles"),
            object.value(QStringLiteral("layoutProfiles")).toObject().toVariantMap() },
    };
}

QVariantMap SettingsBridge::integrationSnapshotFromReply(const QString& payload)
{
    if (payload.isEmpty())
        return { { QStringLiteral("shellReady"), false } };

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        setLastError(
            QStringLiteral("The desktop environment returned an invalid integration status"));
        return { { QStringLiteral("shellReady"), false } };
    }
    setLastError({ });
    return document.object().toVariantMap();
}

QVariantMap SettingsBridge::shortcutsSnapshotFromReply(const QString& payload)
{
    if (payload.isEmpty())
        return { };

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        setLastError(
            QStringLiteral("The desktop environment returned an invalid shortcuts configuration"));
        return { };
    }

    const QJsonObject object = document.object();
    if (!object.contains(QStringLiteral("shortcuts"))) {
        setLastError(QStringLiteral(
            "The shortcuts configuration from the desktop environment is incomplete"));
        return { };
    }

    QVariantList shortcuts;
    for (const QJsonValue& value : object.value(QStringLiteral("shortcuts")).toArray()) {
        const QJsonObject item = value.toObject();
        shortcuts.append(QVariantMap {
            { QStringLiteral("id"), item.value(QStringLiteral("id")).toString() },
            { QStringLiteral("description"), item.value(QStringLiteral("description")).toString() },
            { QStringLiteral("defaultCombo"),
                item.value(QStringLiteral("defaultCombo")).toString() },
            { QStringLiteral("combo"), item.value(QStringLiteral("combo")).toString() },
            { QStringLiteral("custom"), item.value(QStringLiteral("custom")).toBool() },
        });
    }

    // The Shell validates rebinding requests and reports rejections
    // (unknown id, malformed combo, duplicate binding) inline instead of
    // failing the IPC call, so surface it the same way as transport errors.
    const QString error = object.value(QStringLiteral("error")).toString();
    setLastError(error);
    return {
        { QStringLiteral("shortcuts"), shortcuts },
        { QStringLiteral("error"), error },
    };
}

namespace {
// A probe runs on a worker thread whose owner joins it during shutdown; every
// D-Bus round-trip in it must be bounded or a hung service stalls the exit for
// as long as the service stays silent (measured at 4.5s against a 5s-lag
// responder). kDbusProbeTimeoutMs mirrors the daemon's kDbusCallTimeoutMs.
constexpr int kDbusProbeTimeoutMs = 2000;

QDBusMessage boundedBusCall(const QDBusConnection& bus, const QString& service,
    const QString& path, const QString& interface, const QString& method,
    const QVariantList& arguments = {})
{
    QDBusInterface target(service, path, interface, bus);
    target.setTimeout(kDbusProbeTimeoutMs);
    if (arguments.isEmpty())
        return target.call(method);
    return target.callWithArgumentList(QDBus::Block, method, arguments);
}

} // namespace

void SettingsBridge::startIntegrationProbe(const QVariantMap& replyMap)
{
    m_probeTasks.start(
        [replyMap] {
            QVariantMap result = replyMap;

            const QDBusConnection sessionBus = QDBusConnection::sessionBus();
            auto* busInterface = sessionBus.interface();
            const QThread* worker = QThread::currentThread();
            QString notificationProvider = QStringLiteral("none");
            QString notificationOwner;
            uint notificationPid = 0;
            if (busInterface && !worker->isInterruptionRequested()) {
                // Direct bus messages with an explicit timeout: serviceOwner/
                // servicePid on the shared QDBusConnectionInterface cannot be
                // bounded, and a hung notification service would stall the
                // probe past its owner's shutdown join.
                const QDBusMessage ownerReply = boundedBusCall(sessionBus,
                    QStringLiteral("org.freedesktop.DBus"),
                    QStringLiteral("/org/freedesktop/DBus"),
                    QStringLiteral("org.freedesktop.DBus"), QStringLiteral("GetNameOwner"),
                    { QVariant(QStringLiteral("org.freedesktop.Notifications")) });
                if (ownerReply.type() == QDBusMessage::ReplyMessage
                    && !ownerReply.arguments().isEmpty()) {
                    notificationOwner = ownerReply.arguments().constFirst().toString();
                }
                if (!notificationOwner.isEmpty()) {
                    const QDBusMessage pidReply = boundedBusCall(sessionBus,
                        QStringLiteral("org.freedesktop.DBus"),
                        QStringLiteral("/org/freedesktop/DBus"),
                        QStringLiteral("org.freedesktop.DBus"), QStringLiteral("GetConnectionUnixProcessID"),
                        { QVariant(notificationOwner) });
                    if (pidReply.type() == QDBusMessage::ReplyMessage
                        && !pidReply.arguments().isEmpty()) {
                        notificationPid = pidReply.arguments().constFirst().toUInt();
                    }

                    QFile commandLine(QStringLiteral("/proc/%1/cmdline").arg(notificationPid));
                    QString command;
                    if (commandLine.open(QIODevice::ReadOnly)) {
                        QByteArray raw = commandLine.readAll();
                        raw.replace('\0', ' ');
                        command = QString::fromLocal8Bit(raw).trimmed();
                    }
                    if (command.contains(QStringLiteral("plasmashell"))) {
                        notificationProvider = QStringLiteral("plasma");
                    } else if (command.contains(QStringLiteral("/qs"))
                        || command.contains(QStringLiteral("quickshell"))) {
                        notificationProvider = QStringLiteral("kos");
                    } else {
                        notificationProvider = QStringLiteral("other");
                    }
                    result.insert(QStringLiteral("notificationCommand"), command);
                }
            }
            result.insert(QStringLiteral("notificationProvider"), notificationProvider);
            result.insert(QStringLiteral("notificationOwner"), notificationOwner);
            result.insert(QStringLiteral("notificationPid"), notificationPid);

            const bool interrupted = worker->isInterruptionRequested();
            // loadedEffects is an async Q_PROPERTY, not a D-Bus method: read it
            // through the Properties interface so the round-trip carries the
            // same explicit timeout as everything else in this probe.
            QStringList loadedEffects;
            bool kwinAvailable = false;
            if (!interrupted) {
                QDBusInterface effectsService(QStringLiteral("org.kde.KWin"),
                    QStringLiteral("/org/kde/KWin"),
                    QStringLiteral("org.freedesktop.DBus.Properties"), sessionBus);
                effectsService.setTimeout(kDbusProbeTimeoutMs);
                const QDBusMessage propertyReply = effectsService.call(QStringLiteral("Get"),
                    QStringLiteral("org.kde.kwin.Effects"), QStringLiteral("loadedEffects"));
                kwinAvailable = propertyReply.type() == QDBusMessage::ReplyMessage;
                if (kwinAvailable && !propertyReply.arguments().isEmpty()) {
                    const QDBusArgument argument
                        = qvariant_cast<QDBusArgument>(propertyReply.arguments().constFirst());
                    argument.beginArray();
                    while (!argument.atEnd()) {
                        QDBusVariant element;
                        argument >> element;
                        loadedEffects.append(element.variant().toString());
                    }
                    argument.endArray();
                }
            }
            result.insert(
                QStringLiteral("glassLoaded"), loadedEffects.contains(QStringLiteral("glass")));
            result.insert(QStringLiteral("dockAnimationLoaded"),
                loadedEffects.contains(QStringLiteral("kos_dock_window_animation")));
            result.insert(QStringLiteral("contextMenuInputLoaded"),
                loadedEffects.contains(QStringLiteral("kos_context_menu_input")));
            result.insert(QStringLiteral("updatedAt"),
                QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss")));

            return result;
        },
        [this](const QVariantMap& result) {
            m_integrationPending = false;
            emit integrationSnapshotChanged(result);
        });
}

void SettingsBridge::callDock(const QStringList& arguments)
{
    callShell(QStringLiteral("dock-settings"), arguments,
        QStringLiteral("Dock settings request failed"), RequestKind::Dock);
}

void SettingsBridge::pumpDockRequests()
{
    if (m_dockBusy || m_dockQueue.isEmpty())
        return;
    m_dockBusy = true;
    const DockRequest request = m_dockQueue.takeFirst();
    sendShellRequest(
        QStringLiteral("dock-settings"), request.arguments, request.fallbackError, request.kind);
}

QVariantMap SettingsBridge::latestDockState(const QString& payload)
{
    const QVariantMap state = snapshotFromReply(payload);
    // Intermediate acknowledgements clear pending flags without replacing
    // a newer selection that is still queued for the Shell.
    return m_dockQueue.isEmpty() ? state : QVariantMap { };
}

void SettingsBridge::finishDockRequest()
{
    m_dockBusy = false;
    pumpDockRequests();
}

void SettingsBridge::callLauncher(const QStringList& arguments)
{
    callShell(QStringLiteral("applauncher-settings"), arguments,
        QStringLiteral("Launcher settings request failed"), RequestKind::Launcher);
}

void SettingsBridge::callShortcuts(const QStringList& arguments)
{
    callShell(QStringLiteral("shortcuts-settings"), arguments,
        QStringLiteral("Shortcuts request failed"), RequestKind::Shortcuts);
}

void SettingsBridge::callI18n(const QStringList& arguments)
{
    callShell(QStringLiteral("i18n-settings"), arguments,
        QStringLiteral("Language settings request failed"), RequestKind::I18nSnapshot);
}
