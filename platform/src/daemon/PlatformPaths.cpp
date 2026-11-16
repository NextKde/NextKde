#include "PlatformPaths.h"

#include <QByteArray>
#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonValue>
#include <QList>
#include <QMimeData>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <QStringList>
#include <QUrl>

namespace KosPlatform::Detail {

QString cleanPath(const QString &path)
{
    if (path.isEmpty() || path.contains(QChar('\0')))
        return {};
    const QFileInfo raw(path);
    if (!raw.isAbsolute())
        return {};

    // Canonicalise existing entries so `..` and symlink aliases cannot make
    // two requests refer to different paths. For a new rename/create target,
    // canonicalise its existing parent and append only the final component;
    // this preserves legitimate non-existent targets while keeping the
    // operation inside a real directory boundary.
    const QString cleaned = QDir::cleanPath(raw.absoluteFilePath());
    const QFileInfo info(cleaned);
    if (info.exists())
        return info.canonicalFilePath();

    const QString fileName = info.fileName();
    const QFileInfo parentInfo(info.path());
    if (fileName.isEmpty() || fileName == QStringLiteral(".")
        || fileName == QStringLiteral("..")
        || !parentInfo.exists() || !parentInfo.isDir()
        || parentInfo.isSymLink())
        return {};
    const QString canonicalParent = parentInfo.canonicalFilePath();
    if (canonicalParent.isEmpty())
        return {};
    return QDir(canonicalParent).filePath(fileName);
}

QString cleanCreatePath(const QString &path)
{
    if (path.isEmpty() || path.contains(QChar('\0')))
        return {};
    const QFileInfo raw(path);
    if (!raw.isAbsolute())
        return {};
    const QString cleaned = QDir::cleanPath(raw.absoluteFilePath());
    QString cursor = cleaned;
    QStringList suffix;
    while (!QFileInfo(cursor).exists()) {
        const QFileInfo missing(cursor);
        if (missing.fileName().isEmpty() || missing.fileName() == QStringLiteral(".")
            || missing.fileName() == QStringLiteral(".."))
            return {};
        suffix.prepend(missing.fileName());
        const QString parent = missing.path();
        if (parent == cursor)
            return {};
        cursor = parent;
    }
    const QFileInfo base(cursor);
    if (base.isSymLink())
        return {};
    if (!base.isDir()) {
        // The deepest existing component is a regular file rather than a
        // directory. That is a legitimate *destination*: file.copy and
        // clipboard.save-image both replace their target on purpose, and the
        // copy itself goes through QSaveFile (tmp + rename) with file.copy's
        // own same-file guard covering the one case where replacing would
        // destroy the source. Only the final component may be that file: an
        // existing file higher up is not a directory, so a missing component
        // underneath it can never be created.
        if (!suffix.isEmpty() || !base.isFile())
            return {};
        return base.canonicalFilePath();
    }
    QString result = base.canonicalFilePath();
    if (result.isEmpty())
        return {};
    for (const QString &part : suffix)
        result = QDir(result).filePath(part);
    return result;
}

QString resolveDesktopFile(const QString &id)
{
    if (id.isEmpty() || id.contains(QChar('\0')))
        return {};
    // Desktop icons hand over the absolute path of the .desktop file that sits
    // in ~/Desktop, which is never inside an applications directory, so an
    // absolute path is resolved directly instead of being rejected.
    if (QFileInfo(id).isAbsolute()) {
        const QFileInfo info(id);
        if (!info.isFile()
            || !info.fileName().endsWith(QStringLiteral(".desktop"), Qt::CaseInsensitive))
            return {};
        const QString canonical = info.canonicalFilePath();
        return canonical.isEmpty() ? info.absoluteFilePath() : canonical;
    }
    if (id.contains(QChar('/')) || id.contains(QChar('\\')))
        return {};
    const QString name = id.endsWith(QStringLiteral(".desktop"), Qt::CaseInsensitive)
        ? id : id + QStringLiteral(".desktop");
    const QStringList roots = QStandardPaths::standardLocations(QStandardPaths::ApplicationsLocation);
    for (const QString &root : roots) {
        const QString candidate = QDir(root).filePath(name);
        if (QFileInfo(candidate).isFile())
            return QFileInfo(candidate).absoluteFilePath();
    }
    return {};
}

// Resolves a KOS-shipped helper binary. systemd starts this daemon with the
// default system PATH, which does not contain the user install prefix
// (~/.local/bin), so a bare PATH lookup finds nothing even though the binary
// sits in the same prefix as the daemon itself -- every Settings click then
// failed with "KOS 设置应用不可用".
QString resolveOwnExecutable(const QString &name)
{
    const QString onPath = QStandardPaths::findExecutable(name);
    if (!onPath.isEmpty())
        return onPath;

    QStringList candidates;
    // Same install prefix as this daemon: <prefix>/libexec/kos-platform ->
    // <prefix>/bin/<name>. Derived instead of hardcoded, so it holds for the
    // default ~/.local prefix as well as /usr/local or a Nix store path.
    QDir selfDir(QFileInfo(QCoreApplication::applicationFilePath()).absolutePath());
    if (selfDir.dirName() == QStringLiteral("libexec") && selfDir.cdUp())
        candidates.append(selfDir.filePath(QStringLiteral("bin")) + QLatin1Char('/') + name);
    // Fallback for a daemon started straight out of a build tree, which has no
    // sibling bin/ directory next to it.
    const QString home = QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
    if (!home.isEmpty())
        candidates.append(QDir(home).filePath(QStringLiteral(".local/bin/") + name));

    for (const QString &candidate : candidates) {
        const QFileInfo info(candidate);
        if (!info.isFile() || !info.isExecutable())
            continue;
        const QString canonical = info.canonicalFilePath();
        return canonical.isEmpty() ? info.absoluteFilePath() : canonical;
    }
    return {};
}

QStringList cleanPaths(const QJsonValue &value)
{
    QStringList paths;
    QSet<QString> seen;
    for (const QJsonValue &item : value.toArray()) {
        const QString path = cleanPath(item.toString());
        if (!path.isEmpty() && !seen.contains(path)) {
            seen.insert(path);
            paths.append(path);
        }
    }
    return paths;
}

QJsonArray jsonPaths(const QStringList &paths)
{
    QJsonArray values;
    for (const QString &path : paths)
        values.append(path);
    return values;
}

QString mimeOperation(const QMimeData *mime)
{
    if (mime->hasFormat(QString::fromLatin1(kClipboardCutMime))
        && mime->data(QString::fromLatin1(kClipboardCutMime)).trimmed() == "1")
        return QStringLiteral("cut");
    if (mime->hasFormat(QString::fromLatin1(kGnomeFilesMime))) {
        const QByteArray first = mime->data(QString::fromLatin1(kGnomeFilesMime))
                                     .split('\n').value(0).trimmed();
        if (first == "cut")
            return QStringLiteral("cut");
    }
    return QStringLiteral("copy");
}

QStringList localClipboardPaths(const QMimeData *mime)
{
    QStringList result;
    QSet<QString> seen;
    const auto append = [&result, &seen](const QUrl &url) {
        if (!url.isLocalFile())
            return;
        const QString path = cleanPath(url.toLocalFile());
        if (!path.isEmpty() && !seen.contains(path)) {
            seen.insert(path);
            result.append(path);
        }
    };
    for (const QUrl &url : mime->urls())
        append(url);
    if (result.isEmpty() && mime->hasFormat(QStringLiteral("text/uri-list"))) {
        for (QByteArray line : mime->data(QStringLiteral("text/uri-list")).split('\n')) {
            line = line.trimmed();
            if (!line.isEmpty() && !line.startsWith('#'))
                append(QUrl::fromEncoded(line));
        }
    }
    if (result.isEmpty() && mime->hasFormat(QString::fromLatin1(kGnomeFilesMime))) {
        const QList<QByteArray> lines = mime->data(QString::fromLatin1(kGnomeFilesMime))
                                            .split('\n');
        for (qsizetype i = 1; i < lines.size(); ++i)
            append(QUrl::fromEncoded(lines.at(i).trimmed()));
    }
    return result;
}

} // namespace KosPlatform::Detail
