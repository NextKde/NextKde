#include "qmlbridge/portable_session.h"
#include "qmlbridge/cover_image_provider.h"
#include "infrastructure/library/library_scanner.h"
#include "online/kuwo_lyrics.h"
#include "online/platform_catalog.h"
#include "online/radio_catalog.h"
#include <taglib/fileref.h>
#include <taglib/tpropertymap.h>
#include <taglib/tvariant.h>
#include <taglib/mp4file.h>
#include <taglib/mp4properties.h>
#include <QSaveFile>
#include <cmath>
#include <QDateTime>
#include <QCryptographicHash>
#include <QSettings>
#include <QtConcurrentRun>
#include <QFileDialog>
#include <QFileInfo>
#include <QProcess>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QRegularExpression>
#include <QRandomGenerator>
#include <QTextDocumentFragment>
#include <QTimer>
#include <QThreadPool>
#include <QUuid>
#include <QUrlQuery>
#include <algorithm>
#include <limits>

namespace listenfree::qmlbridge {
namespace {
QString s(const std::string& value) { return QString::fromStdString(value); }
QString plain(const QString& value) { return QTextDocumentFragment::fromHtml(value).toPlainText(); }
QString localArtworkUrl(const QString& path) {
    const QFileInfo info(path);
    return "image://covers/" + QString::fromLatin1(QUrl::toPercentEncoding(path)) + "?v="
        + QString::number(info.lastModified().toMSecsSinceEpoch()) + "-" + QString::number(info.size());
}
QString collectionArtworkUrl(QStringList&& candidates, const QString& identity,
                             const QSet<QString>& retainedIdentities,
                             CollectionCoverIndex::Candidates& index,
                             QSet<QString>& indexedIdentities) {
    if (candidates.isEmpty()) return {};
    if (candidates.size() == 1) {
        const auto direct = candidates.front();
        // Keep the identity alive for a stale multi-candidate request even
        // when this group now has only one track. New singleton groups need no
        // index entry, even in a library with many unique albums.
        if (direct.startsWith("image://covers/") && retainedIdentities.contains(identity)) {
            const auto group = QCryptographicHash::hash(identity.toUtf8(), QCryptographicHash::Sha256).toHex().left(24);
            index.insert(QStringLiteral("collection-index/") + QString::fromLatin1(group), std::move(candidates));
            indexedIdentities.insert(identity);
        }
        return direct;
    }
    for (const auto& url : candidates) {
        if (!url.startsWith("image://covers/")) return url;
    }
    // The identity is stable across reloads; the content hash changes with
    // order, membership and each local file's mtime/size cache token.
    QCryptographicHash content(QCryptographicHash::Sha256);
    for (const auto& candidate : candidates) {
        const auto bytes = candidate.toUtf8();
        content.addData(QByteArray::number(bytes.size()));
        content.addData(QByteArrayView(":"));
        content.addData(bytes);
    }
    const auto version = content.result().toHex().left(24);
    const auto group = QCryptographicHash::hash(identity.toUtf8(), QCryptographicHash::Sha256).toHex().left(24);
    const auto groupId = QStringLiteral("collection-index/") + QString::fromLatin1(group);
    index.insert(groupId, std::move(candidates));
    indexedIdentities.insert(identity);
    return QStringLiteral("image://covers/") + groupId + QLatin1Char('/')
        + QString::fromLatin1(version);
}
struct CatalogAggregates {
    QMap<QString, QVariantMap> albums;
    QMap<QString, QVariantMap> artists;
    QMap<QString, QStringList> albumCovers;
    QMap<QString, QStringList> artistCovers;

    void add(const QVariantMap& row) {
        const auto artist = row.value("artist").toString();
        const auto title = row.value("album").toString();
        const auto albumKey = artist + QChar(0x1f) + title;
        auto& album = albums[albumKey];
        album["title"] = title.isEmpty() ? QStringLiteral("未知专辑") : title;
        album["artist"] = artist;
        album["subtitle"] = artist;
        const auto artwork = row.value("artwork").toString();
        if (!artwork.isEmpty()) {
            albumCovers[albumKey].prepend(artwork);
            artistCovers[artist].prepend(artwork);
        }
        album["cover"] = 0;
        album["count"] = album.value("count").toInt() + 1;
        auto& person = artists[artist];
        person["name"] = artist.isEmpty() ? QStringLiteral("未知艺术家") : artist;
        person["title"] = person["name"];
        person["count"] = person.value("count").toInt() + 1;
        person["cover"] = 0;
    }

