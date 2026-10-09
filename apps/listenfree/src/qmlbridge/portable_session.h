#pragma once
#include "infrastructure/database/database.h"
#include "qmlbridge/list_models.h"
#include "qmlbridge/source_controller.h"
#include "media/qmmp_audio_player.h"
#include "media/media_stream_proxy.h"
#include "media/live_stream_relay.h"
#include "media/audio_tail_probe.h"
#include "online/apple_dynamic_artwork_provider.h"
#include "online/lyric_search.h"
#include <QFutureWatcher>
#include <QCache>
#include <QElapsedTimer>
#include <QHash>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QStringList>
#include <QTemporaryDir>
#include <QSet>
#include <memory>
#include <qmmpui/playlistmodel.h>
#include <qmmpui/qmmpuisettings.h>

class QTimer;
class CollectionCoverIndex;

namespace listenfree::qmlbridge {
class PortableSession final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList outputDevices READ outputDevices NOTIFY devicesChanged)
    Q_PROPERTY(QString outputDevice READ outputDevice NOTIFY devicesChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY catalogChanged)
    Q_PROPERTY(bool mockMode READ mockMode CONSTANT)
    Q_PROPERTY(TrackListModel* tracksModel READ tracksModel CONSTANT)
    Q_PROPERTY(QueueModel* queueModel READ queueModel CONSTANT)
    Q_PROPERTY(QVariantList songs READ songs NOTIFY catalogChanged)
    Q_PROPERTY(QVariantList albums READ albums NOTIFY catalogChanged)
    Q_PROPERTY(QVariantList artists READ artists NOTIFY catalogChanged)
    Q_PROPERTY(QVariantList onlinePlaylists READ emptyList CONSTANT)
    Q_PROPERTY(QVariantList myLists READ emptyList CONSTANT)
    Q_PROPERTY(QVariantList comments READ comments NOTIFY commentsChanged)
    Q_PROPERTY(bool commentsBusy READ commentsBusy NOTIFY commentsChanged)
    Q_PROPERTY(QString commentsError READ commentsError NOTIFY commentsChanged)
    Q_PROPERTY(QVariantList lyrics READ lyrics NOTIFY lyricsChanged)
    Q_PROPERTY(QVariantList queueSongs READ queueSongs NOTIFY queueContentsChanged)
    Q_PROPERTY(int currentQueueIndex READ currentQueueIndex NOTIFY queueChanged)
    Q_PROPERTY(QVariantMap currentTrack READ currentTrack NOTIFY currentTrackChanged)
    Q_PROPERTY(QString currentTrackId READ currentTrackId NOTIFY currentTrackChanged)
    Q_PROPERTY(QString dynamicArtworkUrl READ dynamicArtworkUrl NOTIFY artworkChanged)
    Q_PROPERTY(bool dynamicArtworkEnabled READ dynamicArtworkEnabled WRITE setDynamicArtworkEnabled NOTIFY artworkChanged)
    Q_PROPERTY(bool mixing READ mixing NOTIFY progressChanged)
    Q_PROPERTY(QString state READ state NOTIFY changed)
    Q_PROPERTY(qint64 position READ position NOTIFY progressChanged)
    Q_PROPERTY(qint64 duration READ duration NOTIFY changed)
    Q_PROPERTY(bool seekable READ seekable NOTIFY changed)
    Q_PROPERTY(bool live READ live NOTIFY currentTrackChanged)
    Q_PROPERTY(QString radioProgram READ radioProgram NOTIFY changed)
    Q_PROPERTY(float volume READ volume WRITE setVolume NOTIFY changed)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY changed)
    Q_PROPERTY(QString playbackMode READ playbackMode NOTIFY queueChanged)
    Q_PROPERTY(int currentLyricIndex READ currentLyricIndex NOTIFY progressChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY searchResultsChanged)
    Q_PROPERTY(QVariantList searchResults READ searchResults NOTIFY searchResultsChanged)
    Q_PROPERTY(QString searchCategory READ searchCategory WRITE setSearchCategory NOTIFY searchResultsChanged)
    Q_PROPERTY(int searchPage READ searchPage NOTIFY searchResultsChanged)
    Q_PROPERTY(int searchTotal READ searchTotal NOTIFY searchResultsChanged)
    Q_PROPERTY(int searchPageCount READ searchPageCount NOTIFY searchResultsChanged)
    Q_PROPERTY(QString searchError READ searchError NOTIFY searchResultsChanged)
    Q_PROPERTY(QString platform READ platform WRITE setPlatform NOTIFY platformChanged)
    Q_PROPERTY(bool bilibiliSourceEnabled READ bilibiliSourceEnabled NOTIFY bilibiliSourceEnabledChanged)
    Q_PROPERTY(QStringList suggestions READ suggestions NOTIFY suggestionsChanged)
    Q_PROPERTY(QStringList searchHistory READ searchHistory NOTIFY searchHistoryChanged)
    Q_PROPERTY(QVariantMap artistVisual READ artistVisual NOTIFY artistVisualChanged)
    Q_PROPERTY(QString lastQuery READ lastQuery NOTIFY searchResultsChanged)
    Q_PROPERTY(bool equalizerEnabled READ equalizerEnabled NOTIFY equalizerChanged)
    Q_PROPERTY(QVariantList equalizerGains READ equalizerGains NOTIFY equalizerChanged)
    Q_PROPERTY(QVariantList equalizerPresets READ equalizerPresets NOTIFY equalizerChanged)
    Q_PROPERTY(QString equalizerPreset READ equalizerPreset NOTIFY equalizerChanged)
    Q_PROPERTY(double equalizerPreamp READ equalizerPreamp NOTIFY equalizerChanged)
    Q_PROPERTY(bool equalizerAutoHeadroom READ equalizerAutoHeadroom NOTIFY equalizerChanged)
    Q_PROPERTY(double equalizerEffectivePreamp READ equalizerEffectivePreamp NOTIFY equalizerChanged)
    Q_PROPERTY(QVariantMap audioEffects READ audioEffects NOTIFY equalizerChanged)
    Q_PROPERTY(bool audioEffectsAvailable READ audioEffectsAvailable NOTIFY equalizerChanged)
    Q_PROPERTY(QString audioEffectsMessage READ audioEffectsMessage NOTIFY equalizerChanged)
    Q_PROPERTY(QString mediaFormat READ mediaFormat NOTIFY changed)
    Q_PROPERTY(QVariantList lyricCandidates READ lyricCandidates NOTIFY lyricMatchChanged)
    Q_PROPERTY(QVariantList lyricMatchSources READ lyricMatchSources NOTIFY lyricMatchChanged)
    Q_PROPERTY(QString lyricPreview READ lyricPreview NOTIFY lyricPreviewChanged)
    Q_PROPERTY(QVariantList lyricPreviewLines READ lyricPreviewLines NOTIFY lyricPreviewChanged)
    Q_PROPERTY(QString lyricMatchError READ lyricMatchError NOTIFY lyricMatchChanged)
    Q_PROPERTY(bool lyricMatchBusy READ lyricMatchBusy NOTIFY lyricMatchChanged)
    Q_PROPERTY(QVariantList metadataCandidates READ metadataCandidates NOTIFY metadataMatchChanged)
    Q_PROPERTY(bool metadataMatchBusy READ metadataMatchBusy NOTIFY metadataMatchChanged)
    Q_PROPERTY(QString metadataMatchError READ metadataMatchError NOTIFY metadataMatchChanged)
    Q_PROPERTY(QVariantMap metadataArtwork READ metadataArtwork NOTIFY metadataArtworkChanged)
