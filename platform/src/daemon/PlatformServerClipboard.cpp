#include "PlatformServer.h"
#include "PlatformClipboardStorage.h"
#include "PlatformPaths.h"
#include "PlatformProcess.h"

#include <QByteArray>
#include <QClipboard>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QImage>
#include <QList>
#include <QMimeData>
#include <QProcess>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <QStringList>
#include <QTimer>
#include <QUrl>
#include <functional>

namespace KosPlatform {
using namespace Detail;

namespace {

constexpr int kClipboardHistoryCacheTtlMs = 1500;

QString clipboardThumbsDir()
{
    return clipboardStateDir() + QStringLiteral("/thumbs");
}

QString clipboardTopic(const QString &record)
{
    return QString::fromLatin1(QCryptographicHash::hash(record.toUtf8(),
                                                        QCryptographicHash::Sha1)
                                   .toHex());
}

void clipboardRemoveThumb(const QString &record)
{
    if (record.isEmpty())
        return;
    QFile::remove(clipboardThumbsDir() + QLatin1Char('/') + clipboardTopic(record)
                  + QStringLiteral(".png"));
}

// Drops every cached preview whose record is no longer in cliphist's output.
// The list operation is the only place that knows the authoritative current
// history, and it runs on every panel refresh, so eviction by cliphist itself
// cannot leave previews behind.
void clipboardPruneThumbs(const QByteArray &listOutput)
{
    QDir dir(clipboardThumbsDir());
    if (!dir.exists())
        return;
    QSet<QString> keep;
    const QStringList lines = QString::fromUtf8(listOutput).split(QChar('\n'));
    for (const QString &line : lines) {
        if (!line.isEmpty())
            keep.insert(clipboardTopic(line));
    }
    const QStringList cached = dir.entryList({QStringLiteral("*.png")}, QDir::Files);
    for (const QString &name : cached) {
        if (!keep.contains(name.chopped(4)))
            dir.remove(name);
    }
}

} // namespace

namespace Detail {

// ---------------------------------------------------------------------------
// Clipboard pin store and preview cache.
//
// cliphist owns the history, but it cannot keep an entry that must outlive
// history rotation, and it cannot hand the Shell a rendered preview. Both are
// kept under the state directory the Shell already owns, so nothing lands
// outside $XDG_STATE_HOME.
//
// Everything here is content-addressed: a file name is a hash of the bytes (or
// of the cliphist record) it belongs to. That is what makes deletion exact -- a
// delete never has to guess which file to drop -- and it makes pinning the same
// content twice an overwrite instead of a second copy.
// ---------------------------------------------------------------------------

QString clipboardStateDir()
{
    // Mirrors AppearanceConfig::configPath(): Quickshell.stateDir resolves to
    // $XDG_STATE_HOME/quickshell/<shell id>, and this shell's id is "kos".
    const QString stateDir = QStandardPaths::writableLocation(
        QStandardPaths::GenericStateLocation);
    return stateDir + QStringLiteral("/quickshell/kos/clipboard");
}

// Renders a decoded payload into the shared preview size. Returns an empty
// string when the bytes are not an image at all, which is how text pins avoid
// getting a thumbnail file they would never use.
QString clipboardWriteThumb(const QByteArray &content, const QString &path)
{
    QImage image;
    if (!image.loadFromData(content))
        return {};
    return clipboardWriteThumb(image, path);
}

QString clipboardWriteThumb(const QImage &image, const QString &path)
{
    if (image.isNull())
        return {};
    // 192 px covers both places the panel draws an entry (list row and grid
    // tile) at device pixel ratio 2, without keeping full screenshots around.
    if (image.width() > 192 || image.height() > 192) {
        QImage scaled = image.scaled(192, 192, Qt::KeepAspectRatio,
                                     Qt::SmoothTransformation);
        if (!scaled.save(path, "PNG"))
            return {};
        return path;
    }
    if (!image.save(path, "PNG"))
        return {};
    return path;
}

} // namespace Detail

void PlatformServer::startClipboardHistoryWatcher(QProcess *&watcher,
                                                   const QStringList &arguments)
{
    if (watcher)
        return;
    if (arguments.isEmpty())
        return;
    auto *process = new QProcess(this);
    watcher = process;
    const QString program = arguments.first();
    const QStringList args = arguments.mid(1);
    process->setProgram(program);
    process->setArguments(args);
    process->setProcessChannelMode(QProcess::ForwardedErrorChannel);
    connect(process, &QProcess::errorOccurred, this,
            [program](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart)
            qWarning() << "Clipboard history watcher unavailable:" << program;
    });
    connect(process, &QProcess::finished, this,
            [this, process, program, args](int, QProcess::ExitStatus) {
        // wl-paste --watch exits when the Wayland connection disappears. Keep
        // the one resident watcher recoverable without spawning a Shell-side
        // supervisor or multiplying helper executables.
        QTimer::singleShot(2000, this, [this, process, program, args] {
            if (process->state() != QProcess::NotRunning)
                return;
            if (process == m_imageHistoryWatcher && !m_watchImages)
                return;
            process->setProgram(program);
            process->setArguments(args);
            process->start();
        });
    });
    process->start();
}

