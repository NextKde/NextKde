#pragma once

#include <QFileSystemWatcher>
#include <QFutureWatcher>
#include <QMap>
#include <QSet>
#include <QTimer>
#include <atomic>
#include <memory>

namespace listenfree::infrastructure::library {

// Directory events are hints, not a file-operation log. Recheck only dirty
// leaves, wait for writes to settle, then use the existing incremental scanner.
class LibraryDirectoryWatcher final : public QObject {
    Q_OBJECT
public:
    explicit LibraryDirectoryWatcher(QObject* parent = nullptr);
    ~LibraryDirectoryWatcher() override;
    void setRoots(const QStringList& roots);
    void setEnabled(bool enabled);
    void fileCompleted(const QString& path);
    void clearPending();
signals:
    void directoryDirty(const QString& directory);
    void directoriesReady(const QStringList& directories);
    void watchFailed(const QStringList& paths);
private:
    using Fingerprints = QMap<QString, QPair<qint64, qint64>>;
    struct Leaf { Fingerprints files; bool exists{false}; };
    struct Snapshot { quint64 generation; QMap<QString, Leaf> leaves; };
    struct Observed { Fingerprints files; qint64 changedAt{0}; };
    void reset();
    void dirty(const QString& directory);
    void inspect();
    void applySnapshot();
    void registerBatch();
    bool contains(const QString& path) const;

    QFileSystemWatcher watcher_;
    QFutureWatcher<Snapshot> worker_;
    QTimer timer_;
    QStringList roots_, registration_;
    QSet<QString> pending_, knownDirectories_;
    QMap<QString, Observed> observed_;
    std::shared_ptr<std::atomic_bool> cancelled_;
    quint64 generation_{0};
    bool enabled_{false}, suppressReady_{false};
};
}