public:
    QVariantMap metadataArtwork() const { return metadataArtwork_; }
    Q_INVOKABLE void previewMetadataArtwork(int index);
    QVariantList metadataCandidates() const { return metadataCandidates_; }
    bool metadataMatchBusy() const { return metadataMatchBusy_; }
    QString metadataMatchError() const { return metadataMatchError_; }
    Q_INVOKABLE void searchMetadataMatches(const QVariantMap& track, const QString& query, const QString& source = "wy");
    Q_INVOKABLE void cancelMetadataMatch();
    Q_INVOKABLE QVariantMap metadataMatchValues(int index, const QStringList& fields) const;
    QVariantList lyricCandidates() const { return lyricSearch_.results(); }
    QVariantList lyricMatchSources() const { return lyricSearch_.sources(); }
    QString lyricPreview() const { return lyricPreview_; }
    QVariantList lyricPreviewLines() const { return lyricPreviewLines_; }
    QString lyricMatchError() const { return lyricSearch_.message(); }
    bool lyricMatchBusy() const { return lyricSearch_.busy(); }
    Q_INVOKABLE QVariantMap lyricMatchSeed(const QVariantMap& track) const;
    Q_INVOKABLE void searchLyricMatches(const QVariantMap& track, const QString& query = {}, const QString& source = "all");
    Q_INVOKABLE void previewLyricMatch(int index);
    Q_INVOKABLE void cancelLyricMatch();
    Q_INVOKABLE void releaseLyricMatch();
    Q_INVOKABLE bool applyLyricMatch(const QVariantMap& track, const QString& lyrics);
    bool equalizerEnabled() const { return equalizerEnabled_; }
    QVariantList equalizerGains() const { return equalizerGains_; }
    QString mediaFormat() const;
    Q_INVOKABLE void setEqualizerEnabled(bool enabled);
    Q_INVOKABLE void setEqualizerBand(int band, double gain);
    Q_INVOKABLE void resetEqualizer();
    QVariantList equalizerPresets() const;
    QString equalizerPreset() const { return equalizerPreset_; }
    double equalizerPreamp() const { return equalizerPreamp_; }
    bool equalizerAutoHeadroom() const { return equalizerAutoHeadroom_; }
    double equalizerEffectivePreamp() const;
    QVariantMap audioEffects() const { return audioEffects_; }
    bool audioEffectsAvailable() const { return audioEffectsAvailable_; }
    QString audioEffectsMessage() const { return audioEffectsMessage_; }
    Q_INVOKABLE void selectEqualizerPreset(const QString& id);
    Q_INVOKABLE bool saveEqualizerPreset(const QString& name, bool overwrite = false);
    Q_INVOKABLE void deleteEqualizerPreset(const QString& id);
    Q_INVOKABLE void setEqualizerPreamp(double db);
    Q_INVOKABLE void setEqualizerAutoHeadroom(bool enabled);
    Q_INVOKABLE void setAudioEffect(const QString& key, const QVariant& value);
    Q_INVOKABLE void setReverbPreset(const QString& id);
    Q_INVOKABLE void resetAudioEffects();
    Q_INVOKABLE void cyclePlaybackMode();
    void setSmartTransition(bool enabled);
    QStringList searchHistory() const { return searchHistory_; }
    Q_INVOKABLE void clearSearchHistory();
    QVariantMap artistVisual() const { return artistVisual_; }
    Q_INVOKABLE void requestArtistVisual(const QString& name);
    PortableSession(infrastructure::database::Database& database, const QString& databasePath,
                    SourceController& sources, QObject* parent = nullptr);
    ~PortableSession() override;
    bool ready() const { return ready_; }
    // Diagnostic for catalog A/B tests; a sparse reload should hydrate only
    // the affected database rows rather than the entire library.
    qsizetype lastCatalogHydratedRows() const noexcept { return lastCatalogHydratedRows_; }
    bool lastCatalogUsedDelta() const noexcept { return lastCatalogUsedDelta_; }
    bool mixing() const { return smartTransition_ && (player_.mixing() ||
        (mixManual_ && !mixTarget_.isEmpty() && state()=="Playing")); }
    bool mockMode() const { return false; }
    TrackListModel* tracksModel() { return &tracks_; }
    QueueModel* queueModel() { return &queueModel_; }
    QVariantList songs() const { return songs_; }
    QVariantList albums() const { return albums_; }
    QVariantList artists() const { return artists_; }
    std::shared_ptr<CollectionCoverIndex> collectionCoverIndex() const { return collectionCoverIndex_; }
    QVariantList emptyList() const { return {}; }
    QVariantList comments() const { return comments_; }
    bool commentsBusy() const { return commentsBusy_; }
    QString commentsError() const { return commentsError_; }
    Q_INVOKABLE void requestComments(const QString& mode = "latest", bool more = false);
    QVariantList lyrics() const;
    QVariantList queueSongs() const { return queueView_; }
    int currentQueueIndex() const { return navigation_.currentIndex(); }
    QVariantMap currentTrack() const;
    QString currentTrackId() const { return currentTrack().value("trackId").toString(); }
    Q_INVOKABLE bool isCurrentTrack(const QVariantMap& track) const;
    QString dynamicArtworkUrl() const { return motionUrl_; }
    bool dynamicArtworkEnabled() const { return motionEnabled_; }
    Q_INVOKABLE void requestArtwork();
    void setDynamicArtworkEnabled(bool enabled);
    QString state() const;
    qint64 position() const { return mediaReady_ ? player_.position().count() : 0; }
    qint64 duration() const { return mediaReady_ && !live() ? player_.duration().count() : 0; }
    bool seekable() const { return mediaReady_ && !live() && player_.seekable(); }
    bool live() const { return currentTrack().value("isLive").toBool(); }
    QString radioProgram() const { return radioProgram_; }
    float volume() const { return player_.volume(); }
    QString errorMessage() const { return error_; }
    QString playbackMode() const { return mode_; }
    int currentLyricIndex() const;
    bool busy() const { return searchBusy_; }
    QVariantList searchResults() const { return searchResults_; }
    QString searchCategory() const { return searchCategory_; }
    void setSearchCategory(const QString& category);
    int searchPage() const { return searchPage_; }
    int searchTotal() const { return searchTotal_; }
    int searchPageCount() const { return platform_ == "bili" ? bilibiliSearchPages_ : searchTotal_ >= 0 ? qMax(1,(searchTotal_+29)/30) : searchPage_+(searchResults_.size()==30 ? 1 : 0); }
    QString searchError() const { return searchError_; }
    Q_INVOKABLE void goToSearchPage(int page);
    QString platform() const { return platform_; }
    bool bilibiliSourceEnabled() const { return bilibiliSourceEnabled_; }
    void setBilibiliSourceEnabled(bool enabled);
    void setPlatform(const QString& platform);
    QStringList suggestions() const { return suggestions_; }
    Q_INVOKABLE void suggest(const QString& text);
    QString lastQuery() const { return query_; }
    QVariantList outputDevices() const;
    QString outputDevice() const;
    Q_INVOKABLE bool selectOutput(const QString& id);
    Q_INVOKABLE void refreshDevices();
    Q_INVOKABLE void clearShuffleHistory();
    // Explicit refresh also checks filesystem-derived local artwork versions.
    Q_INVOKABLE void reload();
    // Use after a known catalog database commit; the journal then bounds reads.
    void reloadCatalogChanges();
    void redirectDuplicates(const QVariantList& redirects);
    void prepareDuplicateMerge(const QVariantList& groups);
    Q_INVOKABLE void play();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();
    Q_INVOKABLE void seek(qint64 position);
    Q_INVOKABLE void setVolume(float value);
    Q_INVOKABLE void toggleMute();
    Q_INVOKABLE bool openTrack(const QVariantMap& track);
    Q_INVOKABLE bool replaceQueueWithList(const QVariantList& tracks, const QVariantMap& selectedTrack);
    Q_INVOKABLE bool enqueueTrack(const QVariantMap& track, bool next = false);
    Q_INVOKABLE void openLocal(const QString& path);
    Q_INVOKABLE void openUrl(const QUrl& url);
    Q_INVOKABLE bool selectQueue(int index, bool playImmediately = true);
    Q_INVOKABLE bool removeFromQueue(int index);
    Q_INVOKABLE bool moveQueue(int from, int to);
    Q_INVOKABLE void clearQueue();
    Q_INVOKABLE void setPlaybackMode(const QString& mode);
    Q_INVOKABLE void search(const QString& query);
    Q_INVOKABLE void playAll(const QVariantList& tracks);
    Q_INVOKABLE void sortTracks(const QString& column, const QString& order);
    Q_INVOKABLE void importSource();
    Q_INVOKABLE QString albumYear(const QString& localPath) const;
    Q_INVOKABLE void shutdown();
    Q_INVOKABLE bool showInExplorer(const QVariantMap& track);
    Q_INVOKABLE bool removeLibraryTrack(const QVariantMap& track, bool trashFile = false);
    Q_INVOKABLE QVariantMap readTrackTags(const QVariantMap& track) const;
    Q_INVOKABLE void requestTrackArtwork(const QVariantMap& track) { fetchOnlineArtwork(track); }
    Q_INVOKABLE bool saveTrackTags(const QVariantMap& track, const QVariantMap& values);