void PlatformServer::runClipboardDecode(QLocalSocket *socket,
                                         const QJsonObject &request,
                                         const QString &record)
{
    if (record.isEmpty()) {
        respond(socket, request, false, {}, QStringLiteral("invalid-clipboard-entry"),
                QStringLiteral("剪贴板记录无效"), false);
        return;
    }
    const QPointer<QLocalSocket> guardedSocket(socket);
    auto *decode = new QProcess(this);
    decode->setProgram(QStringLiteral("cliphist"));
    decode->setArguments({QStringLiteral("decode")});
    armProcessWatchdog(decode, 15000);
    const auto replied = std::make_shared<bool>(false);
    connect(decode, &QProcess::errorOccurred, this,
            [this, guardedSocket, request, decode, replied](QProcess::ProcessError) {
        if (*replied)
            return;
        *replied = true;
        respond(guardedSocket.data(), request, false, {}, QStringLiteral("clipboard-unavailable"),
                QStringLiteral("剪贴板历史不可用"), true);
        decode->deleteLater();
    });
    connect(decode, &QProcess::finished, this,
            [this, guardedSocket, request, decode, replied](int exitCode, QProcess::ExitStatus) {
        if (*replied)
            return;
        if (exitCode != 0) {
            *replied = true;
            respond(guardedSocket.data(), request, false, {}, QStringLiteral("clipboard-decode-failed"),
                    QStringLiteral("无法恢复剪贴板记录"), true);
            decode->deleteLater();
            return;
        }
        const QByteArray decoded = decode->readAllStandardOutput();
        decode->deleteLater();
        auto *copy = new QProcess(this);
        copy->setProgram(QStringLiteral("wl-copy"));
        armProcessWatchdog(copy, 15000);
        connect(copy, &QProcess::started, this,
                [copy, decoded] {
            copy->write(decoded);
            copy->closeWriteChannel();
        });
        connect(copy, &QProcess::errorOccurred, this,
                [this, guardedSocket, request, copy, replied](QProcess::ProcessError) {
            if (*replied)
                return;
            *replied = true;
            respond(guardedSocket.data(), request, false, {}, QStringLiteral("clipboard-unavailable"),
                    QStringLiteral("无法写入剪贴板"), true);
            copy->deleteLater();
        });
        connect(copy, &QProcess::finished, this,
                [this, guardedSocket, request, copy, replied](int exitCode, QProcess::ExitStatus) {
            if (*replied)
                return;
            *replied = true;
            if (exitCode == 0)
                respond(guardedSocket.data(), request, true,
                        QJsonObject{{QStringLiteral("copied"), true}});
            else
                respond(guardedSocket.data(), request, false, {}, QStringLiteral("clipboard-copy-failed"),
                        QStringLiteral("无法写入剪贴板"), true);
            copy->deleteLater();
        });
        copy->start();
    });
    connect(decode, &QProcess::started, this,
            [decode, record] {
        decode->write(record.toUtf8());
        decode->write("\n");
        decode->closeWriteChannel();
    });
    decode->start();
}

