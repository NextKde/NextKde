#pragma once
#include "FlatpakAppsClient.h"
#include "TaskNotifications.h"
#include <QFutureWatcher>
#include <QTimer>

// Session service: metadata only. Never downloads bundles or confirms plans.
class AppUpdateAgent final : public QObject {
    Q_OBJECT
public:
    explicit AppUpdateAgent(QObject* parent = nullptr);
    void requestCheck();
private:
    friend class AppUpdateAgentTest;
    void tick();
    void start();
    void next();
    void finish();
    FlatpakAppsClient m_client{nullptr, false};
    TaskNotifications m_notifications;
    QFutureWatcher<QString> m_refresh;
    QTimer m_timer;
    QStringList m_pending, m_errors;
    QVariantMap m_notified, m_notificationCandidates;
    QString m_active;
    bool m_running = false, m_waitingInventory = false, m_manual = false;
    qint64 m_nextCheck = 0, m_lastRequest = 0;
};
