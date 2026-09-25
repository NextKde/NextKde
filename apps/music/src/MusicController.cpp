#include "MusicController.h"

#include "AudioCache.h"
#include "LxSourceService.h"
#include "LyricsService.h"
#include "MetadataScanner.h"
#include "MprisService.h"

#include <QCollator>
#include <QCoreApplication>
#include <QDateTime>
#include <QDBusObjectPath>
#include <QDir>
#include <QFileInfo>
#include <QMap>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRandomGenerator>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>
#include <QtConcurrentRun>

#include <algorithm>
#include <iterator>
#include <utility>

namespace {

const QChar albumSeparator(0x1f);

const QStringList &supportedOnlineQualities()
{
    static const QStringList qualities{
        QStringLiteral("128k"),
        QStringLiteral("320k"),
        QStringLiteral("flac"),
        QStringLiteral("flac24bit"),
    };
    return qualities;
}

QString fallbackName(const QString &value, const QString &fallback)
{
    return value.trimmed().isEmpty() ? fallback : value.trimmed();
}

QString trackArtist(const TrackRecord &track)
{
    return track.artist.isEmpty() ? track.albumArtist : track.artist;
}

QString albumFilter(const TrackRecord &track)
{
    return track.album + albumSeparator + track.albumArtist;
}

} // namespace

MusicController::MusicController(QObject *parent)
    : QObject(parent)
    , m_engine(this)
    , m_transcoder(this)
    , m_libraryModel(this)
    , m_queueModel(this)
    , m_playlistTracksModel(this)
    , m_onlineModel(this)
    , m_onlineProvider(this)
    , m_scanWatcher(this)
{
    m_queueModel.setMode(QStringLiteral("queue"));
    m_playlistTracksModel.setMode(QStringLiteral("queue"));
    m_onlineModel.setMode(QStringLiteral("queue"));
    connect(&m_scanWatcher, &QFutureWatcher<ScanResult>::finished,
            this, &MusicController::scanFinished);
    connect(&m_engine, &PlaybackEngine::stateChanged,
            this, &MusicController::playbackStateChanged);
    connect(this, &MusicController::playbackStateChanged, this, &MusicController::playbackStatusChanged);
    connect(&m_engine, &PlaybackEngine::bufferingChanged, this, &MusicController::playbackStatusChanged);
    connect(&m_engine, &PlaybackEngine::downloadCompleted, this, [this](const QString &path) {
        if (m_audioCache)
            m_audioCache->storeCompleted(m_engineCacheKey, path);
    });
    // Separate source, whole-track, and skip deadlines bound every recovery path.
    m_attemptTimeout.setParent(this);
    m_attemptTimeout.setObjectName(QStringLiteral("sourceAttemptTimeout"));
    m_trackTimeout.setParent(this);
    m_trackTimeout.setObjectName(QStringLiteral("trackPreparationTimeout"));
    m_skipTimer.setParent(this);
    m_skipTimer.setObjectName(QStringLiteral("failedTrackSkipDelay"));
    m_attemptTimeout.setSingleShot(true);
    m_attemptTimeout.setInterval(12000);
    m_trackTimeout.setSingleShot(true);
    m_trackTimeout.setInterval(45000);
    m_skipTimer.setSingleShot(true);
    m_skipTimer.setInterval(3000);
    connect(&m_attemptTimeout, &QTimer::timeout, this, [this] {
        schedulePlaybackFailure(tr("音源响应或缓冲超时"));
    });
    connect(&m_trackTimeout, &QTimer::timeout, this, [this] {
        finishFailedTrack(tr("本曲重试已超时"));
    });
    connect(&m_skipTimer, &QTimer::timeout, this, &MusicController::advanceAfterFailure);
    connect(&m_engine, &PlaybackEngine::stateChanged, this, [this] {
        if (m_engine.state() == QLatin1String("Playing")) {
            m_attemptTimeout.stop();
            m_trackTimeout.stop();
            m_recoveryStatus.clear();
            setError({});
            emit playbackStatusChanged();
        } else if (m_engine.state() == QLatin1String("Error")) {
            schedulePlaybackFailure(m_engine.errorMessage());
        }
    });
    m_savePositionTimer.setInterval(5000);
    connect(&m_savePositionTimer, &QTimer::timeout,
            this, &MusicController::persistPlaybackPosition);
    connect(&m_engine, &PlaybackEngine::stateChanged, this, [this] {
        if (m_engine.state() == QLatin1String("Playing"))
            m_savePositionTimer.start();
        else {
            m_savePositionTimer.stop();
            persistPlaybackPosition();
        }
    });
    connect(qApp, &QCoreApplication::aboutToQuit,
            this, &MusicController::persistPlaybackPosition);
    connect(&m_engine, &PlaybackEngine::positionChanged,
            this, &MusicController::positionChanged);
    connect(&m_engine, &PlaybackEngine::positionChanged, this, [this] {
        if (m_engine.state() == QLatin1String("Playing") && m_engine.positionMs() > 3000)
            m_failedTracks.clear();
        if (m_lyricsService)
            m_lyricsService->setPositionMs(m_engine.positionMs());
    });
    connect(&m_engine, &PlaybackEngine::durationChanged,
            this, &MusicController::durationChanged);
    connect(&m_engine, &PlaybackEngine::seekableChanged,
            this, &MusicController::seekableChanged);
    connect(&m_engine, &PlaybackEngine::volumeChanged,
            this, &MusicController::volumeChanged);
    connect(&m_engine, &PlaybackEngine::seeked, this, [this](qint64 position) {
        persistPlaybackPosition();
        emit seeked(position);
    });
    connect(&m_engine, &PlaybackEngine::errorMessageChanged, this, [this] {
        if (!m_engine.errorMessage().isEmpty()) {
            if (m_audioCache && !m_pendingCacheKey.isEmpty())
                m_audioCache->remove(m_pendingCacheKey);
            m_usingCachedAudio = false;
            setError(m_engine.errorMessage());
        }
    });
    connect(&m_engine, &PlaybackEngine::endOfStream, this, [this] { m_failedTracks.clear(); advance(true); });

    const auto notifyTranscode = [this] { emit transcodeChanged(); };
    connect(&m_transcoder, &Transcoder::activeChanged, this, notifyTranscode);
    connect(&m_transcoder, &Transcoder::progressChanged, this, notifyTranscode);
    connect(&m_transcoder, &Transcoder::statusChanged, this, notifyTranscode);
    connect(&m_transcoder, &Transcoder::errorMessageChanged, this, notifyTranscode);
    connect(&m_transcoder, &Transcoder::finished, this, [this](const QUrl &output) {
        emit userMessage(tr("Converted audio saved to %1").arg(output.toLocalFile()));
    });

    m_dataPath = qEnvironmentVariable("KOS_MUSIC_DATA_DIR");
    if (m_dataPath.isEmpty()) {
        m_dataPath = QDir(QStandardPaths::writableLocation(
                              QStandardPaths::GenericDataLocation))
                         .filePath(QStringLiteral("kos/music"));
    }
    QString cachePath = qEnvironmentVariable("KOS_MUSIC_CACHE_DIR");
    if (cachePath.isEmpty()) {
        cachePath = QDir(QStandardPaths::writableLocation(
                             QStandardPaths::GenericCacheLocation))
                        .filePath(QStringLiteral("kos/music"));
    }
    m_artworkPath = QDir(cachePath).filePath(QStringLiteral("artwork"));
    // Defer the database open, library read, source-host startup, and MPRIS
    // registration until the event loop is running so QML can render first.
    QTimer::singleShot(0, this, [this] { initialize(); });
}