    void finish(QVariantList& albumRows, QVariantList& artistRows,
                const QSet<QString>& retainedIdentities,
                CollectionCoverIndex::Candidates& coverIndex,
                QSet<QString>& indexedIdentities) {
        for (auto it = albums.begin(); it != albums.end(); ++it)
            it.value()["artwork"] = collectionArtworkUrl(albumCovers.take(it.key()),
                QStringLiteral("album:") + it.key(), retainedIdentities, coverIndex, indexedIdentities);
        for (auto it = artists.begin(); it != artists.end(); ++it)
            it.value()["artwork"] = collectionArtworkUrl(artistCovers.take(it.key()),
                QStringLiteral("artist:") + it.key(), retainedIdentities, coverIndex, indexedIdentities);
        albumRows.reserve(albums.size());
        for (const auto& album : albums) {
            albumRows.append(album);
            auto& artist = artists[album.value("artist").toString()];
            artist["albumCount"] = artist.value("albumCount").toInt() + 1;
        }
        for (auto it = artists.begin(); it != artists.end(); ++it)
            it.value()["subtitle"] = QStringLiteral("%1 首 · %2 张专辑")
                .arg(it.value().value("count").toInt()).arg(it.value().value("albumCount").toInt());
        artistRows.reserve(artists.size());
        for (const auto& artist : artists) artistRows.append(artist);
    }
};
QString songKey(const QVariantMap& track) {
    if(!track.value("radioId").toString().isEmpty())return "radio:"+track.value("radioProvider").toString()+":"+track.value("radioId").toString();
    const auto path=track.value("localPath").toString();
    if(!path.isEmpty()) return "file:"+QDir::cleanPath(QDir::fromNativeSeparators(QFileInfo(path).absoluteFilePath())).toCaseFolded();
    const auto rid=track.value("rid").toString();
    if(!rid.isEmpty()) return track.value("source").toString().toLower()+":"+rid;
    const auto url=track.value("remoteUrl").toString();
    return url.isEmpty()?QString{}:"url:"+QUrl(url).toString(QUrl::NormalizePathSegments);
}
QString timeLabel(qint64 ms) { return QStringLiteral("%1:%2").arg(ms / 60000, 2, 10, QLatin1Char('0')).arg(ms / 1000 % 60, 2, 10, QLatin1Char('0')); }
QJsonObject kuwoJson(QByteArray bytes) {
    // This endpoint emits single-quoted JSON strings. Convert string tokens,
    // then use the strict JSON parser; never execute the network response.
    QString text = QString::fromUtf8(bytes);
    static const QRegularExpression token("'((?:[^'\\\\]|\\\\.)*)'");
    auto matches = token.globalMatch(text);
    QString converted;
    qsizetype cursor = 0;
    while (matches.hasNext()) {
        const auto match = matches.next();
        converted += text.mid(cursor, match.capturedStart() - cursor);
        auto body = match.captured(1);
        body.replace("\\'", "'");
        body.replace('"', "\\\"");
        converted += '"' + body + '"';
        cursor = match.capturedEnd();
    }
    converted += text.mid(cursor);
    return QJsonDocument::fromJson(converted.toUtf8()).object();
}
}
QVariantMap PortableSession::toMap(const domain::Track& track) {
    const auto duration = static_cast<qint64>(track.duration.count());
    // Catalog rows retain these keys for the session; share their static data
    // instead of allocating identical field names for every track.
    return {{QStringLiteral("trackId"), s(track.id.value())}, {QStringLiteral("title"), s(track.title)},
            {QStringLiteral("artist"), track.artists.empty() ? QString{} : s(track.artists.front().name)},
            {QStringLiteral("album"), track.album ? s(track.album->title) : QString{}},
            {QStringLiteral("durationMs"), duration}, {QStringLiteral("duration"), timeLabel(duration)},
            {QStringLiteral("localPath"), track.localPath ? s(*track.localPath) : QString{}},
            {QStringLiteral("remoteUrl"), track.remoteUrl ? s(*track.remoteUrl) : QString{}},
            {QStringLiteral("artwork"), track.localPath ? localArtworkUrl(s(*track.localPath)) : (track.album && track.album->artworkUrl ? s(*track.album->artworkUrl) : QString{})},
            {QStringLiteral("source"), track.localPath ? QStringLiteral("Local") : QStringLiteral("Online")}};
}
domain::Track PortableSession::toTrack(const QVariantMap& map) {
    domain::Track track;
    track.id = domain::TrackId(map.value("trackId").toString().toStdString());
    track.title = map.value("title").toString().toStdString();
    // Use the same name identities as TagLibMetadataReader. Database upserts
    // replace relations and intentionally reject artists/albums with empty IDs.
    const auto artist = map.value("artist").toString().toStdString();
    if (!artist.empty()) track.artists.push_back({artist, artist});
    const auto album = map.value("album").toString().toStdString();
    track.album = domain::Album{album, album, std::nullopt};
    if (!map.value("artwork").toString().isEmpty()) track.album->artworkUrl = map.value("artwork").toString().toStdString();
    track.duration = std::chrono::milliseconds(map.value("durationMs", map.value("duration")).toLongLong());
    if (!map.value("localPath").toString().isEmpty()) track.localPath = map.value("localPath").toString().toStdString();
    if (!map.value("remoteUrl").toString().isEmpty()) track.remoteUrl = map.value("remoteUrl").toString().toStdString();
    return track;
}
PortableSession::PortableSession(infrastructure::database::Database& database, const QString& path,
                                 SourceController& sources, QObject* parent)
    : QObject(parent), database_(database), databasePath_(path), sources_(sources),
      collectionCoverIndex_(std::make_shared<CollectionCoverIndex>()) {
    // Position ticks are frequent. Keep QML's state, volume, format and error
    // bindings out of that hot path while still refreshing progress whenever a
    // broader playback, track or lyric change affects its derived values.
    connect(this, &PortableSession::changed, this, &PortableSession::progressChanged);
    connect(this, &PortableSession::currentTrackChanged, this, &PortableSession::progressChanged);
    connect(this, &PortableSession::lyricsChanged, this, &PortableSession::progressChanged);
    connect(&lyricSearch_, &online::LyricSearch::changed, this, &PortableSession::lyricMatchChanged);
    uiSettings_.setGroupsEnabled(false);
    QSettings().setValue("ListenFree/clearShuffleHistory",QString::fromStdString(database_.getSetting("playback.clearShuffleHistory").value_or("true"))=="true");
    application::PlaybackEvents events;
    events.onStateChanged = [this](auto state) {
        if (mixTimer_) {
            if (smartTransition_ && state==domain::PlaybackState::Playing) mixTimer_->start();
            else mixTimer_->stop();
        }
        if(state==domain::PlaybackState::Playing){loading_=false;mediaReady_=true;}
        if(state==domain::PlaybackState::Paused)pauseIntent_=false;
        emit changed();
    };
    events.onPositionChanged = [this](auto position) {
        // Qmmp announces Playing before its output thread starts. Restoring a
        // seek/pause then races the output's startup reset; wait for real output.
        if(position.count()>0 && (resumePosition_>0 || resumePaused_)) {
            const auto restore=std::exchange(resumePosition_,0);
            const auto paused=std::exchange(resumePaused_,false);
            const auto gen=generation_;
            QTimer::singleShot(0,this,[this,restore,paused,gen] {
                if(gen!=generation_)return;
                if(restore>0)player_.seek(std::chrono::milliseconds(restore));
                if(paused)player_.pause();
            });
        }
        if(position.count()>5000)consecutiveErrors_=0;
        if(position.count()>30000)radioRetries_=0;
        emit progressChanged();
    };
    events.onDurationChanged = [this](auto) { emit changed(); };
    events.onSeekableChanged = [this](bool) { emit changed(); };
    events.onAudioFormatChanged = [this](auto) { emit changed(); };
    events.onVolumeChanged = [this](auto) { emit changed(); };
    events.onErrorChanged = [this](auto error) {
        if(!error)return;
        if(error->code!=domain::PlaybackErrorCode::Internal){fail(s(error->message));return;}
        // Recreating SoundCore inside its state signal would destroy the sender.
        // Device loss is an output failure, never a reason to skip queue songs.
        const auto generation=generation_;
        QTimer::singleShot(0,this,[this,generation]{
            if(generation!=generation_)return;
            if(restoreAvailableOutput())beginCurrent();
            else fail(QStringLiteral("音频输出不可用，请检查 Windows 输出设备，或在设置中选择其他设备。"),false);
        });
    };
    events.onFinished = [this] {
        const auto generation = generation_;
        QTimer::singleShot(0, this, [this, generation] {
            if (generation != generation_) return;
            if(live()){fail(QStringLiteral("电台连接已中断"));return;}
            const auto track = currentTrack();
            const auto expected = player_.duration().count();
            const auto actual = player_.position().count();
            const bool networkTrack = !track.value("rid").toString().isEmpty() ||
                                       !track.value("remoteUrl").toString().isEmpty();
            if (networkTrack && expected > 0 && actual + 1500 < expected &&
                prematureNetworkRetries_ < 2) {
                ++prematureNetworkRetries_;
                const auto retryGeneration = generation_;
                QTimer::singleShot(300, this, [this, retryGeneration] {
                    if (retryGeneration == generation_) beginCurrent();
                });
                return;
            }
            prematureNetworkRetries_ = 0;
            if (mode_ == "stopAfterCurrent") { stop(); return; }
            if (mode_ == "singleLoop") { beginCurrent(); return; }
            if (mode_ == "endless" && !navigation_.nextTrack()) appendEndlessTrack();
            if (navigation_.nextTrack()) next(); else stop();
        });
    };
    player_.setEvents(std::move(events));
    connect(&liveRelay_,&media::LiveStreamRelay::errorOccurred,this,[this](const QString& message){if(live())fail(message);});
    connect(&player_, &media::QmmpAudioPlayer::streamTitleChanged, this, [this](const QString& title) {
        if (!live()) return;
        const auto program = online::radioProgramTitle(title);
        if (radioProgram_ == program) return;
        radioProgram_ = program;
        emit changed();
    });
    loadAudioEffects();
    connect(&tailProbe_, &media::AudioTailProbe::finished, this, [this](qint64 end) { effectiveMixEnd_=end; });
    mixTimer_ = new QTimer(this);
    mixTimer_->setInterval(50);
    connect(mixTimer_, &QTimer::timeout, this, &PortableSession::updateSmartMix);
    connect(&player_, &media::QmmpAudioPlayer::preparedStarted, this, &PortableSession::commitSmartMix);
    setSmartTransition(database_.getSetting("playback.transition.smart").value_or("false") == "true");
    connect(&sources_, &SourceController::resolutionFinished, this,
            [this](const QString& id, const QString&, const QString&, const QVariantMap& data, const QString& error) {
        if (id == mixResolution_ && !id.isEmpty()) {
            mixResolution_.clear();
            const int manualTarget=mixManual_ ? mixTargetIndex() : -1;
            if (!error.isEmpty()) {
                cancelSmartMix();
                if (manualTarget>=0) { navigation_.setCurrent(manualTarget); beginCurrent(); }
                return;
            }
            const auto url=data.value("url").toString();
            const auto headers=data.value("headers").toMap();
            const auto mixEnd=effectiveMixEnd_>0?effectiveMixEnd_:duration();
            if (!mixManual_ && mixEnd-position()>10000) {
                mixReadyUrl_=url; mixReadyHeaders_=headers;
            } else queueSmartMix(url, headers);
            if (manualTarget>=0 && mixTarget_.isEmpty()) {
                navigation_.setCurrent(manualTarget); beginCurrent();
            }
            return;
        }
        if (id != pending_ || currentTrack().value("entryId").toString() != pendingEntry_) return;
        pending_.clear();
        if (!error.isEmpty()) {
            fail(error, currentTrack().value("source") == "bili" || sources_.hostReady());
            return;
        }
        startResolved(data.value("url").toString(), data.value("headers").toMap());
    });
    connect(&sources_, &SourceController::activeChanged, this, [this] { if (loading_) stop(); });
    connect(&libraryLoad_, &QFutureWatcher<LibraryLoadResult>::finished, this, [this] {
        // Consume the completed snapshot: result() would retain a full prior
        // generation in the watcher until the next scan.
        auto future = libraryLoad_.future();
        auto result = future.takeResult();
        for (const auto& repaired : result.repaired)
            pendingRepairedTrackIds_.insert(s(repaired.id.value()));
        if (reloadAgain_) {
            const bool allowDelta = !reloadAgainForceFull_;
            reloadAgain_ = false;
            reloadAgainForceFull_ = false;
            libraryReloadActive_ = false;
            scheduleReload(allowDelta);
            return;
        }
        if (!result.valid || (result.usedDelta && result.baseCatalogRevision != catalogRevision_)) {
            libraryReloadActive_ = false;
            if (result.usedDelta) scheduleReload(false);
            return;
        }
        if (!pendingRepairedTrackIds_.isEmpty()) {
            int repairedCount = 0;
            for (const auto& id : std::as_const(pendingRepairedTrackIds_)) {
                const auto current = database_.findTrack(domain::TrackId(id.toStdString()));
                if (!current) continue;
                const auto row = toMap(*current);
                for (auto& entry : entries_) if (songKey(entry) == songKey(row)) {
                    for (const auto& key : {"title", "artist", "album"}) entry[key] = row.value(key);
                }
                emit trackMetadataChanged(row);
                ++repairedCount;
            }
            pendingRepairedTrackIds_.clear();
            if (repairedCount) { syncQueue(); emit currentTrackChanged(); }
        }
        if (result.noChanges) {
            libraryReloadActive_ = false;
            return;
        }
        // Keep the previous shared row storage alive across the model swap.
        // Releasing its final 100k-map reference on the GUI thread otherwise
        // stalls the event loop even when no view is reset.
        auto retiredSongs = std::move(songs_);
        const bool preserveIndexes = ready_ && result.baseCatalogRevision == catalogRevision_ && result.sameTrackOrder;
        songs_ = std::move(result.songs);
        albums_ = std::move(result.albums);
        artists_ = std::move(result.artists);
        auto retiredCoverIdentities = std::move(indexedCoverIdentities_);
        indexedCoverIdentities_ = std::move(result.coverIdentities);
        // Image requests may race this swap. Each request takes an implicitly
        // shared candidate list before leaving the index read lock.
        auto retiredCovers = collectionCoverIndex_->replace(std::move(result.coverCandidates));
        if (!preserveIndexes || !tracks_.replaceRowsSameOrder(songs_, result.changedTrackRows))
            tracks_.setRows(songs_);
        ++catalogRevision_;
        databaseRevision_ = result.databaseRevision;
        lastCatalogHydratedRows_ = result.hydratedRows;
        lastCatalogUsedDelta_ = result.usedDelta;
        catalogDatabaseOrder_ = true;
        ready_ = true;
        emit catalogChanged();
        if (!retiredSongs.isEmpty())
            QThreadPool::globalInstance()->start([rows = std::move(retiredSongs)]() mutable { rows.clear(); });
        if (!retiredCovers.isEmpty())
            QThreadPool::globalInstance()->start([covers = std::move(retiredCovers)]() mutable { covers.clear(); });
        if (!retiredCoverIdentities.isEmpty())
            QThreadPool::globalInstance()->start([identities = std::move(retiredCoverIdentities)]() mutable { identities.clear(); });
        libraryReloadActive_ = false;
        if (reloadAgain_) {
            const bool allowDelta = !reloadAgainForceFull_;
            reloadAgain_ = false;
            reloadAgainForceFull_ = false;
            scheduleReload(allowDelta);
        }
    });
    for(const auto& word:QJsonDocument::fromJson(QByteArray::fromStdString(database_.getSetting("search.history").value_or("[]"))).array()) searchHistory_.append(word.toString());
    initializeEmbeddedLyrics();
    restoreQueue();
    restoreAvailableOutput();
    fetchOnlineArtwork(currentTrack());
    reload();
}
PortableSession::~PortableSession() {
    sources_.bilibili().cancel(bilibiliSearchId_);
    shutdown();
    while(!embeddedLyricWritePath_.isEmpty()) { embeddedLyricWrite_.waitForFinished(); finishEmbeddedLyrics(); }
    libraryLoad_.waitForFinished(); player_.setEvents({});
}
void PortableSession::cyclePlaybackMode() {
    const QStringList modes{"listLoop","singleLoop","shuffle","stopAfterCurrent"};
    setPlaybackMode(modes[(modes.indexOf(mode_)+1)%modes.size()]);
}
QString PortableSession::mediaFormat() const {
    const auto track=currentTrack();
    QString codec;
    if(player_.audioFormat())codec=QString::fromStdString(player_.audioFormat()->codec).toUpper();
    if(codec.isEmpty())codec=track.value("format").toString().toUpper();
    const QStringList formats{"FLAC","ALAC","AAC","MP3","OPUS","VORBIS","PCM","APE","WAVPACK"};
    for(const auto& value:formats)if(codec.contains(value))return value=="PCM"?"WAV":value;
    const auto path=track.value("localPath",track.value("remoteUrl")).toString();
    const auto suffix=QFileInfo(QUrl(path).path()).suffix().toUpper();
    return suffix.isEmpty()?QStringLiteral("音频"):suffix;
}

void PortableSession::reload() { scheduleReload(false); }

void PortableSession::reloadCatalogChanges() { scheduleReload(true); }

void PortableSession::scheduleReload(bool allowDelta) {
    if (libraryReloadActive_) {
        reloadAgain_ = true;
        reloadAgainForceFull_ |= !allowDelta;
        return;
    }
    libraryReloadActive_=true;
    const auto path = databasePath_;
    const auto previousSongs = songs_;
    const auto retainedCoverIdentities = indexedCoverIdentities_;
    const auto baseCatalogRevision = catalogRevision_;
    const auto baseDatabaseRevision = databaseRevision_;
    const bool deltaEligible = allowDelta && ready_ && catalogDatabaseOrder_ && baseDatabaseRevision >= 0;
    libraryLoad_.setFuture(QtConcurrent::run([path, previousSongs, retainedCoverIdentities, baseCatalogRevision,
                                              baseDatabaseRevision, deltaEligible] {
        infrastructure::database::Database db;
        LibraryLoadResult result;
        result.baseCatalogRevision = baseCatalogRevision;
        if (!db.openExisting(path)) return result;
        // Repair the old tag-save bug once, off the GUI thread. Only missing
        // relations are restored; audio files and existing metadata stay intact.
        if (db.getSetting("library.metadataRelationsVersion").value_or("") != "1") {
            auto values = db.loadTracks();
            infrastructure::library::TagLibMetadataReader reader;
            for (auto& track : values) {
                if (!track.localPath || (!track.artists.empty() && track.album)) continue;
                const auto mediaPath = QString::fromStdString(*track.localPath);
                if (!QFileInfo(mediaPath).isFile()) continue;
                const auto tags = reader.read(std::filesystem::path(mediaPath.toStdWString()));
                if (!tags) continue;
                bool changed = false;
                if (track.artists.empty() && !tags->artists.empty()) { track.artists = tags->artists; changed = true; }
                if (!track.album && tags->album) { track.album = tags->album; changed = true; }
                if (changed) result.repaired.push_back(track);
            }
            if (result.repaired.empty() || db.restoreMissingRelations(result.repaired)) {
                db.setSetting("library.metadataRelationsVersion", "1");
                // Reflect any concurrent editor save/removal in the published result.
                for (auto it = result.repaired.begin(); it != result.repaired.end();) {
                    if (const auto current = db.findTrack(it->id)) { *it = *current; ++it; }
                    else it = result.repaired.erase(it);
                }
            } else result.repaired.clear();
        }
        // A committed write transaction lists the IDs whose projected rows
        // may have changed. Keep sparse hydration and all map work on this
        // worker. Structural edits still use the full, database-ordered path.
        if (deltaEligible && !previousSongs.isEmpty()) {
            infrastructure::database::CatalogDelta delta;
            constexpr std::size_t maxChangedRows = 256;
            const bool deltaRead = db.readCatalogDelta(baseDatabaseRevision, maxChangedRows, delta);
            if (deltaRead && !delta.requiresFullReload &&
                delta.state.revision == baseDatabaseRevision && delta.changes.empty()) {
                result.databaseRevision = delta.state.revision;
                result.noChanges = true;
                result.valid = true;
                return result;
            }
            if (deltaRead && !delta.requiresFullReload &&
                delta.state.revision > baseDatabaseRevision && !delta.changes.empty()) {
                QHash<QString, qsizetype> indexedRows;
                if (delta.changes.size() > 4) {
                    indexedRows.reserve(previousSongs.size());
                    for (qsizetype row = 0; row < previousSongs.size(); ++row)
                        indexedRows.insert(previousSongs.at(row).toMap().value("trackId").toString(), row);
                }
                QVector<QPair<int, QVariantMap>> updates;
                bool sameOrder = true;
                for (const auto& change : delta.changes) {
                    if (!change.track) { sameOrder = false; break; }
                    const auto id = s(change.trackId);
                    qsizetype row = indexedRows.isEmpty() ? -1 : indexedRows.value(id, -1);
                    if (indexedRows.isEmpty()) {
                        for (qsizetype candidate = 0; candidate < previousSongs.size(); ++candidate) {
                            if (previousSongs.at(candidate).toMap().value("trackId").toString() == id) {
                                row = candidate;
                                break;
                            }
                        }
                    }
                    if (row < 0 || row >= previousSongs.size()) { sameOrder = false; break; }
                    const auto before = previousSongs.at(row).toMap();
                    const auto after = toMap(*change.track);
                    if (before.value("trackId") != after.value("trackId") ||
                        before.value("title") != after.value("title")) {
                        sameOrder = false;
                        break;
                    }
                    if (before != after) updates.append({static_cast<int>(row), after});
                }
                if (sameOrder) {
                    result.songs = previousSongs;
                    std::sort(updates.begin(), updates.end(), [](const auto& left, const auto& right) {
                        return left.first < right.first;
                    });
                    for (const auto& [row, value] : updates) {
                        result.songs[row] = value;
                        result.changedTrackRows.append(row);
                    }
                    CatalogAggregates aggregates;
                    for (const auto& value : result.songs) aggregates.add(value.toMap());
                    aggregates.finish(result.albums, result.artists, retainedCoverIdentities,
                                      result.coverCandidates, result.coverIdentities);
                    result.databaseRevision = delta.state.revision;
                    result.hydratedRows = static_cast<qsizetype>(delta.changes.size());
                    result.sameTrackOrder = true;
                    result.usedDelta = true;
                    result.valid = true;
                    return result;
                }
            }
        }
        // Hydrate one complete track at a time, immediately project it, and
        // keep only the published maps. The model still changes on the GUI
        // thread, while the worker avoids a second full domain catalog.
        CatalogAggregates aggregates;
        const auto project = [&](domain::Track&& track) {
            const auto row = toMap(track);
            result.songs.append(row);
            aggregates.add(row);
        };
        infrastructure::database::CatalogSnapshotState snapshotState;
        if (!db.forEachTrackWithRevision(project, snapshotState)) {
            // A failed stream may have projected a partial catalog. Retry in a
            // fresh SQLite read transaction; never publish loadTracks()'s
            // separate, potentially mixed-generation relation queries.
            result.songs.clear();
            aggregates = {};
            if (!db.forEachTrackWithRevision(project, snapshotState)) return result;
        }
        result.databaseRevision = snapshotState.revision;
        result.hydratedRows = result.songs.size();
        aggregates.finish(result.albums, result.artists, retainedCoverIdentities,
                          result.coverCandidates, result.coverIdentities);
        // All mapping and comparison stays on the read worker. The database
        // primary key guarantees unique track IDs; a missing ID or changed
        // order needs a structural model update and takes the reset path.
        if (!previousSongs.isEmpty() && previousSongs.size() == result.songs.size()) {
            result.sameTrackOrder = true;
            constexpr int maxChangedRows = 256;
            for (qsizetype row = 0; row < result.songs.size(); ++row) {
                const auto& before = previousSongs.at(row);
                const auto& after = result.songs.at(row);
                const auto beforeId = before.toMap().value("trackId").toString();
                if (beforeId.isEmpty() || beforeId != after.toMap().value("trackId").toString()) {
                    result.sameTrackOrder = false;
                    break;
                }
                if (before != after) {
                    result.changedTrackRows.append(static_cast<int>(row));
                    if (result.changedTrackRows.size() > maxChangedRows) {
                        result.sameTrackOrder = false;
                        break;
                    }
                }
            }
            if (!result.sameTrackOrder) result.changedTrackRows.clear();
        }
        result.valid = true;
        return result;
    }));
}
QVariantMap PortableSession::currentTrack() const { return entries_.value(navigation_.currentTrack()); }
QString PortableSession::state() const {
    if (loading_) return "Loading";
    if (!error_.isEmpty()) return "Error";
    switch (player_.state()) {
    case domain::PlaybackState::Playing: return "Playing";
    case domain::PlaybackState::Paused: return "Paused";
    case domain::PlaybackState::Loading: return "Loading";
    case domain::PlaybackState::Buffering: return "Buffering";
    case domain::PlaybackState::Error: return "Error";
    case domain::PlaybackState::Idle: return "Idle";
    default: return "Stopped";
    }
}
void PortableSession::invalidate() {
    resetMixAnalysis();
    cancelSmartMix();
    mixAttempted_=false; mixCooldown_=0;
    radioRetryScheduled_=false;
    pauseIntent_=false;
    ++generation_;
    const auto pending = std::exchange(pending_, {});
    loading_ = false;
    if (!pending.isEmpty()) sources_.cancelResolution(pending);
    if(radioReply_){radioReply_->disconnect(this);radioReply_->abort();radioReply_->deleteLater();radioReply_=nullptr;}
    liveRelay_.cancel();
    player_.stop();
    decoderLocalPath_.clear();
    QTimer::singleShot(0,this,&PortableSession::pumpEmbeddedLyrics);
    proxy_->cancel();
}
void PortableSession::fail(const QString& message, bool skipEligible) {
    if(live() && radioRetryScheduled_)return;
    loading_ = false; error_ = message; emit changed();
    if(live()) {
        if(skipEligible && radioRetries_<3) {
            radioRetryScheduled_=true;
            const int delay=1000*(1<<radioRetries_++);const auto gen=generation_;
            error_=QStringLiteral("直播连接中断，正在重连（%1/3）").arg(radioRetries_);loading_=true;emit changed();
            QTimer::singleShot(delay,this,[this,gen]{if(gen==generation_)beginCurrent();});
        } else {invalidate();emit notice(message+QStringLiteral("，可点击播放重试"));}
        return;
    }
    if(!skipEligible){invalidate();consecutiveErrors_=0;emit notice(message);return;}
    const bool skip = QString::fromStdString(database_.getSetting("playback.skipOnError").value_or("true")) == "true";
    if (skip && ++consecutiveErrors_ < 5 && navigation_.trackCount() > 1) {
        const auto gen = generation_;
        QTimer::singleShot(600, this, [this,gen] { if (gen == generation_) next(); });
    } else emit notice(message + (consecutiveErrors_ >= 5 ? QStringLiteral("（连续失败，已停止）") : QString{}));
}
void PortableSession::beginCurrent() {
    // Decoder timing can still describe the previous source until new media
    // starts. Publish the selected song now, but keep its timeline at zero.
    mediaReady_=false;
    invalidate(); restoreAvailableOutput(); error_.clear(); lyrics_.clear(); emit lyricsChanged();
    radioProgram_.clear();
    if (lyricsReply_) { lyricsReply_->disconnect(this); lyricsReply_->abort(); lyricsReply_->deleteLater(); lyricsReply_=nullptr; }
    if (commentsReply_) { commentsReply_->disconnect(this); commentsReply_->abort(); commentsReply_->deleteLater(); commentsReply_=nullptr; }
    comments_.clear(); commentsMode_.clear(); commentsError_.clear(); commentsBusy_=false; emit commentsChanged();
    motionUrl_.clear(); artworkEntry_.clear(); emit artworkChanged();
    const auto track = currentTrack();
    player_.setLiveBuffering(track.value("isLive").toBool());
    loading_=!track.isEmpty() && track.value("localPath").toString().isEmpty();
    fetchOnlineArtwork(track);
    emit currentTrackChanged(); syncQueue();
    if (track.isEmpty()) { emit changed(); return; }
    if (track.value("radioProvider").toString().startsWith("netease")) {
        resolveRadio();
    } else if (!track.value("rid").toString().isEmpty()) {
        fetchLyrics(track.value("rid").toString());
        pendingEntry_ = track.value("entryId").toString();
        pending_ = sources_.resolveMusicUrl(sources_.activeId(), QString::fromStdString(database_.getSetting("playback.quality").value_or("flac")), online::sourceMusicInfo(track));
        if (pending_.isEmpty())
            fail(sources_.lastError(), track.value("source") == "bili" || sources_.hostReady());
    } else {
        const auto local = track.value("localPath").toString();
        if (!local.isEmpty()) {
            // A file being tagged must finish before a new decoder opens it.
            if(!embeddedLyricWritePath_.isEmpty() && QFileInfo(local)==QFileInfo(embeddedLyricWritePath_)) {
                loading_=true;emit changed();return;
            }
            decoderLocalPath_=QFileInfo(local).absoluteFilePath();
            player_.open({toTrack(track), std::nullopt}); player_.play(); loadLyrics(local);
        } else startResolved(track.value("remoteUrl").toString());
    }
    emit changed();
}
void PortableSession::startResolved(const QString& url, const QVariantMap& headers) {
    const QUrl upstream(url);
    const bool needsRemux=live() && (currentTrack().value("radioHls").toBool() || upstream.path().endsWith(".m3u8",Qt::CaseInsensitive) || upstream.path().endsWith(".flv",Qt::CaseInsensitive));
    const auto proxyUrl = needsRemux ? liveRelay_.publish(upstream) : proxy_->publish(upstream, headers);
    if (proxyUrl.isEmpty()) { fail(QStringLiteral("音源没有返回可播放的 HTTP 地址")); return; }
    player_.open({toTrack(currentTrack()), proxyUrl.toString().toStdString()});
    player_.play(); emit changed();
}
void PortableSession::resolveRadio() {
    const auto row=currentTrack();const bool broadcast=row.value("radioProvider")=="netease-broadcast";
    QUrl url(broadcast?"https://music.163.com/api/voice/broadcast/channel/currentinfo":"https://music.163.com/api/song/enhance/player/url");
    QUrlQuery query;
    if(broadcast)query.addQueryItem("channelId",row.value("radioId").toString());
    else {query.addQueryItem("ids","["+row.value("radioId").toString()+"]");query.addQueryItem("br","128000");}
    url.setQuery(query);QNetworkRequest request(url);request.setTransferTimeout(15000);
    request.setRawHeader("Referer","https://music.163.com/");request.setRawHeader("User-Agent","Mozilla/5.0");
    auto* reply=network_.get(request);radioReply_=reply;const auto gen=generation_;
    connect(reply,&QNetworkReply::finished,this,[this,reply,gen,broadcast]{
        reply->deleteLater();if(gen!=generation_)return;
        const auto root=QJsonDocument::fromJson(reply->readAll()).object();
        const auto entries=root.value("data").toArray();
        const auto data=broadcast?root.value("data").toObject():(entries.isEmpty()?QJsonObject{}:entries.first().toObject());
        const auto url=data.value(broadcast?"playUrl":"url").toString();
        if(reply->error()!=QNetworkReply::NoError || root.value("code").toInt()!=200 || url.isEmpty()) {
            fail(broadcast?QStringLiteral("这个电台暂时没有可用直播地址"):QStringLiteral("这个节目暂不可播放，可能需要登录或订阅"));return;
        }
        radioProgram_=data.value("programName").toString();startResolved(url);emit changed();
    });
}
void PortableSession::play() {
    duplicateResumeEntry_.clear();
    pauseIntent_=false;
    const auto previousPosition=position();
    if(restoreAvailableOutput()){resumePosition_=previousPosition;resumePaused_=false;beginCurrent();return;}
    if (state() == "Paused") { player_.play(); return; }
    if (state() == "Playing" || loading_) return;
    if (navigation_.isEmpty() && !songs_.isEmpty()) { playAll(songs_); return; }
    beginCurrent();
}
void PortableSession::pause() { resetMixAnalysis(); if (!player_.primaryPending()) cancelSmartMix(); duplicateResumeEntry_.clear();if (loading_ || live()) stop(); else {pauseIntent_=state()!="Paused";player_.pause();} }
void PortableSession::stop() { duplicateResumeEntry_.clear();radioRetries_=0;invalidate(); error_.clear(); emit changed(); }
void PortableSession::next() {
    duplicateResumeEntry_.clear();
    // A second click advances from the pending destination, never reuses it.
    if (mixManual_ && mixTargetIndex() >= 0) {
        const int pending = mixTargetIndex();
        cancelSmartMix();
        navigation_.setCurrent(pending);
        invalidate();
    }
    if (mode_ == "endless" && !navigation_.nextTrack()) appendEndlessTrack();
    if (prepareSmartMix(navigation_.indexOf(navigation_.nextTrack()), true)) return;
    const int current=navigation_.currentIndex();int target=-1;
    {const QSignalBlocker blocker(&navigation_);if(navigation_.next())target=navigation_.currentIndex();navigation_.setCurrent(current);}
    invalidate();if(target>=0){navigation_.setCurrent(target);beginCurrent();}else{syncQueue();emit changed();}
}
void PortableSession::previous() {
    duplicateResumeEntry_.clear();
    if (mixManual_ && mixTargetIndex() >= 0) {
        const int pending = mixTargetIndex();
        cancelSmartMix();
        navigation_.setCurrent(pending);
        invalidate();
    }
    const int current=navigation_.currentIndex();int target=current;
    {const QSignalBlocker blocker(&navigation_);if(navigation_.previous())target=navigation_.currentIndex();navigation_.setCurrent(current);}
    if (prepareSmartMix(target, true, false)) return;
    invalidate();navigation_.setCurrent(target);beginCurrent();
}
void PortableSession::seek(qint64 value) {
    if(!seekable())return;
    const int primary=navigation_.currentIndex();
    cancelSmartMix();
    if (navigation_.currentIndex()!=primary) {
        // Seek belongs to the displayed A, even if B has taken over decoding.
        navigation_.setCurrent(primary); resumePosition_=value; resumePaused_=state()=="Paused";
        beginCurrent(); return;
    }
    mixAttempted_=false;
    const auto request = ++seekRequest_;
    if (!currentTrack().value("localPath").toString().isEmpty()) {
        player_.seek(std::chrono::milliseconds(value));
        return;
    }
    // Coalesce rapid online requests before starting a decoder/network seek.
    const auto generation = generation_;
    const auto entry = currentTrack().value("entryId");
    QTimer::singleShot(90, this, [this, request, generation, entry, value] {
        if (request == seekRequest_ && generation == generation_ &&
            entry == currentTrack().value("entryId")) player_.seek(std::chrono::milliseconds(value));
    });
}
void PortableSession::setVolume(float value) {
    player_.setVolume(value);
    const auto actual = player_.volume();
    database_.setSetting("player.volume", QString::number(actual));
    if (actual > 0) {
        lastAudibleVolume_ = actual;
        database_.setSetting("player.unmutedVolume", QString::number(actual));
    }
}
void PortableSession::toggleMute() {
    if (volume() > 0) {
        lastAudibleVolume_ = volume();
        database_.setSetting("player.unmutedVolume", QString::number(lastAudibleVolume_));
        setVolume(0.f);
    } else setVolume(lastAudibleVolume_);
}
bool PortableSession::enqueueTrack(const QVariantMap& value, bool next) {
    return enqueueTrackInternal(value, next, false);
}
bool PortableSession::enqueueTrackInternal(const QVariantMap& value, bool next, bool allowDuplicate) {
    cancelSmartMix(); mixAttempted_=false;
    auto map = value;
    if (map.value("localPath").toString().isEmpty() && map.value("rid").toString().isEmpty() && map.value("remoteUrl").toString().isEmpty() && map.value("radioId").toString().isEmpty()) return false;
    const auto key = songKey(map);
    // The three bulk paths start from an empty queue. Keep their duplicate
    // check linear while preserving the existing lookup for ordinary actions.
    if (batching_ && !next && batchSongKeys_.contains(key)) return true;
    const int existing = allowDuplicate || (batching_ && !next) ? -1 : queueIndexFor(map);
    if(existing>=0) {
        const int current=navigation_.currentIndex();
        if(next && existing!=current) moveQueue(existing,existing<current?current:current+1);
        return true;
    }
    if (!map.value("localPath").toString().isEmpty()) map["artwork"] = localArtworkUrl(map.value("localPath").toString());
    map["entryId"] = QUuid::createUuid().toString(QUuid::WithoutBraces);
    map.remove("resolvedUrl");
    TrackInfo info(map.value("localPath").toString().isEmpty() ? "listenfree:" + map.value("entryId").toString() : map.value("localPath").toString());
    info.setValue(Qmmp::TITLE, map.value("title"));
    info.setValue(Qmmp::ARTIST, map.value("artist"));
    info.setValue(Qmmp::ALBUM, map.value("album"));
    info.setDuration(map.value("durationMs", map.value("duration")).toLongLong());
    auto* track = new PlayListTrack(info);
    const bool firstEntry = navigation_.isEmpty();
    const auto previousQueueSize = queueView_.size();
    entries_.insert(track, map);
    if (next && !navigation_.isEmpty()) navigation_.insertTrack(navigation_.currentIndex() + 1, track);
    else navigation_.addTrack(track);
    if (batching_) batchSongKeys_.insert(key);
    // Ordinary additions are always at the tail. Keep the published list and
    // model in step without rebuilding and resetting every existing row.
    if (!batching_ && !next && queueModel_.rowCount() == previousQueueSize &&
        navigation_.trackCount() == previousQueueSize + 1 &&
        navigation_.track(navigation_.trackCount() - 1) == track) {
        queueView_.append(map);
        if (queueModel_.appendRow(map)) {
            emit queueContentsChanged();
            queueModel_.setCurrentIndex(navigation_.currentIndex());
            saveQueue();
            emit queueChanged();
        } else {
            queueView_.removeLast();
            syncQueue();
        }
    } else syncQueue();
    if (firstEntry && !batching_) emit currentTrackChanged();
    return true;
}
bool PortableSession::appendEndlessTrack() {
    if (songs_.isEmpty()) return false;
    const int count = songs_.size();
    const QString currentPath = currentTrack().value("localPath").toString();
    const int start = QRandomGenerator::global()->bounded(count);
    QVariantMap fallback;
    for (int offset = 0; offset < count; ++offset) {
        const auto candidate = songs_.at((start + offset) % count).toMap();
        const QString path = candidate.value("localPath").toString();
        if (path.isEmpty() || !QFileInfo(path).isFile()) continue;
        if (path != currentPath) return enqueueTrackInternal(candidate, false, true);
        if (fallback.isEmpty()) fallback = candidate;
    }
    return !fallback.isEmpty() && enqueueTrackInternal(fallback, false, true);
}
bool PortableSession::openTrack(const QVariantMap& value) {
    radioRetries_=0;
    if (!enqueueTrack(value)) { fail(QStringLiteral("曲目没有可播放来源")); return false; }
    const int index=queueIndexFor(value);
    if(index==navigation_.currentIndex()) { play(); return true; }
    return selectQueue(index, true);
}
bool PortableSession::replaceQueueWithList(const QVariantList& values, const QVariantMap& selectedTrack) {
    const auto selectedKey = songKey(selectedTrack);
    if (selectedKey.isEmpty()) return false;
    bool containsSelection = false;
    for (const auto& value : values) {
        if (songKey(value.toMap()) == selectedKey) {
            containsSelection = true;
            break;
        }
    }
    if (!containsSelection) return false;

    radioRetries_ = 0;
    clearQueue();
    batchSongKeys_.clear();
    batching_ = true;
    for (const auto& value : values) enqueueTrack(value.toMap());
    batching_ = false;
    batchSongKeys_.clear();
    syncQueue();
    const int selectedIndex = queueIndexFor(selectedTrack);
    return selectedIndex >= 0 && selectQueue(selectedIndex, true);
}
int PortableSession::queueIndexFor(const QVariantMap& track) const {
    const auto key=songKey(track);
    if(key.isEmpty())return -1;
    for(int i=0;i<navigation_.trackCount();++i) if(songKey(entries_.value(navigation_.track(i)))==key)return i;
    return -1;
}
bool PortableSession::isCurrentTrack(const QVariantMap& track) const {
    const auto current = currentTrack();
    if (current.isEmpty() || track.isEmpty()) return false;
    // Share the queue's file / platform identity; titles and row positions are
    // not identities, and resolving an online URL must not change the marker.
    const auto key = songKey(track), currentKey = songKey(current);
    if (!key.isEmpty() && !currentKey.isEmpty()) return key == currentKey;
    const auto id = track.value("trackId").toString();
    return !id.isEmpty() && id == current.value("trackId").toString();
}
void PortableSession::openLocal(const QString& path) {
    for (const auto& value : songs_) if (value.toMap().value("localPath").toString() == path) { openTrack(value.toMap()); return; }
    openTrack({{"trackId", path}, {"title", QFileInfo(path).completeBaseName()}, {"localPath", path}});
}
void PortableSession::openUrl(const QUrl& url) { openTrack({{"trackId", url.toString()}, {"title", url.fileName()}, {"remoteUrl", url.toString()}}); }
bool PortableSession::selectQueue(int index, bool immediately) {
    duplicateResumeEntry_.clear();
    if (index < 0 || index >= navigation_.trackCount()) return false;
    if (immediately && index != navigation_.currentIndex() && prepareSmartMix(index, true)) return true;
    if(immediately){resumePosition_=0;resumePaused_=false;}
    mediaReady_=false;
    invalidate(); navigation_.setCurrent(index); syncQueue(); emit currentTrackChanged();
    if (immediately) beginCurrent();
    return true;
}
bool PortableSession::removeFromQueue(int index) {
    if (index < 0 || index >= navigation_.trackCount()) return false;
    cancelSmartMix(); mixAttempted_=false;
    auto* track = navigation_.track(index); if (!track) return false;
    const bool current = track == navigation_.currentTrack();
    const bool resume = state() == "Playing" || loading_;
    if (current) {mediaReady_=false;invalidate();}
    entries_.remove(track); navigation_.removeTrack(track);
    if (current && !navigation_.isEmpty()) navigation_.setCurrent(std::min(index, navigation_.trackCount() - 1));
    QVariantList nextView;
    for (auto* remaining : navigation_.tracks()) nextView.append(entries_.value(remaining));
    const bool modelRemoved = queueView_.size() == nextView.size() + 1 && queueModel_.removeRow(index);
    queueView_ = std::move(nextView);
    if (!modelRemoved) queueModel_.setRows(queueView_);
    emit queueContentsChanged();
    queueModel_.setCurrentIndex(navigation_.currentIndex());
    saveQueue(); emit queueChanged(); emit currentTrackChanged();
    if (current && resume && !navigation_.isEmpty()) beginCurrent();
    return true;
}
bool PortableSession::moveQueue(int from, int to) {
    if (from < 0 || to < 0 || from >= navigation_.trackCount() || to >= navigation_.trackCount()) return false;
    cancelSmartMix(); mixAttempted_=false;
    auto* movedTrack = navigation_.track(from);
    const auto expectedEntry = entries_.value(movedTrack);
    const auto oldViewRow = queueView_.value(from).toMap();
    const auto oldModelRow = queueModel_.snapshotRows().value(from).toMap();
    navigation_.clearSelection(); navigation_.setSelected(navigation_.track(from)); navigation_.moveTracks(from, to); navigation_.clearSelection();
    // Qmmp may decline a move. Only publish a local row move when its actual
    // destination and row count match the copies we moved from. The command
    // still serializes the complete queue once, at its existing boundary.
    const bool inSync = navigation_.track(to) == movedTrack &&
        queueView_.size() == navigation_.trackCount() &&
        queueModel_.rowCount() == queueView_.size() &&
        oldViewRow == expectedEntry && oldModelRow == oldViewRow;
    if (from != to && inSync && queueModel_.moveRow(from, to)) {
        queueView_.move(from, to);
        emit queueContentsChanged();
        queueModel_.setCurrentIndex(navigation_.currentIndex());
        saveQueue(); emit queueChanged();
    } else syncQueue();
    return true;
}
void PortableSession::clearQueue() { mediaReady_=false;invalidate(); navigation_.clear(); entries_.clear(); lyrics_.clear(); syncQueue(); emit currentTrackChanged(); emit lyricsChanged(); emit changed(); }
void PortableSession::playAll(const QVariantList& values) { clearQueue(); batchSongKeys_.clear(); batching_ = true; for (const auto& value : values) enqueueTrack(value.toMap()); batching_ = false; batchSongKeys_.clear(); syncQueue(); if (!navigation_.isEmpty()) selectQueue(0); }
void PortableSession::setPlaybackMode(const QString& requested) {
    const QString mode = (requested == "repeatAll" || requested == "LoopAll" || requested == "Sequential" || requested == "sequential") ? "listLoop" : (requested == "repeatOne" || requested == "LoopOne") ? "singleLoop" : requested == "Shuffle" ? "shuffle" : requested == "StopAfterCurrent" ? "stopAfterCurrent" : requested == "Endless" ? "endless" : requested;
    if (mode != "listLoop" && mode != "singleLoop" && mode != "shuffle" && mode != "stopAfterCurrent" && mode != "endless") return;
    if (requested == "Sequential" || requested == "sequential") database_.setSetting("playback.defaultMode","LoopAll");
    if (mode == mode_) return;
    cancelSmartMix(); mixAttempted_=false;
    mode_ = mode; uiSettings_.setRepeatableList(mode != "stopAfterCurrent" && mode != "endless"); uiSettings_.setShuffle(mode == "shuffle");
    database_.setSetting("playback.defaultMode",mode=="listLoop"?"LoopAll":mode=="singleLoop"?"LoopOne":mode=="shuffle"?"Shuffle":mode=="endless"?"Endless":"StopAfterCurrent");
    saveQueue(); emit queueChanged();
}
void PortableSession::syncQueue() {
    if (batching_) return;
    QVariantList nextView;
    for (auto* track : navigation_.tracks()) nextView.append(entries_.value(track));
    if (queueView_ != nextView) {
        queueView_ = std::move(nextView);
        queueModel_.setRows(queueView_);
        emit queueContentsChanged();
    }
    queueModel_.setCurrentIndex(navigation_.currentIndex());
    saveQueue(); emit queueChanged();
}
void PortableSession::saveQueue() {
    const QJsonObject state{{"position", static_cast<double>(resumePosition_>0?resumePosition_:position())}, {"items", QJsonArray::fromVariantList(queueView_)}, {"index", navigation_.currentIndex()}, {"mode", mode_}};
    database_.setSetting("portable.queue", QString::fromUtf8(QJsonDocument(state).toJson(QJsonDocument::Compact)));
}
void PortableSession::redirectDuplicates(const QVariantList& redirects) {
    const auto currentPath=QDir::fromNativeSeparators(currentTrack().value("localPath").toString());
    const auto oldPosition=position(); const auto oldState=state();bool currentChanged=false;
    for(const auto& value:redirects) {
        const auto redirect=value.toMap(),from=redirect.value("from").toMap(),to=redirect.value("to").toMap();
        for(auto it=entries_.begin();it!=entries_.end();++it) {
            if(QDir::fromNativeSeparators(it.value().value("localPath").toString()).compare(from.value("path").toString(),Qt::CaseInsensitive)!=0)continue;
            it.value()["localPath"]=to.value("path");it.value()["trackId"]=to.value("id");
            it.value()["artwork"]=localArtworkUrl(to.value("path").toString());
            it.key()->setPath(to.value("path").toString());
            currentChanged|=currentPath.compare(from.value("path").toString(),Qt::CaseInsensitive)==0;
        }
    }
    syncQueue();reloadCatalogChanges();
    if(!duplicateResumeEntry_.isEmpty()) {
        const auto entry=std::exchange(duplicateResumeEntry_,QString{});
        if(currentTrack().value("entryId").toString()==entry && state()!="Playing" && state()!="Paused") {
            resumePosition_=duplicateResumePosition_;resumePaused_=duplicateResumeState_=="Paused";beginCurrent();
        }
    } else if(currentChanged) {
        emit currentTrackChanged();
        if(oldState=="Playing" || oldState=="Paused") {resumePosition_=oldPosition;resumePaused_=oldState=="Paused";beginCurrent();}
    }
}
void PortableSession::prepareDuplicateMerge(const QVariantList& groups) {
    if(state()!="Playing" && state()!="Paused")return;
    const auto track=currentTrack();
    for(const auto& value:groups)for(const auto& duplicate:value.toMap().value("duplicates").toList()) {
        if(QDir::fromNativeSeparators(track.value("localPath").toString()).compare(duplicate.toMap().value("path").toString(),Qt::CaseInsensitive)!=0)continue;
        duplicateResumeEntry_=track.value("entryId").toString();duplicateResumeState_=state();duplicateResumePosition_=position();
        invalidate();emit changed();return;
    }
}
void PortableSession::restoreQueue() {
    const auto raw = database_.getSetting("portable.queue");
    const auto state = raw ? QJsonDocument::fromJson(QByteArray::fromStdString(*raw)).object() : QJsonObject{};
    if (QString::fromStdString(database_.getSetting("playback.restorePosition").value_or("true")) == "true") resumePosition_=static_cast<qint64>(state.value("position").toDouble());
    batchSongKeys_.clear();
    batching_ = true;
    const auto items=state.value("items").toArray();
    const auto selected=items.isEmpty()?QVariantMap{}:items[std::clamp(state.value("index").toInt(),0,int(items.size()-1))].toObject().toVariantMap();
    for (const auto& value : items) enqueueTrack(value.toObject().toVariantMap());
    batching_ = false;
    batchSongKeys_.clear();
    if (!navigation_.isEmpty()) navigation_.setCurrent(std::max(0,queueIndexFor(selected)));
    setPlaybackMode(state.value("mode").toString("listLoop")); syncQueue();
    player_.setVolume(QString::fromStdString(database_.getSetting("player.volume").value_or("0.6")).toFloat());
    lastAudibleVolume_ = volume() > 0 ? volume()
        : QString::fromStdString(database_.getSetting("player.unmutedVolume").value_or("0.6")).toFloat();
    if (!std::isfinite(lastAudibleVolume_) || lastAudibleVolume_ <= 0 || lastAudibleVolume_ > 1) lastAudibleVolume_ = .6f;
}
void PortableSession::shutdown() { if (stopped_) return; stopped_ = true; saveQueue(); invalidate(); pumpEmbeddedLyrics(); }
void PortableSession::importSource() {
    const auto path = QFileDialog::getOpenFileName(nullptr, QStringLiteral("导入 LX 音源"), {}, "JavaScript (*.js *.mjs)");
    if (!path.isEmpty() && !sources_.importLocalFile(path)) emit notice(sources_.lastError());
}
void PortableSession::sortTracks(const QString& column, const QString& order) {
    const bool descending = order.toLower().contains("desc");
    std::stable_sort(songs_.begin(), songs_.end(), [&](const QVariant& a, const QVariant& b) {
        const auto left = a.toMap().value(column).toString(), right = b.toMap().value(column).toString();
        return descending ? QString::localeAwareCompare(left, right) > 0 : QString::localeAwareCompare(left, right) < 0;
    });
    tracks_.setRows(songs_);
    catalogDatabaseOrder_ = false;
    ++catalogRevision_;
    emit catalogChanged();
}
void PortableSession::search(const QString& searchText) {
    query_ = searchText.trimmed(); searchPage_ = 1; searchTotal_ = -1;
    if (!query_.isEmpty() && !query_.startsWith("http")) {
        searchHistory_.removeAll(query_); searchHistory_.prepend(query_); searchHistory_=searchHistory_.mid(0,20);
        database_.setSetting("search.history",QString::fromUtf8(QJsonDocument(QJsonArray::fromStringList(searchHistory_)).toJson(QJsonDocument::Compact)));
        emit searchHistoryChanged();
    }
    if (query_.contains("music.163.com")) { platform_="wy"; emit platformChanged(); }
    else if (query_.contains("kuwo.cn")) { platform_="kw"; emit platformChanged(); }
    requestSearchPage();
}
void PortableSession::setSearchCategory(const QString& category) {
    if (platform_=="bili" && category=="albums") return;
    if (category==searchCategory_ || !QStringList{"songs","playlists","albums"}.contains(category)) return;
    searchCategory_=category; searchPage_=1; searchTotal_=-1; requestSearchPage();
}
void PortableSession::goToSearchPage(int page) {
    if (query_.isEmpty() || page<1 || page>searchPageCount() || page==searchPage_) return;
    searchPage_=page; requestSearchPage();
}
void PortableSession::requestSearchPage() {
    const auto generation=++searchGeneration_;
    sources_.bilibili().cancel(bilibiliSearchId_); bilibiliSearchId_.clear();
    if (searchReply_) {
        auto* previous=searchReply_.data(); searchReply_.clear(); previous->abort();
    }
    searchResults_.clear(); searchError_.clear(); searchBusy_=false;
    if (query_.isEmpty()) { emit searchResultsChanged(); return; }
    if (platform_=="bili") {
        searchBusy_=true; emit searchResultsChanged();
        bilibiliSearchId_=sources_.bilibili().search(query_,searchPage_,searchCategory_,this,
            [this,generation](QVariantMap data,QString error) {
                if (generation!=searchGeneration_) return;
                bilibiliSearchId_.clear(); searchBusy_=false;
                searchResults_=data.value("rows").toList(); searchError_=error;
                searchTotal_=data.value("total",-1).toInt();
                bilibiliSearchPages_=qMax(searchPage_,data.value("pages",1).toInt());
                emit searchResultsChanged();
            });
        return;
    }
    QString operation=searchCategory_=="albums" ? "searchAlbums" : searchCategory_=="playlists" ? "searchPlaylists" : "search";
    QString term=query_;
    bool directSong=false;
    QNetworkReply* reply=nullptr;
    if (searchCategory_=="songs") {
        const auto id=QRegularExpression("(?:[?&]id=|play_detail/|^)([0-9]+)").match(query_);
        if (id.hasMatch() && (platform_=="kw" || platform_=="wy")) {
            directSong=true; term=id.captured(1);
            if (platform_=="wy") operation="song";
            else {
                QUrl url("https://search.kuwo.cn/r.s");QUrlQuery q;
                q.addQueryItem("type","musicinfo");q.addQueryItem("rid","MUSIC_"+term);
                q.addQueryItem("encoding","utf8");q.addQueryItem("rformat","json");url.setQuery(q);
                QNetworkRequest request(url);request.setTransferTimeout(12000);reply=network_.get(request);
            }
        }
    }
    if (!reply) reply=online::platformRequest(network_,platform_,operation,term,"hot",searchPage_,30);
    if (!reply) { searchError_="此平台暂不支持当前分类";emit searchResultsChanged();return; }
    searchReply_=reply;searchBusy_=true;emit searchResultsChanged();
    const auto provider=platform_, category=searchCategory_;
    connect(reply,&QNetworkReply::finished,this,[this,reply,provider,category,directSong] {
        reply->deleteLater();if(searchReply_!=reply)return;
        searchReply_.clear();searchBusy_=false;
        if (reply->error()==QNetworkReply::NoError) {
            const auto data=online::platformJson(reply->readAll());
            searchResults_=online::platformSearchRows(provider,category,data).mid(0,30);
            searchTotal_=directSong ? static_cast<int>(searchResults_.size()) : online::platformSearchTotal(provider,category,data);
            if (data.isEmpty() || (searchResults_.isEmpty() && searchTotal_!=0 &&
                (data.value("code").toVariant().toInt()!=0 && data.value("code").toVariant().toInt()!=200)))
                searchError_="平台暂未返回可用结果，请重试或切换平台";
        } else searchError_="搜索暂不可用，请重试或切换平台";
        emit searchResultsChanged();
        if (category=="songs" && !searchResults_.isEmpty()) fetchOnlineArtwork(searchResults_.first().toMap());
    });
}
void PortableSession::fetchOnlineArtwork(const QVariantMap& track) {
    const auto provider=track.value("source").toString();
    if(provider!="kw" && provider!="wy")return;
    const auto rid=track.value("rid").toString(), key=songKey(track);
    if(!QRegularExpression("^[0-9]+$").match(rid).hasMatch() || !track.value("artwork").toString().isEmpty())return;
    if(const auto* cached=artworkUrls_.object(key)) {
        emit trackArtworkResolved(provider,rid,*cached);
        return;
    }
    if(artworkRequests_.contains(key))return;
    QNetworkReply* reply=nullptr;
    if(provider=="wy")reply=online::platformRequest(network_,provider,"song",rid);
    else {
        // Dedicated cover lookup from the old LX Kuwo provider.
        QUrl url("https://artistpicserver.kuwo.cn/pic.web");QUrlQuery query;
        query.addQueryItem("corp","kuwo");query.addQueryItem("type","rid_pic");query.addQueryItem("pictype","500");
        query.addQueryItem("size","500");query.addQueryItem("rid",rid);url.setQuery(query);
        QNetworkRequest request(url);request.setTransferTimeout(8000);reply=network_.get(request);
    }
    if(!reply)return;
    artworkRequests_.insert(key);
    connect(reply,&QIODevice::readyRead,this,[reply]{if(reply->bytesAvailable()>512*1024)reply->abort();});
    connect(reply,&QNetworkReply::finished,this,[this,reply,key,provider,rid]{
        artworkRequests_.remove(key);reply->deleteLater();
        if(reply->error()!=QNetworkReply::NoError)return;
        QString value;
        if(provider=="wy") {
            const auto rows=online::platformSongs(provider,online::platformJson(reply->readAll()));
            if(!rows.isEmpty())value=rows.first().toMap().value("artwork").toString();
        } else value=QString::fromUtf8(reply->readAll()).trimmed();
        const QUrl cover(value);
        if(!cover.isValid() || cover.host().isEmpty() || (cover.scheme()!="https" && cover.scheme()!="http"))return;
        const auto artwork=cover.toString();
        artworkUrls_.insert(key,new QString(artwork));
        bool queueUpdated=false,searchUpdated=false;
        for(auto& row:entries_)if(songKey(row)==key){row["artwork"]=cover.toString();queueUpdated=true;}
        for(auto& value:searchResults_){auto row=value.toMap();if(songKey(row)!=key)continue;row["artwork"]=cover.toString();value=row;searchUpdated=true;}
        if(queueUpdated){syncQueue();if(songKey(currentTrack())==key)emit currentTrackChanged();}
        if(searchUpdated)emit searchResultsChanged();
        emit trackArtworkResolved(provider,rid,artwork);
    });
}
void PortableSession::loadLyrics(const QString& path) {
    const auto pending=pendingEmbeddedLyrics_.constFind(QFileInfo(path).absoluteFilePath());
    if(pending!=pendingEmbeddedLyrics_.cend()) { lyrics_=online::parseTimedLyrics(pending->toString());emit lyricsChanged();return; }
    QString text;
    QFile file(QFileInfo(path).absolutePath() + '/' + QFileInfo(path).completeBaseName() + ".lrc");
    if (file.open(QIODevice::ReadOnly) && file.size() <= 1024*1024) text=QString::fromUtf8(file.readAll());
    if (text.isEmpty()) {
        const auto native=path.toStdWString();
        TagLib::FileRef audio(native.c_str(), false);
        if (!audio.isNull()) {
            const auto properties=audio.file()->properties();
            for (const auto* key : {"LYRICS", "UNSYNCEDLYRICS"}) {
                if (properties.contains(key) && !properties[key].isEmpty()) {
                    text=QString::fromStdString(properties[key].front().to8Bit(true)); break;
                }
            }
        }
    }
    lyrics_=online::parseTimedLyrics(text); emit lyricsChanged();
}
void PortableSession::fetchLyrics(const QString& rid) {
    const auto track=currentTrack();
    const auto key="lyrics.override."+QString::fromLatin1((track.value("source").toString()+":"+track.value("rid",track.value("trackId")).toString()).toUtf8().toBase64(QByteArray::Base64UrlEncoding));
    if(const auto saved=database_.getSetting(key)){lyrics_=online::parseTimedLyrics(QString::fromStdString(*saved));emit lyricsChanged();return;}
    const auto provider=currentTrack().value("source").toString();
    if(provider!="kw") {
        if(provider!="wy")return;
        const auto entry=currentTrack().value("entryId");
        auto* reply=online::platformRequest(network_,provider,"lyrics",rid);if(!reply)return;lyricsReply_=reply;
        connect(reply,&QNetworkReply::finished,this,[this,reply,entry]{
            reply->deleteLater();if(lyricsReply_!=reply || currentTrack().value("entryId")!=entry)return;lyricsReply_=nullptr;
            const auto object=online::platformJson(reply->readAll());
            lyrics_=online::parseTimedLyrics(object.value("lrc").toObject().value("lyric").toString()+"\n"+object.value("tlyric").toObject().value("lyric").toString());emit lyricsChanged();
        });return;
    }

    if (!QRegularExpression("^[0-9]+$").match(rid).hasMatch()) return;
    const auto query=online::kuwoXor("user=12345,web,web,web&requester=localhost&req=1&rid=MUSIC_"+rid.toLatin1()+"&lrcx=1").toBase64();
    QNetworkRequest request(QUrl("https://newlyric.kuwo.cn/newlyric.lrc?"+QString::fromLatin1(query)));
    request.setTransferTimeout(12000);
    const auto entry=currentTrack().value("entryId").toString();
    auto* reply=network_.get(request); lyricsReply_=reply;
    connect(reply,&QNetworkReply::readyRead,this,[reply] { if (reply->bytesAvailable()>2*1024*1024) reply->abort(); });
    connect(reply,&QNetworkReply::finished,this,[this,reply,entry] {
        const auto bytes=reply->readAll(); reply->deleteLater();
        if (lyricsReply_!=reply || currentTrack().value("entryId").toString()!=entry) return;
        lyricsReply_=nullptr;
        if (reply->error()!=QNetworkReply::NoError) return;
        lyrics_=online::parseTimedLyrics(online::decodeKuwoLyrics(bytes)); emit lyricsChanged();
    });
}
void PortableSession::requestComments(const QString& mode, bool more) {
    const auto track=currentTrack(); const auto rid=track.value("rid").toString();
    if (commentsReply_) { auto* old=commentsReply_.data(); commentsReply_.clear(); old->abort(); }
    const auto sort=(mode=="hot" || mode=="popular")?QString("hot"):QString("latest");
    if (!more || commentsMode_!=sort) comments_.clear();
    commentsMode_=sort; commentsBusy_=true; commentsError_.clear(); emit commentsChanged();
    const auto entry=track.value("entryId").toString();
    if(!track.value("localPath").toString().isEmpty()) {
        const auto key=songKey(track);
        if(commentMatches_.contains(key)) { fetchNeteaseComments(commentMatches_.value(key),entry,sort,more);return; }
        auto* reply=online::platformRequest(network_,"wy","search",track.value("title").toString()+" "+track.value("artist").toString());
        if(!reply){commentsBusy_=false;commentsError_=QStringLiteral("无法查询网易云歌曲");emit commentsChanged();return;}
        commentsReply_=reply;
        connect(reply,&QNetworkReply::finished,this,[this,reply,entry,sort,more,track,key] {
            reply->deleteLater();if(commentsReply_!=reply)return;commentsReply_.clear();
            if(currentTrack().value("entryId").toString()!=entry){commentsBusy_=false;emit commentsChanged();return;}
            const auto normalize=[](QString value){return value.normalized(QString::NormalizationForm_KC).toCaseFolded().remove(QRegularExpression("[\\s\\p{P}\\p{S}]+"));};
            const auto title=normalize(track.value("title").toString()), artist=normalize(track.value("artist").toString());
            QString matched; qint64 best=std::numeric_limits<qint64>::max();
            if(reply->error()==QNetworkReply::NoError) for(const auto& value:online::platformSongs("wy",online::platformJson(reply->readAll()))) {
                const auto row=value.toMap();const auto candidate=normalize(row.value("artist").toString());
                if(title.isEmpty() || artist.isEmpty() || normalize(row.value("title").toString())!=title || candidate.isEmpty())continue;
                if(candidate!=artist && !(candidate.contains(artist) && artist.size()>=3) && !(artist.contains(candidate) && candidate.size()>=3))continue;
                const auto duration=track.value("durationMs").toLongLong(), other=row.value("durationMs").toLongLong();
                const qint64 difference=duration>0 && other>0?qAbs(duration-other):0;
                if(difference>15000)continue;
                const qint64 score=difference+(candidate==artist?0:100000);
                if(score<best){best=score;matched=row.value("rid").toString();}
            }
            if(matched.isEmpty()){commentsBusy_=false;commentsError_=QStringLiteral("未找到匹配的网易云歌曲，可检查本地标题和艺术家标签后重试");emit commentsChanged();return;}
            if(commentMatches_.size()>=128)commentMatches_.clear();
            commentMatches_.insert(key,matched);fetchNeteaseComments(matched,entry,sort,more);
        });return;
    }
    if(track.value("source").toString()=="wy" && !rid.isEmpty()){fetchNeteaseComments(rid,entry,sort,more);return;}
    if(track.value("source").toString()!="kw" || rid.isEmpty()) {
        commentsBusy_=false;commentsError_=QStringLiteral("此歌曲暂无可用评论接口");emit commentsChanged();return;
    }
    const QString type=sort=="hot"?"get_rec_comment":"get_comment";
    QUrl url("https://ncomment.kuwo.cn/com.s"); QUrlQuery query;
    query.setQuery("f=web&type="+type+"&aapiver=1&prod=kwplayer_ar_10.5.2.0&digest=15&sid="+rid+"&start="+QString::number(comments_.size())+"&msgflag=1&count=30&newver=3&uid=0"); url.setQuery(query);
    QNetworkRequest request(url); request.setTransferTimeout(12000);
    request.setRawHeader("User-Agent","Dalvik/2.1.0 (Linux; U; Android 9;)");
    auto* reply=network_.get(request); commentsReply_=reply;
    connect(reply,&QNetworkReply::readyRead,this,[reply] { if (reply->bytesAvailable()>2*1024*1024) reply->abort(); });
    connect(reply,&QNetworkReply::finished,this,[this,reply,entry,sort] {
        const auto bytes=reply->readAll(); reply->deleteLater();
        if (commentsReply_!=reply || currentTrack().value("entryId").toString()!=entry) return;
        commentsReply_=nullptr; commentsBusy_=false;
        const auto root=QJsonDocument::fromJson(bytes).object();
        if (reply->error()!=QNetworkReply::NoError || root.value("code").toVariant().toString()!="200") commentsError_=QStringLiteral("评论加载失败，点击重试");
        else for (const auto& value:root.value(sort=="hot"?"hot_comments":"comments").toArray()) {
            const auto row=value.toObject();
            comments_.append(QVariantMap{{"id",row.value("id").toVariant()},{"user",row.value("u_name").toString()},
                {"body",row.value("msg").toString()},{"likes",row.value("like_num").toVariant()},
                {"time",QDateTime::fromSecsSinceEpoch(row.value("time").toVariant().toLongLong()).toString("yyyy-MM-dd hh:mm")},
                {"avatar",row.value("u_pic").toString()},{"replies",QVariantList{}}});
        }
        emit commentsChanged();
    });
}
void PortableSession::fetchNeteaseComments(const QString& rid,const QString& entry,const QString& sort,bool more) {
    Q_UNUSED(more)
    QUrl url("https://music.163.com/api/v1/resource/"+QString(sort=="hot"?"hotcomments/":"comments/")+"R_SO_4_"+rid);
    QUrlQuery query;query.addQueryItem("limit","30");query.addQueryItem("offset",QString::number(comments_.size()));url.setQuery(query);
    QNetworkRequest request(url);request.setTransferTimeout(12000);
    request.setRawHeader("User-Agent","Mozilla/5.0");request.setRawHeader("Referer","https://music.163.com/");
    auto* reply=network_.get(request);commentsReply_=reply;
    connect(reply,&QNetworkReply::readyRead,this,[reply]{if(reply->bytesAvailable()>2*1024*1024)reply->abort();});
    connect(reply,&QNetworkReply::finished,this,[this,reply,entry,sort]{
        reply->deleteLater();if(commentsReply_!=reply)return;commentsReply_.clear();commentsBusy_=false;
        if(currentTrack().value("entryId").toString()!=entry){emit commentsChanged();return;}
        const auto root=QJsonDocument::fromJson(reply->readAll()).object();
        if(reply->error()!=QNetworkReply::NoError || root.value("code").toInt()!=200)commentsError_=QStringLiteral("网易云评论加载失败，点击重试");
        else {
            QSet<QString> seen;for(const auto& item:comments_)seen.insert(item.toMap().value("id").toString());
            for(const auto& value:root.value(sort=="hot"?"hotComments":"comments").toArray()) {
                const auto row=value.toObject(), user=row.value("user").toObject();
                const auto id=row.value("commentId").toVariant().toString();if(seen.contains(id))continue;seen.insert(id);
                QVariantList replies;for(const auto& nested:row.value("beReplied").toArray()) {
                    const auto r=nested.toObject();replies.append(QVariantMap{{"user",r.value("user").toObject().value("nickname").toString()},{"body",r.value("content").toString()}});
                }
                comments_.append(QVariantMap{{"id",id},{"user",user.value("nickname").toString()},{"avatar",user.value("avatarUrl").toString()},
                    {"body",row.value("content").toString()},{"likes",row.value("likedCount").toInt()},
                    {"time",QDateTime::fromMSecsSinceEpoch(row.value("time").toVariant().toLongLong()).toString("yyyy-MM-dd hh:mm")},{"replies",replies}});
            }
        }
        emit commentsChanged();
    });
}
int PortableSession::currentLyricIndex() const {
    // parseTimedLyrics publishes rows in timestamp order. The lyric cursor is
    // queried on every progress update, including long word-timed tracks.
    const auto next = std::upper_bound(lyrics_.cbegin(), lyrics_.cend(), position(),
        [](qint64 value, const QVariant& row) {
            return value < row.toMap().value("timeMs").toLongLong();
        });
    return static_cast<int>(next - lyrics_.cbegin()) - 1;
}
void PortableSession::setDynamicArtworkEnabled(bool enabled) {
    motionEnabled_ = enabled;
    if (!enabled) { motionUrl_.clear(); artworkEntry_.clear(); }
    else requestArtwork();
    emit artworkChanged();
}
void PortableSession::requestArtwork() {
    if (!motionEnabled_ || live() || !currentTrack().value("radioId").toString().isEmpty()) return;
    const auto map = currentTrack();
    const auto entry = map.value("entryId").toString();
    if (entry.isEmpty() || artworkEntry_ == entry || map.value("artist").toString().isEmpty()) return;
    artworkEntry_ = entry;
    artworkProvider_.fetch({map.value("title").toString(), map.value("artist").toString(), map.value("album").toString()},
        [this, entry](const std::optional<online::AppleDynamicCoverResult>& result) {
            if (!motionEnabled_ || currentTrack().value("entryId").toString() != entry || !result) return;
            motionUrl_ = result->videoUrl; emit artworkChanged();
        });
}
}

