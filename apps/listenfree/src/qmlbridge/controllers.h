#pragma once

#include "application/application_facade.h"
#include "application/ports.h"
#include "infrastructure/library/library_scan_writer.h"
#include "infrastructure/library/library_directory_watcher.h"
#include "qmlbridge/list_models.h"

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariant>
#include <QVariantMap>
#include <QUrl>
#include <QtGlobal>
#include <cstdint>
#include <memory>
#include <optional>
#include <vector>

namespace listenfree::qmlbridge {

class AppController final : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)
    Q_PROPERTY(bool mockMode READ mockMode CONSTANT)
    Q_PROPERTY(TrackListModel* tracksModel READ tracksModel CONSTANT)
    Q_PROPERTY(QueueModel* queueModel READ queueModel CONSTANT)
    Q_PROPERTY(QString playbackState READ playbackState NOTIFY playbackStateChanged)
public:
    explicit AppController(QObject* parent = nullptr);
    [[nodiscard]] bool ready() const noexcept { return facade_.ready(); }
    [[nodiscard]] bool mockMode() const noexcept { return true; }
    [[nodiscard]] TrackListModel* tracksModel() const noexcept { return tracksModel_.get(); }
    [[nodiscard]] QueueModel* queueModel() const noexcept { return queueModel_.get(); }
    [[nodiscard]] QString playbackState() const;
    Q_INVOKABLE void initialize();
    Q_INVOKABLE void shutdown();
signals:
    void readyChanged();
    void playbackStateChanged();
private:
    application::ApplicationFacade facade_;
    std::unique_ptr<TrackListModel> tracksModel_;
    std::unique_ptr<QueueModel> queueModel_;
};

class LibraryController final : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool scanning READ scanning NOTIFY scanningChanged)
    Q_PROPERTY(quint64 importedCount READ importedCount NOTIFY importedCountChanged)
    Q_PROPERTY(quint64 totalCount READ totalCount NOTIFY totalCountChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(QStringList roots READ roots NOTIFY rootsChanged)
public:
    explicit LibraryController(application::ILocalLibraryScanner& scanner,
                               application::ITrackRepository& repository,
                               application::ILibraryFolderRepository* folderRepository,
                               const QString& databasePath = {},
                               QObject* parent = nullptr);
    ~LibraryController() override;

    [[nodiscard]] bool scanning() const noexcept { return scanning_; }
    [[nodiscard]] bool maintenance() const noexcept { return maintenance_; }
    [[nodiscard]] quint64 importedCount() const noexcept { return importedCount_; }
    [[nodiscard]] quint64 totalCount() const noexcept { return totalCount_; }
    [[nodiscard]] QString lastError() const { return lastError_; }
    [[nodiscard]] QStringList roots() const { return roots_; }

    Q_INVOKABLE void scan(const QStringList& roots);
    Q_INVOKABLE bool addRoot(const QString& path);
    Q_INVOKABLE bool removeRoot(const QString& path);
    Q_INVOKABLE void scanDefault();
    Q_INVOKABLE void cancel();
    void setAutoWatchEnabled(bool enabled);
    void notifyFileCompleted(const QString& path);
    void refreshTotalCount();
    void reloadRoots();
    bool beginMaintenance();
    void endMaintenance();
signals:
    void scanningChanged();
    void libraryContentChanged();
    void importedCountChanged();
    void totalCountChanged();
    void lastErrorChanged();
    void rootsChanged();
private slots:
    void handleCommitted(std::uint64_t generation, int count);
    void handleCommitFailed(std::uint64_t generation, const QString& reason);
    void handleDrained();
private:
    void handleBatch(std::uint64_t generation, std::vector<domain::Track> batch);
    void handleFinished(std::uint64_t generation, application::ScanOutcome outcome);
    void finish(std::uint64_t generation, application::ScanOutcome outcome);
    void maybeApplyFinish();
    void applyFinish(std::uint64_t generation, const application::ScanOutcome& outcome);
    void setLastError(QString error);
    void refreshRoots();
    void beginScan(const QStringList& roots, bool recursive);
    void cancelActiveScan();
    void scanPendingDirectories();

    application::ILocalLibraryScanner& scanner_;
    application::ITrackRepository& repository_;
    application::ILibraryFolderRepository* folderRepository_{nullptr};
    std::unique_ptr<infrastructure::library::LibraryScanWriter> writer_;
    QString databasePath_;
    bool writerStarted_{false};
    int pendingCommits_{0};
    bool finishPending_{false};
    application::ScanOutcome pendingOutcome_;
    std::optional<application::ScanId> activeScanId_;
    std::uint64_t generation_{0};
    quint64 importedCount_{0};
    quint64 totalCount_{0};
    QString lastError_;
    QStringList roots_;
    QStringList activeScanRoots_;
    bool activeScanRecursive_{true};
    bool scanning_{false};
    infrastructure::library::LibraryDirectoryWatcher directoryWatcher_;
    QSet<QString> pendingDirectories_;
    bool autoWatchEnabled_{false}, automaticScan_{false};
    bool maintenance_{false};
};