void MusicController::initialize()
{
    const QString cachePath = QFileInfo(m_artworkPath).absolutePath();
    m_sourceService = std::make_unique<LxSourceService>(m_dataPath, this);
    m_lyricsService = std::make_unique<LyricsService>(
        QDir(cachePath).filePath(QStringLiteral("lyrics")), this);
    m_audioCache = std::make_unique<AudioCache>(
        QDir(cachePath).filePath(QStringLiteral("audio")));
    m_engine.setDownloadDirectory(m_audioCache->downloadDirectory());
    connect(&m_onlineProvider, &OnlineMusicProvider::searchingChanged,
            this, &MusicController::onlineSearchingChanged);
    connect(&m_onlineProvider, &OnlineMusicProvider::errorMessageChanged,
            this, &MusicController::onlineErrorChanged);
    connect(&m_onlineProvider, &OnlineMusicProvider::resultsReady,
            &m_onlineModel, &TrackListModel::setTracks);
    connect(m_sourceService.get(), &LxSourceService::sourcesChanged,
            this, &MusicController::musicSourcesChanged);
    connect(m_sourceService.get(), &LxSourceService::stateChanged,
            this, &MusicController::musicSourceStateChanged);
    connect(m_sourceService.get(), &LxSourceService::stateChanged, this, [this] {
        if (!m_waitingForSource)
            return;
        if (m_sourceService->state() == QLatin1String("ready"))
            resolveWithReadySource();
        else if (m_sourceService->state() == QLatin1String("error"))
            schedulePlaybackFailure(m_sourceService->errorMessage());
    });
    connect(m_sourceService.get(), &LxSourceService::errorMessageChanged,
            this, &MusicController::musicSourceErrorChanged);
    connect(m_sourceService.get(), &LxSourceService::capabilitiesChanged,
            this, [this] {
        const QStringList qualities = onlineQualities();
        if (m_resolvingTrackId < 0 && m_attemptName.isEmpty()
            && !qualities.isEmpty() && !qualities.contains(m_onlineQuality)) {
            const QString fallback = qualities.contains(QStringLiteral("128k"))
                ? QStringLiteral("128k") : qualities.first();
            if (m_onlineQuality != fallback) {
                m_onlineQuality = fallback;
                if (m_ready)
                    m_database.setSetting(QStringLiteral("onlineQuality"), fallback);
                emit onlineQualityChanged();
            }
        }
        emit onlineQualitiesChanged();
    });
    connect(m_sourceService.get(), &LxSourceService::sourceImported,
            this, [this](const QString &name) {
        emit userMessage(tr("Music source %1 was imported").arg(name));
    });
    connect(m_sourceService.get(), &LxSourceService::resolved,
            this, [this](qint64 trackId, const QUrl &url) {
        if (trackId != m_resolvingTrackId || trackId != currentTrackId())
            return;
        loadPreparedTrack(url);
    });
    connect(m_sourceService.get(), &LxSourceService::resolveFailed,
            this, [this](qint64 trackId, const QString &message) {
        if (trackId != m_resolvingTrackId || trackId != currentTrackId())
            return;
        schedulePlaybackFailure(message);
    });
    connect(m_lyricsService.get(), &LyricsService::lyricsChanged,
            this, &MusicController::lyricsChanged);
    connect(m_lyricsService.get(), &LyricsService::currentLineChanged,
            this, &MusicController::currentLyricChanged);
    connect(m_lyricsService.get(), &LyricsService::loadingChanged,
            this, &MusicController::lyricsLoadingChanged);
    connect(m_lyricsService.get(), &LyricsService::errorMessageChanged,
            this, &MusicController::lyricsErrorChanged);
    QString databaseError;
    if (!m_database.open(QDir(m_dataPath).filePath(QStringLiteral("library.sqlite")),
                         &databaseError)) {
        setError(databaseError);
        emit readyChanged();
        return;
    }
    m_ready = true;
    m_lyricsEnabled = m_database.setting(QStringLiteral("lyricsEnabled"), QStringLiteral("true"))
        != QLatin1String("false");
    emit lyricsEnabledChanged();
    const QString storedOnlineQuality =
        m_database.setting(QStringLiteral("onlineQuality"), QStringLiteral("128k"))
            .trimmed().toLower();
    if (supportedOnlineQualities().contains(storedOnlineQuality))
        m_onlineQuality = storedOnlineQuality;
    m_repeatMode = m_database.setting(QStringLiteral("repeat"), QStringLiteral("none"));
    if (m_repeatMode != QLatin1String("track")
        && m_repeatMode != QLatin1String("playlist")) {
        m_repeatMode = QStringLiteral("none");
    }
    m_shuffle = m_database.setting(QStringLiteral("shuffle"), QStringLiteral("false"))
                    == QLatin1String("true");
    bool volumeOk = false;
    const double storedVolume = m_database.setting(QStringLiteral("volume"),
                                                   QStringLiteral("0.8"))
                                    .toDouble(&volumeOk);
    m_engine.setVolume(volumeOk ? storedVolume : 0.8);
    refreshLibrary();
    m_queueIds = m_database.queueTrackIds();
    m_queueIndex = m_database.setting(QStringLiteral("queueIndex"), QStringLiteral("-1"))
                       .toInt();
    refreshQueueModel();
    if (m_queueIndex < 0 || m_queueIndex >= m_queueIds.size())
        m_queueIndex = m_queueIds.isEmpty() ? -1 : 0;
    const QJsonObject playback = QJsonDocument::fromJson(
        m_database.setting(QStringLiteral("playbackPosition")).toUtf8()).object();
    if (playback.value(QStringLiteral("trackId")).toString().toLongLong() == currentTrackId())
        m_resumePositionMs = std::max<qint64>(0,
            playback.value(QStringLiteral("positionMs")).toVariant().toLongLong());
    m_mpris = new MprisService(this, this);
    emit mprisRegisteredChanged();
    emit queueChanged();
    emit currentTrackChanged();
    emit positionChanged();
    emit durationChanged();
    emit playbackStateChanged();
    emit readyChanged();
    rescanLibrary();
}

MusicController::~MusicController()
{
    persistPlaybackPosition();
    disconnect(&m_engine, &PlaybackEngine::stateChanged, this, nullptr);
    disconnect(&m_engine, &PlaybackEngine::positionChanged, this, nullptr);
    m_engine.stop();
}

