#pragma once

#include <QObject>
#include <QStringList>
#include <functional>
#include <memory>

namespace listenfree {
// WinSparkle owns download, verification and its native UI. Only installation
// location and graceful Qt shutdown cross this adapter.
class UpdateService final : public QObject {
    Q_OBJECT
public:
    struct Configuration {
        QString libraryPath, appDirectory, version, feedUrl, publicKey, registryPath;
        bool portable = false;
        std::function<bool(const QString &, const QStringList &)> launchInstaller;
    };
    static Configuration productionConfiguration();
    explicit UpdateService(Configuration configuration, QObject *parent = nullptr);
    ~UpdateService() override;
    bool check(QString *error = nullptr);
    bool loaded() const;
    static QStringList installerArguments(const QString &directory, bool portable);
signals:
    void shutdownRequested();
    void updateFound();
    void noUpdateFound();
    void updateError();
    void dismissed();
private:
    friend class UpdateServiceTests;
    bool initialize(QString *error);
    struct Private;
    std::unique_ptr<Private> d;
};
} // namespace listenfree
