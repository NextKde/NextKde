#include "PlatformServer.h"
#include "../kwin/KWinBridge.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QGuiApplication>
#include <QSaveFile>
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

bool installShortcuts(bool install)
{
    const QString contract = shortcutContractPath();
    QFile file(contract);
    if (!install) {
        const QString appDir = QDir(QStandardPaths::writableLocation(QStandardPaths::ApplicationsLocation)).absolutePath();
        QDir applications(appDir);
        QByteArray contractBytes;
        if (file.open(QIODevice::ReadOnly))
            contractBytes = file.readAll();
        const QJsonDocument document = QJsonDocument::fromJson(contractBytes);
        if (document.isObject()) {
            for (const QJsonValue &value : document.object().value(QStringLiteral("shortcuts")).toArray()) {
                const QString id = value.toObject().value(QStringLiteral("id")).toString();
                if (!id.isEmpty())
                    applications.remove(id + QStringLiteral(".desktop"));
            }
        }
        const QString rcPath = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
            + QStringLiteral("/kglobalshortcutsrc");
        QFile rc(rcPath);
        if (!rc.open(QIODevice::ReadOnly | QIODevice::Text))
            return true;
        const QStringList lines = QString::fromUtf8(rc.readAll()).split(QChar('\n'));
        rc.close();
        QStringList kept;
        bool dropping = false;
        for (const QString &line : lines) {
            if (line.startsWith(QStringLiteral("[services][")) && line.endsWith(QStringLiteral(".desktop]"))) {
                dropping = true;
                continue;
            }
            if (dropping && line.startsWith(QChar('[')))
                dropping = false;
            if (!dropping)
                kept.append(line);
        }
        QSaveFile output(rcPath);
        if (output.open(QIODevice::WriteOnly | QIODevice::Text)) {
            output.write(kept.join(QChar('\n')).toUtf8());
            output.commit();
        }
        return true;
    }
    if (!file.open(QIODevice::ReadOnly))
        return false;
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject())
        return false;
    const QJsonArray shortcuts = document.object().value(QStringLiteral("shortcuts")).toArray();
    const QString applicationsPath = QStandardPaths::writableLocation(QStandardPaths::ApplicationsLocation);
    QDir().mkpath(applicationsPath);
    const QString rcPath = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
        + QStringLiteral("/kglobalshortcutsrc");
    QDir().mkpath(QFileInfo(rcPath).absolutePath());
    QFile rc(rcPath);
    QString existing;
    if (rc.open(QIODevice::ReadOnly | QIODevice::Text)) {
        existing = QString::fromUtf8(rc.readAll());
        rc.close();
    }
    QStringList rcLines = existing.split(QChar('\n'));
    for (const QJsonValue &value : shortcuts) {
        const QJsonObject item = value.toObject();
        const QString id = item.value(QStringLiteral("id")).toString();
        const QString description = item.value(QStringLiteral("description")).toString();
        const QString target = item.value(QStringLiteral("target")).toString();
        const QString action = item.value(QStringLiteral("action")).toString();
        const QString combo = item.value(QStringLiteral("default")).toString();
        if (id.isEmpty() || target.isEmpty() || action.isEmpty() || combo.isEmpty())
            continue;
        QSaveFile desktop(QDir(applicationsPath).filePath(id + QStringLiteral(".desktop")));
        if (!desktop.open(QIODevice::WriteOnly | QIODevice::Text))
            return false;
        const QString command = QStringLiteral("qs -c kos ipc call %1 %2").arg(target, action);
        desktop.write(QStringLiteral("[Desktop Entry]\nType=Application\nName=%1\nExec=%2\nNoDisplay=true\nX-KDE-GlobalAccel-CommandShortcut=true\n").arg(description, command).toUtf8());
        if (!desktop.commit())
            return false;
        const QString header = QStringLiteral("[services][%1.desktop]").arg(id);
        for (int index = rcLines.size() - 1; index >= 0; --index) {
            if (rcLines.at(index).trimmed() == header) {
                rcLines.removeAt(index);
                if (index < rcLines.size() && rcLines.at(index).startsWith(QStringLiteral("_launch=")))
                    rcLines.removeAt(index);
            }
        }
        rcLines << header << QStringLiteral("_launch=%1").arg(combo);
    }
    QSaveFile output(rcPath);
    if (!output.open(QIODevice::WriteOnly | QIODevice::Text))
        return false;
    output.write(rcLines.join(QChar('\n')).toUtf8());
    return output.commit();
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
        return installShortcuts(action == QStringLiteral("install")) ? 0 : 1;
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
