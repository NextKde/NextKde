#pragma once

#include <QByteArray>
#include <QFileSystemWatcher>
#include <QJsonObject>
#include <QObject>
#include <QStringList>
#include <QTimer>

namespace KosPlatform::WidgetPackageIndex {

inline constexpr int kMinSupportedSdkVersion = 1;
inline constexpr int kMaxSupportedSdkVersion = 1;
inline constexpr int kCurrentApiRevision = 1;

// Discovery only: inspect package metadata without instantiating either QML entry.
QJsonObject snapshot();
QJsonObject snapshotForRoots(const QStringList &dataRoots,
                             int minSdkVersion = kMinSupportedSdkVersion,
                             int maxSdkVersion = kMaxSupportedSdkVersion,
                             int currentApiRevision = kCurrentApiRevision);

// Watches installed widget package roots with inotify (via QFileSystemWatcher)
// and emits debounced snapshots only when the indexed catalog actually changes.
class WidgetPackageWatcher final : public QObject {
    Q_OBJECT

public:
    explicit WidgetPackageWatcher(QObject *parent = nullptr);
    explicit WidgetPackageWatcher(const QStringList &dataRoots, QObject *parent = nullptr);

public slots:
    void resyncWatches();

signals:
    void snapshotChanged(const QJsonObject &snapshot);

private:
    void onWatchEvent();
    void handleDebouncedChange();

    QStringList m_dataRoots;
    QFileSystemWatcher m_watcher;
    QTimer m_debounceTimer;
    QByteArray m_lastSnapshotBytes;
};

}
