#pragma once

#include "AppOperationPolicy.h"

#include <QFutureWatcher>
#include <QObject>
#include <QTimer>
#include <QVariantMap>
#include <QElapsedTimer>
#include <QFile>
#include <memory>
#include "FlatpakTransactionProcess.h"

// Flatpak inventory and transactions never fall back to the source installer.
class FlatpakApps final : public QObject {
    Q_OBJECT
public:
    explicit FlatpakApps(QObject* parent = nullptr);
    ~FlatpakApps() override;
    bool hasActiveMutation() const { return busy() && isAppMutation(m_action); }
    void refresh();
    QVariantMap state(const QString& appId) const;
    bool querying() const { return m_watcher.isRunning(); }
    bool busy() const { return !m_activeId.isEmpty(); }
    bool uninstall(const QString& appId);
    bool removeRetired(const QString& appId);
    bool checkUpdates(const QString& appId);
    bool update(const QString& appId);
    bool install(const QString& appId);
    void cancel();
signals:
    void changed();
    void mutationFinished(const QString& appId, const QString& code);
    void operationFinished(const QString& appId, const QString& code, const QString& message);
private:
    struct Cancellation;
    friend class FlatpakCompatibilityTest;
    friend int FlatpakTransactionProcess::helperMain();
    static QVariantMap executeRemoval(const QVariantMap& request, const std::shared_ptr<Cancellation>& cancellation);
    static QVariantMap executeDeployment(const QVariantMap& request, const std::shared_ptr<Cancellation>& cancellation);
    struct Inventory {
        QVariantMap apps;
        QString error;
    };
    bool deploy(const QString& appId, bool installing);
    bool remove(const QString& appId, bool retired);
    bool beginOperation(const QString& appId, const QString& action, int timeout);
    void reportProgress();
    QFutureWatcher<Inventory> m_watcher;
    QFutureWatcher<QVariantMap> m_transaction;
    QTimer m_refreshTimer, m_deadline, m_transactionDeadline, m_progressTimer;
    QElapsedTimer m_elapsed;
    QFile m_log;
    QVariantMap m_progress;
    QString m_logPath, m_logAppId, m_lastStatus;
    std::shared_ptr<Cancellation> m_cancellation, m_transactionCancellation;
    Inventory m_inventory;
    QVariantMap m_updates, m_checkedInstallation;
    QString m_activeId, m_action, m_targetCommit, m_transactionCode, m_transactionMessage;
    bool m_verifying = false, m_timedOut = false;
};
