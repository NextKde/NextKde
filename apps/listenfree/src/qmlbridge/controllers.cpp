#include "qmlbridge/controllers.h"

#include "application/playback_service.h"
#include "infrastructure/database/database.h"
#if defined(LISTENFREE_HAS_MPV)
#include "media/mpv_audio_player.h"
#endif
#include "media/qt_audio_player.h"

#include <QPointer>
#include <QDir>
#include <QFileInfo>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QTimer>

#include <algorithm>
#include <exception>
#include <filesystem>
#include <iterator>
#include <span>
#include <stdexcept>

namespace listenfree::qmlbridge {

AppController::AppController(QObject* parent)
    : QObject(parent),
      facade_(nullptr),
      tracksModel_(std::make_unique<TrackListModel>()),
      queueModel_(std::make_unique<QueueModel>()) {
    connect(&facade_, &application::ApplicationFacade::readyChanged, this, [this] {
        tracksModel_->setTracks(facade_.tracks());
        std::vector<domain::Track> queueTracks;
        queueTracks.reserve(facade_.queue().items().size());
        for (const auto& item : facade_.queue().items()) queueTracks.push_back(item.track);
        queueModel_->setTracks(std::move(queueTracks));
        emit readyChanged();
        emit playbackStateChanged();
    });
}

QString AppController::playbackState() const {
    switch (facade_.playbackState()) {
    case domain::PlaybackState::Idle: return QStringLiteral("Idle");
    case domain::PlaybackState::Loading: return QStringLiteral("Loading");
    case domain::PlaybackState::Playing: return QStringLiteral("Playing");
    case domain::PlaybackState::Paused: return QStringLiteral("Paused");
    case domain::PlaybackState::Stopped: return QStringLiteral("Stopped");
    case domain::PlaybackState::Buffering: return QStringLiteral("Buffering");
    case domain::PlaybackState::Error: return QStringLiteral("Error");
    }
    return QStringLiteral("Error");
}

void AppController::initialize() { facade_.initializeMock(); }
void AppController::shutdown() {}

LibraryController::LibraryController(application::ILocalLibraryScanner& scanner,
                                     application::ITrackRepository& repository,
                                     application::ILibraryFolderRepository* folderRepository,
                                     const QString& databasePath,
                                     QObject* parent)
    : QObject(parent), scanner_(scanner), repository_(repository),
      folderRepository_(folderRepository),
      writer_(std::make_unique<infrastructure::library::LibraryScanWriter>()), databasePath_(databasePath) {
    // Scan batches are persisted on the writer thread (fooyin scan-writer
    // pattern); this controller only forwards batches and counts results, so
    // scanning keeps the GUI thread responsive.
    connect(writer_.get(), &infrastructure::library::LibraryScanWriter::committed,
            this, &LibraryController::handleCommitted);
    connect(writer_.get(), &infrastructure::library::LibraryScanWriter::commitFailed,
            this, &LibraryController::handleCommitFailed);
    connect(writer_.get(), &infrastructure::library::LibraryScanWriter::drained,
            this, &LibraryController::handleDrained);

    writer_->setAcceptedGeneration(1);
    refreshTotalCount();
    if (folderRepository_) refreshRoots();
    directoryWatcher_.setRoots(roots_);
    connect(&directoryWatcher_, &infrastructure::library::LibraryDirectoryWatcher::directoryDirty,
            this, [this](const QString& directory) { pendingDirectories_.remove(directory); });
    connect(this, &LibraryController::rootsChanged, this, [this] {
        pendingDirectories_.clear();
        directoryWatcher_.setRoots(roots_);
    });
    connect(&directoryWatcher_, &infrastructure::library::LibraryDirectoryWatcher::directoriesReady,
            this, [this](const QStringList& directories) {
        for (const auto& directory : directories) pendingDirectories_.insert(directory);
        scanPendingDirectories();
    });
    connect(&directoryWatcher_, &infrastructure::library::LibraryDirectoryWatcher::watchFailed,
            this, [this](const QStringList& paths) {
        setLastError(QStringLiteral("无法监听目录或文件：") + paths.join(QStringLiteral("、")));
    });
    connect(this, &LibraryController::scanningChanged, this, [this] {
        if (!scanning_) QTimer::singleShot(0, this, &LibraryController::scanPendingDirectories);
    });
}

LibraryController::~LibraryController() {
    directoryWatcher_.setEnabled(false);
    ++generation_;
    const auto activeScanId = activeScanId_;
    activeScanId_.reset();
    scanning_ = false;
    if (activeScanId) scanner_.cancel(*activeScanId);
    // writer_ (unique_ptr) is destroyed after this body and quits its thread
    // after draining the queued commits.
}

void LibraryController::scan(const QStringList& roots) {
    cancelActiveScan();
    automaticScan_ = false;
    beginScan(roots, true);
}

void LibraryController::setAutoWatchEnabled(bool enabled) {
    if (autoWatchEnabled_ == enabled) return;
    autoWatchEnabled_ = enabled;
    directoryWatcher_.setEnabled(enabled && !maintenance_);
    if (!enabled) {
        pendingDirectories_.clear();
        if (automaticScan_) cancel();
    }
}

void LibraryController::notifyFileCompleted(const QString& path) {
    directoryWatcher_.fileCompleted(path);
}

void LibraryController::scanPendingDirectories() {
    if (!autoWatchEnabled_ || maintenance_ || scanning_ || pendingDirectories_.isEmpty()) return;
    const auto directories = pendingDirectories_.values();
    pendingDirectories_.clear();
    beginScan(directories, false);
    automaticScan_ = scanning_;
}

void LibraryController::beginScan(const QStringList& roots, bool recursive) {
    if(maintenance_) { setLastError(tr("资料库维护正在进行，请稍后扫描。")); return; }

    const auto generation = ++generation_;
    activeScanRoots_=roots;activeScanRecursive_=recursive;
    finishPending_=false;
    pendingOutcome_={};
    activeScanId_.reset();
    if (importedCount_ != 0) {
        importedCount_ = 0;
        emit importedCountChanged();
    }
    setLastError({});
    scanning_ = true;
    emit scanningChanged();

    if (!writerStarted_) {
        writerStarted_ = true;
        QMetaObject::invokeMethod(writer_.get(),
                                  [writer = writer_.get(), path = databasePath_] { writer->initialize(path); },
                                  Qt::QueuedConnection);
    }

    application::ScanRequest request;
    request.recursive = recursive;
    request.roots.reserve(static_cast<std::size_t>(roots.size()));
    for (const auto& root : roots) {
        if (!root.isEmpty()) request.roots.emplace_back(root.toStdWString());
    }
    QPointer<LibraryController> guard(this);
    application::ScanCallbacks callbacks;
    callbacks.onBatch = [guard, generation](std::vector<domain::Track> batch) mutable {
        if (guard) guard->handleBatch(generation, std::move(batch));
    };
    callbacks.onFinished = [guard, generation](application::ScanOutcome outcome) mutable {
        if (guard) guard->handleFinished(generation, std::move(outcome));
    };

    try {
        request.knownFiles = repository_.localFiles();
        const auto scanId = scanner_.start(request, std::move(callbacks));
        if (generation == generation_ && scanning_) {
            activeScanId_ = scanId;
        } else {
            scanner_.cancel(scanId);
        }
    } catch (const std::exception& error) {
        finish(generation, {application::ScanStatus::Failed, error.what()});
    } catch (...) {
        finish(generation, {application::ScanStatus::Failed, "library.scan-start-failed"});
    }
}

bool LibraryController::addRoot(const QString& path) {
    if(maintenance_)return false;
    if (!folderRepository_) return false;
    try {
        const QFileInfo candidateInfo(path);
        const QString candidate = QDir(candidateInfo.absoluteFilePath()).canonicalPath();
        if (candidate.isEmpty()) return false;
        const auto isWithin = [](const QString& directory, const QString& maybeChild) {
            if (directory == maybeChild) return true;
            const QString relative = QDir(directory).relativeFilePath(maybeChild);
            return !relative.isEmpty() && !relative.startsWith(QStringLiteral("../"));
        };
        for (const QString& root : roots_) {
            if (isWithin(root, candidate) || isWithin(candidate, root)) return false;
        }
        if (!folderRepository_->add(std::filesystem::path(path.toStdWString()))) return false;
        refreshRoots();
        scan(roots_);
        return true;
    } catch (const std::exception&) {
        setLastError(QStringLiteral("library.folder-add-failed"));
        return false;
    }
}

bool LibraryController::removeRoot(const QString& path) {
    if(maintenance_)return false;
    if (!folderRepository_) return false;
    try {
        const auto candidate = std::filesystem::path(path.toStdWString());
        const auto storedRoots = folderRepository_->roots();
        const auto stored = std::find_if(
            storedRoots.begin(), storedRoots.end(), [&](const application::LibraryFolder& root) {
                return QString::compare(QString::fromStdWString(root.path.wstring()), path,
                                        Qt::CaseInsensitive) == 0;
            });
        if (stored == storedRoots.end()) return false;

        const auto generation = ++generation_;
        writer_->setAcceptedGeneration(generation);
        if (activeScanId_) {
            scanner_.cancel(*activeScanId_);
            activeScanId_.reset();
        }
        if (!folderRepository_->remove(stored->id, candidate)) return false;
        refreshRoots();
        refreshTotalCount();
        pendingOutcome_ = {};
        finishPending_ = false;
        if (scanning_) {
            scanning_ = false;
            emit scanningChanged();
        } else {
            emit libraryContentChanged();
        }
        return true;
    } catch (const std::exception&) {
        setLastError(QStringLiteral("library.folder-remove-failed"));
        return false;
    }
}

void LibraryController::cancel() {
    pendingDirectories_.clear();
    directoryWatcher_.clearPending();
    automaticScan_ = false;
    cancelActiveScan();
}

void LibraryController::cancelActiveScan() {
    if (!scanning_) return;
    const auto generation = generation_;
    writer_->cancelReconciliation(generation);
    const auto activeScanId = activeScanId_;
    finish(generation, {application::ScanStatus::Cancelled, {}});
    if (activeScanId) scanner_.cancel(*activeScanId);
}

void LibraryController::handleBatch(std::uint64_t generation, std::vector<domain::Track> batch) {
    if (generation != generation_ || !scanning_ || batch.empty()) return;

    // Forward the batch to the writer thread; the queued invocation keeps
    // per-scan ordering, so a later drain implies every commit is applied.
    auto payload = std::make_shared<std::vector<domain::Track>>(std::move(batch));
    ++pendingCommits_;
    QMetaObject::invokeMethod(writer_.get(),
                              [writer = writer_.get(), generation, payload] { writer->commit(generation, payload); },
                              Qt::QueuedConnection);
}

void LibraryController::handleCommitted(std::uint64_t generation, int count) {
    --pendingCommits_;
    if (generation != generation_) return;
    importedCount_ += static_cast<quint64>(count);
    emit importedCountChanged();
    maybeApplyFinish();
}

void LibraryController::handleCommitFailed(std::uint64_t generation, const QString& reason) {
    --pendingCommits_;
    if (generation != generation_) return;
    if (const auto activeScanId = activeScanId_; activeScanId) scanner_.cancel(*activeScanId);
    finish(generation, {application::ScanStatus::Failed, reason.toStdString()});
}

void LibraryController::handleDrained() {
    maybeApplyFinish();
}

void LibraryController::handleFinished(std::uint64_t generation, application::ScanOutcome outcome) {
    if(generation == generation_ && scanning_ && !databasePath_.isEmpty()
       && !finishPending_ && outcome.status == application::ScanStatus::Completed) {
        ++pendingCommits_;
        QMetaObject::invokeMethod(writer_.get(), [writer=writer_.get(),generation,roots=activeScanRoots_,recursive=activeScanRecursive_] {
            writer->reconcile(generation,roots,recursive);
        },Qt::QueuedConnection);
    }
    finish(generation, std::move(outcome));
}

void LibraryController::finish(std::uint64_t generation, application::ScanOutcome outcome) {
    if (generation != generation_ || !scanning_) return;
    if (outcome.status == application::ScanStatus::Failed) {
        setLastError(outcome.error.empty() ? QStringLiteral("library.scan-failed")
                                           : QString::fromStdString(outcome.error));
    }
    // Keep scanning_ true until the writer drained every queued commit so the
    // post-scan model refresh cannot miss the final batches.
    if (pendingCommits_ > 0) {
        finishPending_ = true;
        if (pendingOutcome_.status != application::ScanStatus::Failed) pendingOutcome_ = outcome;
        QMetaObject::invokeMethod(writer_.get(), [writer = writer_.get()] { writer->drain(); }, Qt::QueuedConnection);
        return;
    }
    applyFinish(generation, outcome);
}

void LibraryController::maybeApplyFinish() {
    if (!finishPending_ || pendingCommits_ > 0) return;
    finishPending_ = false;
    applyFinish(generation_, pendingOutcome_);
}

void LibraryController::applyFinish(std::uint64_t generation, const application::ScanOutcome& outcome) {
    if (generation != generation_ || !scanning_) return;
    activeScanId_.reset();
    if (outcome.status == application::ScanStatus::Failed) {
        setLastError(outcome.error.empty() ? QStringLiteral("library.scan-failed")
                                           : QString::fromStdString(outcome.error));
    }
    scanning_ = false;
    refreshTotalCount();
    emit scanningChanged();
}

void LibraryController::setLastError(QString error) {
    if (lastError_ == error) return;
    lastError_ = std::move(error);
    emit lastErrorChanged();
}

class PlayerController::Impl final {
public:
    explicit Impl(std::unique_ptr<application::IAudioPlayer> ownedPlayer)
        : playerOwner(std::move(ownedPlayer)), player(requirePlayer(playerOwner)),
          backend(dynamic_cast<application::IPlaybackBackend*>(playerOwner.get())),
          devices(dynamic_cast<application::IAudioDeviceService*>(playerOwner.get())),
          playback(player) {}

