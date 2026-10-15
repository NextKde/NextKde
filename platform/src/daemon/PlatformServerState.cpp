#include "PlatformServer.h"
#include "PlatformPaths.h"

#include <QByteArray>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonValue>
#include <QSaveFile>
#include <QStandardPaths>

namespace KosPlatform {
using namespace Detail;

namespace {

constexpr qint64 kMaxStateFileBytes = 1024 * 1024;

constexpr qsizetype kMaxStateDirLength = 512;

constexpr qsizetype kMaxStateFileNameLength = 255;

QString stateRootPath()
{
    // Mirrors Quickshell.stateDir's root: $XDG_STATE_HOME/quickshell.
    return QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation)
        + QStringLiteral("/quickshell");
}

// Returns the resolved absolute path for <root>/<dir>/<file>, or {} when the
// pair escapes the root. `dir` may be empty (the root itself), a relative
// sub-path, or an absolute path that must sit under the root; `file` is a
// bare file name. Everything existing is canonicalized first, so `..`
// segments and symlinks that resolve outside the root are rejected by the
// final prefix check rather than by string comparison on the raw input.
QString resolveStatePath(const QString &dir, const QString &file)
{
    if (file.isEmpty() || file.size() > kMaxStateFileNameLength
        || file == QStringLiteral(".") || file == QStringLiteral("..")
        || file.contains(QLatin1Char('/')) || file.contains(QLatin1Char('\\'))
        || file.contains(QChar('\0')))
        return {};
    if (dir.size() > kMaxStateDirLength || dir.contains(QChar('\0')))
        return {};

    const QString root = QDir::cleanPath(stateRootPath());
    QString joined;
    if (QFileInfo(dir).isAbsolute())
        joined = QDir::cleanPath(dir);
    else
        joined = QDir::cleanPath(dir.isEmpty() ? root
                                               : root + QLatin1Char('/') + dir);
    if (joined != root && !joined.startsWith(root + QLatin1Char('/')))
        return {};

    // cleanCreatePath canonicalizes the deepest existing ancestor and appends
    // the still-missing components literally, so it resolves both an existing
    // directory and one about to be mkpath'ed.
    const QString resolvedRoot = cleanCreatePath(root);
    if (resolvedRoot.isEmpty())
        return {};
    const QString resolvedDir = cleanCreatePath(joined);
    if (resolvedDir.isEmpty()
        || (resolvedDir != resolvedRoot
            && !resolvedDir.startsWith(resolvedRoot + QLatin1Char('/'))))
        return {};
    // An existing dir must be a real directory; a file here would make the
    // append below meaningless (and mkpath would fail later anyway).
    const QFileInfo dirInfo(resolvedDir);
    if (dirInfo.exists() && !dirInfo.isDir())
        return {};

    const QString target = resolvedDir + QLatin1Char('/') + file;
    const QFileInfo targetInfo(target);
    if (!targetInfo.exists())
        return target;
    // The file exists: resolve it once more so a symlink planted inside the
    // state tree cannot point a read outside the root. (QSaveFile replaces a
    // symlink atomically instead of following it, but reads do follow.)
    const QString canonicalTarget = targetInfo.canonicalFilePath();
    if (canonicalTarget.isEmpty()
        || !canonicalTarget.startsWith(resolvedRoot + QLatin1Char('/')))
        return {};
    return canonicalTarget;
}

} // namespace

bool PlatformServer::handleStateOperation(QLocalSocket *socket, const QJsonObject &request)
{
    const QString op = operation(request);
    if (!op.startsWith(QStringLiteral("state.")))
        return false;
    const QJsonObject payload = request.value(QStringLiteral("payload")).toObject();
    const QString path = resolveStatePath(
        payload.value(QStringLiteral("dir")).toString(),
        payload.value(QStringLiteral("file")).toString());
    if (path.isEmpty()) {
        respond(socket, request, false, {}, QStringLiteral("invalid-state-path"),
                QStringLiteral("状态文件路径无效或越出状态目录"), false);
        return true;
    }
    if (op == QStringLiteral("state.read")) {
        const QFileInfo info(path);
        if (!info.exists()) {
            // A missing file is not an error: consumers treat it as "no
            // persisted state yet", same as a first-run config directory.
            respond(socket, request, true,
                    QJsonObject{{QStringLiteral("data"), QString()},
                                {QStringLiteral("exists"), false}});
            return true;
        }
        if (!info.isFile() || info.size() > kMaxStateFileBytes) {
            respond(socket, request, false, {}, QStringLiteral("invalid-state-file"),
                    QStringLiteral("状态文件不可读或超过大小上限"), false);
            return true;
        }
        QFile input(path);
        if (!input.open(QIODevice::ReadOnly)) {
            respond(socket, request, false, {}, QStringLiteral("state-read-failed"),
                    QStringLiteral("无法读取状态文件"), true);
            return true;
        }
        // Read at most cap+1 so a file grown between stat() and open() can't
        // exceed the documented bound.
        const QByteArray content = input.read(kMaxStateFileBytes + 1);
        if (content.size() > kMaxStateFileBytes) {
            respond(socket, request, false, {}, QStringLiteral("invalid-state-file"),
                    QStringLiteral("状态文件超过大小上限"), false);
            return true;
        }
        respond(socket, request, true,
                QJsonObject{{QStringLiteral("data"), QString::fromUtf8(content)},
                            {QStringLiteral("exists"), true}});
        return true;
    }
    if (op == QStringLiteral("state.write")) {
        const QJsonValue data = payload.value(QStringLiteral("data"));
        if (!data.isString()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-state-data"),
                    QStringLiteral("state.write 需要字符串 data 字段"), false);
            return true;
        }
        const QByteArray bytes = data.toString().toUtf8();
        if (bytes.size() > kMaxStateFileBytes) {
            respond(socket, request, false, {}, QStringLiteral("state-data-too-large"),
                    QStringLiteral("状态内容超过大小上限"), false);
            return true;
        }
        const QString parent = QFileInfo(path).path();
        if (!QDir().mkpath(parent)) {
            respond(socket, request, false, {}, QStringLiteral("state-write-failed"),
                    QStringLiteral("无法创建状态目录"), true);
            return true;
        }
        // QSaveFile writes to a sibling temp file and renames on commit, so a
        // crash mid-write never leaves a half-written state file behind.
        QSaveFile output(path);
        if (!output.open(QIODevice::WriteOnly)
            || output.write(bytes) != bytes.size()
            || !output.commit()) {
            respond(socket, request, false, {}, QStringLiteral("state-write-failed"),
                    QStringLiteral("无法写入状态文件"), true);
            return true;
        }
        respond(socket, request, true,
                QJsonObject{{QStringLiteral("written"), bytes.size()}});
        return true;
    }
    return false;
}

} // namespace KosPlatform