void PlatformServer::runClipboardDelete(QLocalSocket *socket,
                                         const QJsonObject &request,
                                         const QString &record)
{
    if (record.isEmpty()) {
        respond(socket, request, false, {}, QStringLiteral("invalid-clipboard-entry"),
                QStringLiteral("剪贴板记录无效"), false);
        return;
    }
    const QPointer<QLocalSocket> guardedSocket(socket);
    auto *process = new QProcess(this);
    process->setProgram(QStringLiteral("cliphist"));
    process->setArguments({QStringLiteral("delete")});
    armProcessWatchdog(process, 10000);
    const auto replied = std::make_shared<bool>(false);
    connect(process, &QProcess::errorOccurred, this,
            [this, guardedSocket, request, process, replied](QProcess::ProcessError) {
        if (*replied)
            return;
        *replied = true;
        respond(guardedSocket.data(), request, false, {}, QStringLiteral("clipboard-unavailable"),
                QStringLiteral("剪贴板历史不可用"), true);
        process->deleteLater();
    });
    connect(process, &QProcess::finished, this,
            [this, guardedSocket, request, process, record, replied](int exitCode,
                                                              QProcess::ExitStatus) {
        if (*replied)
            return;
        *replied = true;
        if (exitCode == 0) {
            // The cached preview belongs to the entry that just went away.
            // Dropping it here is what keeps the state directory from growing
            // a file per deleted entry.
            clipboardRemoveThumb(record);
            invalidateReplies(QStringLiteral("clipboard.history.list"));
            respond(guardedSocket.data(), request, true,
                    QJsonObject{{QStringLiteral("deleted"), true}});
        } else {
            respond(guardedSocket.data(), request, false, {}, QStringLiteral("clipboard-delete-failed"),
                    QStringLiteral("无法删除剪贴板记录"), true);
        }
        process->deleteLater();
    });
    connect(process, &QProcess::started, this,
            [process, record] {
        process->write(record.toUtf8());
        process->write("\n");
        process->closeWriteChannel();
    });
    process->start();
}

void PlatformServer::runCliphistDecode(const QString &record,
                                       std::function<void(bool, const QByteArray &)> done)
{
    auto *process = new QProcess(this);
    process->setProgram(QStringLiteral("cliphist"));
    process->setArguments({QStringLiteral("decode")});
    armProcessWatchdog(process, 15000);
    const auto replied = std::make_shared<bool>(false);
    connect(process, &QProcess::errorOccurred, this,
            [process, replied, done](QProcess::ProcessError) {
        if (*replied)
            return;
        *replied = true;
        process->deleteLater();
        done(false, {});
    });
    connect(process, &QProcess::finished, this,
            [process, replied, done](int exitCode, QProcess::ExitStatus) {
        if (*replied)
            return;
        *replied = true;
        const QByteArray output = process->readAllStandardOutput();
        process->deleteLater();
        done(exitCode == 0, output);
    });
    connect(process, &QProcess::started, this,
            [process, record] {
        process->write(record.toUtf8());
        process->write("\n");
        process->closeWriteChannel();
    });
    process->start();
}

void PlatformServer::runWlCopy(const QByteArray &payload,
                               std::function<void(bool)> done)
{
    auto *process = new QProcess(this);
    process->setProgram(QStringLiteral("wl-copy"));
    armProcessWatchdog(process, 15000);
    const auto replied = std::make_shared<bool>(false);
    connect(process, &QProcess::errorOccurred, this,
            [process, replied, done](QProcess::ProcessError) {
        if (*replied)
            return;
        *replied = true;
        process->deleteLater();
        done(false);
    });
    connect(process, &QProcess::finished, this,
            [process, replied, done](int exitCode, QProcess::ExitStatus) {
        if (*replied)
            return;
        *replied = true;
        process->deleteLater();
        done(exitCode == 0);
    });
    connect(process, &QProcess::started, this,
            [process, payload] {
        process->write(payload);
        process->closeWriteChannel();
    });
    process->start();
}

void PlatformServer::runClipboardThumb(QLocalSocket *socket,
                                       const QJsonObject &request,
                                       const QString &record)
{
    if (record.isEmpty()) {
        respond(socket, request, false, {}, QStringLiteral("invalid-clipboard-entry"),
                QStringLiteral("剪贴板记录无效"), false);
        return;
    }
    const QPointer<QLocalSocket> guardedSocket(socket);
    const QString path = clipboardThumbsDir() + QLatin1Char('/')
        + clipboardTopic(record) + QStringLiteral(".png");
    if (QFileInfo::exists(path)) {
        respond(guardedSocket.data(), request, true,
                QJsonObject{{QStringLiteral("path"), path}});
        return;
    }
    runCliphistDecode(record, [this, guardedSocket, request, path](bool ok,
                                                                 const QByteArray &content) {
        if (!ok) {
            respond(guardedSocket.data(), request, false, {},
                    QStringLiteral("clipboard-decode-failed"),
                    QStringLiteral("无法恢复剪贴板记录"), true);
            return;
        }
        if (!QDir().mkpath(clipboardThumbsDir())
            || clipboardWriteThumb(content, path).isEmpty()) {
            respond(guardedSocket.data(), request, false, {},
                    QStringLiteral("clipboard-image-unavailable"),
                    QStringLiteral("剪贴板记录不是图片"), false);
            return;
        }
        respond(guardedSocket.data(), request, true,
                QJsonObject{{QStringLiteral("path"), path}});
    });
}

