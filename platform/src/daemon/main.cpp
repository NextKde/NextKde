#include "PlatformServer.h"
#include "../kwin/KWinBridge.h"

#include <QDir>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QGuiApplication>
#include <QSaveFile>
#include <QLoggingCategory>
#include <QStandardPaths>
#include <QSet>
#include <QRegularExpression>
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

QString normalizedShortcut(QString value)
{
    value = value.trimmed();
    const qsizetype comma = value.indexOf(QChar(','));
    if (comma >= 0)
        value.truncate(comma);
    return value.trimmed();
}

QString shortcutIdFromHeader(const QString &line)
{
    static const QRegularExpression header(
        QStringLiteral("^\\[services\\]\\[([^]]+)\\]$"));
    const auto match = header.match(line.trimmed());
    if (!match.hasMatch())
        return {};
    const QString desktop = match.captured(1);
    return desktop.endsWith(QStringLiteral(".desktop"))
        ? desktop.left(desktop.size() - 8) : QString{};
}

QStringList removeShortcutSections(const QStringList &lines,
                                   const QSet<QString> &ids)
{
    QStringList kept;
    bool dropping = false;
    for (const QString &line : lines) {
        const QString id = shortcutIdFromHeader(line);
        if (!id.isEmpty()) {
            dropping = ids.contains(id);
            if (dropping)
                continue;
        }
        if (!dropping)
            kept.append(line);
    }
    return kept;
}

void refreshGlobalAccel(const QJsonArray &shortcuts, bool install)
{
    QDBusInterface accel(QStringLiteral("org.kde.kglobalaccel"),
                         QStringLiteral("/kglobalaccel"),
                         QStringLiteral("org.kde.KGlobalAccel"),
                         QDBusConnection::sessionBus());
    if (!accel.isValid())
        return;
    const QString method = install ? QStringLiteral("doRegister")
                                   : QStringLiteral("unRegister");
    for (const QJsonValue &value : shortcuts) {
        const QString id = value.toObject().value(QStringLiteral("id")).toString();
        if (id.isEmpty())
            continue;
        const QDBusMessage reply = accel.call(method,
            QStringList{id + QStringLiteral(".desktop"), QStringLiteral("_launch")});
        if (reply.type() == QDBusMessage::ErrorMessage) {
            QTextStream(stderr) << "Unable to refresh global shortcut " << id
                                << ": " << reply.errorMessage() << Qt::endl;
        }
    }
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
        const QJsonArray shortcuts = document.isObject()
            ? document.object().value(QStringLiteral("shortcuts")).toArray() : QJsonArray{};
        QSet<QString> ids;
        for (const QJsonValue &value : shortcuts) {
            const QString id = value.toObject().value(QStringLiteral("id")).toString();
            if (!id.isEmpty()) {
                ids.insert(id);
                applications.remove(id + QStringLiteral(".desktop"));
            }
        }
        if (!ids.isEmpty()) {
            const QString rcPath = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
                + QStringLiteral("/kglobalshortcutsrc");
            QFile rc(rcPath);
            if (!rc.open(QIODevice::ReadOnly | QIODevice::Text)) {
                refreshGlobalAccel(shortcuts, false);
                return true;
            }
            const QStringList lines = QString::fromUtf8(rc.readAll()).split(QChar('\n'));
            rc.close();
            const QStringList kept = removeShortcutSections(lines, ids);
            QSaveFile output(rcPath);
            if (!output.open(QIODevice::WriteOnly | QIODevice::Text))
                return false;
            output.write(kept.join(QChar('\n')).toUtf8());
            if (!output.commit())
                return false;
        }
        refreshGlobalAccel(shortcuts, false);
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
    QDir applications(applicationsPath);
    if (!QDir().mkpath(applicationsPath))
        return false;
    const QString rcPath = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
        + QStringLiteral("/kglobalshortcutsrc");
    QDir().mkpath(QFileInfo(rcPath).absolutePath());
    QFile rc(rcPath);
    QString existing;
    if (rc.open(QIODevice::ReadOnly | QIODevice::Text)) {
        existing = QString::fromUtf8(rc.readAll());
        rc.close();
    }
    const QStringList existingLines = existing.split(QChar('\n'));

    QSet<QString> ids;
    QHash<QString, QString> requested;
    for (const QJsonValue &value : shortcuts) {
        const QJsonObject item = value.toObject();
        const QString id = item.value(QStringLiteral("id")).toString().trimmed();
        const QString combo = normalizedShortcut(item.value(QStringLiteral("default")).toString());
        if (id.isEmpty() || combo.isEmpty()
            || item.value(QStringLiteral("target")).toString().trimmed().isEmpty()
            || item.value(QStringLiteral("action")).toString().trimmed().isEmpty())
            continue;
        if (ids.contains(id) || requested.values().contains(combo)) {
            QTextStream(stderr) << "Duplicate KOS shortcut definition: " << id
                                << " / " << combo << Qt::endl;
            return false;
        }
        ids.insert(id);
        requested.insert(id, combo);
    }

    QString currentId;
    for (const QString &line : existingLines) {
        const QString headerId = shortcutIdFromHeader(line);
        if (!headerId.isEmpty()) {
            currentId = headerId;
            continue;
        }
        if (line.trimmed().startsWith(QChar('['))) {
            currentId.clear();
            continue;
        }
        const QString trimmedLine = line.trimmed();
        if (currentId.isEmpty() || !trimmedLine.startsWith(QStringLiteral("_launch=")))
            continue;
        const QString combo = normalizedShortcut(trimmedLine.mid(8));
        for (auto it = requested.cbegin(); it != requested.cend(); ++it) {
            if (it.key() != currentId && !combo.isEmpty() && combo == it.value()) {
                QTextStream(stderr) << "Shortcut conflict: " << it.key()
                                    << " wants " << combo << ", already used by "
                                    << currentId << Qt::endl;
                return false;
            }
        }
    }

    QStringList rcLines = removeShortcutSections(existingLines, ids);
    for (const QJsonValue &value : shortcuts) {
        const QJsonObject item = value.toObject();
        const QString id = item.value(QStringLiteral("id")).toString().trimmed();
        if (!ids.contains(id))
            continue;
        const QString description = item.value(QStringLiteral("description")).toString();
        const QString target = item.value(QStringLiteral("target")).toString();
        const QString action = item.value(QStringLiteral("action")).toString();
        const QString combo = requested.value(id);
        QSaveFile desktop(QDir(applicationsPath).filePath(id + QStringLiteral(".desktop")));
        if (!desktop.open(QIODevice::WriteOnly | QIODevice::Text))
            return false;
        const QString command = QStringLiteral("qs -c kos ipc call %1 %2").arg(target, action);
        desktop.write(QStringLiteral("[Desktop Entry]\nType=Application\nName=%1\nExec=%2\nNoDisplay=true\nX-KDE-GlobalAccel-CommandShortcut=true\n").arg(description, command).toUtf8());
        if (!desktop.commit())
            return false;
        rcLines << QStringLiteral("[services][%1.desktop]").arg(id)
                << QStringLiteral("_launch=%1").arg(combo);
    }
    QSaveFile output(rcPath);
    if (!output.open(QIODevice::WriteOnly | QIODevice::Text))
        return false;
    output.write(rcLines.join(QChar('\n')).toUtf8());
    if (!output.commit())
        return false;
    refreshGlobalAccel(shortcuts, true);
    return true;
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