namespace listenfree::qmlbridge {
QVariantList PortableSession::outputDevices() const {
    QVariantList list; for (const auto& d : player_.devices()) list.append(QVariantMap{{"label",s(d.name)},{"value",s(d.id)}}); return list;
}
QString PortableSession::outputDevice() const { return s(player_.selectedDeviceId()); }
bool PortableSession::restoreAvailableOutput() {
    const auto selected=player_.selectedDeviceId();
    if(selected=="default")return false;
    const auto devices=player_.devices();
    if(std::any_of(devices.begin(),devices.end(),[&](const auto& device){return device.id==selected;}))return false;
    const auto volume=player_.volume();
    if(!player_.select("default"))return false;
    player_.setVolume(volume);
    database_.setSetting("audio.outputDeviceId","default");
    emit devicesChanged();return true;
}
bool PortableSession::selectOutput(const QString& id) {
    if (id == outputDevice()) {
        const auto devices=player_.devices();
        return std::any_of(devices.begin(),devices.end(),[&](const auto& device){return device.id==id.toStdString();});
    }
    const auto wasState=state(); const bool paused=pauseIntent_ || wasState=="Paused";const auto pos=position(); const auto volume=player_.volume();
    if (!player_.select(id.toStdString())) { emit notice("输出设备不可用"); return false; }
    player_.setVolume(volume);
    if (wasState == "Playing" || wasState == "Paused") { resumePosition_=pos; resumePaused_=paused; beginCurrent(); }
    emit devicesChanged(); return true;
}
void PortableSession::refreshDevices() { player_.refresh(); emit devicesChanged(); }
void PortableSession::clearShuffleHistory() { const auto mode=mode_; setPlaybackMode("listLoop"); setPlaybackMode(mode); }
}

