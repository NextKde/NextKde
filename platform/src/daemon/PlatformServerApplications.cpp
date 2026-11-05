#include "PlatformServer.h"

#include <KIO/ApplicationLauncherJob>
#include <KService>
#include <QJsonArray>
#include <QJsonValue>
#include <QList>
#include <QUrl>
#include <QDate>
#include <QTimer>
#include <QSet>
#include <QFutureWatcher>
#include <QRegularExpression>
#include <QtConcurrentRun>
#include <KShell>
#include "IndependentAppWidgets.h"

namespace KosPlatform {

bool PlatformServer::handleApplication(QLocalSocket *socket,
                                       const QJsonObject &request)
{
    const QString op = operation(request);
    if (op == QLatin1String("application.widget-snapshot") || op == QLatin1String("application.widget-open")) {
        const QJsonObject payload = request.value(QStringLiteral("payload")).toObject();
        const QString key = payload.value(QStringLiteral("app")).toString();
        if (!IndependentAppWidgets::supported(key)) {
            respond(socket, request, false, {}, QStringLiteral("invalid-widget-app"), QStringLiteral("Unsupported widget application"), false);
            return true;
        }
        const bool opening = op == QLatin1String("application.widget-open");
        QStringList arguments;
        const QJsonObject options = payload.value(QStringLiteral("options")).toObject();
        const QSet<QString> allowed = key == QLatin1String("calendar")
            ? QSet<QString>{QStringLiteral("date"), QStringLiteral("view"), QStringLiteral("item")}
            : QSet<QString>{QStringLiteral("location")};
        for (auto it = options.begin(); it != options.end(); ++it) {
            const QString value = it.value().toString();
            const bool valid = allowed.contains(it.key()) && it.value().isString()
                && !value.isEmpty() && value.size() <= 512
                && !value.contains(QRegularExpression(QStringLiteral("[\\x00-\\x1f\\x7f]")))
                && (it.key() != QLatin1String("date") || (QDate::fromString(value, Qt::ISODate).isValid()
                    && QDate::fromString(value, Qt::ISODate).toString(Qt::ISODate) == value))
                && (it.key() != QLatin1String("view") || QStringList{QStringLiteral("today"), QStringLiteral("reminders"),
                    QStringLiteral("day"), QStringLiteral("week"), QStringLiteral("month"), QStringLiteral("year")}.contains(value));
            if (!valid) {
                respond(socket, request, false, {}, QStringLiteral("invalid-widget-options"), QStringLiteral("Invalid widget navigation arguments"), false);
                return true;
            }
            arguments << QStringLiteral("--") + it.key() << value;
        }
        if (payload.contains(QStringLiteral("options")) && !payload.value(QStringLiteral("options")).isObject()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-widget-options"), QStringLiteral("Invalid widget navigation arguments"), false);
            return true;
        }
        const QString token = payload.value(QStringLiteral("sourceToken")).toString();
        if (opening && token.size() != 64) {
            respond(socket, request, false, {}, QStringLiteral("source-changed"), QStringLiteral("Application source changed; refresh the widget"), true);
            return true;
        }
        const QString flight = QStringLiteral("widget:") + key + QStringLiteral(":snapshot");
        if (m_widgetTimedOut.contains(key) || (m_widgetQueries.contains(key) && (opening || m_widgetOpening.contains(key)))) {
            respond(socket, request, false, {}, QStringLiteral("widget-query-busy"),
                    QStringLiteral("Application inspection is still running; installation state is unknown"), true);
            return true;
        }
        if (opening) {
            if (m_widgetOpening.contains(key)) {
                respond(socket, request, false, {}, QStringLiteral("busy"), QStringLiteral("Application launch is already in progress"), true);
                return true;
            }
            m_widgetOpening.insert(key);
        } else if (queueIfInFlight(flight, socket, request)) {
            return true;
        }
        m_widgetQueries.insert(key);
        const auto control = std::make_shared<IndependentAppWidgets::QueryControl>();
        const auto timedOut = std::make_shared<bool>(false);
        auto *watcher = new QFutureWatcher<QJsonObject>(this);
        auto *deadline = new QTimer(watcher);
        deadline->setSingleShot(true);
        const QPointer<QLocalSocket> guarded(socket);
        const auto expire = [this, control, timedOut, key, opening, guarded, request, flight] {
            if (*timedOut) return;
            *timedOut = true;
            control->cancel();
            m_widgetTimedOut.insert(key);
            if (opening) {
                m_widgetOpening.remove(key);
                respond(guarded.data(), request, false, {}, QStringLiteral("widget-query-timeout"),
                        QStringLiteral("Application inspection timed out; installation state is unknown"), true);
            } else {
                completeInFlight(flight, false, {}, QStringLiteral("widget-query-timeout"),
                                 QStringLiteral("Application inspection timed out; installation state is unknown"), true);
            }
        };
        connect(deadline, &QTimer::timeout, this, expire);
        if (opening) connect(socket, &QLocalSocket::disconnected, watcher, [control] { control->cancel(); });
        connect(watcher, &QObject::destroyed, this, [control] { control->cancel(); });
        deadline->start(15000);
        connect(watcher, &QFutureWatcher<QJsonObject>::finished, this,
                [this, watcher, deadline, control, timedOut, expire, guarded, request, key, opening, flight, token, arguments] {
            const auto result = watcher->result();
            deadline->stop();
            if (control->expired()) expire();
            m_widgetQueries.remove(key);
            m_widgetTimedOut.remove(key);
            watcher->deleteLater();
            if (*timedOut) return;
            if (!opening) {
                completeInFlight(flight, true, result);
                return;
            }
            if (!guarded || guarded->state() != QLocalSocket::ConnectedState) {
                m_widgetOpening.remove(key);
                return;
            }
            if (!result.value(QStringLiteral("installed")).toBool()
                || result.value(QStringLiteral("sourceToken")).toString() != token) {
                m_widgetOpening.remove(key);
                respond(guarded.data(), request, false, {}, QStringLiteral("source-changed"), QStringLiteral("Application installation changed; refresh the widget"), true);
                return;
            }
            if (!IndependentAppWidgets::launchEntryMatches(result)) {
                m_widgetOpening.remove(key);
                respond(guarded.data(), request, false, {}, QStringLiteral("source-changed"), QStringLiteral("Application entry or deployment changed"), true);
                return;
            }
            KService::Ptr service(new KService(result.value(QStringLiteral("entryPath")).toString()));
            if (!service->isApplication() || service->exec() != result.value(QStringLiteral("command")).toString()
                || !IndependentAppWidgets::launchEntryMatches(result)) {
                m_widgetOpening.remove(key);
                respond(guarded.data(), request, false, {}, QStringLiteral("source-changed"), QStringLiteral("Application entry changed"), true);
                return;
            }
            // Include the final local checks in the preflight deadline too.
            if (control->expired()) {
                m_widgetOpening.remove(key);
                respond(guarded.data(), request, false, {}, QStringLiteral("widget-query-timeout"),
                        QStringLiteral("Application inspection timed out; installation state is unknown"), true);
                return;
            }
            QString exec = service->exec();
            for (const auto &argument : arguments) {
                QString escaped = argument;
                escaped.replace(QLatin1Char('%'), QStringLiteral("%%"));
                exec += QLatin1Char(' ') + KShell::quoteArg(escaped);
            }
            service->setExec(exec);
            launchDesktopService(guarded.data(), request, service, {}, key);
        });
        watcher->setFuture(QtConcurrent::run([key, control] { return IndependentAppWidgets::snapshot(key, control); }));
        return true;
    }
    if (op != QStringLiteral("application.launch"))
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
                                          const KService::Ptr &service, const QList<QUrl> &urls,
                                          const QString &widgetKey)
{
    if (!service || !service->isApplication()) {
        m_widgetOpening.remove(widgetKey);
        respond(socket, request, false, {}, QStringLiteral("invalid-desktop-file"),
                QStringLiteral("应用启动器无效"), false);
        return;
    }
    auto *job = new KIO::ApplicationLauncherJob(service, this);
    job->setUrls(urls);
    connect(job, &QObject::destroyed, this, [this, widgetKey] {
        m_widgetOpening.remove(widgetKey);
    });
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
