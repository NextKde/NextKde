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

// One process owns each operation, independently of the lifetime of its QML page.
class AppStore final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap music READ music NOTIFY changed)
    Q_PROPERTY(QVariantList apps READ apps NOTIFY changed)
    Q_PROPERTY(bool anyBusy READ anyBusy NOTIFY changed)
    Q_PROPERTY(bool hasActiveMutation READ hasActiveMutation NOTIFY changed)
public:
    explicit AppStore(const QString& resourcesDirectory, QObject* parent = nullptr);
    ~AppStore() override;
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
};
