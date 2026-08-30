#pragma once

#include "MusicDatabase.h"
#include "PlaybackEngine.h"
#include "TrackListModel.h"
#include "Transcoder.h"

#include <QFutureWatcher>
#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QtQmlIntegration/qqmlintegration.h>

#include <optional>

class MprisService;

class MusicController : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(TrackListModel *libraryModel READ libraryModel CONSTANT)
    Q_PROPERTY(TrackListModel *queueModel READ queueModel CONSTANT)
    Q_PROPERTY(TrackListModel *playlistTracksModel READ playlistTracksModel CONSTANT)
    Q_PROPERTY(QVariantList albums READ albums NOTIFY libraryChanged)
    Q_PROPERTY(QVariantList artists READ artists NOTIFY libraryChanged)
    Q_PROPERTY(QVariantList playlists READ playlists NOTIFY playlistsChanged)
    Q_PROPERTY(QStringList libraryFolders READ libraryFolders NOTIFY libraryFoldersChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)
    Q_PROPERTY(bool scanning READ scanning NOTIFY scanningChanged)
    Q_PROPERTY(QString scanStatus READ scanStatus NOTIFY scanningChanged)
    Q_PROPERTY(QStringList scanWarnings READ scanWarnings NOTIFY scanningChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)

    Q_PROPERTY(bool engineAvailable READ engineAvailable CONSTANT)
    Q_PROPERTY(QString engineBackend READ engineBackend CONSTANT)
    Q_PROPERTY(bool mprisRegistered READ mprisRegistered NOTIFY mprisRegisteredChanged)
    Q_PROPERTY(QString playbackState READ playbackState NOTIFY playbackStateChanged)
    Q_PROPERTY(qlonglong currentTrackId READ currentTrackId NOTIFY currentTrackChanged)
    Q_PROPERTY(QString currentTitle READ currentTitle NOTIFY currentTrackChanged)
    Q_PROPERTY(QString currentArtist READ currentArtist NOTIFY currentTrackChanged)
    Q_PROPERTY(QString currentAlbum READ currentAlbum NOTIFY currentTrackChanged)
    Q_PROPERTY(QString currentArtworkUrl READ currentArtworkUrl NOTIFY currentTrackChanged)
    Q_PROPERTY(qlonglong positionMs READ positionMs NOTIFY positionChanged)
    Q_PROPERTY(qlonglong durationMs READ durationMs NOTIFY durationChanged)
    Q_PROPERTY(bool seekable READ seekable NOTIFY seekableChanged)
    Q_PROPERTY(double volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(bool shuffle READ shuffle WRITE setShuffle NOTIFY shuffleChanged)
    Q_PROPERTY(QString repeatMode READ repeatMode WRITE setRepeatMode NOTIFY repeatModeChanged)
    Q_PROPERTY(bool canGoNext READ canGoNext NOTIFY queueChanged)
    Q_PROPERTY(bool canGoPrevious READ canGoPrevious NOTIFY queueChanged)
    Q_PROPERTY(int queueIndex READ queueIndex NOTIFY queueChanged)

    Q_PROPERTY(QVariantList availableTranscodeFormats READ availableTranscodeFormats CONSTANT)
    Q_PROPERTY(bool transcoding READ transcoding NOTIFY transcodeChanged)
    Q_PROPERTY(double transcodeProgress READ transcodeProgress NOTIFY transcodeChanged)
    Q_PROPERTY(QString transcodeStatus READ transcodeStatus NOTIFY transcodeChanged)
    Q_PROPERTY(QString transcodeError READ transcodeError NOTIFY transcodeChanged)

public:
    explicit MusicController(QObject *parent = nullptr);
    ~MusicController() override;

    TrackListModel *libraryModel();
    TrackListModel *queueModel();
    TrackListModel *playlistTracksModel();
    QVariantList albums() const;
    QVariantList artists() const;
    QVariantList playlists() const;
    QStringList libraryFolders() const;
    bool ready() const;
    bool scanning() const;
    QString scanStatus() const;
    QStringList scanWarnings() const;
    QString errorMessage() const;

    bool engineAvailable() const;
    QString engineBackend() const;
    bool mprisRegistered() const;
    QString playbackState() const;
    qlonglong currentTrackId() const;
    QString currentTitle() const;
    QString currentArtist() const;
    QString currentAlbum() const;
    QString currentArtworkUrl() const;
    qlonglong positionMs() const;
    qlonglong durationMs() const;
    bool seekable() const;
    double volume() const;
    bool shuffle() const;
    QString repeatMode() const;
    bool canGoNext() const;
    bool canGoPrevious() const;
    int queueIndex() const;

    QVariantList availableTranscodeFormats() const;
    bool transcoding() const;
    double transcodeProgress() const;
    QString transcodeStatus() const;
    QString transcodeError() const;

    QVariantMap mprisMetadata() const;
    QString mprisLoopStatus() const;

    Q_INVOKABLE void addLibraryFolder(const QString &pathOrUrl);
    Q_INVOKABLE void removeLibraryFolder(const QString &pathOrUrl);
    Q_INVOKABLE void rescanLibrary();
    Q_INVOKABLE void setLibraryView(const QString &mode, const QString &filterValue = {});
    Q_INVOKABLE void setSearch(const QString &search);

    Q_INVOKABLE void playTrack(qlonglong trackId);
    Q_INVOKABLE void playQueueRow(int row);
    Q_INVOKABLE void playAlbum(const QString &album);
    Q_INVOKABLE void playArtist(const QString &artist);
    Q_INVOKABLE void enqueueTrack(qlonglong trackId);
    Q_INVOKABLE void playTrackNext(qlonglong trackId);
    Q_INVOKABLE void removeQueueRow(int row);
    Q_INVOKABLE void clearQueue();
    Q_INVOKABLE void play();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void togglePlayPause();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();
    Q_INVOKABLE void seek(qlonglong positionMs);
    Q_INVOKABLE void seekFraction(double fraction);
    void setVolume(double volume);
    void setShuffle(bool shuffle);
    void setRepeatMode(const QString &mode);

    Q_INVOKABLE void createPlaylist(const QString &name);
    Q_INVOKABLE void renamePlaylist(qlonglong playlistId, const QString &name);
    Q_INVOKABLE void removePlaylist(qlonglong playlistId);
    Q_INVOKABLE void selectPlaylist(qlonglong playlistId);
    Q_INVOKABLE void addTrackToPlaylist(qlonglong playlistId, qlonglong trackId);
    Q_INVOKABLE void removeTrackFromPlaylist(qlonglong playlistId, qlonglong trackId);
    Q_INVOKABLE void playPlaylist(qlonglong playlistId);

    Q_INVOKABLE void transcodeTrack(qlonglong trackId, const QString &outputUrl,
                                    const QString &formatId, bool overwrite = true);
    Q_INVOKABLE void cancelTranscode();
    Q_INVOKABLE void openUri(const QString &uriOrPath);
    Q_INVOKABLE void requestRaise();
    Q_INVOKABLE void clearError();

signals:
    void readyChanged();
    void libraryChanged();
    void playlistsChanged();
    void libraryFoldersChanged();
    void scanningChanged();
    void errorMessageChanged();
    void mprisRegisteredChanged();
    void playbackStateChanged();
    void currentTrackChanged();
    void positionChanged();
    void durationChanged();
    void seekableChanged();
    void volumeChanged();
    void shuffleChanged();
    void repeatModeChanged();
    void queueChanged();
    void transcodeChanged();
    void seeked(qlonglong positionMs);
    void raiseRequested();
    void userMessage(const QString &message);

private slots:
    void scanFinished();

private:
    void setError(const QString &message);
    void startNextScan();
    void refreshLibrary();
    void refreshGroups();
    void refreshPlaylists();
    void refreshQueueModel();
    void refreshPlaylistModel();
    void setQueue(const QList<qint64> &trackIds, int currentIndex);
    void persistQueue();
    void startCurrentTrack();
    void advance(bool fromEndOfStream);
    QList<TrackRecord> tracksForIds(const QList<qint64> &ids) const;
    std::optional<TrackRecord> findTrack(qint64 id) const;
    static QString localPath(const QString &pathOrUrl);

    MusicDatabase m_database;
    PlaybackEngine m_engine;
    Transcoder m_transcoder;
    TrackListModel m_libraryModel;
    TrackListModel m_queueModel;
    TrackListModel m_playlistTracksModel;
    QFutureWatcher<ScanResult> m_scanWatcher;
    MprisService *m_mpris = nullptr;
    QList<TrackRecord> m_tracks;
    QList<qint64> m_queueIds;
    QStringList m_pendingScanRoots;
    QVariantList m_albums;
    QVariantList m_artists;
    QVariantList m_playlists;
    QStringList m_libraryFolders;
    QStringList m_scanWarnings;
    QString m_dataPath;
    QString m_artworkPath;
    QString m_scanStatus = QStringLiteral("Idle");
    QString m_errorMessage;
    QString m_repeatMode = QStringLiteral("none");
    QString m_activeScanRoot;
    qint64 m_selectedPlaylistId = -1;
    int m_queueIndex = -1;
    bool m_ready = false;
    bool m_scanning = false;
    bool m_shuffle = false;
};