TrackListModel *MusicController::libraryModel() { return &m_libraryModel; }
TrackListModel *MusicController::queueModel() { return &m_queueModel; }
TrackListModel *MusicController::playlistTracksModel() { return &m_playlistTracksModel; }
TrackListModel *MusicController::onlineModel() { return &m_onlineModel; }
QVariantList MusicController::albums() const { return m_albums; }
QVariantList MusicController::artists() const { return m_artists; }
QVariantList MusicController::playlists() const { return m_playlists; }
QStringList MusicController::libraryFolders() const { return m_libraryFolders; }
bool MusicController::ready() const { return m_ready; }
bool MusicController::scanning() const { return m_scanning; }
QString MusicController::scanStatus() const { return m_scanStatus; }
QStringList MusicController::scanWarnings() const { return m_scanWarnings; }
QString MusicController::errorMessage() const { return m_errorMessage; }
bool MusicController::onlineSearching() const { return m_onlineProvider.searching(); }
QString MusicController::onlineError() const { return m_onlineProvider.errorMessage(); }
QVariantList MusicController::musicSources() const
{
    return m_sourceService ? m_sourceService->sources() : QVariantList{};
}
QString MusicController::activeMusicSourceId() const
{
    return m_sourceService ? m_sourceService->activeSourceId() : QString{};
}
QString MusicController::musicSourceState() const
{
    return m_sourceService ? m_sourceService->state() : QStringLiteral("inactive");
}
QString MusicController::musicSourceError() const
{
    return m_sourceService ? m_sourceService->errorMessage() : QString{};
}
QStringList MusicController::onlineQualities() const { return m_sourceService ? m_sourceService->availableQualities() : QStringList{}; }
QString MusicController::onlineQuality() const { return m_onlineQuality; }
QVariantList MusicController::lyrics() const
{
    return m_lyricsEnabled && m_lyricsService && m_lyricsService->loadedTrackId() == currentTrackId()
        ? m_lyricsService->lines() : QVariantList{};
}
int MusicController::currentLyricIndex() const
{
    return m_lyricsService && m_lyricsService->loadedTrackId() == currentTrackId()
        ? m_lyricsService->currentLineIndex() : -1;
}
QString MusicController::currentLyric() const
{
    const QVariantList lines = lyrics();
    const int index = currentLyricIndex();
    return index >= 0 && index < lines.size()
        ? lines.at(index).toMap().value(QStringLiteral("text")).toString() : QString{};
}
QString MusicController::nextLyric() const
{
    const QVariantList lines = lyrics();
    const int index = currentLyricIndex() + 1;
    return index >= 0 && index < lines.size()
        ? lines.at(index).toMap().value(QStringLiteral("text")).toString() : QString{};
}
bool MusicController::lyricsLoading() const
{
    return m_lyricsService && m_lyricsService->loading();
}
QString MusicController::lyricsError() const
{
    return m_lyricsService ? m_lyricsService->errorMessage() : QString{};
}
bool MusicController::engineAvailable() const { return m_engine.available(); }
QString MusicController::engineBackend() const { return m_engine.backendName(); }
bool MusicController::mprisRegistered() const { return m_mpris && m_mpris->registered(); }
bool MusicController::lyricsEnabled() const { return m_lyricsEnabled; }
void MusicController::setLyricsEnabled(bool enabled)
{
    if (enabled == m_lyricsEnabled || !m_ready)
        return;
    m_lyricsEnabled = enabled;
    m_database.setSetting(QStringLiteral("lyricsEnabled"), enabled ? QStringLiteral("true") : QStringLiteral("false"));
    if (m_lyricsService) {
        m_lyricsService->load(enabled ? findTrack(currentTrackId()).value_or(TrackRecord{}) : TrackRecord{});
        m_lyricsService->setPositionMs(positionMs());
    }
    emit lyricsEnabledChanged();
    emit lyricsChanged();
    emit currentLyricChanged();
}

double MusicController::cacheProgress() const
{
    if (playbackState() == QLatin1String("Error") || playbackState() == QLatin1String("Stopped")
        || m_loadedTrackId != currentTrackId()) return -1;
    return m_usingCachedAudio ? 1 : m_engine.downloadProgress();
}

QString MusicController::playbackStatusText() const
{
    if (!m_recoveryStatus.isEmpty())
        return m_recoveryStatus;
    if (m_resolvingTrackId >= 0)
        return tr("正在获取播放地址…");
    if (playbackState() == QLatin1String("Error"))
        return tr("播放失败，点击重试");
    if (m_engine.state() == QLatin1String("Loading"))
        return m_engine.bufferingPercent() < 100
            ? tr("正在缓冲 %1%…").arg(m_engine.bufferingPercent())
            : tr("正在准备播放…");
    const auto track = findTrack(currentTrackId());
    if (track && track->source != QLatin1String("local")) {
        if (m_usingCachedAudio)
            return tr("已缓存，可离线播放");
        if (m_engine.downloadProgress() >= 1)
            return tr("本曲已缓冲完成");
        if (m_engine.downloadProgress() >= 0)
            return tr("正在缓存 %1%").arg(qRound(m_engine.downloadProgress() * 100));
        if (m_engine.state() == QLatin1String("Playing"))
            return tr("正在在线播放");
    }
    return {};
}
QString MusicController::playbackState() const
{
    if (m_preparationFailed)
        return QStringLiteral("Error");
    if (m_resolvingTrackId >= 0)
        return m_playWhenReady ? QStringLiteral("Loading") : QStringLiteral("Paused");
    if (m_loadedTrackId != currentTrackId() && m_resumePositionMs > 0)
        return QStringLiteral("Paused");
    return m_engine.state();
}
qlonglong MusicController::currentTrackId() const
{
    return m_queueIndex >= 0 && m_queueIndex < m_queueIds.size()
        ? m_queueIds.at(m_queueIndex) : -1;
}
QString MusicController::currentTitle() const
{
    const auto track = findTrack(currentTrackId());
    return track ? track->title : QString{};
}
QString MusicController::currentArtist() const
{
    const auto track = findTrack(currentTrackId());
    return track ? track->artist : QString{};
}
QString MusicController::currentAlbum() const
{
    const auto track = findTrack(currentTrackId());
    return track ? track->album : QString{};
}
QString MusicController::currentArtworkUrl() const
{
    const auto track = findTrack(currentTrackId());
    return track ? track->artworkUrl : QString{};
}
qlonglong MusicController::positionMs() const
{
    return m_loadedTrackId == currentTrackId() && m_loadedTrackId >= 0
        ? m_engine.positionMs() : m_resumePositionMs;
}
qlonglong MusicController::durationMs() const
{
    if (m_loadedTrackId == currentTrackId() && m_engine.durationMs() > 0)
        return m_engine.durationMs();
    const auto track = findTrack(currentTrackId());
    return track ? track->durationMs : 0;
}
bool MusicController::seekable() const
{
    return m_loadedTrackId >= 0 && m_loadedTrackId == currentTrackId() && m_engine.seekable();
}
double MusicController::volume() const { return m_engine.volume(); }
bool MusicController::shuffle() const { return m_shuffle; }
QString MusicController::repeatMode() const { return m_repeatMode; }
QString MusicController::playbackMode() const
{
    if (m_repeatMode == QLatin1String("track"))
        return QStringLiteral("track");
    if (m_shuffle)
        return QStringLiteral("shuffle");
    if (m_repeatMode == QLatin1String("playlist"))
        return QStringLiteral("playlist");
    return QStringLiteral("sequential");
}
QString MusicController::librarySearch() const { return m_librarySearch; }
bool MusicController::canGoNext() const
{
    return !m_queueIds.isEmpty()
        && ((m_shuffle && m_queueIds.size() > 1)
            || m_repeatMode == QLatin1String("playlist")
            || m_queueIndex + 1 < m_queueIds.size());
}
bool MusicController::canGoPrevious() const
{
    return !m_queueIds.isEmpty()
        && (m_queueIndex > 0 || m_repeatMode == QLatin1String("playlist"));
}
int MusicController::queueIndex() const { return m_queueIndex; }
QVariantList MusicController::availableTranscodeFormats() const
{
    return m_transcoder.availableFormats();
}
bool MusicController::transcoding() const { return m_transcoder.active(); }
double MusicController::transcodeProgress() const { return m_transcoder.progress(); }
QString MusicController::transcodeStatus() const { return m_transcoder.status(); }
QString MusicController::transcodeError() const { return m_transcoder.errorMessage(); }

