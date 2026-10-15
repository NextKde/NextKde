#include "PlatformServer.h"

#include <KIO/ApplicationLauncherJob>
#include <KService>
#include <QJsonArray>
#include <QJsonValue>
#include <QList>
#include <QUrl>

namespace KosPlatform {

bool PlatformServer::handleApplication(QLocalSocket *socket,
                                       const QJsonObject &request)
{
    if (operation(request) != QStringLiteral("application.launch"))
        return false;

    const QJsonObject payload = request.value(QStringLiteral("payload")).toObject();
    const QString desktopId = payload.value(QStringLiteral("desktopId")).toString().trimmed();
    if (desktopId.isEmpty() || desktopId.contains(QChar('/'))
        || desktopId.contains(QChar('\\')) || desktopId.size() > 255) {
        respond(socket, request, false, {}, QStringLiteral("invalid-desktop-id"),
                QStringLiteral("应用标识无效"), false);
        return true;
    }

    const KService::Ptr service = KService::serviceByStorageId(desktopId);
    if (!service || !service->isApplication()) {
        respond(socket, request, false, {}, QStringLiteral("application-not-found"),
                QStringLiteral("应用启动器不存在"), false);
        return true;
    }

    QList<QUrl> urls;
    const QJsonValue urlsValue = payload.value(QStringLiteral("urls"));
    if (!urlsValue.isUndefined() && !urlsValue.isArray()) {
        respond(socket, request, false, {}, QStringLiteral("invalid-urls"),
                QStringLiteral("应用 URL 参数无效"), false);
        return true;
    }
    const QJsonArray urlArray = urlsValue.toArray();
    if (urlArray.size() > 64) {
        respond(socket, request, false, {}, QStringLiteral("too-many-urls"),
                QStringLiteral("应用 URL 参数过多"), false);
        return true;
    }
    for (const QJsonValue &value : urlArray) {
        if (!value.isString()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-urls"),
                    QStringLiteral("应用 URL 参数无效"), false);
            return true;
        }
        const QUrl url = QUrl::fromUserInput(value.toString());
        if (!url.isValid()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-urls"),
                    QStringLiteral("应用 URL 参数无效"), false);
            return true;
        }
        urls.append(url);
    }

    launchDesktopService(socket, request, service, urls);
    return true;
}

void PlatformServer::launchDesktopService(QLocalSocket *socket, const QJsonObject &request,
                                          const KService::Ptr &service, const QList<QUrl> &urls)
{
    if (!service || !service->isApplication()) {
        respond(socket, request, false, {}, QStringLiteral("invalid-desktop-file"),
                QStringLiteral("应用启动器无效"), false);
        return;
    }
    auto *job = new KIO::ApplicationLauncherJob(service, this);
    job->setUrls(urls);
    const QPointer<QLocalSocket> guardedSocket(socket);
    connect(job, &KJob::result, this,
            [this, guardedSocket, request, job]() {
        if (job->error() != 0) {
            respond(guardedSocket.data(), request, false, {},
                    QStringLiteral("application-launch-failed"),
                    job->errorText().isEmpty() ? QStringLiteral("应用启动失败")
                                               : job->errorText(),
                    true);
            return;
        }
        QJsonArray pids;
        for (const qint64 pid : job->pids())
            pids.append(pid);
        respond(guardedSocket.data(), request, true,
                QJsonObject{{QStringLiteral("started"), true},
                            {QStringLiteral("pids"), pids}});
    });
    job->start();
}

} // namespace KosPlatform