namespace listenfree::qmlbridge {
QVariantList PortableSession::lyrics() const {
    const auto mode=QString::fromStdString(database_.getSetting("lyrics.chineseConversion").value_or("Off"));
    if(mode=="Off")return lyrics_;
    const auto convert=[&](const QString& text) {
        if(text.isEmpty())return text;
        const auto flags=mode=="Traditional"?LCMAP_TRADITIONAL_CHINESE:LCMAP_SIMPLIFIED_CHINESE;
        const int n=LCMapStringEx(L"zh-CN",flags,reinterpret_cast<const wchar_t*>(text.utf16()),int(text.size()),nullptr,0,nullptr,nullptr,0);
        if(n<=0)return text;
        QString result(n,Qt::Uninitialized);
        LCMapStringEx(L"zh-CN",flags,reinterpret_cast<const wchar_t*>(text.utf16()),int(text.size()),reinterpret_cast<wchar_t*>(result.data()),n,nullptr,nullptr,0);return result;
    };
    QVariantList rows;
    for(const auto& value:lyrics_){auto row=value.toMap();row["text"]=convert(row.value("text").toString());row["translation"]=convert(row.value("translation").toString());QVariantList words;for(const auto& v:row.value("words").toList()){auto w=v.toMap();w["text"]=convert(w.value("text").toString());words.append(w);}row["words"]=words;rows.append(row);}return rows;
}
}