signals:
    void smartMixCommitted(bool mixed);
    void metadataMatchChanged();
    void metadataArtworkChanged();
    void lyricMatchChanged();
    void lyricPreviewChanged();
    void equalizerChanged();
    void trackMetadataChanged(const QVariantMap& track);
    void trackArtworkResolved(const QString& source, const QString& rid, const QString& artwork);
    void searchHistoryChanged();
    void artistVisualChanged();
    void platformChanged();
    void bilibiliSourceEnabledChanged();
    void suggestionsChanged();
    void devicesChanged();
    void changed();
    void progressChanged();
    void catalogChanged();
    void localLibraryChanged();
    void currentTrackChanged();
    void queueChanged();
    void queueContentsChanged();
    void lyricsChanged();
    void commentsChanged();
    void searchResultsChanged();
    void notice(const QString& message);
    void artworkChanged();
private:
    bool enqueueTrackInternal(const QVariantMap& track, bool next, bool allowDuplicate);
    bool appendEndlessTrack();
    void scheduleReload(bool allowDelta);
    QVariantList metadataCandidates_;
    QPointer<QNetworkReply> metadataMatchReply_;
    QPointer<QNetworkReply> metadataArtworkReply_;
    QVariantMap metadataArtwork_;
    quint64 metadataArtworkGeneration_{0};
    int metadataArtworkIndex_{-1};
    std::shared_ptr<QTemporaryDir> metadataArtworkDirectory_{std::make_shared<QTemporaryDir>()};
    QSet<QString> metadataArtworkFiles_;
    void fetchMetadataArtwork(const QUrl& url, quint64 generation);
    bool metadataMatchBusy_{false};
    QString metadataMatchError_;
    QString lyricPreview_;
    QVariantList lyricPreviewLines_;
    QVariantMap pendingEmbeddedLyrics_;
    QFutureWatcher<QString> embeddedLyricWrite_;
    QVariantMap embeddedLyricWriteTags_;
    QString embeddedLyricWritePath_, embeddedLyricWriteText_, decoderLocalPath_;
    QSet<QString> embeddedLyricFailures_;
    void initializeEmbeddedLyrics();
    bool persistEmbeddedLyrics();
    void pumpEmbeddedLyrics();
    void finishEmbeddedLyrics();
    bool equalizerEnabled_{false};
    QVariantList equalizerGains_;
    QString equalizerPreset_{"flat"};
    QVariantList userEqualizerPresets_;
    double equalizerPreamp_{0};
    bool equalizerAutoHeadroom_{true};
    QVariantMap audioEffects_;
    bool audioEffectsAvailable_{false};
    QString audioEffectsMessage_;
    void loadAudioEffects();
    void persistEqualizer();
    void persistAudioEffects();
    void applyEqualizer();
    infrastructure::database::Database& database_;
    QString databasePath_;
    SourceController& sources_;
    std::shared_ptr<CollectionCoverIndex> collectionCoverIndex_;
    QmmpUiSettings uiSettings_;
    PlayListModel navigation_{"ListenFree"};
    QHash<PlayListTrack*, QVariantMap> entries_;
    media::QmmpAudioPlayer player_;
    float lastAudibleVolume_{0.6f};
    std::unique_ptr<media::MediaStreamProxy> proxy_{std::make_unique<media::MediaStreamProxy>()};
    media::LiveStreamRelay liveRelay_;
    QPointer<QNetworkReply> radioReply_;
    QString radioProgram_;
    int radioRetries_{};
    bool radioRetryScheduled_{};
    void resolveRadio();
    online::AppleDynamicArtworkProvider artworkProvider_;
    QString motionUrl_, artworkEntry_;
    bool motionEnabled_{true};
    TrackListModel tracks_;
    QueueModel queueModel_;
    QVariantList songs_, albums_, artists_, queueView_, lyrics_, searchResults_;
    QSet<QString> indexedCoverIdentities_;
    struct LibraryLoadResult {
        QVariantList songs;
        QVariantList albums;
        QVariantList artists;
        QHash<QString, QStringList> coverCandidates;
        QSet<QString> coverIdentities;
        std::vector<domain::Track> repaired;
        quint64 baseCatalogRevision{};
        std::int64_t databaseRevision{-1};
        qsizetype hydratedRows{};
        bool valid{};
        bool noChanges{};
        bool usedDelta{};
        bool sameTrackOrder{};
        QVector<int> changedTrackRows;
    };
    QFutureWatcher<LibraryLoadResult> libraryLoad_;
    quint64 catalogRevision_{};
    std::int64_t databaseRevision_{-1};
    qsizetype lastCatalogHydratedRows_{};
    bool lastCatalogUsedDelta_{};
    bool catalogDatabaseOrder_{true};
    QSet<QString> pendingRepairedTrackIds_;
    QNetworkAccessManager network_;
    online::LyricSearch lyricSearch_{network_};
    QString platform_{"kw"};
    QString searchCategory_{"songs"}, searchError_;
    int searchPage_{1}, searchTotal_{-1};
    bool bilibiliSourceEnabled_{false};
    int bilibiliSearchPages_{1};
    QString bilibiliSearchId_;
    quint64 searchGeneration_{0};
    void requestSearchPage();
    QStringList suggestions_;
    QPointer<QNetworkReply> suggestionReply_;
    QPointer<QNetworkReply> searchReply_, lyricsReply_, commentsReply_;
    QVariantList comments_;
    QString commentsMode_, commentsError_;
    bool commentsBusy_{false};
    QHash<QString,QString> commentMatches_;
    void fetchNeteaseComments(const QString& rid, const QString& entry, const QString& sort, bool more);
    int queueIndexFor(const QVariantMap& track) const;
    void fetchLyrics(const QString& rid);
    QSet<QString> artworkRequests_;
    QCache<QString, QString> artworkUrls_{128};
    QVariantMap artistVisual_;
    QString artistVisualName_;
    QHash<QString,QVariantMap> artistVisualCache_;
    QString pending_, pendingEntry_, error_, mode_, query_;
    QStringList searchHistory_;
    qint64 resumePosition_{0};
    bool resumePaused_{false}, pauseIntent_{false};
    QString duplicateResumeEntry_,duplicateResumeState_;
    qint64 duplicateResumePosition_{0};
    int consecutiveErrors_{0};
    int prematureNetworkRetries_{0};
    bool batching_{false};
    QSet<QString> batchSongKeys_;
    bool loading_{false}, mediaReady_{false}, ready_{false}, searchBusy_{false}, stopped_{false}, reloadAgain_{false};
    bool reloadAgainForceFull_{false};
    bool libraryReloadActive_{false};
    quint64 generation_{0};
    quint64 seekRequest_{0};
    bool smartTransition_{false};
    bool mixAttempted_{false}, mixManual_{false}, mixArmed_{false}, mixAdvance_{true};
    QString mixTarget_, mixResolution_, mixReadyUrl_;
    QVariantMap mixReadyHeaders_;
    int mixIndex_{-1};
    QElapsedTimer mixPreparationClock_;
    qint64 mixCooldown_{0};
    std::unique_ptr<media::MediaStreamProxy> mixProxy_;
    QTimer* mixTimer_{};
    media::AudioTailProbe tailProbe_;
    QString tailProbeSource_;
    qint64 effectiveMixEnd_{-1};
    void resetMixAnalysis();
    void updateSmartMix();
    bool prepareSmartMix(int index, bool manual, bool advanceNavigation = true);
    void queueSmartMix(const QString& url = {}, const QVariantMap& headers = {});
    void cancelSmartMix();
    void commitSmartMix();
    int mixTargetIndex() const;
    void beginCurrent();
    void fetchOnlineArtwork(const QVariantMap& track);
    void invalidate();
    void syncQueue();
    void saveQueue();
    void restoreQueue();
    void startResolved(const QString& url, const QVariantMap& headers = {});
    bool restoreAvailableOutput();
    void fail(const QString& message, bool skipEligible = true);
    void loadLyrics(const QString& path);
    static domain::Track toTrack(const QVariantMap& map);
    static QVariantMap toMap(const domain::Track& track);
};
}
