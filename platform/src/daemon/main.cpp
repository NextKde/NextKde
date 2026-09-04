#include "PlatformServer.h"
#include "Shortcuts.h"
#include "../kwin/KWinBridge.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QGuiApplication>
#include <QLoggingCategory>
#include <QStandardPaths>
#include <QTextStream>

using namespace KosPlatform;

namespace {

QString shortcutContractPath()
{
    const QString configured = qEnvironmentVariable("KOS_SHORTCUTS_FILE");
    if (!configured.isEmpty())
        return configured;
    const QString source = QDir::current().filePath(QStringLiteral("shared/contracts/shortcuts.v1.json"));
    if (QFileInfo::exists(source))
        return source;
    return QStandardPaths::locate(QStandardPaths::GenericDataLocation,
        QStringLiteral("kos/shared/contracts/shortcuts.v1.json"));
}

// The CLI is the installed-layout fallback: it composes `qs -c kos` Exec
// lines because it has no way to know how a development Shell was launched.
// The running Shell applies its own set through `shortcuts.apply`, whose
// Exec always matches the live instance.
constexpr auto kCliExecTemplate = "qs -c kos ipc call %1 %2";

int cliShortcuts(bool install)
{
    const QString contract = shortcutContractPath();
    QFile file(contract);
    if (!file.open(QIODevice::ReadOnly)) {
        QTextStream(stderr) << "Unable to open shortcut contract " << contract << '\n';
        return 1;
    }
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        QTextStream(stderr) << "Invalid shortcut contract " << contract << '\n';
        return 1;
    }
    const QJsonArray shortcuts = document.object().value(QStringLiteral("shortcuts")).toArray();

    if (!install) {
        QStringList ids;
        for (const QJsonValue &value : shortcuts) {
            const QString id = value.toObject().value(QStringLiteral("id")).toString();
            if (!id.isEmpty())
                ids.append(id);
        }
        QString error;
        if (!uninstallShortcutIds(ids, legacyKosShortcutIds(), &error)) {
            QTextStream(stderr) << error << '\n';
            return 1;
        }
        return 0;
    }

    QJsonArray requested;
    for (const QJsonValue &value : shortcuts) {
        const QJsonObject item = value.toObject();
        const QString id = item.value(QStringLiteral("id")).toString().trimmed();
        const QString combo = normalizedShortcutCombo(
            item.value(QStringLiteral("default")).toString());
        const QString target = item.value(QStringLiteral("target")).toString().trimmed();
        const QString action = item.value(QStringLiteral("action")).toString().trimmed();
        if (id.isEmpty() || combo.isEmpty() || target.isEmpty() || action.isEmpty())
            continue;
        const QString exec = QString::fromUtf8(kCliExecTemplate).arg(target, action);
        requested.append(QJsonObject{
            {QStringLiteral("id"), id},
            {QStringLiteral("description"), item.value(QStringLiteral("description")).toString()},
            {QStringLiteral("combo"), combo},
            {QStringLiteral("exec"), exec},
        });
    }
    QString error;
    if (!installShortcutSet(requested, legacyKosShortcutIds(), &error)) {
        QTextStream(stderr) << error << '\n';
        return 1;
    }
    return 0;
}

} // namespace

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("kos-platform"));
    app.setDesktopFileName(QStringLiteral("org.kos.Platform"));

    const QStringList arguments = app.arguments();
    if (arguments.size() > 1 && arguments.at(1) == QStringLiteral("shortcuts")) {
        const QString action = arguments.value(2, QStringLiteral("install"));
        if (action != QStringLiteral("install") && action != QStringLiteral("uninstall")) {
            QTextStream(stderr) << "Usage: kos-platform shortcuts [install|uninstall]\n";
            return 2;
        }
        return cliShortcuts(action == QStringLiteral("install"));
    }
    if (arguments.size() > 1 && arguments.at(1) != QStringLiteral("daemon")) {
        QTextStream(stderr) << "Usage: kos-platform daemon\n";
        return 2;
    }

    PlatformServer server;
    if (!server.listen())
        return 1;

    startKWinBridge([&server](const QJsonObject &event) {
        server.broadcastKWinEvent(event);
    });

    QTextStream(stdout) << "READY " << server.socketPath() << Qt::endl;
    return app.exec();
}