namespace listenfree::qmlbridge {
void PortableSession::setPlatform(const QString& value) {
    if((!QStringList{"kw","kg","tx","wy","mg"}.contains(value) && !(value=="bili" && bilibiliSourceEnabled_)) || value==platform_)return;
    QString text=query_;
    if(text.startsWith("http",Qt::CaseInsensitive))text=searchResults_.isEmpty()?QString():searchResults_.first().toMap().value("title").toString();
    platform_=value;
    if (platform_=="bili" && searchCategory_=="albums") searchCategory_="songs";
    suggest({}); emit platformChanged();
    if(!text.isEmpty())search(text);
    else { query_.clear(); searchPage_=1; searchTotal_=-1; requestSearchPage(); }
}
void PortableSession::setBilibiliSourceEnabled(bool enabled) {
    if (bilibiliSourceEnabled_==enabled) return;
    bilibiliSourceEnabled_=enabled;
    if (!enabled && platform_=="bili") setPlatform("kw");
    emit bilibiliSourceEnabledChanged();
}
void PortableSession::suggest(const QString& text) {
    if(suggestionReply_){suggestionReply_->disconnect(this);suggestionReply_->abort();suggestionReply_->deleteLater();suggestionReply_=nullptr;}
    suggestions_.clear();if(text.trimmed().isEmpty()){emit suggestionsChanged();return;}
    emit suggestionsChanged();auto* reply=online::platformRequest(network_,platform_,"suggest",text.trimmed());if(!reply)return;suggestionReply_=reply;const auto provider=platform_;
    connect(reply,&QNetworkReply::finished,this,[this,reply,provider]{reply->deleteLater();if(suggestionReply_!=reply)return;suggestionReply_=nullptr;
        if(reply->error()==QNetworkReply::NoError){suggestions_.append(online::platformSuggestions(provider,online::platformJson(reply->readAll())));suggestions_.removeDuplicates();suggestions_=suggestions_.mid(0,8);}emit suggestionsChanged();});
}
}