QVariantMap MusicController::mprisMetadata() const
{
    const auto track = findTrack(currentTrackId());
    if (!track)
        return {};
    const QString objectPath = QStringLiteral("/org/nextkde/KosMusic/track/t%1")
                                   .arg(track->id);
    QVariantMap metadata{
        {QStringLiteral("mpris:trackid"),
         QVariant::fromValue(QDBusObjectPath(objectPath))},
        {QStringLiteral("mpris:length"),
         QVariant::fromValue<qlonglong>(track->durationMs * 1000)},
        {QStringLiteral("xesam:title"), track->title},
        {QStringLiteral("xesam:artist"), QStringList{track->artist}},
        {QStringLiteral("xesam:album"), track->album},
        {QStringLiteral("xesam:url"), track->url.isEmpty() ? track->path : track->url},
        {QStringLiteral("xesam:trackNumber"), track->trackNumber},
        {QStringLiteral("xesam:genre"), QStringList{track->genre}},
    };
    if (!track->artworkUrl.isEmpty())
        metadata.insert(QStringLiteral("mpris:artUrl"), track->artworkUrl);
    const QString lyric = currentLyric();
    const QString followingLyric = nextLyric();
    metadata.insert(QStringLiteral("xesam:asText"), lyric);
    metadata.insert(QStringLiteral("kos:currentLyric"), lyric);
    metadata.insert(QStringLiteral("kos:nextLyric"), followingLyric);
    metadata.insert(QStringLiteral("kos:lyricIndex"), currentLyricIndex());
    metadata.insert(QStringLiteral("kos:playbackStatus"), playbackStatusText());
    metadata.insert(QStringLiteral("kos:playbackState"), playbackState());
    metadata.insert(QStringLiteral("kos:lyricsEnabled"), m_lyricsEnabled);
    return metadata;
}

QString MusicController::mprisLoopStatus() const
{
    if (m_repeatMode == QLatin1String("track"))
        return QStringLiteral("Track");
    if (m_repeatMode == QLatin1String("playlist"))
        return QStringLiteral("Playlist");
    return QStringLiteral("None");
}

void MusicController::addLibraryFolder(const QString &pathOrUrl)
{
    if (!m_ready)
        return;
    const QString path = localPath(pathOrUrl);
    const QFileInfo info(path);
    QString canonical = info.canonicalFilePath();
    if (canonical.isEmpty())
        canonical = info.absoluteFilePath();
    if (!info.isDir() || !info.isReadable()) {
        setError(tr("Music folder is not readable: %1").arg(path));
        return;
    }
    QString error;
    if (!m_database.addLibraryRoot(canonical, &error)) {
        setError(error);
        return;
    }
    m_libraryFolders = m_database.libraryRoots();
    emit libraryFoldersChanged();
    if (!m_pendingScanRoots.contains(canonical) && m_activeScanRoot != canonical)
        m_pendingScanRoots.append(canonical);
    startNextScan();
}

void MusicController::removeLibraryFolder(const QString &pathOrUrl)
{
    if (!m_ready)
        return;
    const QFileInfo info(localPath(pathOrUrl));
    QString path = info.canonicalFilePath();
    if (path.isEmpty())
        path = info.absoluteFilePath();
    QString error;
    if (!m_database.removeLibraryRoot(path, &error)) {
        setError(error);
        return;
    }
    m_pendingScanRoots.removeAll(path);
    refreshLibrary();
    emit userMessage(tr("Music folder removed from the library"));
}

void MusicController::rescanLibrary()
{
    if (!m_ready)
        return;
    const QStringList roots = m_database.libraryRoots();
    for (const QString &root : roots) {
        if (!m_pendingScanRoots.contains(root) && m_activeScanRoot != root)
            m_pendingScanRoots.append(root);
    }
    startNextScan();
}

void MusicController::setLibraryView(const QString &mode, const QString &filterValue)
{
    m_libraryModel.setView(mode, filterValue);
}

void MusicController::setSearch(const QString &search)
{
    const QString normalized = TrackListModel::normalizeSearchText(search);
    if (m_librarySearch == normalized)
        return;
    m_librarySearch = normalized;
    m_libraryModel.setSearch(normalized);
    applyGroupSearch();
    emit librarySearchChanged();
    emit libraryChanged();
}

void MusicController::searchOnline(const QString &query)
{
    m_onlineProvider.search(query);
}

qint64 MusicController::storeOnlineTrack(int row)
{
    const auto track = m_onlineModel.trackAt(row);
    if (!track)
        return -1;
    QString error;
    const qint64 id = m_database.addExternalTrack(*track, &error);
    if (id < 0) {
        setError(error);
        return -1;
    }
    refreshLibrary();
    return id;
}

void MusicController::playOnlineRow(int row)
{
    const qint64 id = storeOnlineTrack(row);
    if (id < 0)
        return;
    setQueue({id}, 0);
    startCurrentTrack();
}

void MusicController::enqueueOnlineRow(int row)
{
    const qint64 id = storeOnlineTrack(row);
    if (id >= 0)
        enqueueTrack(id);
}

void MusicController::importMusicSource(const QString &pathOrUrl)
{
    if (m_sourceService)
        m_sourceService->importSource(pathOrUrl);
}

void MusicController::activateMusicSource(const QString &sourceId)
{
    if (m_sourceService)
        m_sourceService->activateSource(sourceId);
}

void MusicController::removeMusicSource(const QString &sourceId)
{
    if (m_sourceService)
        m_sourceService->removeSource(sourceId);
}

void MusicController::playTrack(qlonglong trackId)
{
    if (!findTrack(trackId))
        return;
    QList<qint64> context = m_libraryModel.visibleIds();
    int index = context.indexOf(trackId);
    if (index < 0) {
        context = {trackId};
        index = 0;
    }
    setQueue(context, index);
    startCurrentTrack();
}

void MusicController::playQueueRow(int row)
{
    if (row < 0 || row >= m_queueIds.size())
        return;
    m_queueIndex = row;
    persistQueue();
    emit queueChanged();
    emit currentTrackChanged();
    startCurrentTrack();
}

void MusicController::playPlaylistRow(int row)
{
    if (!m_ready)
        return;
    const QList<qint64> ids = m_database.playlistTrackIds(m_selectedPlaylistId);
    if (row < 0 || row >= ids.size())
        return;
    setQueue(ids, row);
    startCurrentTrack();
}

void MusicController::playAlbum(const QString &album)
{
    const qsizetype separator = album.indexOf(albumSeparator);
    const QString albumName = separator < 0 ? album : album.left(separator);
    const QString albumArtist = separator < 0 ? QString{} : album.mid(separator + 1);
    QList<TrackRecord> tracks;
    std::copy_if(m_tracks.cbegin(), m_tracks.cend(), std::back_inserter(tracks),
                 [&albumName, &albumArtist, separator](const TrackRecord &track) {
                     return track.album.compare(albumName, Qt::CaseInsensitive) == 0
                         && (separator < 0
                             || track.albumArtist.compare(albumArtist,
                                                          Qt::CaseInsensitive) == 0);
                 });
    std::stable_sort(tracks.begin(), tracks.end(), [](const TrackRecord &left,
                                                      const TrackRecord &right) {
        if (left.discNumber != right.discNumber)
            return left.discNumber < right.discNumber;
        if (left.trackNumber != right.trackNumber)
            return left.trackNumber < right.trackNumber;
        return left.title.localeAwareCompare(right.title) < 0;
    });
    QList<qint64> ids;
    for (const TrackRecord &track : std::as_const(tracks))
        ids.append(track.id);
    if (!ids.isEmpty()) {
        setQueue(ids, 0);
        startCurrentTrack();
    }
}

