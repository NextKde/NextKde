#pragma once
#include <QJsonObject>
#include <QObject>
#include <QProcess>
#include <QTimer>
#include <QVariantMap>

// Independent settings backend: usable even when the battery cell is absent.
class PowerSettings : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap state READ state NOTIFY changed)
public:
    explicit PowerSettings(QObject *parent = nullptr);
    ~PowerSettings() override;
    QVariantMap state() const;
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void setProfile(const QString &profile);
signals:
    void changed();
private slots:
    void systemChanged(const QString &interface, const QVariantMap &properties,
                       const QStringList &invalidated);
private:
    void start(const QStringList &arguments, bool writing);
    void finishFromBus();
    void applyParsed(const QJsonObject &parsed);
    void complete(bool ok);
    QProcess m_process;
    QTimer m_timeout;
    QStringList m_arguments;
    QStringList m_profiles;
    QString m_active, m_pending, m_degraded, m_error;
    bool m_busy = false, m_writing = false, m_refreshQueued = false;
    bool m_busAttempted = false;
    int m_revision = 0, m_readRevision = 0;
};