namespace listenfree::qmlbridge {
void PortableSession::requestArtistVisual(const QString& name) {
    if(artistVisualName_==name && artistVisual_.value("source")=="apple" && !artistVisual_.value("hero").toString().isEmpty())return;
    artistVisualName_=name;artistVisual_=artistVisualCache_.value(name);artistVisual_["requestedName"]=name;emit artistVisualChanged();
    if(artistVisualCache_.contains(name))return;
    artworkProvider_.fetchArtist(name,[this,name](QVariantMap result){
        if(artistVisualCache_.size()>=24)artistVisualCache_.clear();
        if (result.value("source")=="apple" && !result.value("hero").toString().isEmpty()) artistVisualCache_.insert(name,result);
        if(artistVisualName_==name){artistVisual_=result;artistVisual_["requestedName"]=name;emit artistVisualChanged();}
    });
}
}

namespace listenfree::qmlbridge {
void PortableSession::clearSearchHistory() { searchHistory_.clear();database_.setSetting("search.history","[]");emit searchHistoryChanged(); }
}

namespace listenfree::qmlbridge {
QString PortableSession::albumYear(const QString& path) const {
    if(path.isEmpty())return {};
    TagLib::FileRef file(path.toStdWString().c_str(),false);
    if(file.isNull() || !file.tag() || !file.tag()->year())return {};
    return QString::number(file.tag()->year());
}
}