void MusicController::playArtist(const QString &artist)
{
    QList<TrackRecord> tracks;
    for (const TrackRecord &track : std::as_const(m_tracks)) {
        if (trackArtist(track).compare(artist, Qt::CaseInsensitive) == 0)
            tracks.append(track);
    }
    std::stable_sort(tracks.begin(), tracks.end(), [](const TrackRecord &left,
                                                      const TrackRecord &right) {
        const int albumOrder = left.album.localeAwareCompare(right.album);
        if (albumOrder != 0)
            return albumOrder < 0;
        if (left.discNumber != right.discNumber)
            return left.discNumber < right.discNumber;
        if (left.trackNumber != right.trackNumber)
            return left.trackNumber < right.trackNumber;
        return left.title.localeAwareCompare(right.title) < 0;
    });
    QList<qint64> ids;
    for (const TrackRecord &track : std::as_const(tracks))
        ids.append(track.id);
    if (!ids.isEmpty()) {
        setQueue(ids, 0);
        startCurrentTrack();
    }
}

void MusicController::enqueueTrack(qlonglong trackId)
{
    if (!findTrack(trackId))
        return;
    m_queueIds.append(trackId);
    if (m_queueIndex < 0)
        m_queueIndex = 0;
    refreshQueueModel();
    persistQueue();
    emit queueChanged();
}

void MusicController::playTrackNext(qlonglong trackId)
{
    if (!findTrack(trackId))
        return;
    const int position = std::clamp(m_queueIndex + 1, 0,
                                    static_cast<int>(m_queueIds.size()));
    m_queueIds.insert(position, trackId);
    if (m_queueIndex < 0)
        m_queueIndex = 0;
    refreshQueueModel();
    persistQueue();
    emit queueChanged();
}

void MusicController::removeQueueRow(int row)
{
    if (row < 0 || row >= m_queueIds.size())
        return;
    const bool removingCurrent = row == m_queueIndex;
    m_queueIds.removeAt(row);
    if (m_queueIds.isEmpty()) {
        m_queueIndex = -1;
        m_engine.stop();
        m_lyricsService->load({});
    } else if (row < m_queueIndex) {
        --m_queueIndex;
    } else if (m_queueIndex >= m_queueIds.size()) {
        m_queueIndex = m_queueIds.size() - 1;
    }
    if (removingCurrent) {
        cancelRecovery();
        m_preparationFailed = false;
        m_playWhenReady = false;
        m_sourceService->cancelResolves();
        m_loadedTrackId = -1;
        m_resumePositionMs = 0;
        if (!m_queueIds.isEmpty())
            m_lyricsService->load({});
        if (m_resolvingTrackId >= 0) {
            m_resolvingTrackId = -1;
            emit playbackStateChanged();
        }
        m_engine.stop();
    }
    refreshQueueModel();
    persistQueue();
    emit queueChanged();
    emit currentTrackChanged();
}

void MusicController::clearQueue()
{
    if (!m_ready)
        return;
    stop();
    setQueue({}, -1);
}

void MusicController::play()
{
    if (m_queueIds.isEmpty())
        return;
    if (m_queueIndex < 0)
        m_queueIndex = 0;
    const auto track = findTrack(currentTrackId());
    if (!track)
        return;
    m_playWhenReady = true;
    if (m_preparationFailed) {
        startCurrentTrack(positionMs());
        return;
    }
    if (m_resolvingTrackId == track->id) {
        if (!m_attemptTimeout.isActive()) m_attemptTimeout.start();
        if (!m_trackTimeout.isActive()) m_trackTimeout.start();
        emit playbackStateChanged();
        return;
    }
    if (m_loadedTrackId != track->id || m_engine.source().isEmpty()
        || m_engine.state() == QLatin1String("Error")
        || m_engine.state() == QLatin1String("Stopped")) {
        startCurrentTrack(positionMs());
    } else {
        m_engine.play();
    }
}

void MusicController::pause()
{
    m_playWhenReady = false;
    m_skipTimer.stop();
    m_attemptTimeout.stop();
    m_trackTimeout.stop();
    if (m_preparationFailed) m_recoveryStatus = tr("已暂停自动跳过，点击播放可重试");
    if (m_loadedTrackId == currentTrackId())
        m_engine.pause();
    persistPlaybackPosition();
    emit playbackStateChanged();
}
void MusicController::togglePlayPause()
{
    if (playbackState() == QLatin1String("Playing")
        || playbackState() == QLatin1String("Loading"))
        pause();
    else
        play();
}
void MusicController::stop()
{
    cancelRecovery();
    m_playWhenReady = false;
    m_failedTracks.clear();
    m_preparationFailed = false;
    m_resolvingTrackId = -1;
    if (m_sourceService)
        m_sourceService->cancelResolves();
    m_resumePositionMs = 0;
    emit playbackStateChanged();
    m_engine.stop();
    persistPlaybackPosition();
}
void MusicController::next() { advance(false); }
void MusicController::previous()
{
    if (m_engine.positionMs() > 3000) {
        m_engine.seek(0);
        return;
    }
    if (m_queueIds.isEmpty())
        return;
    int previousIndex = m_queueIndex - 1;
    if (previousIndex < 0 && m_repeatMode == QLatin1String("playlist"))
        previousIndex = m_queueIds.size() - 1;
    if (previousIndex < 0)
        return;
    m_queueIndex = previousIndex;
    persistQueue();
    emit queueChanged();
    emit currentTrackChanged();
    startCurrentTrack();
}
void MusicController::seek(qlonglong positionMs) { m_engine.seek(positionMs); }
void MusicController::seekFraction(double fraction)
{
    m_engine.seek(static_cast<qint64>(std::clamp(fraction, 0.0, 1.0) * durationMs()));
}

void MusicController::setVolume(double volume)
{
    if (!m_ready)
        return;
    m_engine.setVolume(volume);
    m_database.setSetting(QStringLiteral("volume"), QString::number(m_engine.volume()));
}

void MusicController::setShuffle(bool shuffle)
{
    if (!m_ready)
        return;
    if (m_shuffle == shuffle)
        return;
    m_shuffle = shuffle;
    m_database.setSetting(QStringLiteral("shuffle"), shuffle ? QStringLiteral("true")
                                                             : QStringLiteral("false"));
    emit shuffleChanged();
    emit playbackModeChanged();
    emit queueChanged();
}

void MusicController::setRepeatMode(const QString &mode)
{
    if (!m_ready)
        return;
    QString normalized = mode.toLower();
    if (normalized == QLatin1String("none")) {
        // Valid as-is.
    } else if (normalized != QLatin1String("track")
               && normalized != QLatin1String("playlist")) {
        normalized = QStringLiteral("none");
    }
    if (m_repeatMode == normalized)
        return;
    m_repeatMode = normalized;
    m_database.setSetting(QStringLiteral("repeat"), normalized);
    emit repeatModeChanged();
    emit playbackModeChanged();
    emit queueChanged();
}

