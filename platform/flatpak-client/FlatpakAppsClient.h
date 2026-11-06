#pragma once

#include <QElapsedTimer>
#include <QObject>
#include <QProcess>
#include <QTimer>
#include <QVariantMap>
#include <functional>

// Software deployment/removal notifications exclude preparation. Preparation
// may configure component sources and is separately locked by hasActiveMutation.
inline bool isWorkerMutation(const QString& action)
{
    return action == QLatin1String("install") || action == QLatin1String("update")
        || action == QLatin1String("confirm-plan") || action == QLatin1String("uninstall");
}

// Qt-only front end for the optional Flatpak worker.
class FlatpakAppsClient final : public QObject {
    Q_OBJECT
public:
    explicit FlatpakAppsClient(QObject* parent = nullptr);
    ~FlatpakAppsClient() override;
    void refresh();
    QVariantMap state(const QString& appId) const;
    bool querying() const { return !m_requestId.isEmpty() || !m_queue.isEmpty(); }
    bool busy() const { return !m_activeId.isEmpty() && m_activeAction != "inventory"; }
    bool hasActiveMutation() const { return busy() && (isWorkerMutation(m_activeAction) || m_activeAction.startsWith("prepare-")); }
    bool uninstall(const QString& appId);
    bool checkUpdates(const QString& appId);
    bool update(const QString& appId);
    bool install(const QString& appId);
    bool preparePlan(const QString& appId, bool installing);
    bool confirmPlan(const QString& appId, const QString& planId);
    QString planId(const QString& appId) const;
    void cancel();
    QVariantMap plan(const QString& appId) const;
    static QVariantMap inventory(const std::function<bool()>& cancelled);
signals:
    void changed();
    void operationFinished(const QString& appId, const QString& code, const QString& message);
    void mutationFinished(const QString& appId, const QString& code);
private:
    friend class IndependentAppsTest;
    bool start(const QString& appId, const QString& action);
    bool ensureWorker();
    void startNext();
    void finish(int exitCode, QProcess::ExitStatus status);
    void failActive(const QString& code, const QString& message);
    QProcess m_process;
    QTimer m_refreshTimer, m_deadline, m_killTimer;
    QVariantMap m_states;
    QStringList m_queue;
    QString m_activeId, m_activeAction, m_lastStatus, m_lastCode, m_requestId;
    QString m_planId, m_forcedCode, m_forcedMessage;
    QByteArray m_stdout;
    bool m_cancelRequested = false;
    bool m_workerResponded = false;
};
