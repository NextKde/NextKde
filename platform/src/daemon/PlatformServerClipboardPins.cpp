#include "PlatformServer.h"
#include "PlatformClipboardStorage.h"

#include <QByteArray>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStringList>

namespace KosPlatform {
using namespace Detail;

namespace {

QString clipboardPinnedDir()
{
    return clipboardStateDir() + QStringLiteral("/pinned");
}

QString clipboardPinId(const QByteArray &content)
{
    return QString::fromLatin1(QCryptographicHash::hash(content,
                                                        QCryptographicHash::Sha1)
                                   .toHex()
                                   .left(16));
}

// Pin ids travel through the Shell, so they are validated before ever being
// joined onto a path.
bool isClipboardPinId(const QString &pinId)
{
    static const QRegularExpression pattern(QStringLiteral("^[0-9a-f]{16}$"));
    return pattern.match(pinId).hasMatch();
}

bool clipboardWriteFile(const QString &path, const QByteArray &bytes)
{
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly))
        return false;
    file.write(bytes);
    return file.commit();
}

} // namespace

void PlatformServer::runClipboardPinnedList(QLocalSocket *socket,
                                            const QJsonObject &request)
{
    const QString pinnedDir = clipboardPinnedDir();
    QJsonArray items;
    const QStringList metas = QDir(pinnedDir).entryList({QStringLiteral("*.json")},
                                                        QDir::Files, QDir::Name);
    for (const QString &metaName : metas) {
        const QString pinId = metaName.chopped(5); // ".json"
        if (!isClipboardPinId(pinId))
            continue;
        QFile metaFile(pinnedDir + QLatin1Char('/') + metaName);
        if (!metaFile.open(QIODevice::ReadOnly))
            continue;
        const QJsonObject meta = QJsonDocument::fromJson(metaFile.readAll()).object();
        const bool isImage = meta.value(QStringLiteral("isImage")).toBool();
        const QString thumbnailPath = pinnedDir + QLatin1Char('/') + pinId
            + QStringLiteral(".png");
        items.append(QJsonObject{
            {QStringLiteral("pinId"), pinId},
            {QStringLiteral("isImage"), isImage},
            {QStringLiteral("preview"), meta.value(QStringLiteral("preview")).toString()},
            {QStringLiteral("thumbnailPath"),
             isImage && QFileInfo::exists(thumbnailPath) ? thumbnailPath : QString()},
        });
    }
    respond(socket, request, true, QJsonObject{{QStringLiteral("items"), items}});
}

void PlatformServer::runClipboardPinnedAdd(QLocalSocket *socket,
                                           const QJsonObject &request,
                                           const QString &record,
                                           const QString &preview)
{
    if (record.isEmpty()) {
        respond(socket, request, false, {}, QStringLiteral("invalid-clipboard-entry"),
                QStringLiteral("剪贴板记录无效"), false);
        return;
    }
    const QPointer<QLocalSocket> guardedSocket(socket);
    runCliphistDecode(record, [this, guardedSocket, request, preview](bool ok,
                                                                     const QByteArray &content) {
        if (!ok) {
            respond(guardedSocket.data(), request, false, {},
                    QStringLiteral("clipboard-decode-failed"),
                    QStringLiteral("无法恢复剪贴板记录"), true);
            return;
        }
        const QString pinnedDir = clipboardPinnedDir();
        // Content-addressed: pinning the same thing twice overwrites its own
        // three files instead of producing a second copy.
        const QString pinId = clipboardPinId(content);
        const QString dataPath = pinnedDir + QLatin1Char('/') + pinId
            + QStringLiteral(".data");
        const QString metaPath = pinnedDir + QLatin1Char('/') + pinId
            + QStringLiteral(".json");
        const QString thumbPath = pinnedDir + QLatin1Char('/') + pinId
            + QStringLiteral(".png");

        if (!QDir().mkpath(pinnedDir) || !clipboardWriteFile(dataPath, content)) {
            respond(guardedSocket.data(), request, false, {},
                    QStringLiteral("clipboard-pin-failed"),
                    QStringLiteral("无法写入固定条目"), true);
            return;
        }

        // The payload decides what this is, not the Shell's guess: a decodable
        // image gets a rendered preview, anything else stays text-only.
        QImage probe;
        const bool isImage = probe.loadFromData(content);
        if (isImage)
            clipboardWriteThumb(probe, thumbPath);

        const QJsonObject meta{{QStringLiteral("preview"), preview},
                               {QStringLiteral("isImage"), isImage}};
        if (!clipboardWriteFile(metaPath,
                                QJsonDocument(meta).toJson(QJsonDocument::Compact))) {
            // Never leave a half-written pin behind.
            QFile::remove(dataPath);
            QFile::remove(thumbPath);
            respond(guardedSocket.data(), request, false, {},
                    QStringLiteral("clipboard-pin-failed"),
                    QStringLiteral("无法写入固定条目"), true);
            return;
        }

        respond(guardedSocket.data(), request, true,
                QJsonObject{{QStringLiteral("pinId"), pinId},
                            {QStringLiteral("isImage"), isImage},
                            {QStringLiteral("preview"), preview},
                            {QStringLiteral("thumbnailPath"),
                             isImage ? thumbPath : QString()}});
    });
}

void PlatformServer::runClipboardPinnedRemove(QLocalSocket *socket,
                                              const QJsonObject &request,
                                              const QString &pinId)
{
    if (!isClipboardPinId(pinId)) {
        respond(socket, request, false, {}, QStringLiteral("invalid-clipboard-pin"),
                QStringLiteral("固定条目标识无效"), false);
        return;
    }
    const QString pinnedDir = clipboardPinnedDir();
    bool removed = false;
    const QStringList suffixes{QStringLiteral(".data"), QStringLiteral(".json"),
                               QStringLiteral(".png")};
    for (const QString &suffix : suffixes) {
        removed = QFile::remove(pinnedDir + QLatin1Char('/') + pinId + suffix)
            || removed;
    }
    respond(socket, request, true, QJsonObject{{QStringLiteral("removed"), removed}});
}

void PlatformServer::runClipboardPinnedCopy(QLocalSocket *socket,
                                            const QJsonObject &request,
                                            const QString &pinId)
{
    if (!isClipboardPinId(pinId)) {
        respond(socket, request, false, {}, QStringLiteral("invalid-clipboard-pin"),
                QStringLiteral("固定条目标识无效"), false);
        return;
    }
    QFile file(clipboardPinnedDir() + QLatin1Char('/') + pinId
               + QStringLiteral(".data"));
    if (!file.open(QIODevice::ReadOnly)) {
        respond(socket, request, false, {}, QStringLiteral("clipboard-pin-missing"),
                QStringLiteral("固定条目不存在"), false);
        return;
    }
    const QByteArray content = file.readAll();
    file.close();

    const QPointer<QLocalSocket> guardedSocket(socket);
    runWlCopy(content, [this, guardedSocket, request](bool ok) {
        if (ok) {
            respond(guardedSocket.data(), request, true,
                    QJsonObject{{QStringLiteral("copied"), true}});
        } else {
            respond(guardedSocket.data(), request, false, {},
                    QStringLiteral("clipboard-copy-failed"),
                    QStringLiteral("无法写入剪贴板"), true);
        }
    });
}

} // namespace KosPlatform
