#include "AppUpdateAgent.h"
#include "AppCatalog.h"
#include <QDateTime>
#include <QRandomGenerator>
#include <QLockFile>
#include <QtConcurrentRun>

AppUpdateAgent::AppUpdateAgent(QObject* parent) : QObject(parent)
{
    auto previousStatus = AppCatalog::readState("update-status");
    previousStatus["running"] = false;
    AppCatalog::writeState("update-status", previousStatus);
    m_notified = AppCatalog::readState("notified");
    m_lastRequest = AppCatalog::readState("check-request").value("timestamp").toLongLong();
    const auto last = QDateTime::fromString(AppCatalog::readState("update-status").value("finishedAt").toString(), Qt::ISODate).toSecsSinceEpoch();
    const auto now = QDateTime::currentSecsSinceEpoch();
    m_nextCheck = qMax(now + 120 + QRandomGenerator::global()->bounded(120), last + 6 * 3600);
    m_timer.setInterval(15000);
    connect(&m_timer, &QTimer::timeout, this, &AppUpdateAgent::tick);
    connect(&m_refresh, &QFutureWatcher<QString>::finished, this, [this] {
        if (!m_refresh.result().isEmpty()) m_errors.append(m_refresh.result());
        m_waitingInventory = true;
        m_client.refresh();
    });
    connect(&m_client, &FlatpakAppsClient::changed, this, [this] {
        if (m_running && m_waitingInventory && !m_client.querying()) {
            m_waitingInventory = false;
            for (const auto& item : AppCatalog::apps()) {
                const auto entry = item.toMap();
                const auto id = entry.value("appId").toString();
                const auto state = m_client.state(id);
                if (entry.value("active").toBool() && !state.value("known").toBool())
                    m_errors.append(id + ": " + state.value("error").toString());
                if (entry.value("active").toBool() && entry.value("format").toString() == "flatpak"
                    && state.value("known").toBool() && state.value("canDiscover").toBool()
                    && !state.value("installations").toList().isEmpty()) m_pending.append(id);
            }
            QTimer::singleShot(0, this, &AppUpdateAgent::next);
        }
    });
    connect(&m_client, &FlatpakAppsClient::operationFinished, this,
        [this](const QString& id, const QString& code, const QString& message) {
            if (!m_running || m_active != id) return;
            if (!code.isEmpty()) m_errors.append(id + ": " + code + " " + message);
            m_active.clear();
            QTimer::singleShot(0, this, &AppUpdateAgent::next);
        });
    connect(&m_notifications, &TaskNotifications::updatesDelivered, this, [this] {
        for (auto it = m_notificationCandidates.begin(); it != m_notificationCandidates.end(); ++it) m_notified[it.key()] = it.value();
        AppCatalog::writeState("notified", m_notified);
        m_notificationCandidates.clear();
    });
    m_timer.start();
}
void AppUpdateAgent::requestCheck() { m_manual = true; tick(); }
void AppUpdateAgent::tick()
{
    const auto request = AppCatalog::readState("check-request").value("timestamp").toLongLong();
    if (request > m_lastRequest) { m_lastRequest = request; m_manual = true; }
    if (m_running) return;
    const auto preferences = AppCatalog::readState("preferences");
    if (m_manual || (preferences.value("automaticUpdates", true).toBool() && QDateTime::currentSecsSinceEpoch() >= m_nextCheck)) start();
}
void AppUpdateAgent::start()
{
    QLockFile mutationLock(AppCatalog::stateDirectory() + "/flatpak-mutation.lock");
    if (!mutationLock.tryLock(0)) return; // Retry on the next tick after a foreground transaction.
    m_running = true; m_manual = false; m_errors.clear(); m_pending.clear();
    m_lastRequest = AppCatalog::readState("check-request").value("timestamp").toLongLong();
    AppCatalog::writeState("update-status", {{"running", true}, {"startedAt", QDateTime::currentDateTimeUtc().toString(Qt::ISODate)}});
    m_refresh.setFuture(QtConcurrent::run([] { return AppCatalog::refresh(); }));
}
void AppUpdateAgent::next()
{
    if (!m_running || !m_active.isEmpty()) return;
    if (m_client.querying()) { QTimer::singleShot(500, this, &AppUpdateAgent::next); return; }
    if (m_pending.isEmpty()) { finish(); return; }
    m_active = m_pending.takeFirst();
    if (!m_client.checkUpdates(m_active)) {
        m_errors.append(m_active + ": check unavailable"); m_active.clear();
        QTimer::singleShot(0, this, &AppUpdateAgent::next);
    }
}
void AppUpdateAgent::finish()
{
    int count = 0;
    for (const auto& item : AppCatalog::apps()) {
        const auto app = item.toMap(); const auto id = app.value("appId").toString();
        const auto update = m_client.state(id).value("update").toMap();
        if (!app.value("active").toBool() || !update.value("available").toBool()) continue;
        const auto candidate = update.value("version").toString() + ':' + update.value("commit").toString();
        if (m_notified.value(id).toString() != candidate) { ++count; m_notificationCandidates[id] = candidate; }
    }
    AppCatalog::writeState("update-status", {{"running", false}, {"finishedAt", QDateTime::currentDateTimeUtc().toString(Qt::ISODate)},
        {"error", m_errors.join('\n')}});
    if (count && AppCatalog::readState("preferences").value("updateNotifications", true).toBool())
        m_notifications.sendUpdates(count);
    else m_notificationCandidates.clear();
    m_client.releaseIdleWorker();
    m_running = false;
    m_nextCheck = QDateTime::currentSecsSinceEpoch() + (m_errors.isEmpty() ? 6 * 3600 : 3600)
        + QRandomGenerator::global()->bounded(300);
}
