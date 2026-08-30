#include "MusicController.h"

#include "MetadataScanner.h"
#include "MprisService.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDBusObjectPath>
#include <QDir>
#include <QFileInfo>
#include <QMap>
#include <QRandomGenerator>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>
#include <QtConcurrentRun>

#include <algorithm>
#include <iterator>
#include <utility>

namespace {

QString fallbackName(const QString &value, const QString &fallback)
{
    return value.trimmed().isEmpty() ? fallback : value.trimmed();
}

} // namespace

MusicController::MusicController(QObject *parent)
    : QObject(parent)
    , m_engine(this)
    , m_transcoder(this)
    , m_libraryModel(this)
    , m_queueModel(this)
    , m_playlistTracksModel(this)
    , m_scanWatcher(this)
{
    m_queueModel.setMode(QStringLiteral("queue"));
    m_playlistTracksModel.setMode(QStringLiteral("queue"));
    connect(&m_scanWatcher, &QFutureWatcher<ScanResult>::finished,
            this, &MusicController::scanFinished);
    connect(&m_engine, &PlaybackEngine::stateChanged,
            this, &MusicController::playbackStateChanged);
    connect(&m_engine, &PlaybackEngine::positionChanged,
            this, &MusicController::positionChanged);
    connect(&m_engine, &PlaybackEngine::durationChanged,
            this, &MusicController::durationChanged);
    connect(&m_engine, &PlaybackEngine::seekableChanged,
            this, &MusicController::seekableChanged);
    connect(&m_engine, &PlaybackEngine::volumeChanged,
            this, &MusicController::volumeChanged);
    connect(&m_engine, &PlaybackEngine::seeked, this, [this](qint64 position) {
        emit seeked(position);
    });
    connect(&m_engine, &PlaybackEngine::errorMessageChanged, this, [this] {
        if (!m_engine.errorMessage().isEmpty())
            setError(m_engine.errorMessage());
    });
    connect(&m_engine, &PlaybackEngine::endOfStream, this, [this] { advance(true); });

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
    QString databaseError;
    if (!m_database.open(QDir(m_dataPath).filePath(QStringLiteral("library.sqlite")),
                         &databaseError)) {
        setError(databaseError);
        return;
    }
    m_ready = true;
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
    m_mpris = new MprisService(this, this);
    emit mprisRegisteredChanged();

    QTimer::singleShot(0, this, [this] {
        emit readyChanged();
        rescanLibrary();
        const QStringList arguments = QCoreApplication::arguments().mid(1);
        for (const QString &argument : arguments) {
            if (argument.startsWith(QLatin1Char('-')))
                continue;
            const QUrl candidate(argument);
            const QString local = candidate.isLocalFile()
                ? candidate.toLocalFile() : argument;
            if (QFileInfo::exists(local))
                openUri(argument);
        }
    });
}

MusicController::~MusicController() = default;

TrackListModel *MusicController::libraryModel() { return &m_libraryModel; }
TrackListModel *MusicController::queueModel() { return &m_queueModel; }
TrackListModel *MusicController::playlistTracksModel() { return &m_playlistTracksModel; }
QVariantList MusicController::albums() const { return m_albums; }
QVariantList MusicController::artists() const { return m_artists; }
QVariantList MusicController::playlists() const { return m_playlists; }
QStringList MusicController::libraryFolders() const { return m_libraryFolders; }
bool MusicController::ready() const { return m_ready; }
bool MusicController::scanning() const { return m_scanning; }
QString MusicController::scanStatus() const { return m_scanStatus; }
QStringList MusicController::scanWarnings() const { return m_scanWarnings; }
QString MusicController::errorMessage() const { return m_errorMessage; }
bool MusicController::engineAvailable() const { return m_engine.available(); }
QString MusicController::engineBackend() const { return m_engine.backendName(); }
bool MusicController::mprisRegistered() const { return m_mpris && m_mpris->registered(); }
QString MusicController::playbackState() const { return m_engine.state(); }
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
qlonglong MusicController::positionMs() const { return m_engine.positionMs(); }
qlonglong MusicController::durationMs() const
{
    if (m_engine.durationMs() > 0)
        return m_engine.durationMs();
    const auto track = findTrack(currentTrackId());
    return track ? track->durationMs : 0;
}
bool MusicController::seekable() const { return m_engine.seekable(); }
double MusicController::volume() const { return m_engine.volume(); }
bool MusicController::shuffle() const { return m_shuffle; }
QString MusicController::repeatMode() const { return m_repeatMode; }
bool MusicController::canGoNext() const
{
    return !m_queueIds.isEmpty()
        && (m_shuffle || m_repeatMode == QLatin1String("playlist")
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
        {QStringLiteral("xesam:url"), track->url},
        {QStringLiteral("xesam:trackNumber"), track->trackNumber},
        {QStringLiteral("xesam:genre"), QStringList{track->genre}},
    };
    if (!track->artworkUrl.isEmpty())
        metadata.insert(QStringLiteral("mpris:artUrl"), track->artworkUrl);
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
    m_libraryModel.setFilterValue(filterValue);
    m_libraryModel.setMode(mode);
}

void MusicController::setSearch(const QString &search)
{
    m_libraryModel.setSearch(search);
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
    const QList<qint64> ids = m_database.playlistTrackIds(m_selectedPlaylistId);
    if (row < 0 || row >= ids.size())
        return;
    setQueue(ids, row);
    startCurrentTrack();
}

