#pragma once

#include <QFutureWatcher>
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <atomic>

// Manages installation, updates, verification and removal of third-party QML
// widget packages sourced from signed AppCatalog widgets.json directories.
class WidgetPackages final : public QObject {
    Q_OBJECT
public:
    struct DeployResult {
        QString code;
        QString message;
        QString installedVersion;
    };

    explicit WidgetPackages(QObject* parent = nullptr);
    ~WidgetPackages() override;

    QVariantList widgets() const;
    bool busy() const;
    bool hasActiveMutation() const;

    void refresh();
    void perform(const QString& id, const QString& action);
    void cancel(const QString& id);
    void openRepository(const QString& id);

    static QString widgetInstallRoot();
    static int compareSemver(const QString& lhs, const QString& rhs);
    static DeployResult deployVerifiedArchive(const QString& appId,
                                              const QString& expectedVersion,
                                              const QString& assetName,
                                              const QString& expectedSha256,
                                              qint64 expectedSize,
                                              const QByteArray& archiveBytes,
                                              const QString& installRoot,
                                              bool requireUpgrade,
                                              const QString& currentVersion,
                                              bool allowDowngrade);
    static DeployResult removeManagedPackage(const QString& appId,
                                             const QString& installRoot);

signals:
    void changed();
    void taskFinished(const QString& name, const QString& code);

private:
    int indexOf(const QString& id) const;
    void syncCatalog();

    QVariantList m_widgets;
    QMap<QString, QVariantMap> m_results;
    QString m_catalogContext;
    QString m_activeId;
    QString m_activeName;
    QString m_stage;
    std::atomic_bool m_cancelled{false};
    QFutureWatcher<DeployResult> m_watcher;
};
