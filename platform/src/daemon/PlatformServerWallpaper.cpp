#include "PlatformServer.h"
#include "../wallpaper/PlasmaWallpaperAdapter.h"

#include <QFileInfo>
#include <QFutureWatcher>
#include <QtConcurrent>

namespace KosPlatform {

bool PlatformServer::handleWallpaperOperation(QLocalSocket *socket,
                                               const QJsonObject &request)
{
    const QString op = operation(request);
    if (op == QStringLiteral("wallpaper.preview.desktop")) {
        const QPointer<QLocalSocket> guardedSocket(socket);
        const QPointer<PlatformServer> guard(this);
        const bool showing = request.value(QStringLiteral("payload")).toObject()
            .value(QStringLiteral("showing")).toBool();
        PlasmaWallpaperAdapter::showDesktop(showing,
            [guard, guardedSocket, request](bool ok, bool previous, const QString &error) {
                if (guard && guardedSocket)
                    guard->respond(guardedSocket, request, ok,
                        QJsonObject{{QStringLiteral("previous"), previous}},
                        ok ? QString() : QStringLiteral("desktop-preview-failed"), error);
            });
        return true;
    }
    if (op != QStringLiteral("wallpaper.plasma.proxy")
            && op != QStringLiteral("wallpaper.plasma.restore"))
        return false;

    const QJsonObject payload = request.value(QStringLiteral("payload")).toObject();
    const int screens = payload.value(QStringLiteral("screenCount")).toInt();
    const QString accent = payload.value(QStringLiteral("accent")).toString();
    const QString image = payload.value(QStringLiteral("imagePath")).toString();
    const bool dark = payload.value(QStringLiteral("dark")).toBool();
    const QPointer<QLocalSocket> guardedSocket(socket);
    auto *watcher = new QFutureWatcher<QPair<bool, QString>>(this);
    connect(watcher, &QFutureWatcherBase::finished, this,
            [this, watcher, guardedSocket, request] {
        const auto result = watcher->result();
        if (guardedSocket) {
            respond(guardedSocket.data(), request, result.first, {},
                    result.first ? QString() : QStringLiteral("plasma-wallpaper-failed"),
                    result.second, !result.first);
        }
        watcher->deleteLater();
    });
    watcher->setFuture(QtConcurrent::run([op, accent, dark, screens, image] {
        QString error;
        const bool ok = op == QStringLiteral("wallpaper.plasma.proxy")
            ? PlasmaWallpaperAdapter::applyProxy(accent, dark, screens, &error)
            : PlasmaWallpaperAdapter::restoreImage(image, screens, &error);
        return QPair<bool, QString>(ok, error);
    }));
    return true;
}

#ifdef KOS_SPATIAL_ENABLED
void PlatformServer::runDepthGenerate(QLocalSocket *socket, const QJsonObject &request)
{
    const QString requestedPath = request.value(QStringLiteral("payload")).toObject()
        .value(QStringLiteral("imagePath")).toString();
    const QFileInfo imageInfo(requestedPath);
    if (!imageInfo.isAbsolute() || !imageInfo.exists() || !imageInfo.isFile()
        || imageInfo.canonicalFilePath().isEmpty()) {
        respond(socket, request, false, {}, QStringLiteral("invalid-image-path"),
                QStringLiteral("图片路径无效或文件不存在"), false);
        return;
    }

    const QPointer<QLocalSocket> guardedSocket(socket);
    const QString imagePath = imageInfo.canonicalFilePath();
    const bool prepareSpatial = request.value(QStringLiteral("payload"))
        .toObject().value(QStringLiteral("prepareSpatial")).toBool(false);
    m_aiWorker.generateDepth(imagePath,
        [this, guardedSocket, request](bool ok, const QJsonObject &result,
                                      const QString &code, const QString &message,
                                      bool retryable) {
        if (!ok) {
            respond(guardedSocket.data(), request, false, {}, code, message, retryable);
            return;
        }
        respond(guardedSocket.data(), request, true, result);
    }, prepareSpatial);
}
#endif

} // namespace KosPlatform
