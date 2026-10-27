#include "PlatformServer.h"
#include "PlatformDbus.h"
#include "PlatformPaths.h"
#include "PlatformProcess.h"

#include <KService>
#include <QByteArray>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QFutureWatcher>
#include <QJsonArray>
#include <QList>
#include <QMimeDatabase>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QStringList>
#include <QUrl>
#include <QVariant>
#include <QtConcurrent>
#include <filesystem>

namespace KosPlatform {
using namespace Detail;

namespace {

struct CopyResult {
    QString error;
};

// Runs on a m_copyPool thread: QFile/QSaveFile are plain file objects and
// safe off the event loop. The 1MiB chunk loop matches the old inline
// implementation, including the QSaveFile commit() fsync.
CopyResult copyFileChunked(const QString &source, const QString &destination)
{
    QFile input(source);
    QSaveFile output(destination);
    if (!input.open(QIODevice::ReadOnly))
        return {QStringLiteral("open-source")};
    if (!output.open(QIODevice::WriteOnly))
        return {QStringLiteral("open-destination")};
    while (!input.atEnd()) {
        const QByteArray chunk = input.read(1024 * 1024);
        if (chunk.isEmpty() && !input.atEnd())
            return {QStringLiteral("read")};
        if (output.write(chunk) != chunk.size())
            return {QStringLiteral("write")};
    }
    if (!output.commit())
        return {QStringLiteral("commit")};
    return {};
}

QString freedesktopTrashRoot()
{
    QString dataHome = qEnvironmentVariable("XDG_DATA_HOME");
    if (dataHome.isEmpty())
        dataHome = QDir(QStandardPaths::writableLocation(QStandardPaths::HomeLocation))
            .filePath(QStringLiteral(".local/share"));
    const QFileInfo info(dataHome);
    if (!info.isAbsolute())
        return {};
    return QDir(info.absoluteFilePath()).filePath(QStringLiteral("Trash"));
}

bool removeTrashEntry(const QString &path)
{
    const QFileInfo info(path);
    if (info.isSymLink() || !info.isDir())
        return QFile::remove(path);
    return QDir(path).removeRecursively();
}

bool emptyTrashDirectory(const QString &directory)
{
    const QFileInfo rootInfo(directory);
    if (!rootInfo.exists())
        return true;
    if (!rootInfo.isDir() || rootInfo.isSymLink())
        return false;
    QDirIterator iterator(directory, QDir::NoDotAndDotDot | QDir::AllEntries
                          | QDir::Hidden | QDir::System);
    while (iterator.hasNext()) {
        iterator.next();
        if (!removeTrashEntry(iterator.filePath()))
            return false;
    }
    return true;
}

QString uniquePath(const QString &destination, const QString &baseName)
{
    QString candidate = QDir(destination).filePath(baseName);
    if (!QFileInfo::exists(candidate) && !QFileInfo(candidate).isSymLink())
        return candidate;
    const QFileInfo sourceInfo(baseName);
    const QString suffix = sourceInfo.suffix();
    const QString stem = suffix.isEmpty() ? baseName
                                          : baseName.left(baseName.size() - suffix.size() - 1);
    for (int index = 1; index < 10000; ++index) {
        const QString copyName = suffix.isEmpty()
            ? QStringLiteral("%1 (copy %2)").arg(stem).arg(index)
            : QStringLiteral("%1 (copy %2).%3").arg(stem).arg(index).arg(suffix);
        candidate = QDir(destination).filePath(copyName);
        if (!QFileInfo::exists(candidate) && !QFileInfo(candidate).isSymLink())
            return candidate;
    }
    return {};
}

bool copyRecursively(const QString &source, const QString &target)
{
    const QFileInfo info(source);
    // Preserve the link itself, including its relative target. Following a
    // directory link can copy outside the source tree or recurse in a cycle.
    if (info.isSymLink()) {
        std::error_code error;
        const auto link = std::filesystem::read_symlink(
            std::filesystem::path(QFile::encodeName(source).constData()), error);
        if (error)
            return false;
        std::filesystem::create_symlink(link,
            std::filesystem::path(QFile::encodeName(target).constData()), error);
        return !error;
    }
    if (info.isDir()) {
        // The parent already exists. An atomic mkdir rejects a target claimed
        // by another transfer rather than merging two unrelated directories.
        if (!QDir().mkdir(target))
            return false;
        QDirIterator iterator(source, QDir::NoDotAndDotDot | QDir::AllEntries
                                         | QDir::Hidden | QDir::System);
        while (iterator.hasNext()) {
            iterator.next();
            const QString childTarget = QDir(target).filePath(iterator.fileName());
            if (!copyRecursively(iterator.filePath(), childTarget))
                return false;
        }
        return true;
    }
    // Special files such as FIFOs are not ordinary copy inputs and may block
    // indefinitely. Fail before a move can remove the source directory.
    return info.isFile() && QFile::copy(source, target);
}

bool moveOrCopy(const QString &source, const QString &destination, bool move)
{
    const QFileInfo sourceInfo(source);
    if (!sourceInfo.exists())
        return false;
    if (sourceInfo.isDir() && destination.startsWith(sourceInfo.absoluteFilePath() + QDir::separator()))
        return false;
    if (move && QFile::rename(source, destination))
        return true;
    if (!copyRecursively(source, destination))
        return false;
    if (!move)
        return true;
    return sourceInfo.isDir() ? QDir(source).removeRecursively() : QFile::remove(source);
}

} // namespace

// Copy/transfer queue bounds. The pool runs 2 threads; without a queue cap a
// client batch-submitting copies onto a slow disk grows the queue for as long
// as it keeps sending, and each entry holds its path list until it runs.
// Bounds mirror the general in-flight admission in PlatformServer.cpp
// (peer 32 / total 256) scaled to what a 2-thread pool can realistically drain.
namespace {
constexpr int kMaxCopyJobsTotal = 32;
constexpr int kMaxCopyJobsPerPeer = 8;
} // namespace

bool PlatformServer::admitCopyJob(QLocalSocket *socket, const QJsonObject &request)
{
    if (m_copyJobs < kMaxCopyJobsTotal)
        return ++m_copyJobs, true;
    respond(socket, request, false, {}, QStringLiteral("busy"),
            QStringLiteral("文件操作队列已满"), true);
    return false;
}

void PlatformServer::releaseCopyJob()
{
    Q_ASSERT(m_copyJobs > 0);
    --m_copyJobs;
}

bool PlatformServer::handleFileOperation(QLocalSocket *socket, const QJsonObject &request)
{
    const QString op = operation(request);
    const QJsonObject payload = request.value(QStringLiteral("payload")).toObject();

    // --- small text documents -------------------------------------------
    // The island's notes and anything else that is a document rather than a
    // file to hand to another application. Reading is capped so a client
    // cannot pull a multi-gigabyte log through the socket, and the write path
    // reports the committed byte count so a caller can tell a truncation from
    // a success. Both stay inside the same path cleaning as the copy paths:
    // an absolute path, no NUL, no symlinked parent.
    if (op == QStringLiteral("file.read-text")) {
        const QString path = cleanPath(payload.value(QStringLiteral("path")).toString());
        if (path.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-path"),
                    QStringLiteral("文件路径无效"), false);
            return true;
        }
        const QFileInfo info(path);
        if (!info.exists() || !info.isFile()) {
            respond(socket, request, false, {}, QStringLiteral("missing"),
                    QStringLiteral("文件不存在"), false);
            return true;
        }
        const qint64 limit = qBound<qint64>(qint64(4096),
            static_cast<qint64>(payload.value(QStringLiteral("limit")).toDouble(4 * 1024 * 1024)),
            qint64(32 * 1024 * 1024));
        if (info.size() > limit) {
            respond(socket, request, false, {}, QStringLiteral("too-large"),
                    QStringLiteral("文件超过读取上限"), false);
            return true;
        }
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly)) {
            respond(socket, request, false, {}, QStringLiteral("open-failed"),
                    QStringLiteral("无法读取文件"), false);
            return true;
        }
        const QByteArray data = file.readAll();
        QJsonObject result;
        result.insert(QStringLiteral("text"), QString::fromUtf8(data));
        result.insert(QStringLiteral("bytes"), static_cast<double>(data.size()));
        respond(socket, request, true, result, {}, {}, false);
        return true;
    }

    if (op == QStringLiteral("file.write-text")) {
        const QString requested = payload.value(QStringLiteral("path")).toString();
        // cleanCreatePath refuses a path whose parent does not exist, which is
        // the right rule for a copy target the caller was supposed to have
        // prepared. A document store cannot pre-create anything through this
        // protocol, so an explicit mkdir flag is honoured first, and the path
        // is re-cleaned afterwards -- the security check still runs, it just
        // runs on a directory this daemon created.
        QString path = cleanCreatePath(requested);
        if (path.isEmpty() && payload.value(QStringLiteral("mkdir")).toBool(false)
                && QFileInfo(requested).isAbsolute()) {
            QDir().mkpath(QFileInfo(requested).absolutePath());
            path = cleanCreatePath(requested);
        }
        if (path.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-path"),
                    QStringLiteral("文件路径无效"), false);
            return true;
        }
        const QByteArray data = payload.value(QStringLiteral("text")).toString().toUtf8();
        QSaveFile file(path);
        if (!file.open(QIODevice::WriteOnly)) {
            respond(socket, request, false, {}, QStringLiteral("open-failed"),
                    QStringLiteral("无法写入文件"), false);
            return true;
        }
        if (file.write(data) != data.size()) {
            file.cancelWriting();
            respond(socket, request, false, {}, QStringLiteral("write-failed"),
                    QStringLiteral("写入失败"), false);
            return true;
        }
        if (!file.commit()) {
            respond(socket, request, false, {}, QStringLiteral("commit-failed"),
                    QStringLiteral("写入未落盘"), false);
            return true;
        }
        QJsonObject result;
        result.insert(QStringLiteral("bytes"), static_cast<double>(data.size()));
        respond(socket, request, true, result, {}, {}, false);
        return true;
    }

    if (op == QStringLiteral("file.open")) {
        const QString path = cleanPath(payload.value(QStringLiteral("path")).toString());
        if (path.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-path"), QStringLiteral("文件路径无效"), false);
            return true;
        }
        // xdg-open hands the request to a GUI helper whose lifetime is not
        // this request's business; no watchdog.
        runCommand(socket, request, QStringLiteral("xdg-open"), {path}, {}, 0);
        return true;
    }
    if (op == QStringLiteral("file.copy")) {
        const QString source = cleanPath(payload.value(QStringLiteral("source")).toString());
        const QString destination = cleanCreatePath(payload.value(QStringLiteral("destination")).toString());
        if (source.isEmpty() || destination.isEmpty() || !QFileInfo(source).isFile()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-path"),
                    QStringLiteral("文件路径无效"), false);
            return true;
        }
        if (!QDir().mkpath(QFileInfo(destination).path())) {
            respond(socket, request, false, {}, QStringLiteral("copy-failed"),
                    QStringLiteral("无法创建目标目录"), true);
            return true;
        }
        // Reject copying onto the same file rather than replacing it with an
        // unnecessary temporary copy. Canonical
        // paths resolve symlinks; when one side has no canonical form (the
        // destination usually does not exist yet) fall back to absolutes.
        const QFileInfo sourceInfo(source);
        const QFileInfo destinationInfo(destination);
        const QString sourceCanonical = sourceInfo.canonicalFilePath();
        const QString destinationCanonical = destinationInfo.canonicalFilePath();
        const bool sameFile = !sourceCanonical.isEmpty() && !destinationCanonical.isEmpty()
            ? sourceCanonical == destinationCanonical
            : sourceInfo.absoluteFilePath() == destinationInfo.absoluteFilePath();
        if (sameFile) {
            respond(socket, request, false, {}, QStringLiteral("copy-failed"),
                    QStringLiteral("无法复制文件"), true);
            return true;
        }
        // The copy itself runs on m_copyPool: a multi-GB transfer would
        // otherwise block every socket client, KWin broadcast and D-Bus
        // signal on this event loop for its whole duration.
        if (!admitCopyJob(socket, request))
            return true;
        auto *watcher = new QFutureWatcher<CopyResult>(this);
        const QPointer<QLocalSocket> guardedSocket(socket);
        connect(watcher, &QFutureWatcher<CopyResult>::finished, this,
                [this, watcher, guardedSocket, request, destination]() {
            watcher->deleteLater();
            releaseCopyJob();
            if (watcher->result().error.isEmpty()) {
                respond(guardedSocket.data(), request, true,
                        QJsonObject{{QStringLiteral("path"), destination}});
            } else {
                respond(guardedSocket.data(), request, false, {},
                        QStringLiteral("copy-failed"),
                        QStringLiteral("无法复制文件"), true);
            }
        });
        watcher->setFuture(QtConcurrent::run(&m_copyPool, copyFileChunked,
                                             source, destination));
        return true;
    }
    if (op == QStringLiteral("file.launch")) {
        // "打开" on a desktop launcher sends desktopFile (an absolute path),
        // "打开方式" only knows the installed storage id.
        const QString requested = payload.value(QStringLiteral("desktopFile")).toString();
        const QString desktop = resolveDesktopFile(requested.isEmpty()
            ? payload.value(QStringLiteral("desktopId")).toString() : requested);
        const QString target = cleanPath(payload.value(QStringLiteral("path")).toString());
        if (desktop.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-desktop-file"),
                    QStringLiteral("启动器不存在"), false);
            return true;
        }
        if (target.isEmpty() && payload.contains(QStringLiteral("path"))) {
            respond(socket, request, false, {}, QStringLiteral("invalid-path"), QStringLiteral("文件路径无效"), false);
            return true;
        }
        const KService::Ptr service(new KService(desktop));
        launchDesktopService(socket, request, service,
                             target.isEmpty() ? QList<QUrl>{} : QList<QUrl>{QUrl::fromLocalFile(target)});
        return true;
    }
    if (op == QStringLiteral("file.trash")) {
        const QStringList paths = cleanPaths(payload.value(QStringLiteral("paths")));
        if (paths.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-path"), QStringLiteral("文件路径无效"), false);
            return true;
        }
        runCommand(socket, request, QStringLiteral("gio"), QStringList{QStringLiteral("trash")} + paths, {}, 30000);
        return true;
    }
    if (op == QStringLiteral("file.trash-state")) {
        const QString root = freedesktopTrashRoot();
        if (root.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("trash-unavailable"),
                    QStringLiteral("回收站路径不可用"), false);
            return true;
        }
        const QFileInfo files(root + QStringLiteral("/files"));
        bool hasItems = false;
        if (files.exists() && files.isDir() && !files.isSymLink()) {
            QDirIterator iterator(files.absoluteFilePath(),
                                   QDir::NoDotAndDotDot | QDir::AllEntries
                                       | QDir::Hidden | QDir::System);
            hasItems = iterator.hasNext();
        }
        respond(socket, request, true,
                QJsonObject{{QStringLiteral("hasItems"), hasItems}});
        return true;
    }
    if (op == QStringLiteral("file.empty-trash")) {
        const QString root = freedesktopTrashRoot();
        if (root.isEmpty() || !emptyTrashDirectory(root + QStringLiteral("/files"))
            || !emptyTrashDirectory(root + QStringLiteral("/info"))) {
            respond(socket, request, false, {}, QStringLiteral("trash-empty-failed"),
                    QStringLiteral("无法清空回收站"), true);
            return true;
        }
        respond(socket, request, true,
                QJsonObject{{QStringLiteral("emptied"), true}});
        return true;
    }
    if (op == QStringLiteral("file.open-trash")) {
        const QString dolphin = QStandardPaths::findExecutable(QStringLiteral("dolphin"));
        if (dolphin.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("trash-unavailable"),
                    QStringLiteral("Dolphin 不可用"), false);
            return true;
        }
        // Dolphin is a long-lived GUI process; killing it on a watchdog
        // would close the file manager window the user just opened.
        runCommand(socket, request, dolphin, {QStringLiteral("trash:")}, {}, 0);
        return true;
    }
    if (op == QStringLiteral("file.rename")) {
        const QString source = cleanPath(payload.value(QStringLiteral("source")).toString());
        const QString target = cleanPath(payload.value(QStringLiteral("target")).toString());
        if (source.isEmpty() || target.isEmpty() || QFileInfo::exists(target)) {
            respond(socket, request, false, {}, QStringLiteral("target-exists"), QStringLiteral("目标文件已存在或路径无效"), false);
            return true;
        }
        if (QFile::rename(source, target))
            respond(socket, request, true, QJsonObject{{QStringLiteral("path"), target}});
        else
            respond(socket, request, false, {}, QStringLiteral("rename-failed"), QStringLiteral("重命名失败"), true);
        return true;
    }
    if (op == QStringLiteral("file.create-folder") || op == QStringLiteral("file.create-file")) {
        const QString directory = cleanPath(payload.value(QStringLiteral("directory")).toString());
        if (directory.isEmpty() || !QFileInfo(directory).isDir()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-path"), QStringLiteral("文件路径无效"), false);
            return true;
        }
        const QString baseName = op.endsWith(QStringLiteral("folder"))
            ? QStringLiteral("untitled folder") : QStringLiteral("untitled file.txt");
        QString path = uniquePath(directory, baseName);
        const bool ok = path.isEmpty() ? false
            : (op.endsWith(QStringLiteral("folder")) ? QDir().mkpath(path)
               : [&path] { QFile file(path); return file.open(QIODevice::WriteOnly); }());
        if (ok)
            respond(socket, request, true, QJsonObject{{QStringLiteral("path"), path}});
        else
            respond(socket, request, false, {}, QStringLiteral("create-failed"), QStringLiteral("创建失败"), true);
        return true;
    }
    if (op == QStringLiteral("file.transfer")) {
        const QString destination = cleanPath(payload.value(QStringLiteral("destination")).toString());
        const QString mode = payload.value(QStringLiteral("mode")).toString();
        const bool move = mode == QStringLiteral("move");
        const QStringList paths = cleanPaths(payload.value(QStringLiteral("paths")));
        if (destination.isEmpty() || paths.isEmpty()
            || (mode != QStringLiteral("copy") && !move)) {
            respond(socket, request, false, {}, QStringLiteral("invalid-transfer"),
                    QStringLiteral("文件传输请求无效"), false);
            return true;
        }
        if (!QFileInfo(destination).isDir() && !QDir().mkpath(destination)) {
            respond(socket, request, false, {}, QStringLiteral("invalid-destination"),
                    QStringLiteral("目标文件夹无效"), false);
            return true;
        }
        // Directory traversal and cross-filesystem moves can take as long as
        // file.copy; keep both off the socket/event loop.
        if (!admitCopyJob(socket, request))
            return true;
        using TransferResult = QPair<bool, QStringList>;
        auto *watcher = new QFutureWatcher<TransferResult>(this);
        const QPointer<QLocalSocket> guardedSocket(socket);
        connect(watcher, &QFutureWatcherBase::finished, this,
                [this, watcher, guardedSocket, request, mode] {
            const auto result = watcher->result();
            watcher->deleteLater();
            releaseCopyJob();
            if (!result.first) {
                respond(guardedSocket.data(), request, false, {},
                        QStringLiteral("transfer-failed"), QStringLiteral("文件传输未完成"), true);
                return;
            }
            respond(guardedSocket.data(), request, true,
                    QJsonObject{{QStringLiteral("paths"), jsonPaths(result.second)},
                                {QStringLiteral("mode"), mode}});
        });
        watcher->setFuture(QtConcurrent::run(&m_copyPool, [paths, destination, move] {
            QStringList transferred;
            for (const QString &source : paths) {
                const QString target = uniquePath(destination, QFileInfo(source).fileName());
                if (target.isEmpty() || target == source || !moveOrCopy(source, target, move))
                    return TransferResult(false, transferred);
                transferred.append(target);
            }
            return TransferResult(true, transferred);
        }));
        return true;
    }
    if (op == QStringLiteral("file.open-with")) {
        const QString path = cleanPath(payload.value(QStringLiteral("path")).toString());
        if (path.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-path"), QStringLiteral("文件路径无效"), false);
            return true;
        }
        const QString requestedMime = payload.value(QStringLiteral("mime")).toString().trimmed();
        const QPointer<QLocalSocket> guardedSocket(socket);
        auto finish = [this, guardedSocket, request, path](const QString &mime) {
            if (mime.isEmpty()) {
                respond(guardedSocket.data(), request, false, {}, QStringLiteral("mime-unavailable"),
                        QStringLiteral("无法确定文件类型"), false);
                return;
            }
            auto *process = new QProcess(this);
            process->setProgram(QStringLiteral("gio"));
            process->setArguments({QStringLiteral("mime"), mime});
            armProcessWatchdog(process, 10000);
            connect(process, &QProcess::errorOccurred, this,
                    [this, guardedSocket, request, process](QProcess::ProcessError) {
                QObject::disconnect(process, &QProcess::finished, this, nullptr);
                respond(guardedSocket.data(), request, false, {}, QStringLiteral("open-with-failed"),
                        QStringLiteral("无法读取打开方式"), true);
                process->deleteLater();
            });
            connect(process, &QProcess::finished, this,
                    [this, guardedSocket, request, process, mime, path](int exitCode, QProcess::ExitStatus) {
                const QString output = QString::fromUtf8(process->readAllStandardOutput());
                if (exitCode != 0) {
                    respond(guardedSocket.data(), request, false, {}, QStringLiteral("open-with-failed"),
                            QStringLiteral("无法读取打开方式"), true);
                    process->deleteLater();
                    return;
                }
                QString defaultId;
                QStringList handlers;
                const QStringList lines = output.split(QRegularExpression(QStringLiteral("\\r?\\n")));
                for (const QString &line : lines) {
                    const QString trimmed = line.trimmed();
                    const QRegularExpressionMatch defaultMatch =
                        QRegularExpression(QStringLiteral("^Default application.*:\\s*(\\S+)$"))
                            .match(trimmed);
                    if (defaultMatch.hasMatch())
                        defaultId = defaultMatch.captured(1);
                    const QRegularExpressionMatch idMatch =
                        QRegularExpression(QStringLiteral("^(\\S+\\.desktop)$")).match(trimmed);
                    if (idMatch.hasMatch() && !handlers.contains(idMatch.captured(1)))
                        handlers.append(idMatch.captured(1));
                }
                if (!defaultId.isEmpty() && !handlers.contains(defaultId))
                    handlers.prepend(defaultId);
                respond(guardedSocket.data(), request, true,
                        QJsonObject{{QStringLiteral("path"), path},
                                    {QStringLiteral("mime"), mime},
                                    {QStringLiteral("defaultId"), defaultId},
                                    {QStringLiteral("handlers"), QJsonArray::fromStringList(handlers)}});
                process->deleteLater();
            });
            process->start();
        };
        if (!requestedMime.isEmpty()) {
            finish(requestedMime);
            return true;
        }
        auto *info = new QProcess(this);
        info->setProgram(QStringLiteral("gio"));
        info->setArguments({QStringLiteral("info"), QStringLiteral("-a"),
                            QStringLiteral("standard::content-type"), path});
        armProcessWatchdog(info, 10000);
        connect(info, &QProcess::errorOccurred, this,
                [this, info, finish](QProcess::ProcessError) {
            QObject::disconnect(info, &QProcess::finished, this, nullptr);
            finish(QString());
            info->deleteLater();
        });
        connect(info, &QProcess::finished, this,
                [info, finish](int exitCode, QProcess::ExitStatus) {
            const QString output = QString::fromUtf8(info->readAllStandardOutput());
            QString mime;
            if (exitCode == 0) {
                const QRegularExpressionMatch match =
                    QRegularExpression(QStringLiteral("standard::content-type:\\s*(\\S+)"))
                        .match(output);
                if (match.hasMatch())
                    mime = match.captured(1);
            }
            finish(mime);
            info->deleteLater();
        });
        info->start();
        return true;
    }
    if (op == QStringLiteral("file.set-default")) {
        const QString mime = payload.value(QStringLiteral("mime")).toString().trimmed();
        const QString desktopId = payload.value(QStringLiteral("desktopId")).toString().trimmed();
        if (mime.isEmpty() || desktopId.isEmpty() || desktopId.contains(QChar('/'))
            || !desktopId.endsWith(QStringLiteral(".desktop"))) {
            respond(socket, request, false, {}, QStringLiteral("invalid-handler"),
                    QStringLiteral("默认应用无效"), false);
            return true;
        }
        runCommand(socket, request, QStringLiteral("gio"),
                   {QStringLiteral("mime"), mime, desktopId}, {}, 15000);
        return true;
    }
    if (op == QStringLiteral("file.open-kde")) {
        const QString path = cleanPath(payload.value(QStringLiteral("path")).toString());
        if (path.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-path"),
                    QStringLiteral("文件路径无效"), false);
            return true;
        }
        QDBusInterface portal(QStringLiteral("org.freedesktop.impl.portal.desktop.kde"),
                              QStringLiteral("/org/freedesktop/portal/desktop"),
                              QStringLiteral("org.freedesktop.portal.AppChooser"),
                              QDBusConnection::sessionBus());
        portal.setTimeout(kDbusCallTimeoutMs);
        if (!portal.isValid()) {
            respond(socket, request, false, {}, QStringLiteral("open-with-unavailable"),
                    QStringLiteral("KDE 打开方式面板不可用"), false);
            return true;
        }
        const QString mime = QMimeDatabase().mimeTypeForFile(
            path, QMimeDatabase::MatchExtension).name();
        QVariantMap options;
        options.insert(QStringLiteral("content_type"), mime);
        options.insert(QStringLiteral("uri"), QUrl::fromLocalFile(path).toString());
        options.insert(QStringLiteral("filename"), QFileInfo(path).fileName());
        options.insert(QStringLiteral("modal"), true);
        QString token = requestId(request);
        token.replace(QRegularExpression(QStringLiteral("[^A-Za-z0-9_]")),
                      QStringLiteral("_"));
        if (token.isEmpty())
            token = QStringLiteral("request");
        const QDBusPendingCall pending = portal.asyncCall(
            QStringLiteral("ChooseApplication"),
            QVariant::fromValue(QDBusObjectPath(
                QStringLiteral("/org/freedesktop/portal/desktop/request/kos_open_with_")
                    + token)),
            QString(), QString(), QStringList(), options);
        auto *watcher = new QDBusPendingCallWatcher(pending, this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this,
                [this, guardedSocket = QPointer<QLocalSocket>(socket),
                 request, path, watcher] {
            const QDBusMessage reply = watcher->reply();
            watcher->deleteLater();
            if (reply.type() == QDBusMessage::ErrorMessage
                || reply.arguments().size() < 2
                || reply.arguments().at(0).toUInt() != 0) {
                respond(guardedSocket.data(), request, false, {}, QStringLiteral("open-with-failed"),
                        QStringLiteral("KDE 打开方式面板调用失败"), true);
                return;
            }
            const QString applicationId = reply.arguments().at(1).toMap()
                                              .value(QStringLiteral("choice")).toString();
            if (applicationId.isEmpty()) {
                respond(guardedSocket.data(), request, true,
                        QJsonObject{{QStringLiteral("cancelled"), true}});
                return;
            }
            const QString desktop = resolveDesktopFile(applicationId);
            if (desktop.isEmpty()) {
                respond(guardedSocket.data(), request, false, {}, QStringLiteral("open-with-failed"),
                        QStringLiteral("无法启动选中的应用"), true);
                return;
            }
            launchDesktopService(guardedSocket.data(), request, KService::Ptr(new KService(desktop)),
                                 {QUrl::fromLocalFile(path)});
        });
        return true;
    }
    return false;
}

} // namespace KosPlatform
