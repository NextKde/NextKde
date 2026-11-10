#pragma once

#include <QElapsedTimer>
#include <QFile>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QProcess>
#include <QTimer>
#include <QVariantMap>
#include "IndependentApps.h"
#include <QFutureWatcher>

// One process owns each operation, independently of the lifetime of its QML page.
class AppStore final : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool testMode READ testMode NOTIFY changed)
    Q_PROPERTY(bool releasesBusy READ releasesBusy NOTIFY changed)
    Q_PROPERTY(QVariantMap releases READ releases NOTIFY changed)
    Q_PROPERTY(QVariantList sources READ sources NOTIFY changed)
    Q_PROPERTY(QString catalogError READ catalogError NOTIFY changed)
    Q_PROPERTY(bool catalogBusy READ catalogBusy NOTIFY changed)
    Q_PROPERTY(bool automaticUpdates READ automaticUpdates WRITE setAutomaticUpdates NOTIFY changed)
    Q_PROPERTY(bool updateNotifications READ updateNotifications WRITE setUpdateNotifications NOTIFY changed)
    Q_PROPERTY(QVariantMap updateStatus READ updateStatus NOTIFY changed)
    Q_PROPERTY(int updateCount READ updateCount NOTIFY changed)
    Q_PROPERTY(QVariantMap music READ music NOTIFY changed)
    Q_PROPERTY(QVariantList apps READ apps NOTIFY changed)
    Q_PROPERTY(bool anyBusy READ anyBusy NOTIFY changed)
    Q_PROPERTY(bool hasActiveMutation READ hasActiveMutation NOTIFY changed)
public:
    explicit AppStore(const QString& resourcesDirectory, QObject* parent = nullptr);
    ~AppStore() override;
    bool startUpdateAgent(bool checkNow = false);
    bool testMode() const;
    Q_INVOKABLE QString setTestMode(bool enabled);
    bool releasesBusy() const { return m_releases.isRunning(); }
    QVariantMap releases() const { return m_releaseResult; }
    Q_INVOKABLE void loadReleases(const QString& repository);
    Q_INVOKABLE QString selectSourceRelease(const QString& id, const QString& repository, const QString& tag);
    Q_INVOKABLE QString selectAppRelease(const QString& id, const QString& repository, const QString& tag);
    QVariantList sources() const;
    QString catalogError() const { return m_catalogError; }
    bool catalogBusy() const { return m_catalogRefresh.isRunning(); }
    bool automaticUpdates() const;
    void setAutomaticUpdates(bool enabled);
    bool updateNotifications() const;
    void setUpdateNotifications(bool enabled);
    QVariantMap updateStatus() const;
    int updateCount() const;
    Q_INVOKABLE void refreshCatalog();
    Q_INVOKABLE void ensureCatalogFresh();
    Q_INVOKABLE QString addSource(const QString& id, const QString& repository, const QString& fingerprint, const QString& publicKeyFile);
    Q_INVOKABLE QString removeSource(const QString& id);
    Q_INVOKABLE void checkAllUpdates();
    QVariantMap music() const;
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void install();
    Q_INVOKABLE void uninstall();
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void open();
    Q_INVOKABLE void openLog();
    Q_INVOKABLE void openRepository();
    QVariantList apps() const;
    bool anyBusy() const;
    bool hasActiveMutation() const;
    Q_INVOKABLE void install(const QString& id);
    Q_INVOKABLE void uninstall(const QString& id);
    Q_INVOKABLE void update(const QString& id);
    Q_INVOKABLE void confirmPlan(const QString& id, const QString& planId);
    Q_INVOKABLE void cancel(const QString& id);
    Q_INVOKABLE void open(const QString& id);
    Q_INVOKABLE void openLog(const QString& id);
    Q_INVOKABLE void openRepository(const QString& id);
    Q_INVOKABLE void checkUpdates(const QString& id);
    Q_INVOKABLE void refreshApps();
    Q_INVOKABLE void cleanupProgram(const QString& id, const QString& action);
signals:
    void changed();
    void taskFinished(const QString& name, const QString& code);
private:
    IndependentApps m_independent;
    QFutureWatcher<QString> m_catalogRefresh;
    QString m_catalogError, m_releaseContext, m_checkAfterRefresh;
    QFutureWatcher<QVariantMap> m_releases;
    QVariantMap m_releaseResult;
};
