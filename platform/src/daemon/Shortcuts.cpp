#include "Shortcuts.h"

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <QTextStream>

namespace KosPlatform {

namespace {

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

QString kglobalAccelerRcPath()
{
    return QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
        + QStringLiteral("/kglobalshortcutsrc");
}

QString applicationsPath()
{
    return QStandardPaths::writableLocation(QStandardPaths::ApplicationsLocation);
}

// Ask the running kglobalaccel to pick up (or drop) the service actions.
// Config-file edits alone only take effect after kglobalaccel restarts.
void refreshGlobalAccel(const QStringList &ids, bool install)
{
    QDBusInterface accel(QStringLiteral("org.kde.kglobalaccel"),
                         QStringLiteral("/kglobalaccel"),
                         QStringLiteral("org.kde.KGlobalAccel"),
                         QDBusConnection::sessionBus());
    if (!accel.isValid())
        return;
    const QString method = install ? QStringLiteral("doRegister")
                                   : QStringLiteral("unRegister");
    for (const QString &id : ids) {
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

void removeDesktopEntries(const QStringList &ids)
{
    const QString dir = applicationsPath();
    for (const QString &id : ids) {
        if (!id.isEmpty())
            QFile::remove(QDir(dir).filePath(id + QStringLiteral(".desktop")));
    }
}

} // namespace

QString normalizedShortcutCombo(QString value)
{
    return normalizedShortcut(std::move(value));
}

QStringList legacyKosShortcutIds()
{
    return {
        QStringLiteral("net.local.quickshell-search"),
        QStringLiteral("net.local.quickshell-launcher"),
        QStringLiteral("net.local.quickshell-control-center"),
        QStringLiteral("net.local.quickshell-overview"),
    };
}

bool uninstallShortcutIds(const QStringList &ids,
                          const QStringList &legacyIds,
                          QString *error)
{
    QStringList all = ids;
    all.append(legacyIds);
    all.removeAll(QString());
    removeDesktopEntries(all);

    QFile rc(kglobalAccelerRcPath());
    if (!rc.open(QIODevice::ReadOnly | QIODevice::Text)) {
        refreshGlobalAccel(all, false);
        return true;
    }
    const QStringList lines = QString::fromUtf8(rc.readAll()).split(QChar('\n'));
    rc.close();
    const QStringList kept = removeShortcutSections(lines, QSet<QString>(all.cbegin(), all.cend()));
    QSaveFile output(kglobalAccelerRcPath());
    if (!output.open(QIODevice::WriteOnly | QIODevice::Text)) {
        if (error)
            *error = QStringLiteral("无法写入 kglobalshortcutsrc");
        return false;
    }
    output.write(kept.join(QChar('\n')).toUtf8());
    if (!output.commit()) {
        if (error)
            *error = QStringLiteral("无法提交 kglobalshortcutsrc");
        return false;
    }
    refreshGlobalAccel(all, false);
    return true;
}

bool installShortcutSet(const QJsonArray &shortcuts,
                        const QStringList &legacyIds,
                        QString *error)
{
    // Validate and normalize the requested set before touching any file so
    // a malformed or conflicting request never leaves a half-applied state.
    QSet<QString> ids;
    QHash<QString, QString> requested;
    for (const QJsonValue &value : shortcuts) {
        const QJsonObject item = value.toObject();
        const QString id = item.value(QStringLiteral("id")).toString().trimmed();
        const QString combo = normalizedShortcut(item.value(QStringLiteral("combo")).toString());
        const QString exec = item.value(QStringLiteral("exec")).toString().trimmed();
        if (id.isEmpty() || combo.isEmpty() || exec.isEmpty()) {
            if (error)
                *error = QStringLiteral("快捷键定义不完整：%1").arg(id);
            return false;
        }
        if (ids.contains(id) || requested.values().contains(combo)) {
            if (error)
                *error = QStringLiteral("重复的 KOS 快捷键定义：%1 / %2").arg(id, combo);
            return false;
        }
        ids.insert(id);
        requested.insert(id, combo);
    }

    const QString rcPath = kglobalAccelerRcPath();
    QDir().mkpath(QFileInfo(rcPath).absolutePath());
    const QString appPath = applicationsPath();
    QDir().mkpath(appPath);

    QFile rc(rcPath);
    QString existing;
    if (rc.open(QIODevice::ReadOnly | QIODevice::Text)) {
        existing = QString::fromUtf8(rc.readAll());
        rc.close();
    }
    const QStringList existingLines = existing.split(QChar('\n'));

    // A requested combo may not collide with a binding owned by another
    // desktop service. KOS-owned sections are replaced wholesale below, so
    // only foreign sections matter here.
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
        if (ids.contains(currentId) || legacyIds.contains(currentId))
            continue;
        const QString combo = normalizedShortcut(trimmedLine.mid(8));
        if (combo.isEmpty())
            continue;
        for (auto it = requested.cbegin(); it != requested.cend(); ++it) {
            if (it.value() == combo) {
                if (error)
                    *error = QStringLiteral("快捷键 %1 已被 %2 占用")
                                 .arg(combo, currentId);
                return false;
            }
        }
    }

    // Replace KOS sections (current ids plus superseded legacy entries) and
    // rewrite the service desktop entries with the caller-provided Exec.
    QSet<QString> removal = ids;
    for (const QString &legacy : legacyIds)
        removal.insert(legacy);
    QStringList rcLines = removeShortcutSections(existingLines, removal);
    for (const QString &legacy : legacyIds)
        QFile::remove(QDir(appPath).filePath(legacy + QStringLiteral(".desktop")));

    for (const QJsonValue &value : shortcuts) {
        const QJsonObject item = value.toObject();
        const QString id = item.value(QStringLiteral("id")).toString().trimmed();
        if (!ids.contains(id))
            continue;
        const QString description = item.value(QStringLiteral("description")).toString();
        const QString combo = requested.value(id);
        const QString exec = item.value(QStringLiteral("exec")).toString().trimmed();
        QSaveFile desktop(QDir(appPath).filePath(id + QStringLiteral(".desktop")));
        if (!desktop.open(QIODevice::WriteOnly | QIODevice::Text)) {
            if (error)
                *error = QStringLiteral("无法写入快捷键启动项 %1").arg(id);
            return false;
        }
        desktop.write(QStringLiteral("[Desktop Entry]\nType=Application\nName=%1\nExec=%2\nNoDisplay=true\nX-KDE-GlobalAccel-CommandShortcut=true\n").arg(description, exec).toUtf8());
        if (!desktop.commit()) {
            if (error)
                *error = QStringLiteral("无法提交快捷键启动项 %1").arg(id);
            return false;
        }
        rcLines << QStringLiteral("[services][%1.desktop]").arg(id)
                << QStringLiteral("_launch=%1").arg(combo);
    }
    QSaveFile output(rcPath);
    if (!output.open(QIODevice::WriteOnly | QIODevice::Text)) {
        if (error)
            *error = QStringLiteral("无法写入 kglobalshortcutsrc");
        return false;
    }
    output.write(rcLines.join(QChar('\n')).toUtf8());
    if (!output.commit()) {
        if (error)
            *error = QStringLiteral("无法提交 kglobalshortcutsrc");
        return false;
    }
    refreshGlobalAccel(requested.keys(), true);
    return true;
}

} // namespace KosPlatform
