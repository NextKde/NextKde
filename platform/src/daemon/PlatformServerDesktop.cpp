#include "PlatformServer.h"
#include "Shortcuts.h"
#include "PlatformDbus.h"
#include "PlatformPaths.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonValue>
#include <QProcess>
#include <QProcessEnvironment>
#include <QSet>
#include <QStandardPaths>
#include <QStringList>
#include <QVariant>

namespace KosPlatform {
using namespace Detail;

bool PlatformServer::handleDesktopOperation(QLocalSocket *socket, const QJsonObject &request)
{
    const QString op = operation(request);
    const QJsonObject payload = request.value(QStringLiteral("payload")).toObject();
    if (op == QStringLiteral("settings.open")) {
        QString module = payload.value(QStringLiteral("module")).toString();
        if (module == QStringLiteral("kcm_nightcolor")) {
            module = QStringLiteral("kcm_nightlight");
        }
        static const QSet<QString> allowedModules{
            QStringLiteral("kcm_bluetooth"),
            QStringLiteral("kcm_keys"),
            QStringLiteral("kcm_networkmanagement"),
            QStringLiteral("kcm_kscreen"),
            QStringLiteral("kcm_pulseaudio"),
            QStringLiteral("kcm_nightlight"),
            QStringLiteral("kcm_notifications"),
            QStringLiteral("kcm_soundtheme")};
        if (!allowedModules.contains(module)) {
            respond(socket, request, false, {}, QStringLiteral("invalid-settings-module"),
                    QStringLiteral("设置模块不受支持"), false);
            return true;
        }
        const QString kcmshell = QStandardPaths::findExecutable(QStringLiteral("kcmshell6"));
        const QString systemsettings = QStandardPaths::findExecutable(QStringLiteral("systemsettings"));
        const QString executable = !kcmshell.isEmpty() ? kcmshell : systemsettings;
        if (executable.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("settings-unavailable"),
                    QStringLiteral("KDE 系统设置不可用"), false);
            return true;
        }
        const bool started = QProcess::startDetached(executable, {module});
        respond(socket, request, started, {{QStringLiteral("started"), started}});
        return true;
    }
    if (op == QStringLiteral("settings.launch")) {
        // Fixed argv on purpose: the op exists so the Shell never has to spawn
        // a shell just to resolve kos-settings on PATH, and no caller-supplied
        // argument can turn it into arbitrary command execution.
        //
        // The only tunable is the environment: Settings talks back to its
        // Shell over Quickshell IPC, so a development Shell passes its
        // Quickshell.shellDir through `shellDir` and the child reconnects to
        // that same session instead of the installed `kos` configuration.
        // The value must canonicalise to an existing directory; it is data in
        // KOS_SHELL_DIR, never part of the argv.
        QString shellDir;
        const QJsonValue shellDirValue = payload.value(QStringLiteral("shellDir"));
        if (!shellDirValue.isUndefined()) {
            const QString raw = shellDirValue.toString();
            if (raw.isEmpty() || raw.size() > 1024 || raw.contains(QChar('\0'))) {
                respond(socket, request, false, {}, QStringLiteral("invalid-shell-dir"),
                        QStringLiteral("Shell 目录无效"), false);
                return true;
            }
            const QFileInfo info(raw);
            if (!info.isAbsolute()) {
                respond(socket, request, false, {}, QStringLiteral("invalid-shell-dir"),
                        QStringLiteral("Shell 目录无效"), false);
                return true;
            }
            const QString canonical = info.canonicalFilePath();
            if (canonical.isEmpty() || !QFileInfo(canonical).isDir()) {
                respond(socket, request, false, {}, QStringLiteral("invalid-shell-dir"),
                        QStringLiteral("Shell 目录无效"), false);
                return true;
            }
            shellDir = canonical;
        }
        const QString executable = resolveOwnExecutable(
            QStringLiteral("kos-settings"));
        if (executable.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("settings-unavailable"),
                    QStringLiteral("KOS 设置应用不可用"), true);
            return true;
        }
        QProcess process;
        process.setProgram(executable);
        if (!shellDir.isEmpty()) {
            QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
            environment.insert(QStringLiteral("KOS_SHELL_DIR"), shellDir);
            process.setProcessEnvironment(environment);
        }
        const bool started = process.startDetached();
        respond(socket, request, started, {{QStringLiteral("started"), started}});
        return true;
    }
    if (op == QStringLiteral("notify")) {
        // Bounded freedesktop notification. The daemon prefers the session
        // D-Bus interface (owned by the Shell's own NotificationServer or
        // Plasma) and falls back to a fixed-argv notify-send spawn; either way
        // the payload is validated data, never a command line.
        const QString summary = payload.value(QStringLiteral("summary")).toString();
        const QString body = payload.value(QStringLiteral("body")).toString();
        const QString icon = payload.value(QStringLiteral("icon")).toString();
        // appName is cosmetic (notification grouping / banner header); an
        // empty or oversized value silently falls back to the daemon's name
        // instead of rejecting the whole notification.
        const QString appName = [] (const QString &raw) {
            return (!raw.isEmpty() && raw.size() <= 128
                    && !raw.contains(QChar('\0')))
                ? raw : QStringLiteral("KOS Shell");
        }(payload.value(QStringLiteral("appName")).toString());
        const QString urgencyName = payload.value(QStringLiteral("urgency"))
            .toString(QStringLiteral("normal"));
        uchar urgency = 1;
        if (urgencyName == QStringLiteral("low"))
            urgency = 0;
        else if (urgencyName == QStringLiteral("critical"))
            urgency = 2;
        else if (urgencyName != QStringLiteral("normal")) {
            respond(socket, request, false, {}, QStringLiteral("invalid-notification"),
                    QStringLiteral("通知 urgency 无效"), false);
            return true;
        }
        if (summary.isEmpty() || summary.size() > 256 || body.size() > 1024
            || icon.size() > 255
            || summary.contains(QChar('\0')) || body.contains(QChar('\0'))
            || icon.contains(QChar('\0'))) {
            respond(socket, request, false, {}, QStringLiteral("invalid-notification"),
                    QStringLiteral("通知内容无效或超过长度上限"), false);
            return true;
        }
        if (dbusServiceRegistered(QDBusConnection::sessionBus(),
                                  QStringLiteral("org.freedesktop.Notifications"))) {
            QDBusMessage call = QDBusMessage::createMethodCall(
                QStringLiteral("org.freedesktop.Notifications"),
                QStringLiteral("/org/freedesktop/Notifications"),
                QStringLiteral("org.freedesktop.Notifications"),
                QStringLiteral("Notify"));
            const QVariantMap hints{
                {QStringLiteral("urgency"), QVariant::fromValue<uchar>(urgency)}};
            call.setArguments({appName, 0U, icon, summary, body,
                               QStringList{}, hints, 5000});
            // Fire-and-forget: the notification UI owns delivery, and a slow
            // or absent implementation must not hold the socket reply.
            QDBusConnection::sessionBus().asyncCall(call, kDbusCallTimeoutMs);
            respond(socket, request, true, QJsonObject{{QStringLiteral("delivered"), true}});
            return true;
        }
        const QString notifySend = QStandardPaths::findExecutable(
            QStringLiteral("notify-send"));
        if (notifySend.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("notify-unavailable"),
                    QStringLiteral("没有可用的通知服务"), true);
            return true;
        }
        QStringList args{QStringLiteral("-a"), appName};
        if (!icon.isEmpty())
            args << QStringLiteral("-i") << icon;
        args << QStringLiteral("-u") << urgencyName
             << QStringLiteral("-t") << QStringLiteral("5000")
             // A summary starting with '-' would otherwise be parsed as a
             // GOption flag; "--" terminates option parsing.
             << QStringLiteral("--") << summary << body;
        const bool started = QProcess::startDetached(notifySend, args);
        respond(socket, request, started,
                QJsonObject{{QStringLiteral("delivered"), started}});
        return true;
    }
    if (op == QStringLiteral("shortcuts.apply")) {
        // The Shell owns shortcut semantics: it composes each Exec line to
        // match how that Shell instance was launched. The daemon registers
        // the set with KGlobalAccel and runs the Exec lines on activation.
        const QJsonArray shortcuts = payload.value(QStringLiteral("shortcuts")).toArray();
        if (shortcuts.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-shortcut-payload"),
                    QStringLiteral("快捷键请求无效"), false);
            return true;
        }
        QJsonArray normalized;
        for (const QJsonValue &value : shortcuts) {
            QJsonObject item = value.toObject();
            item.insert(QStringLiteral("combo"),
                        normalizedShortcutCombo(item.value(QStringLiteral("combo")).toString()));
            normalized.append(item);
        }
        QString error;
        if (!applyShortcutSet(normalized, &error)) {
            respond(socket, request, false, {},
                    QStringLiteral("shortcuts-apply-failed"),
                    error.isEmpty() ? QStringLiteral("无法应用快捷键") : error, false);
            return true;
        }
        QJsonArray applied;
        for (const QJsonValue &value : normalized)
            applied.append(value.toObject().value(QStringLiteral("id")).toString());
        respond(socket, request, true, QJsonObject{{QStringLiteral("applied"), applied}});
        return true;
    }
    if (op == QStringLiteral("shortcuts.uninstall")) {
        removeShortcuts();
        respond(socket, request, true, QJsonObject{{QStringLiteral("uninstalled"), true}});
        return true;
    }
    if (op == QStringLiteral("session.lock")) {
        runCommand(socket, request, QStringLiteral("loginctl"), {QStringLiteral("lock-session")}, {}, 15000);
        return true;
    }
    if (op == QStringLiteral("session.suspend") || op == QStringLiteral("session.hibernate")
        || op == QStringLiteral("session.reboot") || op == QStringLiteral("session.poweroff")) {
        const QString action = op.mid(QStringLiteral("session.").size());
        runCommand(socket, request, QStringLiteral("systemctl"), {action}, {}, 15000);
        return true;
    }
    if (op == QStringLiteral("session.logout")) {
        // plasma-kwin_wayland/kos-shell/kos-platform are PartOf=graphical-
        // session.target, not members of the login session's scope, so
        // `loginctl terminate-session` never reaches them: it kills the PAM
        // helper trio and leaves the compositor running, still holding the
        // DRM device, so the next login's fresh compositor fails to become
        // DRM master and the new session hangs on a blank screen. Stopping
        // the target is what actually tears the session down; --no-block
        // matters because this daemon is itself PartOf=graphical-session
        // .target and would be stopped by this same command, so the call
        // must return before its own process is reaped by that stop.
        runCommand(socket, request, QStringLiteral("systemctl"),
                   {QStringLiteral("--user"), QStringLiteral("--no-block"),
                    QStringLiteral("stop"), QStringLiteral("graphical-session.target")},
                   {}, 15000);
        return true;
    }
    if (op == QStringLiteral("session.switch-user")) {
        runCommand(socket, request, QStringLiteral("dm-tool"), {QStringLiteral("switch-to-greeter")}, {}, 15000);
        return true;
    }
    if (op == QStringLiteral("screenshot.capture")) {
        const QStringList candidates{QStringLiteral("mark-shot"), QStringLiteral("markshot"),
                                     QStringLiteral("flameshot"), QStringLiteral("ksnip"),
                                     QStringLiteral("spectacle"), QStringLiteral("grimblast")};
        for (const QString &candidate : candidates) {
            const QString executable = QStandardPaths::findExecutable(candidate);
            if (executable.isEmpty())
                continue;
            QStringList args;
            if (candidate == QStringLiteral("mark-shot") || candidate == QStringLiteral("markshot")) args = {QStringLiteral("--capture")};
            else if (candidate == QStringLiteral("flameshot")) args = {QStringLiteral("gui")};
            else if (candidate == QStringLiteral("ksnip")) args = {QStringLiteral("-r")};
            else if (candidate == QStringLiteral("spectacle")) args = {QStringLiteral("-r")};
            else args = {QStringLiteral("copy"), QStringLiteral("area")};
            // Interactive capture tools (flameshot gui, region pickers) stay
            // alive until the user finishes; no watchdog.
            runCommand(socket, request, executable, args, {}, 0);
            return true;
        }
        respond(socket, request, false, {}, QStringLiteral("screenshot-unavailable"),
                QStringLiteral("没有可用的截图工具"), false);
        return true;
    }
    return false;
}

} // namespace KosPlatform