    static application::IAudioPlayer& requirePlayer(
        const std::unique_ptr<application::IAudioPlayer>& candidate) {
        if (!candidate) throw std::invalid_argument("PlayerController requires an audio player");
        return *candidate;
    }

    std::unique_ptr<application::IAudioPlayer> playerOwner;
    application::IAudioPlayer& player;
    application::IPlaybackBackend* backend;
    application::IAudioDeviceService* devices;
    application::PlaybackService playback{player};
};

namespace {

std::unique_ptr<application::IAudioPlayer> makeDefaultAudioPlayer() {
#if defined(LISTENFREE_HAS_MPV)
    auto mpv = std::make_unique<media::MpvAudioPlayer>();
    if (mpv->available()) return mpv;
#endif
    return std::make_unique<media::QtAudioPlayer>();
}

QString playbackStateName(domain::PlaybackState state) {
    switch (state) {
    case domain::PlaybackState::Idle: return QStringLiteral("Idle");
    case domain::PlaybackState::Loading: return QStringLiteral("Loading");
    case domain::PlaybackState::Playing: return QStringLiteral("Playing");
    case domain::PlaybackState::Paused: return QStringLiteral("Paused");
    case domain::PlaybackState::Stopped: return QStringLiteral("Stopped");
    case domain::PlaybackState::Buffering: return QStringLiteral("Buffering");
    case domain::PlaybackState::Error: return QStringLiteral("Error");
    }
    return QStringLiteral("Error");
}

} // namespace

PlayerController::PlayerController(QObject* parent)
    : PlayerController(makeDefaultAudioPlayer(), parent) {}

PlayerController::PlayerController(std::unique_ptr<application::IAudioPlayer> player, QObject* parent)
    : QObject(parent), queueModel_(std::make_unique<QueueModel>()),
      impl_(std::make_unique<Impl>(std::move(player))) {
    application::PlaybackServiceEvents events;
    events.onStateChanged = [this] { emit stateChanged(); };
    events.onPositionChanged = [this] { emit positionChanged(); };
    events.onDurationChanged = [this] { emit durationChanged(); };
    events.onSeekableChanged = [this] { emit seekableChanged(); };
    events.onVolumeChanged = [this] { emit volumeChanged(); };
    events.onMutedChanged = [this] { emit mutedChanged(); };
    events.onErrorChanged = [this] { emit errorChanged(); };
    events.onAudioFormatChanged = [this] { emit audioFormatChanged(); };
    events.onQueueChanged = [this] { syncQueueModel(); };
    events.onCurrentItemChanged = [this] { emit currentTrackChanged(); };
    events.onLyricsChanged = [this] { emit lyricsChanged(); };
    events.onCurrentLyricChanged = [this] { emit currentLyricChanged(); };
    impl_->playback.setEvents(std::move(events));

    application::PlaybackBackendEvents backendEvents;
    backendEvents.onCapabilitiesChanged = [this](std::uint32_t) { emit capabilitiesChanged(); };
    if (impl_->backend) impl_->backend->setBackendEvents(std::move(backendEvents));
    application::AudioDeviceEvents deviceEvents;
    deviceEvents.onDevicesChanged = [this] { emit devicesChanged(); };
    deviceEvents.onSelectedDeviceChanged = [this](std::string) { emit devicesChanged(); };
    if (impl_->devices) impl_->devices->setDeviceEvents(std::move(deviceEvents));
}

PlayerController::~PlayerController() {
    if (impl_->backend) impl_->backend->setBackendEvents({});
    if (impl_->devices) impl_->devices->setDeviceEvents({});
}

QString PlayerController::state() const { return playbackStateName(impl_->player.state()); }
qint64 PlayerController::position() const noexcept { return impl_->player.position().count(); }
qint64 PlayerController::duration() const noexcept { return impl_->player.duration().count(); }
bool PlayerController::seekable() const noexcept { return impl_->player.seekable(); }
float PlayerController::volume() const noexcept { return impl_->player.volume(); }
bool PlayerController::muted() const noexcept { return impl_->player.muted(); }
quint32 PlayerController::capabilities() const noexcept {
    return impl_->backend ? impl_->backend->capabilities() : 0U;
}
QStringList PlayerController::deviceIds() const {
    QStringList result;
    if (!impl_->devices) return result;
    for (const auto& device : impl_->devices->devices()) {
        result.push_back(QString::fromStdString(device.id));
    }
    return result;
}

QString PlayerController::errorCode() const {
    const auto error = impl_->player.lastError();
    if (!error) return {};
    switch (error->code) {
    case domain::PlaybackErrorCode::InvalidTransition: return QStringLiteral("invalid-transition");
    case domain::PlaybackErrorCode::OpenFailed: return QStringLiteral("open-failed");
    case domain::PlaybackErrorCode::Network: return QStringLiteral("network");
    case domain::PlaybackErrorCode::Unsupported: return QStringLiteral("unsupported");
    case domain::PlaybackErrorCode::Internal: return QStringLiteral("internal");
    }
    return QStringLiteral("internal");
}

QString PlayerController::errorMessage() const {
    const auto error = impl_->player.lastError();
    return error ? QString::fromStdString(error->message) : QString{};
}

bool PlayerController::errorRetryable() const {
    const auto error = impl_->player.lastError();
    return error && error->retryable;
}

QString PlayerController::audioCodec() const {
    const auto format = impl_->player.audioFormat();
    return format ? QString::fromStdString(format->codec) : QString{};
}

int PlayerController::sampleRate() const {
    const auto format = impl_->player.audioFormat();
    return format ? format->sampleRate : 0;
}

int PlayerController::channelCount() const {
    const auto format = impl_->player.audioFormat();
    return format ? format->channels : 0;
}

QString PlayerController::currentTrackId() const {
    const auto* item = impl_->playback.currentItem();
    return item ? QString::fromStdString(item->track.id.value()) : QString{};
}

int PlayerController::currentLyricIndex() const noexcept {
    const auto index = impl_->playback.currentLyricIndex();
    return index ? static_cast<int>(*index) : -1;
}

QString PlayerController::currentLyricText() const {
    const auto line = impl_->playback.currentLyricLine();
    return line ? QString::fromStdString(line->text) : QString{};
}

int PlayerController::lyricLineCount() const noexcept {
    return static_cast<int>(impl_->playback.lyrics().size());
}

void PlayerController::openLocal(const QString& path) {
    if (path.isEmpty()) {
        setQueue({});
        return;
    }
    domain::PlaybackItem item;
    item.track.localPath = path.toStdString();
    setQueue({item});
    impl_->player.open(item);
}

void PlayerController::openUrl(const QUrl& url) {
    if (url.isEmpty()) {
        setQueue({});
        return;
    }
    domain::PlaybackItem item;
    item.resolvedUrl = url.toString().toStdString();
    setQueue({item});
    impl_->player.open(item);
}

void PlayerController::play() {
    if (impl_->player.state() == domain::PlaybackState::Idle && impl_->playback.currentItem()) {
        impl_->playback.playCurrent();
    } else {
        impl_->player.play();
    }
}

QVariantMap PlayerController::currentTrack() const {
    const auto* item = impl_->playback.currentItem();
    if (item == nullptr) return {};
    const auto& track = item->track;
    QVariantMap result;
    result.insert(QStringLiteral("trackId"), QString::fromStdString(track.id.value()));
    result.insert(QStringLiteral("title"), QString::fromStdString(track.title));
    QStringList artists;
    artists.reserve(static_cast<qsizetype>(track.artists.size()));
    for (const auto& artist : track.artists) artists.push_back(QString::fromStdString(artist.name));
    result.insert(QStringLiteral("artist"), artists.join(QStringLiteral(" / ")));
    result.insert(QStringLiteral("album"), track.album ? QString::fromStdString(track.album->title) : QString{});
    result.insert(QStringLiteral("durationMs"), static_cast<qint64>(track.duration.count()));
    result.insert(QStringLiteral("artwork"), track.album && track.album->artworkUrl
                                                  ? QString::fromStdString(*track.album->artworkUrl)
                                                  : QString{});
    result.insert(QStringLiteral("localPath"), track.localPath ? QString::fromStdString(*track.localPath) : QString{});
    result.insert(QStringLiteral("remoteUrl"), track.remoteUrl ? QString::fromStdString(*track.remoteUrl) : QString{});
    return result;
}

void LibraryController::scanDefault() {
    if(maintenance_)return;
    if(!databasePath_.isEmpty()) {
        infrastructure::database::Database database;
        if(!database.openExisting(databasePath_) || !database.restoreExcludedFiles(roots_)) {
            setLastError(QStringLiteral("无法重新导入已移除的歌曲"));return;
        }
    }
    scan(roots_);
}

void LibraryController::refreshRoots() {
    if (!folderRepository_) return;
    try {
        const auto stored = folderRepository_->roots();
        QStringList roots;
        roots.reserve(static_cast<std::size_t>(stored.size()));
        std::transform(stored.begin(), stored.end(), std::back_inserter(roots),
                       [](const application::LibraryFolder& folder) {
                           return QString::fromStdWString(folder.path.wstring());
                       });
        roots_ = std::move(roots);
    } catch (const std::exception&) {
        roots_.clear();
    }
    emit rootsChanged();
}

void LibraryController::refreshTotalCount() {
    quint64 count{0};
    try {
        count = static_cast<quint64>(repository_.count());
    } catch (const std::exception&) {
        count = 0;
    }
    if (totalCount_ == count) return;
    totalCount_ = count;
    emit totalCountChanged();
}
void PlayerController::pause() { impl_->player.pause(); }
void PlayerController::next() { impl_->playback.next(); }
void PlayerController::previous() {
    const auto& items = impl_->playback.queue().items();
    if (items.empty()) return;
    const auto current = impl_->playback.queue().currentIndex();
    const auto previous = current == 0 ? items.size() - 1 : current - 1;
    impl_->playback.select(previous, true);
}
bool PlayerController::selectQueue(int index, bool playImmediately) {
    return index >= 0 && impl_->playback.select(static_cast<std::size_t>(index), playImmediately);
}
bool PlayerController::removeFromQueue(int index) {
    return index >= 0 && impl_->playback.remove(static_cast<std::size_t>(index));
}
bool PlayerController::moveQueue(int from, int to) {
    return from >= 0 && to >= 0
           && impl_->playback.move(static_cast<std::size_t>(from), static_cast<std::size_t>(to));
}
void PlayerController::stop() { impl_->player.stop(); }
void PlayerController::seek(qint64 position) {
    impl_->player.seek(std::chrono::milliseconds(position));
}
void PlayerController::setVolume(float volume) { impl_->player.setVolume(volume); }
void PlayerController::setMuted(bool muted) { impl_->player.setMuted(muted); }
bool PlayerController::selectDevice(const QString& id) {
    return impl_->devices && impl_->devices->select(id.toStdString());
}

void PlayerController::setQueue(std::vector<domain::PlaybackItem> items, std::size_t currentIndex) {
    impl_->playback.setQueue(std::move(items), currentIndex);
}

void PlayerController::setLyrics(std::vector<domain::LyricLine> lyrics) {
    impl_->playback.setLyrics(std::move(lyrics));
}

void PlayerController::syncQueueModel() {
    std::vector<domain::Track> tracks;
    tracks.reserve(impl_->playback.queue().items().size());
    for (const auto& item : impl_->playback.queue().items()) tracks.push_back(item.track);
    queueModel_->setTracks(std::move(tracks));
    queueModel_->setCurrentIndex(impl_->playback.queue().empty()
                                     ? -1
                                     : static_cast<int>(impl_->playback.queue().currentIndex()));
}

QString PlaylistController::create(const QString& title) {
    const QString id = QStringLiteral("playlist-%1").arg(playlists_.size() + 1);
    QVariantMap item;
    item.insert(QStringLiteral("id"), id);
    item.insert(QStringLiteral("title"), title.trimmed().isEmpty() ? QStringLiteral("新建歌单 1234") : title.trimmed());
    item.insert(QStringLiteral("kind"), QStringLiteral("Local"));
    item.insert(QStringLiteral("entryCount"), 0);
    playlists_.push_back(item);
    emit changed();
    return id;
}

bool PlaylistController::rename(const QString& id, const QString& title) {
    if (id.isEmpty() || title.trimmed().isEmpty()) {
        emit errorOccurred(QStringLiteral("playlist.rename.invalid"));
        return false;
    }
    for (auto& value : playlists_) {
        auto item = value.toMap();
        if (item.value(QStringLiteral("id")).toString() != id) continue;
        item.insert(QStringLiteral("title"), title.trimmed());
        value = item;
        emit changed();
        return true;
    }
    emit errorOccurred(QStringLiteral("playlist.rename.not-found"));
    return false;
}

bool PlaylistController::remove(const QString& id) {
    if (id.isEmpty()) return false;
    for (qsizetype i = 0; i < playlists_.size(); ++i) {
        if (playlists_.at(i).toMap().value(QStringLiteral("id")).toString() != id) continue;
        playlists_.removeAt(i);
        emit changed();
        return true;
    }
    return false;
}

void OnlineController::search(const QString& query) {
    if (busy_) return;
    busy_ = true;
    emit busyChanged();
    QTimer::singleShot(0, this, [this, query] {
        busy_ = false;
        emit busyChanged();
        lastQuery_ = query.trimmed();
        searchResults_.clear();
        if (!lastQuery_.isEmpty()) {
            const QStringList suffixes{QStringLiteral(" (Live)"), QStringLiteral(" (Acoustic)"), QStringLiteral(" (Remix)")};
            for (int i = 0; i < suffixes.size(); ++i) {
                QVariantMap item;
                item.insert(QStringLiteral("title"), lastQuery_ + suffixes.at(i));
                item.insert(QStringLiteral("artist"), i == 0 ? QStringLiteral("ListenFree Online") : QStringLiteral("精选音源"));
                item.insert(QStringLiteral("album"), QStringLiteral("搜索结果"));
                item.insert(QStringLiteral("duration"), QStringLiteral("03:%1").arg(20 + i * 7, 2, 10, QLatin1Char('0')));
                item.insert(QStringLiteral("source"), QStringLiteral("OnlineProvider"));
                searchResults_.push_back(item);
            }
        }
        emit searchResultsChanged();
        emit searchFinished(searchResults_);
    });
}

void OnlineController::refreshPlaylist(const QString& id) {
    if (busy_) return;
    busy_ = true;
    emit busyChanged();
    QTimer::singleShot(0, this, [this, id] {
        busy_ = false;
        emit busyChanged();
        emit playlistRefreshFinished(id, !id.isEmpty());
    });
}

QVariant SettingsController::value(const QString& key, const QVariant& fallback) const {
    if (repository_) {
        try {
            const auto stored = repository_->get(key.toStdString());
            if (stored) {
                QVariant result = QString::fromStdString(*stored);
                if (fallback.isValid()) result.convert(fallback.metaType());
                return result;
            }
        } catch (const std::exception&) {
        }
    }
    return values_.value(key, fallback);
}

void LibraryController::reloadRoots() {
    refreshRoots();
}

bool LibraryController::beginMaintenance() {
    if(scanning_ || maintenance_ || pendingCommits_>0)return false;
    maintenance_=true;directoryWatcher_.setEnabled(false);return true;
}
void LibraryController::endMaintenance() {
    maintenance_=false;directoryWatcher_.setEnabled(autoWatchEnabled_);refreshTotalCount();
}

bool SettingsController::reloadValues(const QVariantMap& values) {
    applyingBatch_=true;batchRejected_=false;
    for (auto it=values.begin();it!=values.end();++it) values_.insert(it.key(),it.value());
    ++revision_; emit settingsChanged();
    for (auto it=values.begin();it!=values.end();++it) emit valueChanged(it.key(),it.value());
    emit valuesReloaded(values);applyingBatch_=false;return !batchRejected_;
}
void SettingsController::forgetScrollPositions() {
    for(auto it=values_.begin();it!=values_.end();)if(it.key().startsWith("scroll."))it=values_.erase(it);else ++it;
    ++revision_;emit settingsChanged();
}

void SettingsController::setValue(const QString& key, const QVariant& value) {
    if (key.isEmpty() || values_.value(key) == value) return;
    if (repository_) {
        try {
            if (!repository_->set(key.toStdString(), value.toString().toStdString())) return;
        } catch (const std::exception&) {
            return;
        }
    }
    values_.insert(key, value);
    ++revision_;
    emit settingsChanged();
    emit valueChanged(key, value);
}

SettingsController::SettingsController(QObject* parent) : QObject(parent) {}

SettingsController::SettingsController(application::ISettingsRepository& repository, QObject* parent)
    : QObject(parent), repository_(&repository) {}

SettingsController::~SettingsController() = default;

QString SettingsController::localFilePath(const QUrl& url) const {
    return url.isLocalFile() ? QDir::toNativeSeparators(url.toLocalFile()) : QString{};
}

QVariantMap SettingsController::resolveBackground(const QUrl& url, bool wallpaperProject) const {
    const auto fail = [](const QString& error) { return QVariantMap{{"error", error}}; };
    if (url.isEmpty()) return {};
    if (!url.isLocalFile()) return fail(tr("请选择本地文件。"));
    QFileInfo file(url.toLocalFile());
    if (!file.isFile() || !file.isReadable()) return fail(tr("背景文件不存在或无法读取，请重新选择。"));
    QString kind = "Video";
    if (wallpaperProject) {
        QFile project(file.absoluteFilePath());
        if (file.size() > 1024 * 1024 || !project.open(QIODevice::ReadOnly))
            return fail(tr("无法读取 Wallpaper 项目，或项目配置超过 1 MiB。"));
        QJsonParseError error;
        const auto document = QJsonDocument::fromJson(project.read(1024 * 1024 + 1), &error);
        if (error.error != QJsonParseError::NoError || !document.isObject())
            return fail(tr("项目配置无效，请选择 Wallpaper Engine 的 project.json。"));
        const auto object = document.object();
        const auto type = object.value("type").toString().toLower();
        if (type != "video" && type != "image")
            return fail(tr("此项目需要 Wallpaper Engine 渲染；当前仅支持本地视频和图片项目，暂不支持场景、网页或应用壁纸。"));
        kind = type == "image" ? "Image" : "Video";
        const auto relative = object.value("file").toString();
        if (relative.isEmpty() || relative.contains(QChar::Null) || QDir::isAbsolutePath(relative) || !QUrl(relative).scheme().isEmpty())
            return fail(tr("项目未提供有效的本地媒体路径。"));
        const auto directory = file.absoluteDir();
        file = QFileInfo(directory.filePath(relative));
        const auto canonical = file.canonicalFilePath();
        if (!file.isFile() || !file.isReadable() || !canonical.startsWith(directory.canonicalPath() + '/', Qt::CaseInsensitive))
            return fail(tr("找不到项目内的媒体文件，请保留完整的壁纸目录。"));
    }
    const auto suffix = file.suffix().toLower();
    const QStringList extensions = kind == "Image"
        ? QStringList{"jpg", "jpeg", "png", "webp", "bmp"}
        : QStringList{"mp4", "m4v", "mov", "mkv", "webm", "avi", "wmv"};
    if (!extensions.contains(suffix)) return fail(tr("此背景文件格式暂不支持，请选择常见图片或视频文件。"));
    return {{"kind", kind}, {"source", QUrl::fromLocalFile(file.absoluteFilePath())}, {"error", QString{}}};
}

} // namespace listenfree::qmlbridge