void MusicController::setPlaybackMode(const QString &mode)
{
    QString normalized = mode.trimmed().toLower();
    if (normalized != QLatin1String("sequential")
        && normalized != QLatin1String("playlist")
        && normalized != QLatin1String("track")
        && normalized != QLatin1String("shuffle")) {
        normalized = QStringLiteral("sequential");
    }
    const bool nextShuffle = normalized == QLatin1String("shuffle");
    const QString nextRepeat = normalized == QLatin1String("track")
        ? QStringLiteral("track")
        : normalized == QLatin1String("playlist")
            ? QStringLiteral("playlist") : QStringLiteral("none");
    const bool shuffleChangedValue = m_shuffle != nextShuffle;
    const bool repeatChangedValue = m_repeatMode != nextRepeat;
    if (!shuffleChangedValue && !repeatChangedValue)
        return;
    m_shuffle = nextShuffle;
    m_repeatMode = nextRepeat;
    m_database.setSetting(QStringLiteral("shuffle"), m_shuffle
                          ? QStringLiteral("true") : QStringLiteral("false"));
    m_database.setSetting(QStringLiteral("repeat"), m_repeatMode);
    if (shuffleChangedValue)
        emit shuffleChanged();
    if (repeatChangedValue)
        emit repeatModeChanged();
    emit playbackModeChanged();
    emit queueChanged();
}

void MusicController::setOnlineQuality(const QString &quality)
{
    const QString normalized = quality.trimmed().toLower();
    const QStringList available = onlineQualities();
    const QStringList &allowed = available.isEmpty()
        ? supportedOnlineQualities() : available;
    if (!allowed.contains(normalized))
        return;
    if (m_onlineQuality == normalized)
        return;
    m_onlineQuality = normalized;
    m_database.setSetting(QStringLiteral("onlineQuality"), normalized);
    emit onlineQualityChanged();
}

void MusicController::createPlaylist(const QString &name)
{
    if (!m_ready)
        return;
    const QString cleaned = name.trimmed().left(128);
    if (cleaned.isEmpty())
        return;
    QString error;
    if (m_database.createPlaylist(cleaned, &error) < 0)
        setError(error);
    refreshPlaylists();
}

void MusicController::renamePlaylist(qlonglong playlistId, const QString &name)
{
    if (!m_ready)
        return;
    const QString cleaned = name.trimmed().left(128);
    if (cleaned.isEmpty())
        return;
    QString error;
    if (!m_database.renamePlaylist(playlistId, cleaned, &error))
        setError(error);
    refreshPlaylists();
}

void MusicController::removePlaylist(qlonglong playlistId)
{
    if (!m_ready)
        return;
    QString error;
    if (!m_database.removePlaylist(playlistId, &error))
        setError(error);
    if (m_selectedPlaylistId == playlistId)
        m_selectedPlaylistId = -1;
    refreshPlaylists();
    refreshPlaylistModel();
}

void MusicController::selectPlaylist(qlonglong playlistId)
{
    if (!m_ready)
        return;
    m_selectedPlaylistId = playlistId;
    refreshPlaylistModel();
}

void MusicController::addTrackToPlaylist(qlonglong playlistId, qlonglong trackId)
{
    if (!m_ready)
        return;
    QString error;
    if (!m_database.addTrackToPlaylist(playlistId, trackId, &error))
        setError(error);
    refreshPlaylists();
    if (m_selectedPlaylistId == playlistId)
        refreshPlaylistModel();
}

void MusicController::removeTrackFromPlaylist(qlonglong playlistId, qlonglong trackId)
{
    if (!m_ready)
        return;
    QString error;
    if (!m_database.removeTrackFromPlaylist(playlistId, trackId, &error))
        setError(error);
    refreshPlaylists();
    if (m_selectedPlaylistId == playlistId)
        refreshPlaylistModel();
}

void MusicController::playPlaylist(qlonglong playlistId)
{
    if (!m_ready)
        return;
    const QList<qint64> ids = m_database.playlistTrackIds(playlistId);
    if (ids.isEmpty())
        return;
    setQueue(ids, 0);
    startCurrentTrack();
}

void MusicController::transcodeTrack(qlonglong trackId, const QString &outputUrl,
                                     const QString &formatId, bool overwrite)
{
    const auto track = findTrack(trackId);
    if (!track)
        return;
    QUrl destination(outputUrl);
    if (!destination.isValid() || destination.scheme().isEmpty())
        destination = QUrl::fromLocalFile(QFileInfo(outputUrl).absoluteFilePath());
    if (!m_transcoder.start(QUrl(track->url), destination, formatId, overwrite))
        setError(m_transcoder.errorMessage());
}

void MusicController::cancelTranscode() { m_transcoder.cancel(); }

void MusicController::openUri(const QString &uriOrPath)
{
    if (!m_ready)
        return;
    QUrl url(uriOrPath);
    if (!url.isValid() || url.scheme().isEmpty())
        url = QUrl::fromLocalFile(QFileInfo(uriOrPath).absoluteFilePath());
    if (!url.isLocalFile()) {
        setError(tr("Only local audio files are supported in version 1"));
        return;
    }
    QString path = QFileInfo(url.toLocalFile()).canonicalFilePath();
    if (path.isEmpty())
        path = QFileInfo(url.toLocalFile()).absoluteFilePath();
    QString error;
    std::optional<TrackRecord> existing = m_database.trackForPath(path, &error);
    qint64 id = existing ? existing->id : -1;
    if (!existing) {
        QString warning;
        const auto scanned = MetadataScanner::scanFile(path, m_artworkPath, &warning);
        if (!scanned) {
            setError(warning);
            return;
        }
        id = m_database.addExternalTrack(*scanned, &error);
        if (id < 0) {
            setError(error);
            return;
        }
        refreshLibrary();
    }
    playTrack(id);
}

void MusicController::requestRaise() { emit raiseRequested(); }

void MusicController::clearError() { setError({}); }

void MusicController::scanFinished()
{
    if (!m_ready)
        return;
    const ScanResult result = m_scanWatcher.result();
    QString error;
    if (m_database.libraryRoots().contains(result.rootPath)
        && !m_database.applyScan(result, &error)) {
        setError(error);
    }
    m_scanWarnings.append(result.warnings);
    if (m_scanWarnings.size() > 100)
        m_scanWarnings = m_scanWarnings.mid(m_scanWarnings.size() - 100);
    m_activeScanRoot.clear();
    refreshLibrary();
    startNextScan();
}

void MusicController::setError(const QString &message)
{
    if (m_errorMessage == message)
        return;
    m_errorMessage = message;
    emit errorMessageChanged();
}

void MusicController::startNextScan()
{
    if (m_scanWatcher.isRunning())
        return;
    if (m_pendingScanRoots.isEmpty()) {
        const bool changed = m_scanning;
        m_scanning = false;
        m_scanStatus = QStringLiteral("Idle");
        if (changed)
            emit scanningChanged();
        return;
    }
    m_activeScanRoot = m_pendingScanRoots.takeFirst();
    m_scanning = true;
    m_scanStatus = tr("Scanning %1").arg(m_activeScanRoot);
    emit scanningChanged();
    QString fingerprintError;
    const FingerprintMap known = m_database.fingerprints(m_activeScanRoot,
                                                         &fingerprintError);
    if (!fingerprintError.isEmpty())
        setError(fingerprintError);
    const QString root = m_activeScanRoot;
    const QString artworkPath = m_artworkPath;
    m_scanWatcher.setFuture(QtConcurrent::run([root, known, artworkPath] {
        return MetadataScanner::scan(root, known, artworkPath);
    }));
}

void MusicController::refreshLibrary()
{
    QString error;
    m_tracks = m_database.allTracks(&error);
    if (!error.isEmpty())
        setError(error);
    // Keep an id -> row index: findTrack is consulted by every current-track
    // property getter and by tracksForIds for each queued/playlist row, so a
    // linear scan turns each property read into an O(n) walk.
    m_trackIndex.clear();
    m_trackIndex.reserve(m_tracks.size());
    for (int index = 0; index < m_tracks.size(); ++index)
        m_trackIndex.insert(m_tracks.at(index).id, index);
    m_libraryFolders = m_database.libraryRoots();
    m_libraryModel.setTracks(m_tracks);
    refreshGroups();
    refreshPlaylists();
    refreshQueueModel();
    refreshPlaylistModel();
    emit libraryFoldersChanged();
    emit libraryChanged();
}