class PlayerController final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
    Q_PROPERTY(qint64 position READ position NOTIFY positionChanged)
    Q_PROPERTY(qint64 duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(bool seekable READ seekable NOTIFY seekableChanged)
    Q_PROPERTY(float volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(bool muted READ muted WRITE setMuted NOTIFY mutedChanged)
    Q_PROPERTY(quint32 capabilities READ capabilities NOTIFY capabilitiesChanged)
    Q_PROPERTY(QStringList deviceIds READ deviceIds NOTIFY devicesChanged)
    Q_PROPERTY(QString errorCode READ errorCode NOTIFY errorChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorChanged)
    Q_PROPERTY(bool errorRetryable READ errorRetryable NOTIFY errorChanged)
    Q_PROPERTY(QString audioCodec READ audioCodec NOTIFY audioFormatChanged)
    Q_PROPERTY(int sampleRate READ sampleRate NOTIFY audioFormatChanged)
    Q_PROPERTY(int channelCount READ channelCount NOTIFY audioFormatChanged)
    Q_PROPERTY(QueueModel* queueModel READ queueModel CONSTANT)
    Q_PROPERTY(QString currentTrackId READ currentTrackId NOTIFY currentTrackChanged)
    Q_PROPERTY(QVariantMap currentTrack READ currentTrack NOTIFY currentTrackChanged)
    Q_PROPERTY(int currentLyricIndex READ currentLyricIndex NOTIFY currentLyricChanged)
    Q_PROPERTY(QString currentLyricText READ currentLyricText NOTIFY currentLyricChanged)
    Q_PROPERTY(int lyricLineCount READ lyricLineCount NOTIFY lyricsChanged)
public:
    explicit PlayerController(QObject* parent = nullptr);
    explicit PlayerController(std::unique_ptr<application::IAudioPlayer> player,
                              QObject* parent = nullptr);
    ~PlayerController() override;
    [[nodiscard]] QString state() const;
    [[nodiscard]] qint64 position() const noexcept;
    [[nodiscard]] qint64 duration() const noexcept;
    [[nodiscard]] bool seekable() const noexcept;
    [[nodiscard]] float volume() const noexcept;
    [[nodiscard]] bool muted() const noexcept;
    [[nodiscard]] quint32 capabilities() const noexcept;
    [[nodiscard]] QStringList deviceIds() const;
    [[nodiscard]] QString errorCode() const;
    [[nodiscard]] QString errorMessage() const;
    [[nodiscard]] bool errorRetryable() const;
    [[nodiscard]] QString audioCodec() const;
    [[nodiscard]] int sampleRate() const;
    [[nodiscard]] int channelCount() const;
    [[nodiscard]] QueueModel* queueModel() const noexcept { return queueModel_.get(); }
    [[nodiscard]] QString currentTrackId() const;
    [[nodiscard]] QVariantMap currentTrack() const;
    [[nodiscard]] int currentLyricIndex() const noexcept;
    [[nodiscard]] QString currentLyricText() const;
    [[nodiscard]] int lyricLineCount() const noexcept;
    Q_INVOKABLE void openLocal(const QString& path);
    Q_INVOKABLE void openUrl(const QUrl& url);
    Q_INVOKABLE void play();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();
    Q_INVOKABLE bool selectQueue(int index, bool playImmediately = true);
    Q_INVOKABLE bool removeFromQueue(int index);
    Q_INVOKABLE bool moveQueue(int from, int to);
    Q_INVOKABLE void stop();
    Q_INVOKABLE void seek(qint64 position);
    Q_INVOKABLE void setVolume(float volume);
    Q_INVOKABLE void setMuted(bool muted);
    Q_INVOKABLE bool selectDevice(const QString& id);
    void setQueue(std::vector<domain::PlaybackItem> items, std::size_t currentIndex = 0);
    void setLyrics(std::vector<domain::LyricLine> lyrics);
signals:
    void stateChanged();
    void positionChanged();
    void durationChanged();
    void seekableChanged();
    void volumeChanged();
    void mutedChanged();
    void capabilitiesChanged();
    void devicesChanged();
    void errorChanged();
    void audioFormatChanged();
    void currentTrackChanged();
    void currentLyricChanged();
    void lyricsChanged();
private:
    class Impl;
    std::unique_ptr<QueueModel> queueModel_;
    std::unique_ptr<Impl> impl_;
    void syncQueueModel();
};

class PlaylistController final : public QObject {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY changed)
    Q_PROPERTY(QVariantList playlists READ playlists NOTIFY changed)
public:
    explicit PlaylistController(QObject* parent = nullptr) : QObject(parent) {}
    [[nodiscard]] int count() const noexcept { return static_cast<int>(playlists_.size()); }
    [[nodiscard]] QVariantList playlists() const { return playlists_; }
    Q_INVOKABLE QString create(const QString& title);
    Q_INVOKABLE bool rename(const QString& id, const QString& title);
    Q_INVOKABLE bool remove(const QString& id);
signals:
    void changed();
    void errorOccurred(const QString& message);
private:
    QVariantList playlists_;
};

