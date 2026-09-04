#include "Shortcuts.h"

#include <KGlobalAccel>

#include <QAction>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonObject>
#include <QKeySequence>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <QTextStream>

namespace KosPlatform {

namespace {

// Desktop files written by superseded shortcut layouts: one-file-per-shortcut
// generations and the single-Action-file experiment. User created entries
// (net.local.qs*) are left alone.
const QStringList kLegacyDesktopIds = {
    QStringLiteral("net.local.kos"),
    QStringLiteral("net.local.kos-launcher"),
    QStringLiteral("net.local.kos-window-switcher"),
    QStringLiteral("net.local.kos-control-center"),
    QStringLiteral("net.local.kos-overview"),
    QStringLiteral("net.local.kos-clipboard"),
    QStringLiteral("net.local.kos-show-desktop"),
    QStringLiteral("net.local.quickshell-search"),
    QStringLiteral("net.local.quickshell-launcher"),
    QStringLiteral("net.local.quickshell-control-center"),
    QStringLiteral("net.local.quickshell-overview"),
};

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

QString kglobalAccelerRcPath()
{
    return QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
        + QStringLiteral("/kglobalshortcutsrc");
}

QString applicationsPath()
{
    return QStandardPaths::writableLocation(QStandardPaths::ApplicationsLocation);
}

} // namespace

QString normalizedShortcutCombo(QString value)
{
    return normalizedShortcut(std::move(value));
}

void cleanShortcutLayouts()
{
    const QString appDir = applicationsPath();
    for (const QString &id : kLegacyDesktopIds)
        QFile::remove(QDir(appDir).filePath(id + QStringLiteral(".desktop")));

    QFile rc(kglobalAccelerRcPath());
    if (!rc.open(QIODevice::ReadOnly | QIODevice::Text))
        return;
    const QStringList lines = QString::fromUtf8(rc.readAll()).split(QChar('\n'));
    rc.close();

    QSet<QString> legacy(kLegacyDesktopIds.cbegin(), kLegacyDesktopIds.cend());
    QStringList kept;
    bool dropping = false;
    for (const QString &line : lines) {
        const QString id = shortcutIdFromHeader(line);
        if (!id.isEmpty()) {
            dropping = legacy.contains(id);
            if (dropping)
                continue;
        }
        if (!dropping)
            kept.append(line);
    }
    if (kept.size() == lines.size())
        return;
    QSaveFile output(kglobalAccelerRcPath());
    if (!output.open(QIODevice::WriteOnly | QIODevice::Text))
        return;
    output.write(kept.join(QChar('\n')).toUtf8());
    output.commit();
}

void removeShortcuts()
{
    cleanShortcutLayouts();
    KGlobalAccel *accel = KGlobalAccel::self();
    const auto actions = QGuiApplication::instance()->findChildren<QAction *>();
    for (QAction *action : actions) {
        if (!action->property("kosShortcut").toBool())
            continue;
        accel->setShortcut(action, {});
        action->deleteLater();
    }
}

bool applyShortcutSet(const QJsonArray &shortcuts, QString *error)
{
    // Validate before touching any QAction so a malformed request never
    // leaves a half-registered state.
    struct Request {
        QString id;
        QString description;
        QString combo;
        QString exec;
    };
    QList<Request> requests;
    QSet<QString> ids;
    QSet<QString> combos;
    for (const QJsonValue &value : shortcuts) {
        const QJsonObject item = value.toObject();
        Request request;
        request.id = item.value(QStringLiteral("id")).toString().trimmed();
        request.description = item.value(QStringLiteral("description")).toString();
        request.combo = normalizedShortcut(item.value(QStringLiteral("combo")).toString());
        request.exec = item.value(QStringLiteral("exec")).toString().trimmed();
        if (request.id.isEmpty() || request.combo.isEmpty() || request.exec.isEmpty()) {
            if (error)
                *error = QStringLiteral("快捷键定义不完整：%1").arg(request.id);
            return false;
        }
        if (ids.contains(request.id) || combos.contains(request.combo)) {
            if (error)
                *error = QStringLiteral("重复的 KOS 快捷键定义：%1 / %2")
                             .arg(request.id, request.combo);
            return false;
        }
        const QKeySequence sequence(request.combo);
        if (sequence.isEmpty()) {
            if (error)
                *error = QStringLiteral("无效的快捷键组合：%1").arg(request.combo);
            return false;
        }
        ids.insert(request.id);
        combos.insert(request.combo);
        requests.append(request);
    }

    // Superseded layouts would keep dead service entries in the Shortcuts
    // KCM alongside the real component.
    cleanShortcutLayouts();

    KGlobalAccel *accel = KGlobalAccel::self();
    for (const Request &request : requests) {
        QAction *action = QGuiApplication::instance()->findChild<QAction *>(
            request.id);
        const bool created = action == nullptr;
        if (created) {
            action = new QAction(QGuiApplication::instance());
            action->setObjectName(request.id);
            action->setProperty("kosShortcut", true);
            // Read the Exec from the property at trigger time so a later
            // apply (dev shell -> installed shell switch) takes effect.
            QObject::connect(action, &QAction::triggered, action, [action]() {
                const QString exec = action->property("kosExec").toString();
                if (!exec.isEmpty())
                    QProcess::startDetached(QStringLiteral("/bin/sh"),
                                            {QStringLiteral("-c"), exec});
            });
        }
        action->setText(request.description);
        action->setProperty("kosExec", request.exec);
        const QKeySequence sequence(request.combo);
        // NoAutoloading: kos-settings is the authoritative source; without
        // it a first registration could silently pick up a stale saved value.
        if (created)
            accel->setDefaultShortcut(action, {sequence});
        accel->setShortcut(action, {sequence}, KGlobalAccel::NoAutoloading);
    }
    return true;
}

} // namespace KosPlatform