void MusicController::refreshGroups()
{
    struct Group {
        QString name;
        QString filterValue;
        QString subtitle;
        QString artwork;
        QStringList searchFields;
        int count = 0;
    };
    QMap<QString, Group> albumsByName;
    QMap<QString, Group> artistsByName;
    for (const TrackRecord &track : std::as_const(m_tracks)) {
        const QString albumName = fallbackName(track.album, tr("Unknown album"));
        const QString albumArtist = fallbackName(
            track.albumArtist, fallbackName(track.artist, tr("Unknown artist")));
        Group &album = albumsByName[albumFilter(track).toCaseFolded()];
        album.name = albumName;
        album.filterValue = albumFilter(track);
        album.subtitle = albumArtist;
        if (album.artwork.isEmpty())
            album.artwork = track.artworkUrl;
        album.searchFields.append({albumName, albumArtist, track.title, track.artist,
                                   track.albumArtist, track.genre});
        ++album.count;

        const QString artistValue = trackArtist(track);
        const QString artistName = fallbackName(artistValue, tr("Unknown artist"));
        Group &artist = artistsByName[artistName.toCaseFolded()];
        artist.name = artistName;
        artist.filterValue = artistValue;
        if (artist.artwork.isEmpty())
            artist.artwork = track.artworkUrl;
        artist.searchFields.append({artistName, track.title, track.album,
                                    track.albumArtist, track.genre});
        ++artist.count;
    }

    QCollator collator;
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    collator.setNumericMode(true);
    QList<Group> albumGroups = albumsByName.values();
    QList<Group> artistGroups = artistsByName.values();
    const auto localizedOrder = [&collator](const Group &left, const Group &right) {
        return collator.compare(left.name, right.name) < 0;
    };
    std::stable_sort(albumGroups.begin(), albumGroups.end(), localizedOrder);
    std::stable_sort(artistGroups.begin(), artistGroups.end(), localizedOrder);

    m_allAlbums.clear();
    for (const Group &group : std::as_const(albumGroups)) {
        m_allAlbums.append(QVariantMap{{QStringLiteral("name"), group.name},
                                       {QStringLiteral("filterValue"), group.filterValue},
                                       {QStringLiteral("subtitle"), group.subtitle},
                                       {QStringLiteral("artworkUrl"), group.artwork},
                                       {QStringLiteral("searchFields"), group.searchFields},
                                       {QStringLiteral("count"), group.count}});
    }
    m_allArtists.clear();
    for (const Group &group : std::as_const(artistGroups)) {
        m_allArtists.append(QVariantMap{{QStringLiteral("name"), group.name},
                                        {QStringLiteral("filterValue"), group.filterValue},
                                        {QStringLiteral("artworkUrl"), group.artwork},
                                        {QStringLiteral("searchFields"), group.searchFields},
                                        {QStringLiteral("count"), group.count}});
    }
    applyGroupSearch();
}

void MusicController::applyGroupSearch()
{
    const auto filter = [this](const QVariantList &source) {
        QVariantList result;
        for (const QVariant &entry : source) {
            const QVariantMap group = entry.toMap();
            if (TrackListModel::matchesSearch(
                    group.value(QStringLiteral("searchFields")).toStringList(),
                    m_librarySearch)) {
                result.append(entry);
            }
        }
        return result;
    };
    m_albums = filter(m_allAlbums);
    m_artists = filter(m_allArtists);
}

void MusicController::refreshPlaylists()
{
    m_playlists = m_database.playlists();
    emit playlistsChanged();
}

void MusicController::refreshQueueModel()
{
    const QList<TrackRecord> queueTracks = tracksForIds(m_queueIds);
    if (queueTracks.size() != m_queueIds.size()) {
        m_queueIds.clear();
        for (const TrackRecord &track : queueTracks)
            m_queueIds.append(track.id);
        if (m_queueIndex >= m_queueIds.size())
            m_queueIndex = m_queueIds.isEmpty() ? -1 : m_queueIds.size() - 1;
        persistQueue();
    }
    m_queueModel.setTracks(queueTracks);
}

void MusicController::refreshPlaylistModel()
{
    m_playlistTracksModel.setTracks(
        tracksForIds(m_database.playlistTrackIds(m_selectedPlaylistId)));
}

void MusicController::setQueue(const QList<qint64> &trackIds, int currentIndex)
{
    const int nextIndex = trackIds.isEmpty()
        ? -1 : std::clamp(currentIndex, 0, static_cast<int>(trackIds.size()) - 1);
    const qint64 nextTrackId = nextIndex < 0 ? -1 : trackIds.at(nextIndex);
    if (m_resolvingTrackId >= 0 && m_resolvingTrackId != nextTrackId) {
        m_resolvingTrackId = -1;
        emit playbackStateChanged();
    }
    m_queueIds = trackIds;
    m_queueIndex = nextIndex;
    if (trackIds.isEmpty())
        m_lyricsService->load({});
    refreshQueueModel();
    persistQueue();
    emit queueChanged();
    emit currentTrackChanged();
}

void MusicController::persistQueue()
{
    QString error;
    if (!m_database.setQueueTrackIds(m_queueIds, &error)
        || !m_database.setSetting(QStringLiteral("queueIndex"),
                                  QString::number(m_queueIndex), &error)) {
        setError(error);
    }
}

QString MusicController::audioCacheKey(const TrackRecord &track) const
{
    return track.source + QChar(0x1f) + track.path + QChar(0x1f) + m_onlineQuality;
}

void MusicController::persistPlaybackPosition()
{
    if (!m_ready)
        return;
    const QJsonObject position{
        {QStringLiteral("trackId"), QString::number(currentTrackId())},
        {QStringLiteral("positionMs"), positionMs()},
    };
    m_database.setSetting(QStringLiteral("playbackPosition"),
        QString::fromUtf8(QJsonDocument(position).toJson(QJsonDocument::Compact)));
}

void MusicController::loadPreparedTrack(const QUrl &url)
{
    if (m_resolvingTrackId != currentTrackId() || m_resolvingTrackId < 0)
        return;
    m_recoveryStatus.clear();
    m_engineCacheKey = m_pendingCacheKey;
    m_loadedTrackId = m_resolvingTrackId;
    m_resolvingTrackId = -1;
    if (m_engine.load(url, m_playWhenReady, m_resumePositionMs))
        m_database.recordPlayed(m_loadedTrackId);
    emit playbackStateChanged();
}

void MusicController::startCurrentTrack(qint64 startPositionMs)
{
    const auto track = findTrack(currentTrackId());
    if (!track)
        return;
    cancelRecovery();
    if (!m_automaticAdvance) m_failedTracks.clear();
    m_attemptName.clear();
    m_sourceCandidates.clear();
    m_preparationFailed = false;
    m_sourceService->cancelResolves();
    m_loadedTrackId = -1;
    m_resumePositionMs = std::max<qint64>(0, startPositionMs);
    m_playWhenReady = true;
    m_resolvingTrackId = track->id;
    m_engine.stop();
    setError({});
    persistPlaybackPosition();
    emit currentTrackChanged();
    emit positionChanged();
    emit seekableChanged();
    emit durationChanged();
    m_lyricsService->load(m_lyricsEnabled ? *track : TrackRecord{});
    m_usingCachedAudio = false;
    m_pendingCacheKey.clear();
    if (track->source != QLatin1String("local")) {
        m_pendingCacheKey = audioCacheKey(*track);
        const QString preferred = m_sourceService->activeSourceId();
        if (!preferred.isEmpty()) m_sourceCandidates.append(preferred);
        for (const QVariant &value : m_sourceService->sources()) {
            const QString id = value.toMap().value(QStringLiteral("id")).toString();
            if (!m_sourceCandidates.contains(id)) m_sourceCandidates.append(id);
        }
        const QUrl cached = m_audioCache->lookup(m_pendingCacheKey);
        if (!cached.isEmpty()) {
            m_usingCachedAudio = true;
            loadPreparedTrack(cached);
            return;
        }
        emit playbackStateChanged();
        m_trackTimeout.start();
        tryNextSource();
        return;
    }
    loadPreparedTrack(QUrl(track->url));
}

