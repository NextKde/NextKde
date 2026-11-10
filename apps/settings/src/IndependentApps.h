#pragma once

#include "AppOperationPolicy.h"

#include "FlatpakAppsClient.h"

#include <QElapsedTimer>
#include <QFile>
#include <QJsonObject>
#include <QProcess>
#include <QTimer>
#include <QVariantList>

// Signed catalog entries; executable installation behavior stays in compiled adapters.
class IndependentApps final : public QObject {
    Q_OBJECT
public:
    explicit IndependentApps(const QString& resources, QObject* parent = nullptr);
    ~IndependentApps() override;
    QVariantList apps() const;
    bool busy() const { return m_active >= 0 || !m_pendingStatus.isEmpty() || m_flatpak.busy(); }
    bool hasActiveMutation() const { return m_flatpak.hasActiveMutation() || (m_active >= 0 && (m_verifying || isAppMutation(m_action))); }
    void refresh();
    void perform(const QString& id, const QString& action);
    void confirmPlan(const QString& id, const QString& planId);
    void cancel(const QString& id);
    void open(const QString& id);
    void openLog(const QString& id);
    void openRepository(const QString& id);
signals:
    void changed();
    void taskFinished(const QString& name, const QString& code);
private:
    friend class IndependentAppsTest;
    void syncCatalog();
    int indexOf(const QString& id) const;
    void start(int index, const QString& action);
    void nextStatus();
    void consume();
    void consumeLine(const QByteArray& line);
    void finish(int exitCode, QProcess::ExitStatus status);
    void complete(const QString& code, const QString& message = {});
    void stop(int signal);
    void log(const QByteArray& bytes);
    void applyStatus(QVariantMap& state, const QJsonObject& event);
    FlatpakAppsClient m_flatpak;
    QVariantList m_apps;
    QVariantMap m_flatpakResults;
    QString m_script, m_catalogContext;
    QProcess m_process;
    QTimer m_deadline, m_killTimer, m_elapsedTimer;
    QElapsedTimer m_elapsed;
    QFile m_log;
    QList<int> m_pendingStatus;
    QByteArray m_output;
    QJsonObject m_result;
    QString m_action, m_forcedCode, m_expectedVersion, m_expectedRevision, m_requestedVersion;
    int m_active = -1, m_resultCount = 0;
    qint64 m_group = 0, m_outputBytes = 0;
    bool m_protocolError = false, m_verifying = false, m_expectedInstalled = false;
    // Engine metadata discovery has a 90s global budget; allow 10s for its
    // explicit NETWORK_TIMEOUT result before the controller's final safeguard.
    int m_statusTimeout = 30000, m_releaseTimeout = 100000, m_operationTimeout = 30 * 60 * 1000;
};