bool PlatformServer::handleClipboard(QLocalSocket *socket, const QJsonObject &request)
{
    const QString op = operation(request);
    QClipboard *clipboard = QGuiApplication::clipboard();
    if (!clipboard) {
        respond(socket, request, false, {}, QStringLiteral("clipboard-unavailable"),
                QStringLiteral("剪贴板不可用"), true);
        return true;
    }
    if (op == QStringLiteral("clipboard.set")) {
        const QString mode = request.value(QStringLiteral("payload")).toObject()
                                 .value(QStringLiteral("mode")).toString();
        const QStringList paths = cleanPaths(request.value(QStringLiteral("payload"))
                                                  .toObject().value(QStringLiteral("paths")));
        if ((mode != QStringLiteral("copy") && mode != QStringLiteral("cut"))
            || paths.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-clipboard-request"),
                    QStringLiteral("剪贴板请求无效"), false);
            return true;
        }
        auto *mime = new QMimeData;
        QList<QUrl> urls;
        for (const QString &path : paths)
            urls.append(QUrl::fromLocalFile(path));
        mime->setUrls(urls);
        mime->setData(QString::fromLatin1(kClipboardCutMime), mode == QStringLiteral("cut") ? "1" : "0");
        QByteArray gnome = mode.toUtf8();
        for (const QUrl &url : urls) {
            gnome.append('\n');
            gnome.append(url.toEncoded());
        }
        mime->setData(QString::fromLatin1(kGnomeFilesMime), gnome);
        clipboard->setMimeData(mime, QClipboard::Clipboard);
        if (!clipboard->ownsClipboard()) {
            respond(socket, request, false, {}, QStringLiteral("clipboard-not-owned"),
                    QStringLiteral("无法取得剪贴板所有权"), true);
            return true;
        }
        respond(socket, request, true,
                QJsonObject{{QStringLiteral("mode"), mode},
                            {QStringLiteral("paths"), jsonPaths(paths)}});
        return true;
    }
    if (op == QStringLiteral("clipboard.read")) {
        const QMimeData *mime = clipboard->mimeData(QClipboard::Clipboard);
        if (!mime) {
            respond(socket, request, false, {}, QStringLiteral("clipboard-unavailable"),
                    QStringLiteral("剪贴板不可用"), true);
            return true;
        }
        respond(socket, request, true,
                QJsonObject{{QStringLiteral("mode"), mimeOperation(mime)},
                            {QStringLiteral("paths"), jsonPaths(localClipboardPaths(mime))}});
        return true;
    }
    if (op == QStringLiteral("clipboard.save-image")) {
        const QString destination = cleanCreatePath(request.value(QStringLiteral("payload"))
                                                  .toObject()
                                                  .value(QStringLiteral("destination"))
                                                  .toString());
        const QMimeData *mime = clipboard->mimeData(QClipboard::Clipboard);
        if (destination.isEmpty() || !mime) {
            respond(socket, request, false, {}, QStringLiteral("invalid-clipboard-request"),
                    QStringLiteral("剪贴板请求无效"), false);
            return true;
        }
        QImage image;
        if (mime->hasImage())
            image = qvariant_cast<QImage>(mime->imageData());
        if (image.isNull() && mime->hasFormat(QStringLiteral("image/png")))
            image.loadFromData(mime->data(QStringLiteral("image/png")), "PNG");
        if (image.isNull()) {
            respond(socket, request, false, {}, QStringLiteral("clipboard-image-unavailable"),
                    QStringLiteral("剪贴板中没有 PNG 图片"), false);
            return true;
        }
        QSaveFile output(destination);
        if (!output.open(QIODevice::WriteOnly) || !image.save(&output, "PNG")
            || !output.commit()) {
            respond(socket, request, false, {}, QStringLiteral("clipboard-image-save-failed"),
                    QStringLiteral("无法保存剪贴板图片"), true);
            return true;
        }
        respond(socket, request, true,
                QJsonObject{{QStringLiteral("path"), destination},
                            {QStringLiteral("width"), image.width()},
                            {QStringLiteral("height"), image.height()}});
        return true;
    }
    if (op == QStringLiteral("clipboard.history.watch-images")) {
        m_watchImages = request.value(QStringLiteral("payload")).toObject()
                            .value(QStringLiteral("enabled")).toBool();
        if (!m_watchImages && m_imageHistoryWatcher)
            m_imageHistoryWatcher->kill();
        else if (m_watchImages && m_imageHistoryWatcher
                 && m_imageHistoryWatcher->state() == QProcess::NotRunning)
            m_imageHistoryWatcher->start();
        respond(socket, request, true,
                QJsonObject{{QStringLiteral("enabled"), m_watchImages}});
        return true;
    }
    if (op == QStringLiteral("clipboard.history.list")) {
        runCommand(socket, request, QStringLiteral("cliphist"),
                   {QStringLiteral("list")},
                   [this](const QByteArray &output, int exitCode) {
            // Prune only when the authoritative list actually changed, and no
            // more than once per throttle window: the panel polls this on
            // every refresh, so a naive prune would re-walk the thumbs dir
            // each time for nothing.
            const qint64 now = QDateTime::currentMSecsSinceEpoch();
            const QByteArray hash = QCryptographicHash::hash(
                output, QCryptographicHash::Sha1).toHex();
            if (hash != m_lastClipboardListHash
                || now - m_lastClipboardPruneMs >= 5000) {
                m_lastClipboardListHash = hash;
                m_lastClipboardPruneMs = now;
                clipboardPruneThumbs(output);
            }
            return parseOutput(output, exitCode);
        },
        kDefaultCommandTimeoutMs,
        QStringLiteral("clipboard.history.list"),
        kClipboardHistoryCacheTtlMs);
        return true;
    }
    if (op == QStringLiteral("clipboard.history.copy")) {
        runClipboardDecode(socket, request,
                           request.value(QStringLiteral("payload")).toObject()
                               .value(QStringLiteral("record")).toString());
        return true;
    }
    if (op == QStringLiteral("clipboard.history.delete")) {
        runClipboardDelete(socket, request,
                           request.value(QStringLiteral("payload")).toObject()
                               .value(QStringLiteral("record")).toString());
        return true;
    }
    if (op == QStringLiteral("clipboard.history.clear")) {
        const QPointer<QLocalSocket> guardedSocket(socket);
        auto *process = new QProcess(this);
        process->setProgram(QStringLiteral("cliphist"));
        process->setArguments({QStringLiteral("wipe")});
        armProcessWatchdog(process, 15000);
        const auto replied = std::make_shared<bool>(false);
        connect(process, &QProcess::errorOccurred, this,
                [this, guardedSocket, request, process, replied](QProcess::ProcessError) {
            if (*replied)
                return;
            *replied = true;
            respond(guardedSocket.data(), request, false, {}, QStringLiteral("clipboard-unavailable"),
                    QStringLiteral("剪贴板历史不可用"), true);
            process->deleteLater();
        });
        connect(process, &QProcess::finished, this,
                [this, guardedSocket, request, process, replied](int exitCode, QProcess::ExitStatus) {
            if (*replied)
                return;
            *replied = true;
            if (exitCode == 0) {
                if (auto *clipboard = QGuiApplication::clipboard())
                    clipboard->clear(QClipboard::Clipboard);
                // Pinned entries survive a wipe by design; only the history
                // preview cache is owned by the history that just disappeared.
                QDir(clipboardThumbsDir()).removeRecursively();
                invalidateReplies(QStringLiteral("clipboard.history.list"));
                respond(guardedSocket.data(), request, true,
                        QJsonObject{{QStringLiteral("cleared"), true}});
            } else {
                respond(guardedSocket.data(), request, false, {}, QStringLiteral("clipboard-clear-failed"),
                        QStringLiteral("无法清空剪贴板历史"), true);
            }
            process->deleteLater();
        });
        process->start();
        return true;
    }
    const QJsonObject clipboardPayload =
        request.value(QStringLiteral("payload")).toObject();
    if (op == QStringLiteral("clipboard.thumb")) {
        runClipboardThumb(socket, request,
                          clipboardPayload.value(QStringLiteral("record")).toString());
        return true;
    }
    if (op == QStringLiteral("clipboard.pinned.list")) {
        runClipboardPinnedList(socket, request);
        return true;
    }
    if (op == QStringLiteral("clipboard.pinned.add")) {
        runClipboardPinnedAdd(socket, request,
                              clipboardPayload.value(QStringLiteral("record")).toString(),
                              clipboardPayload.value(QStringLiteral("preview")).toString());
        return true;
    }
    if (op == QStringLiteral("clipboard.pinned.remove")) {
        runClipboardPinnedRemove(socket, request,
                                 clipboardPayload.value(QStringLiteral("pinId")).toString());
        return true;
    }
    if (op == QStringLiteral("clipboard.pinned.copy")) {
        runClipboardPinnedCopy(socket, request,
                               clipboardPayload.value(QStringLiteral("pinId")).toString());
        return true;
    }
    return false;
}

} // namespace KosPlatform