void MusicController::cancelRecovery()
{
    ++m_attemptGeneration;
    m_attemptTimeout.stop();
    m_trackTimeout.stop();
    m_skipTimer.stop();
    m_waitingForSource = false;
    m_failureQueued = false;
    m_recoveryStatus.clear();
}

void MusicController::tryNextSource()
{
    const auto track = findTrack(currentTrackId());
    if (!track || track->source == QLatin1String("local") || m_sourceCandidates.isEmpty()) {
        finishFailedTrack(tr("没有可用的兼容音源"));
        return;
    }
    ++m_attemptGeneration;
    m_failureQueued = false;
    m_sourceService->cancelResolves();
    m_resolvingTrackId = track->id;
    m_loadedTrackId = -1;
    m_engine.stop();
    m_usingCachedAudio = false;
    const QString id = m_sourceCandidates.takeFirst();
    m_attemptName = id;
    for (const QVariant &value : m_sourceService->sources()) {
        const QVariantMap source = value.toMap();
        if (source.value(QStringLiteral("id")).toString() == id)
            m_attemptName = source.value(QStringLiteral("name")).toString();
    }
    m_recoveryStatus = tr("正在尝试音源：%1…").arg(m_attemptName);
    m_waitingForSource = true;
    emit playbackStateChanged();
    m_sourceService->useSourceForPlayback(id);
    if (m_playWhenReady) {
        m_attemptTimeout.start();
        if (!m_trackTimeout.isActive()) m_trackTimeout.start();
    }
    if (m_sourceService->state() == QLatin1String("ready"))
        resolveWithReadySource();
}

void MusicController::resolveWithReadySource()
{
    if (!m_waitingForSource || m_resolvingTrackId != currentTrackId())
        return;
    m_waitingForSource = false;
    const auto track = findTrack(currentTrackId());
    if (track)
        m_sourceService->resolve(track->id, track->source, track->sourceData, m_onlineQuality);
}

void MusicController::schedulePlaybackFailure(const QString &message)
{
    if (m_failureQueued || m_preparationFailed || currentTrackId() < 0)
        return;
    m_failureQueued = true;
    const int generation = m_attemptGeneration;
    // Do not tear down a source/pipeline while it is dispatching its failure signal.
    QTimer::singleShot(0, this, [this, generation, message] {
        if (generation != m_attemptGeneration)
            return;
        m_failureQueued = false;
        m_attemptTimeout.stop();
        m_waitingForSource = false;
        m_sourceService->cancelResolves();
        m_playbackAttempts.append(tr("%1 · %2：%3").arg(currentTitle(),
            m_attemptName.isEmpty() ? tr("音频文件") : m_attemptName, message.left(500)));
        while (m_playbackAttempts.size() > 30) m_playbackAttempts.removeFirst();
        m_resumePositionMs = positionMs();
        if (m_playWhenReady && !m_sourceCandidates.isEmpty())
            tryNextSource();
        else
            finishFailedTrack(message);
    });
}

void MusicController::finishFailedTrack(const QString &message)
{
    m_playbackAttempts.append(tr("%1：%2").arg(currentTitle(), message.left(500)));
    while (m_playbackAttempts.size() > 30) m_playbackAttempts.removeFirst();
    cancelRecovery();
    m_sourceService->cancelResolves();
    m_resolvingTrackId = -1;
    m_resumePositionMs = positionMs();
    m_loadedTrackId = -1;
    m_engine.stop();
    m_preparationFailed = true;
    m_failedTracks.insert(currentTrackId());
    setError(message);
    m_recoveryStatus = m_playWhenReady
        ? tr("本曲无法播放，3 秒后按队列继续…")
        : tr("本曲无法播放，点击重试");
    if (m_playWhenReady) m_skipTimer.start();
    emit playbackStateChanged();
}

void MusicController::advanceAfterFailure()
{
    if (!m_playWhenReady || m_queueIds.isEmpty())
        return;
    QList<int> candidates;
    if (m_shuffle) {
        for (int i = 0; i < m_queueIds.size(); ++i)
            if (!m_failedTracks.contains(m_queueIds.at(i))) candidates.append(i);
    } else {
        for (int step = 1; step <= m_queueIds.size(); ++step) {
            int index = m_queueIndex + step;
            if (index >= m_queueIds.size()) {
                if (m_repeatMode != QLatin1String("playlist")) break;
                index %= m_queueIds.size();
            }
            if (!m_failedTracks.contains(m_queueIds.at(index))) {
                candidates.append(index);
                break;
            }
        }
    }
    if (candidates.isEmpty()) {
        m_playWhenReady = false;
        m_recoveryStatus = tr("没有更多可播放的歌曲，请检查音源后重试");
        emit playbackStateChanged();
        return;
    }
    emit userMessage(tr("已跳过无法播放的歌曲：%1").arg(currentTitle()));
    m_queueIndex = candidates.at(m_shuffle
        ? QRandomGenerator::global()->bounded(candidates.size()) : 0);
    persistQueue();
    emit queueChanged();
    m_automaticAdvance = true;
    startCurrentTrack();
    m_automaticAdvance = false;
}

void MusicController::advance(bool fromEndOfStream)
{
    if (m_queueIds.isEmpty())
        return;
    if (fromEndOfStream && m_repeatMode == QLatin1String("track")) {
        startCurrentTrack();
        return;
    }
    int nextIndex = m_queueIndex + 1;
    if (m_shuffle && m_queueIds.size() > 1) {
        do {
            nextIndex = QRandomGenerator::global()->bounded(m_queueIds.size());
        } while (nextIndex == m_queueIndex);
    } else if (nextIndex >= m_queueIds.size()) {
        if (m_repeatMode == QLatin1String("playlist"))
            nextIndex = 0;
        else {
            m_engine.stop();
            return;
        }
    }
    m_queueIndex = nextIndex;
    persistQueue();
    emit queueChanged();
    emit currentTrackChanged();
    startCurrentTrack();
}

QList<TrackRecord> MusicController::tracksForIds(const QList<qint64> &ids) const
{
    QList<TrackRecord> result;
    result.reserve(ids.size());
    for (qint64 id : ids) {
        const auto track = findTrack(id);
        if (track)
            result.append(*track);
    }
    return result;
}

std::optional<TrackRecord> MusicController::findTrack(qint64 id) const
{
    const auto index = m_trackIndex.constFind(id);
    return index == m_trackIndex.cend()
        ? std::nullopt : std::optional<TrackRecord>(m_tracks.at(index.value()));
}

QString MusicController::localPath(const QString &pathOrUrl)
{
    const QUrl url(pathOrUrl);
    return url.isLocalFile() ? url.toLocalFile() : pathOrUrl;
}