void MusicController::playAlbum(const QString &album)
{
    QList<TrackRecord> tracks;
    std::copy_if(m_tracks.cbegin(), m_tracks.cend(), std::back_inserter(tracks),
                 [&album](const TrackRecord &track) {
                     return track.album.compare(album, Qt::CaseInsensitive) == 0;
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
    QList<qint64> ids;
    for (const TrackRecord &track : std::as_const(m_tracks)) {
        if (track.artist.compare(artist, Qt::CaseInsensitive) == 0
            || track.albumArtist.compare(artist, Qt::CaseInsensitive) == 0) {
            ids.append(track.id);
        }
    }
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
    } else if (row < m_queueIndex) {
        --m_queueIndex;
    } else if (m_queueIndex >= m_queueIds.size()) {
        m_queueIndex = m_queueIds.size() - 1;
    }
    if (removingCurrent)
        m_engine.stop();
    refreshQueueModel();
    persistQueue();
    emit queueChanged();
    emit currentTrackChanged();
}

void MusicController::clearQueue()
{
    m_engine.stop();
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
    if (m_engine.source() != QUrl(track->url))
        startCurrentTrack();
    else
        m_engine.play();
}

void MusicController::pause() { m_engine.pause(); }
void MusicController::togglePlayPause()
{
    if (m_engine.state() == QLatin1String("Playing"))
        pause();
    else
        play();
}
void MusicController::stop() { m_engine.stop(); }
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
    m_engine.setVolume(volume);
    m_database.setSetting(QStringLiteral("volume"), QString::number(m_engine.volume()));
}

void MusicController::setShuffle(bool shuffle)
{
    if (m_shuffle == shuffle)
        return;
    m_shuffle = shuffle;
    m_database.setSetting(QStringLiteral("shuffle"), shuffle ? QStringLiteral("true")
                                                             : QStringLiteral("false"));
    emit shuffleChanged();
    emit queueChanged();
}

void MusicController::setRepeatMode(const QString &mode)
{
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
    emit queueChanged();
}

void MusicController::createPlaylist(const QString &name)
{
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
    m_selectedPlaylistId = playlistId;
    refreshPlaylistModel();
}

void MusicController::addTrackToPlaylist(qlonglong playlistId, qlonglong trackId)
{
    QString error;
    if (!m_database.addTrackToPlaylist(playlistId, trackId, &error))
        setError(error);
    refreshPlaylists();
    if (m_selectedPlaylistId == playlistId)
        refreshPlaylistModel();
}

void MusicController::removeTrackFromPlaylist(qlonglong playlistId, qlonglong trackId)
{
    QString error;
    if (!m_database.removeTrackFromPlaylist(playlistId, trackId, &error))
        setError(error);
    refreshPlaylists();
    if (m_selectedPlaylistId == playlistId)
        refreshPlaylistModel();
}

void MusicController::playPlaylist(qlonglong playlistId)
{
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
        int count = 0;
    };
    QMap<QString, Group> albumsByName;
    QMap<QString, Group> artistsByName;
    for (const TrackRecord &track : std::as_const(m_tracks)) {
        const QString albumName = fallbackName(track.album, tr("Unknown album"));
        Group &album = albumsByName[albumName.toCaseFolded()];
        album.name = albumName;
        album.filterValue = track.album;
        album.subtitle = fallbackName(track.albumArtist, track.artist);
        if (album.artwork.isEmpty())
            album.artwork = track.artworkUrl;
        ++album.count;

        const QString artistName = fallbackName(
            track.albumArtist.isEmpty() ? track.artist : track.albumArtist,
            tr("Unknown artist"));
        Group &artist = artistsByName[artistName.toCaseFolded()];
        artist.name = artistName;
        artist.filterValue = track.albumArtist.isEmpty()
            ? track.artist : track.albumArtist;
        if (artist.artwork.isEmpty())
            artist.artwork = track.artworkUrl;
        ++artist.count;
    }
    m_albums.clear();
    for (const Group &group : albumsByName) {
        m_albums.append(QVariantMap{{QStringLiteral("name"), group.name},
                                    {QStringLiteral("filterValue"), group.filterValue},
                                    {QStringLiteral("subtitle"), group.subtitle},
                                    {QStringLiteral("artworkUrl"), group.artwork},
                                    {QStringLiteral("count"), group.count}});
    }
    m_artists.clear();
    for (const Group &group : artistsByName) {
        m_artists.append(QVariantMap{{QStringLiteral("name"), group.name},
                                     {QStringLiteral("filterValue"), group.filterValue},
                                     {QStringLiteral("artworkUrl"), group.artwork},
                                     {QStringLiteral("count"), group.count}});
    }
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
    m_queueIds = trackIds;
    m_queueIndex = trackIds.isEmpty()
        ? -1 : std::clamp(currentIndex, 0, static_cast<int>(trackIds.size()) - 1);
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

void MusicController::startCurrentTrack()
{
    const auto track = findTrack(currentTrackId());
    if (!track)
        return;
    emit currentTrackChanged();
    emit durationChanged();
    if (m_engine.load(QUrl(track->url), true)) {
        m_database.recordPlayed(track->id);
        refreshLibrary();
    }
}

void MusicController::advance(bool fromEndOfStream)
{
    if (m_queueIds.isEmpty())
        return;
    if (fromEndOfStream && m_repeatMode == QLatin1String("track")) {
        m_engine.seek(0);
        m_engine.play();
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
    const auto found = std::find_if(m_tracks.cbegin(), m_tracks.cend(),
                                    [id](const TrackRecord &track) { return track.id == id; });
    return found == m_tracks.cend() ? std::nullopt : std::optional<TrackRecord>(*found);
}

QString MusicController::localPath(const QString &pathOrUrl)
{
    const QUrl url(pathOrUrl);
    return url.isLocalFile() ? url.toLocalFile() : pathOrUrl;
}