namespace listenfree::qmlbridge {
bool PortableSession::showInExplorer(const QVariantMap& track) {
    const QFileInfo file(track.value("localPath").toString());
    if(!file.isFile()){emit notice(QStringLiteral("本地文件不存在"));return false;}
    const bool ok=QProcess::startDetached("explorer.exe",{"/select,",QDir::toNativeSeparators(file.absoluteFilePath())});
    if(!ok)emit notice(QStringLiteral("无法打开资源管理器"));
    return ok;
}
bool PortableSession::removeLibraryTrack(const QVariantMap& track,bool trashFile) {
    const auto path=track.value("localPath").toString();
    if(path.isEmpty()){emit notice(QStringLiteral("此操作仅适用于本地歌曲"));return false;}
    if(trashFile) {
        if(songKey(currentTrack())==songKey(track))stop();
        if(!QFile::moveToTrash(path)){emit notice(QStringLiteral("无法移入回收站，请检查文件是否被占用"));return false;}
        const int index=queueIndexFor(track);if(index>=0)removeFromQueue(index);
    }
    if(!database_.removeLocalTrack(path,!trashFile)){emit notice(QStringLiteral("资料库索引更新失败"));return false;}
    reloadCatalogChanges();emit localLibraryChanged();return true;
}
QVariantMap PortableSession::readTrackTags(const QVariantMap& track) const {
    auto result=track;const auto path=track.value("localPath").toString();
    if(path.isEmpty())return result;
    if(!embeddedLyricWritePath_.isEmpty() && QFileInfo(path)==QFileInfo(embeddedLyricWritePath_)) {
        for(auto it=embeddedLyricWriteTags_.cbegin();it!=embeddedLyricWriteTags_.cend();++it)result[it.key()]=it.value();
        result["lyrics"]=pendingEmbeddedLyrics_.value(QFileInfo(path).absoluteFilePath());
        return result;
    }
    TagLib::FileRef file(path.toStdWString().c_str(),true);
    const QFileInfo info(path);
    result["fileSize"]=info.size();result["format"]=info.suffix().toUpper();
    result["modified"]=info.lastModified().toString(Qt::ISODate);
    result["artwork"]=localArtworkUrl(path);
    if(file.isNull()){result["tagError"]="此格式无法读取可编辑标签";return result;}
    if(const auto* audio=file.audioProperties()) {
        result["bitrate"]=audio->bitrate();result["sampleRate"]=audio->sampleRate();result["channels"]=audio->channels();
        result["durationMs"]=audio->lengthInMilliseconds();result["duration"]=timeLabel(audio->lengthInMilliseconds());
    }
    if(auto* mp4=dynamic_cast<TagLib::MP4::File*>(file.file());mp4 && mp4->audioProperties())
        result["format"]=mp4->audioProperties()->codec()==TagLib::MP4::Properties::ALAC?"ALAC":"AAC";
    const auto properties=file.file()->properties();
    for(const auto& pair:QList<QPair<QString,QString>>{{"title","TITLE"},{"artist","ARTIST"},{"album","ALBUM"},{"genre","GENRE"},{"year","DATE"},{"track","TRACKNUMBER"},{"disc","DISCNUMBER"},{"albumArtist","ALBUMARTIST"},{"composer","COMPOSER"},{"comment","COMMENT"},{"lyrics","LYRICS"}}) {
        const auto key=TagLib::String(pair.second.toStdString(),TagLib::String::UTF8);
        result[pair.first]=properties.contains(key)?QString::fromStdString(properties[key].toString(" / ").to8Bit(true)):QString{};
    }
    const auto lyricPath=info.path()+"/"+info.completeBaseName()+".lrc";
    QFile sidecar(lyricPath);
    if(sidecar.open(QIODevice::ReadOnly))result["lyrics"]=QString::fromUtf8(sidecar.readAll());
    const auto pending=pendingEmbeddedLyrics_.constFind(info.absoluteFilePath());
    if(pending!=pendingEmbeddedLyrics_.cend())result["lyrics"]=*pending;
    return result;
}
bool PortableSession::saveTrackTags(const QVariantMap& track,const QVariantMap& values) {
    const auto path=track.value("localPath").toString();
    if(path.isEmpty() || !QFileInfo(path).isFile()){emit notice(QStringLiteral("本地文件不存在"));return false;}
    if(values.contains("lyrics")) {
        const auto previous=readTrackTags(track);
        bool lyricsOnly=true;
        for(auto it=values.cbegin();it!=values.cend();++it)
            if(it.key()!="lyrics" && it.value().toString().trimmed()!=previous.value(it.key()).toString().trimmed())lyricsOnly=false;
        if(lyricsOnly)return applyLyricMatch(track,values.value("lyrics").toString());
    }
    if(!embeddedLyricWritePath_.isEmpty() && QFileInfo(path)==QFileInfo(embeddedLyricWritePath_)) {
        emit notice("正在保存内嵌歌词，请稍后再保存歌曲信息");return false;
    }
    QByteArray coverBytes;
    if (values.contains("artwork")) {
        const auto coverPath = values.value("artwork").toUrl().toLocalFile();
        QFile cover(coverPath);
        if (!metadataArtworkFiles_.contains(coverPath) || !cover.open(QIODevice::ReadOnly) || (coverBytes = cover.readAll()).isEmpty()) {
            emit notice(QStringLiteral("封面草稿已失效，请重新匹配封面")); return false;
        }
    }
    {
        TagLib::FileRef file(path.toStdWString().c_str(),false);
        if(file.isNull()){emit notice(QStringLiteral("无法读取音频标签"));return false;}
        if (!coverBytes.isEmpty()) {
            TagLib::List<TagLib::VariantMap> pictures;
            pictures.append({{"data", TagLib::ByteVector(coverBytes.constData(), unsigned(coverBytes.size()))},
                             {"mimeType", "image/jpeg"}, {"pictureType", "Front Cover"}, {"description", ""}});
            for (const auto& picture : file.complexProperties("PICTURE"))
                if (picture["pictureType"].toString() != "Front Cover") pictures.append(picture);
            if (!file.setComplexProperties("PICTURE", pictures)) {
                emit notice(QStringLiteral("此格式不支持内嵌封面，请取消勾选封面后保存")); return false;
            }
        }
        auto properties=file.file()->properties();
        for(const auto& pair:QList<QPair<QString,QString>>{{"title","TITLE"},{"artist","ARTIST"},{"album","ALBUM"},{"genre","GENRE"},{"year","DATE"},{"track","TRACKNUMBER"},{"disc","DISCNUMBER"},{"albumArtist","ALBUMARTIST"},{"composer","COMPOSER"},{"comment","COMMENT"},{"lyrics","LYRICS"}}) {
            if(!values.contains(pair.first))continue;
            const auto key=TagLib::String(pair.second.toStdString(),TagLib::String::UTF8);
            const auto value=pair.first=="lyrics" ? values.value(pair.first).toString() : values.value(pair.first).toString().trimmed();
            if(value.isEmpty())properties.erase(key);else properties.replace(key,TagLib::StringList(TagLib::String(value.toStdString(),TagLib::String::UTF8)));
        }
        const auto rejected=file.file()->setProperties(properties);
        for(auto it=rejected.begin();it!=rejected.end();++it) {
            if(properties.contains(it->first)) {emit notice(QStringLiteral("文件不支持写入标签：")+QString::fromStdString(it->first.to8Bit(true)));return false;}
        }
        if(!file.save()){emit notice(QStringLiteral("标签保存失败，请检查文件权限或占用"));return false;}
    }
    if(values.contains("lyrics")) {
        const QFileInfo info(path);
        const auto sidecar=info.path()+"/"+info.completeBaseName()+".lrc";
        if(QFileInfo::exists(sidecar)) {
            QSaveFile output(sidecar);const auto bytes=values.value("lyrics").toString().toUtf8();
            if(!output.open(QIODevice::WriteOnly) || output.write(bytes)!=bytes.size() || !output.commit()) {
                emit notice("内嵌歌词已写入，但同名 LRC 文件更新失败，请检查文件权限后重试");return false;
            }
        }
    }
    if(values.contains("lyrics")) {
        pendingEmbeddedLyrics_.remove(QFileInfo(path).absoluteFilePath());persistEmbeddedLyrics();
    }
    auto updated=readTrackTags(track);
    auto stored=database_.findTrack(domain::TrackId(track.value("trackId").toString().toStdString()));
    if(stored) {
        auto changed=toTrack(updated);changed.id=stored->id;changed.localPath=stored->localPath;
        if(!database_.upsertTrack(changed)){emit notice(QStringLiteral("标签已保存，但资料库更新失败"));reload();return false;}
    }
    commentMatches_.remove(songKey(track));
    for(auto& row:entries_)if(songKey(row)==songKey(track))for(auto it=updated.begin();it!=updated.end();++it)row[it.key()]=it.value();
    syncQueue();if(songKey(currentTrack())==songKey(track)){loadLyrics(path);emit currentTrackChanged();}
    emit trackMetadataChanged(updated);
    reloadCatalogChanges();return true;
}
}
