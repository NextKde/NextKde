#include "library_directory_watcher.h"
#include "library_scanner.h"

#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QtConcurrent>
#include <utility>

namespace listenfree::infrastructure::library {

LibraryDirectoryWatcher::LibraryDirectoryWatcher(QObject* parent) : QObject(parent) {
    timer_.setSingleShot(true);
    timer_.setInterval(500);
    connect(&timer_, &QTimer::timeout, this, &LibraryDirectoryWatcher::inspect);
    connect(&worker_, &QFutureWatcher<Snapshot>::finished, this, &LibraryDirectoryWatcher::applySnapshot);
    connect(&watcher_, &QFileSystemWatcher::directoryChanged, this, [this](const QString& path) {
        if (contains(path)) dirty(path);
        else for (const auto& root : roots_) if (QFileInfo(root).absolutePath() == path) dirty(root);
    });
    connect(&watcher_, &QFileSystemWatcher::fileChanged, this, [this](const QString& path) {
        dirty(QFileInfo(path).absolutePath());
    });
}

LibraryDirectoryWatcher::~LibraryDirectoryWatcher() {
    if (cancelled_) cancelled_->store(true);
    worker_.waitForFinished();
}

bool LibraryDirectoryWatcher::contains(const QString& path) const {
    for (const auto& root : roots_)
        if (path.compare(root, Qt::CaseInsensitive) == 0 ||
            path.startsWith(root.endsWith('/') ? root : root + '/', Qt::CaseInsensitive)) return true;
    return false;
}

void LibraryDirectoryWatcher::setRoots(const QStringList& roots) {
    roots_.clear();
    for (const auto& root : roots) roots_.append(QDir::cleanPath(QFileInfo(root).absoluteFilePath()));
    reset();
}

void LibraryDirectoryWatcher::setEnabled(bool enabled) {
    if (enabled_ == enabled) return;
    enabled_ = enabled;
    reset();
}

void LibraryDirectoryWatcher::reset() {
    suppressReady_ = false;
    ++generation_;
    if (cancelled_) cancelled_->store(true);
    timer_.stop();
    pending_.clear(); observed_.clear(); knownDirectories_.clear(); registration_.clear();
    if (!watcher_.directories().isEmpty()) watcher_.removePaths(watcher_.directories());
    if (!watcher_.files().isEmpty()) watcher_.removePaths(watcher_.files());
    if (!enabled_) return;
    for (const auto& root : roots_) {
        // Parent watch only restores a temporarily missing registered root.
        registration_.append(QFileInfo(root).absolutePath());
        if (QFileInfo(root).isDir()) registration_.append(root);
        pending_.insert(root);
    }
    registerBatch();
    timer_.start();
}

void LibraryDirectoryWatcher::clearPending() {
    // Cancel imports without interrupting initial directory-watch discovery.
    // Otherwise an early Cancel leaves existing subdirectories unmonitored.
    suppressReady_ = true;
}

void LibraryDirectoryWatcher::dirty(const QString& directory) {
    if (!enabled_ || !contains(directory)) return;
    suppressReady_ = false;
    pending_.insert(directory);
    emit directoryDirty(directory);
    if (!timer_.isActive()) timer_.start();
}

void LibraryDirectoryWatcher::fileCompleted(const QString& path) {
    dirty(QFileInfo(path).absolutePath());
}

void LibraryDirectoryWatcher::inspect() {
    if (!enabled_ || pending_.isEmpty() || worker_.isRunning()) return;
    const auto pending = std::exchange(pending_, {});
    const auto known = knownDirectories_;
    const auto generation = generation_;
    cancelled_ = std::make_shared<std::atomic_bool>(false);
    const auto cancelled = cancelled_;
    worker_.setFuture(QtConcurrent::run([pending, known, generation, cancelled] {
        Snapshot result{generation, {}};
        QStringList queue = pending.values();
        while (!queue.isEmpty() && !cancelled->load()) {
            const auto directory = queue.takeLast();
            if (result.leaves.contains(directory)) continue;
            Leaf leaf;
            leaf.exists = QFileInfo(directory).isDir();
            if (leaf.exists) {
                QDirIterator files(directory, musicFileFilters(), QDir::Files | QDir::NoSymLinks);
                while (files.hasNext() && !cancelled->load()) {
                    const QFileInfo info(files.next());
                    leaf.files.insert(info.absoluteFilePath(), {info.size(), info.lastModified().toMSecsSinceEpoch()});
                }
                QDirIterator children(directory, QDir::Dirs | QDir::NoDotAndDotDot | QDir::NoSymLinks);
                QSet<QString> presentChildren;
                while (children.hasNext() && !cancelled->load()) {
                    const auto child = children.next();
                    presentChildren.insert(child);
                    if (!known.contains(child)) queue.append(child);
                }
                // A parent notification can be the only surviving event when
                // a whole subtree is removed and its own watch is dropped.
                for(const auto& child:known)
                    if(QFileInfo(child).absolutePath()==directory && !presentChildren.contains(child))queue.append(child);
            }
            result.leaves.insert(directory, std::move(leaf));
        }
        return result;
    }));
}

void LibraryDirectoryWatcher::applySnapshot() {
    const auto snapshot = worker_.result();
    if (enabled_ && snapshot.generation == generation_) {
        const auto now = QDateTime::currentMSecsSinceEpoch();
        const auto directories = watcher_.directories();
        const auto files = watcher_.files();
        const QSet<QString> watchedDirectories(directories.begin(), directories.end());
        const QSet<QString> watchedFiles(files.begin(), files.end());
        QStringList ready;
        for (auto it = snapshot.leaves.cbegin(); it != snapshot.leaves.cend(); ++it) {
            if (!contains(it.key())) continue;
            if (!it->exists) {
                ready.append(it.key());
                for (auto known = knownDirectories_.begin(); known != knownDirectories_.end();) {
                    if (*known == it.key() || known->startsWith(it.key() + '/')) {
                        observed_.remove(*known);
                        known = knownDirectories_.erase(known);
                    } else ++known;
                }
                continue;
            }
            knownDirectories_.insert(it.key());
            if (!watchedDirectories.contains(it.key())) registration_.append(it.key());
            for (auto file = it->files.cbegin(); file != it->files.cend(); ++file)
                if (!watchedFiles.contains(file.key())) registration_.append(file.key());
            auto previous = observed_.find(it.key());
            if (previous == observed_.end() || previous->files != it->files) {
                observed_.insert(it.key(), {it->files, now});
                pending_.insert(it.key());
            } else if (now - previous->changedAt < 2000) {
                pending_.insert(it.key());
            } else if (!pending_.contains(it.key())) {
                ready.append(it.key());
            }
        }
        registerBatch();
        if (!ready.isEmpty() && !suppressReady_) emit directoriesReady(ready);
    }
    if (enabled_ && !pending_.isEmpty()) timer_.start();
}

void LibraryDirectoryWatcher::registerBatch() {
    if (!enabled_ || registration_.isEmpty()) return;
    QStringList batch;
    while (!registration_.isEmpty() && batch.size() < 64) {
        const auto path = registration_.takeLast();
        if (QFileInfo::exists(path) && !batch.contains(path)) batch.append(path);
    }
    if (!batch.isEmpty()) {
        auto failed = watcher_.addPaths(batch);
        // Duplicate registrations can arise from events during discovery.
        for (const auto& path : watcher_.directories()) failed.removeAll(path);
        for (const auto& path : watcher_.files()) failed.removeAll(path);
        if (!failed.isEmpty()) emit watchFailed(failed);
    }
    if (!registration_.isEmpty()) QTimer::singleShot(0, this, &LibraryDirectoryWatcher::registerBatch);
}
}