class OnlineController final : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool providerEnabled READ providerEnabled CONSTANT)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString lastQuery READ lastQuery NOTIFY searchResultsChanged)
    Q_PROPERTY(QVariantList searchResults READ searchResults NOTIFY searchResultsChanged)
public:
    explicit OnlineController(QObject* parent = nullptr) : QObject(parent) {}
    [[nodiscard]] bool providerEnabled() const noexcept { return true; }
    [[nodiscard]] bool busy() const noexcept { return busy_; }
    [[nodiscard]] QString lastQuery() const noexcept { return lastQuery_; }
    [[nodiscard]] QVariantList searchResults() const { return searchResults_; }
    Q_INVOKABLE void search(const QString& query);
    Q_INVOKABLE void refreshPlaylist(const QString& id);
signals:
    void busyChanged();
    void searchResultsChanged();
    void searchFinished(const QVariantList& results);
    void playlistRefreshFinished(const QString& id, bool ok);
private:
    bool busy_{false};
    QString lastQuery_;
    QVariantList searchResults_;
};

class SettingsController final : public QObject {
    Q_OBJECT
    Q_PROPERTY(int revision READ revision NOTIFY settingsChanged)
public:
    // Without a repository the controller stays an in-memory fallback used by
    // tests; with one, values persist through the settings table (SQLite).
    explicit SettingsController(QObject* parent = nullptr);
    explicit SettingsController(application::ISettingsRepository& repository, QObject* parent = nullptr);
    ~SettingsController() override;

    int revision() const { return revision_; }
    Q_INVOKABLE QVariant value(const QString& key, const QVariant& fallback = {}) const;
    Q_INVOKABLE void setValue(const QString& key, const QVariant& value);
    Q_INVOKABLE QString localFilePath(const QUrl& url) const;
    Q_INVOKABLE QVariantMap resolveBackground(const QUrl& url, bool wallpaperProject) const;
    bool reloadValues(const QVariantMap& values);
    bool applyingBatch() const { return applyingBatch_; }
    void rejectBatch() { batchRejected_=true; }
    void forgetScrollPositions();
signals:
    void valueChanged(const QString& key, const QVariant& value);
    void settingsChanged();
    void valuesReloaded(const QVariantMap& values);
private:
    int revision_{0};
    bool applyingBatch_{false},batchRejected_{false};
    application::ISettingsRepository* repository_{nullptr};
    QVariantMap values_;
};

} // namespace listenfree::qmlbridge
