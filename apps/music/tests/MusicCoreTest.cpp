#include "MetadataScanner.h"
#include "LyricsService.h"
#include "MusicDatabase.h"
#include "OnlineMusicProvider.h"
#include "TrackListModel.h"

#include <QDataStream>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QNetworkProxy>
#include <QNetworkReply>
#include <QScopeGuard>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QUrl>
#include <QtTest>

#include <utility>

namespace {

bool writeTestWave(const QString &path)
{
    constexpr quint32 sampleRate = 8000;
    constexpr quint16 channels = 1;
    constexpr quint16 bitsPerSample = 16;
    QByteArray samples(static_cast<qsizetype>(sampleRate / 5 * channels
                                              * bitsPerSample / 8), '\0');
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly))
        return false;
    QDataStream stream(&file);
    stream.setByteOrder(QDataStream::LittleEndian);
    stream.writeRawData("RIFF", 4);
    stream << quint32(36 + samples.size());
    stream.writeRawData("WAVEfmt ", 8);
    stream << quint32(16) << quint16(1) << channels << sampleRate;
    stream << quint32(sampleRate * channels * bitsPerSample / 8);
    stream << quint16(channels * bitsPerSample / 8) << bitsPerSample;
    stream.writeRawData("data", 4);
    stream << quint32(samples.size());
    return stream.writeRawData(samples.constData(), samples.size()) == samples.size();
}

TrackRecord track(QString path, QString title, QString artist = {})
{
    TrackRecord result;
    result.path = std::move(path);
    result.url = QUrl::fromLocalFile(result.path).toString();
    result.title = std::move(title);
    result.artist = std::move(artist);
    result.album = QStringLiteral("Test Album");
    result.albumArtist = result.artist;
    result.fileSize = 100;
    result.modifiedMs = 200;
    result.durationMs = 3000;
    result.format = QStringLiteral("WAV");
    return result;
}

} // namespace

class MusicCoreTest : public QObject {
    Q_OBJECT

private slots:
    void databasePersistsLibraryQueueAndPlaylists();
    void scannerSkipsUnchangedFilesAndRemovesMissingFiles();
    void trackModelFiltersAndSorts();
    void trackModelSupportsMultiFieldUnicodeSearch();
    void trackModelSearchesFiveThousandTracks();
    void onlineSearchMetadataParsesAndPersists();
    void onlineSearchRanksArtistMatches();
    void lrcLyricsParseAndSort();
    void unsavedOnlineTrackLoadsCachedLyrics();
    void cancellingPendingLyricsKeepsReplacement();
    void cancellingPendingSearchDoesNotReportFailure();
};

void MusicCoreTest::databasePersistsLibraryQueueAndPlaylists()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString root = directory.filePath(QStringLiteral("library"));
    QVERIFY(QDir().mkpath(root));
    const QString databasePath = directory.filePath(QStringLiteral("music.sqlite"));

    MusicDatabase database;
    QString error;
    QVERIFY2(database.open(databasePath, &error), qPrintable(error));
    QVERIFY2(database.addLibraryRoot(root, &error), qPrintable(error));
    ScanResult scan;
    scan.rootPath = root;
    scan.changedTracks = {
        track(QDir(root).filePath(QStringLiteral("one.wav")), QStringLiteral("One"),
              QStringLiteral("Alice")),
        track(QDir(root).filePath(QStringLiteral("two.wav")), QStringLiteral("Two"),
              QStringLiteral("Bob")),
    };
    for (const TrackRecord &item : std::as_const(scan.changedTracks))
        scan.visitedPaths.append(item.path);
    QVERIFY2(database.applyScan(scan, &error), qPrintable(error));
    const QList<TrackRecord> tracks = database.allTracks(&error);
    QCOMPARE(tracks.size(), 2);

    const qint64 playlistId = database.createPlaylist(QStringLiteral("Focus"), &error);
    QVERIFY2(playlistId > 0, qPrintable(error));
    QVERIFY(database.addTrackToPlaylist(playlistId, tracks.at(0).id, &error));
    QVERIFY(database.addTrackToPlaylist(playlistId, tracks.at(1).id, &error));
    QCOMPARE(database.playlistTrackIds(playlistId, &error).size(), 2);
    QVERIFY(database.setQueueTrackIds({tracks.at(1).id, tracks.at(0).id}, &error));
    QCOMPARE(database.queueTrackIds(&error), QList<qint64>({tracks.at(1).id,
                                                            tracks.at(0).id}));
    QVERIFY(database.setSetting(QStringLiteral("repeat"), QStringLiteral("playlist"), &error));
    QCOMPARE(database.setting(QStringLiteral("repeat"), {}, &error),
             QStringLiteral("playlist"));
}

void MusicCoreTest::scannerSkipsUnchangedFilesAndRemovesMissingFiles()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString root = directory.filePath(QStringLiteral("library"));
    QVERIFY(QDir().mkpath(root));
    const QString wavePath = QDir(root).filePath(QStringLiteral("tone.wav"));
    QVERIFY(writeTestWave(wavePath));

    MusicDatabase database;
    QString error;
    QVERIFY(database.open(directory.filePath(QStringLiteral("music.sqlite")), &error));
    QVERIFY(database.addLibraryRoot(root, &error));
    const QString artwork = directory.filePath(QStringLiteral("artwork"));
    const ScanResult first = MetadataScanner::scan(root, {}, artwork);
    QCOMPARE(first.visitedPaths.size(), 1);
    QCOMPARE(first.changedTracks.size(), 1);
    QCOMPARE(first.changedTracks.first().title, QStringLiteral("tone"));
    QVERIFY2(database.applyScan(first, &error), qPrintable(error));

    const ScanResult second = MetadataScanner::scan(
        root, database.fingerprints(root, &error), artwork);
    QCOMPARE(second.visitedPaths.size(), 1);
    QCOMPARE(second.changedTracks.size(), 0);
    QVERIFY(database.applyScan(second, &error));
    QCOMPARE(database.allTracks(&error).size(), 1);

    QVERIFY(QFile::remove(wavePath));
    const ScanResult third = MetadataScanner::scan(
        root, database.fingerprints(root, &error), artwork);
    QCOMPARE(third.visitedPaths.size(), 0);
    QVERIFY(database.applyScan(third, &error));
    QCOMPARE(database.allTracks(&error).size(), 0);
}

void MusicCoreTest::trackModelFiltersAndSorts()
{
    TrackRecord zebra = track(QStringLiteral("/tmp/z.wav"), QStringLiteral("Zebra"),
                              QStringLiteral("Alice"));
    zebra.id = 2;
    zebra.addedAt = 10;
    TrackRecord alpha = track(QStringLiteral("/tmp/a.wav"), QStringLiteral("Alpha"),
                              QStringLiteral("Bob"));
    alpha.id = 1;
    alpha.addedAt = 20;

    TrackListModel model;
    model.setTracks({zebra, alpha});
    QCOMPARE(model.trackIdAt(0), 1);
    model.setSearch(QStringLiteral("alice"));
    QCOMPARE(model.count(), 1);
    QCOMPARE(model.trackIdAt(0), 2);
    model.setSearch({});
    model.setMode(QStringLiteral("recent"));
    QCOMPARE(model.trackIdAt(0), 1);
    model.setFilterValue(QStringLiteral("Test Album") + QChar(0x1f)
                         + QStringLiteral("Alice"));
    model.setMode(QStringLiteral("album"));
    QCOMPARE(model.count(), 1);
    QCOMPARE(model.trackIdAt(0), 2);
    model.setFilterValue(QStringLiteral("Bob"));
    model.setMode(QStringLiteral("artist"));
    QCOMPARE(model.count(), 1);
    QCOMPARE(model.trackIdAt(0), 1);
}

void MusicCoreTest::trackModelSupportsMultiFieldUnicodeSearch()
{
    TrackRecord original = track(QStringLiteral("/tmp/sunny.wav"),
                                 QStringLiteral("晴天"));
    original.id = 1;
    original.album = QStringLiteral("叶惠美");
    original.albumArtist = QStringLiteral("周杰伦");
    original.genre = QStringLiteral("流行");

    TrackRecord cover = track(QStringLiteral("/tmp/cover.wav"),
                              QStringLiteral("晴天（翻唱版）"),
                              QStringLiteral("示例歌手"));
    cover.id = 2;
    cover.album = QStringLiteral("翻唱合集");

    TrackRecord compatibility = track(QStringLiteral("/tmp/compat.wav"),
                                      QStringLiteral("ＡＢＣ Song"),
                                      QStringLiteral("Case Artist"));
    compatibility.id = 3;

    TrackListModel model;
    model.setTracks({cover, compatibility, original});
    model.setSearch(QStringLiteral("  晴天   周杰伦  "));
    QCOMPARE(model.count(), 1);
    QCOMPARE(model.trackIdAt(0), 1);

    model.setSearch(QStringLiteral("晴天"));
    QCOMPARE(model.count(), 2);
    QCOMPARE(model.trackIdAt(0), 1); // Exact title ranks above a cover.

    model.setSearch(QStringLiteral("abc case"));
    QCOMPARE(model.count(), 1);
    QCOMPARE(model.trackIdAt(0), 3); // NFKC folds full-width Latin letters.

    QVERIFY(TrackListModel::matchesSearch(
        {QStringLiteral("叶惠美"), QStringLiteral("周杰伦"),
         QStringLiteral("晴天"), QStringLiteral("流行")},
        QStringLiteral("晴天 周杰伦")));
    QVERIFY(!TrackListModel::matchesSearch(
        {QStringLiteral("叶惠美"), QStringLiteral("周杰伦")},
        QStringLiteral("稻香 周杰伦")));

    QSignalSpy resetSpy(&model, &QAbstractItemModel::modelReset);
    model.setView(QStringLiteral("album"),
                  QStringLiteral("叶惠美") + QChar(0x1f) + QStringLiteral("周杰伦"));
    QCOMPARE(resetSpy.size(), 1); // Mode and filter update atomically.
}

void MusicCoreTest::trackModelSearchesFiveThousandTracks()
{
    QList<TrackRecord> tracks;
    tracks.reserve(5000);
    for (int index = 0; index < 5000; ++index) {
        TrackRecord item = track(QStringLiteral("/tmp/%1.wav").arg(index),
                                 QStringLiteral("Track %1").arg(index),
                                 QStringLiteral("Artist %1").arg(index % 50));
        item.id = index + 1;
        item.album = QStringLiteral("Album %1").arg(index % 100);
        tracks.append(item);
    }
    tracks[4321].title = QStringLiteral("晴天");
    tracks[4321].albumArtist = QStringLiteral("周杰伦");

    TrackListModel model;
    model.setTracks(tracks);
    QElapsedTimer timer;
    timer.start();
    model.setSearch(QStringLiteral("晴天 周杰伦"));
    const qint64 elapsed = timer.elapsed();
    QCOMPARE(model.count(), 1);
    QCOMPARE(model.trackIdAt(0), 4322);
    QVERIFY2(elapsed < 1500,
             qPrintable(QStringLiteral("5000-track search took %1 ms").arg(elapsed)));
}

void MusicCoreTest::onlineSearchMetadataParsesAndPersists()
{
    const QByteArray payload = R"JSON({
        "code": 200,
        "result": {"songs": [{
            "id": 347230,
            "name": "Test Song",
            "duration": 215000,
            "artists": [{"name": "Alice"}, {"name": "Bob"}],
            "album": {"id": 99, "name": "Test Album", "picUrl": "https://img.test/cover.jpg"}
        }]}
    })JSON";
    QString error;
    const QList<TrackRecord> parsed = OnlineMusicProvider::parseNeteaseSearch(payload, &error);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    QCOMPARE(parsed.size(), 1);
    QCOMPARE(parsed.first().source, QStringLiteral("wy"));
    QCOMPARE(parsed.first().providerId, QStringLiteral("347230"));
    QCOMPARE(parsed.first().path, QStringLiteral("lx://wy/347230"));
    QCOMPARE(parsed.first().artist, QStringLiteral("Alice / Bob"));
    QVERIFY(parsed.first().url.isEmpty());
    QVERIFY(parsed.first().sourceData.contains(QStringLiteral("songmid")));
    const QJsonObject sourceData =
        QJsonDocument::fromJson(parsed.first().sourceData.toUtf8()).object();
    QCOMPARE(sourceData.value(QStringLiteral("interval")).toString(), QStringLiteral("03:35"));
    const QJsonObject meta = sourceData.value(QStringLiteral("meta")).toObject();
    QCOMPARE(meta.value(QStringLiteral("songId")).toString(), QStringLiteral("347230"));
    QVERIFY(!sourceData.value(QStringLiteral("types")).toArray().isEmpty());
    QVERIFY(sourceData.value(QStringLiteral("_types")).toObject()
                .contains(QStringLiteral("128k")));
    QCOMPARE(meta.value(QStringLiteral("qualitys")).toArray(),
             sourceData.value(QStringLiteral("types")).toArray());
    QCOMPARE(meta.value(QStringLiteral("_qualitys")).toObject(),
             sourceData.value(QStringLiteral("_types")).toObject());
    QVERIFY(sourceData.value(QStringLiteral("typeUrl")).isObject());

    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    MusicDatabase database;
    QVERIFY2(database.open(directory.filePath(QStringLiteral("music.sqlite")), &error),
             qPrintable(error));
    const qint64 id = database.addExternalTrack(parsed.first(), &error);
    QVERIFY2(id > 0, qPrintable(error));
    const std::optional<TrackRecord> stored = database.track(id, &error);
    QVERIFY(stored.has_value());
    QCOMPARE(stored->source, QStringLiteral("wy"));
    QCOMPARE(stored->providerId, QStringLiteral("347230"));
    QCOMPARE(stored->sourceData, parsed.first().sourceData);
    QVERIFY(stored->url.isEmpty());

    TrackRecord updated = parsed.first();
    updated.title = QStringLiteral("Updated title");
    QCOMPARE(database.addExternalTrack(updated, &error), id);
    QCOMPARE(database.track(id, &error)->title, QStringLiteral("Updated title"));
}

void MusicCoreTest::onlineSearchRanksArtistMatches()
{
    const QByteArray payload = R"JSON({
        "code": 200,
        "result": {"songs": [
            {
                "id": 1,
                "name": "晴天（深情版）",
                "duration": 200000,
                "artists": [{"name": "翻唱歌手"}],
                "album": {"id": 1, "name": "翻唱"}
            },
            {
                "id": 2,
                "name": "晴天",
                "duration": 269000,
                "artists": [{"name": "周杰伦"}],
                "album": {"id": 2, "name": "叶惠美"}
            }
        ]}
    })JSON";
    QString error;
    const QList<TrackRecord> parsed =
        OnlineMusicProvider::parseNeteaseSearch(payload, &error,
                                                QStringLiteral("晴天 周杰伦"));
    QVERIFY2(error.isEmpty(), qPrintable(error));
    QCOMPARE(parsed.size(), 2);
    QCOMPARE(parsed.first().providerId, QStringLiteral("2"));
    QCOMPARE(parsed.first().artist, QStringLiteral("周杰伦"));
}

void MusicCoreTest::lrcLyricsParseAndSort()
{
    const QVariantList lines = LyricsService::parseLrc(QStringLiteral(
        "[ar:Artist]\n[00:12.50][00:15.005]Second\n[00:01.2]First\ninvalid"));
    QCOMPARE(lines.size(), 3);
    QCOMPARE(lines.at(0).toMap().value(QStringLiteral("timeMs")).toLongLong(), 1200);
    QCOMPARE(lines.at(0).toMap().value(QStringLiteral("text")).toString(),
             QStringLiteral("First"));
    QCOMPARE(lines.at(1).toMap().value(QStringLiteral("timeMs")).toLongLong(), 12500);
    QCOMPARE(lines.at(2).toMap().value(QStringLiteral("timeMs")).toLongLong(), 15005);
}

void MusicCoreTest::unsavedOnlineTrackLoadsCachedLyrics()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    QFile cache(directory.filePath(QStringLiteral("wy-347230.lrc")));
    QVERIFY(cache.open(QIODevice::WriteOnly));
    const QByteArray cachedLyrics("[00:01.00]Cached online lyric\n");
    QCOMPARE(cache.write(cachedLyrics), cachedLyrics.size());
    cache.close();

    TrackRecord online;
    QCOMPARE(online.id, -1);
    online.source = QStringLiteral("wy");
    online.providerId = QStringLiteral("347230");

    LyricsService lyrics(directory.path());
    lyrics.load(online);

    QCOMPARE(lyrics.lines().size(), 1);
    QCOMPARE(lyrics.lines().first().toMap().value(QStringLiteral("timeMs")).toLongLong(),
             1000);
    QCOMPARE(lyrics.lines().first().toMap().value(QStringLiteral("text")).toString(),
             QStringLiteral("Cached online lyric"));
    QVERIFY(!lyrics.loading());
    QVERIFY(lyrics.errorMessage().isEmpty());
}

void MusicCoreTest::cancellingPendingLyricsKeepsReplacement()
{
    QTemporaryDir directory;
    QFile cached(directory.filePath(QStringLiteral("replacement.lrc")));
    QVERIFY(cached.open(QIODevice::WriteOnly));
    cached.write("[00:01.00]Replacement lyric\n");
    cached.close();
    // Hold the HTTPS CONNECT locally, so cancellation is deterministic and offline.
    QTcpServer proxy;
    QVERIFY(proxy.listen(QHostAddress::LocalHost));
    LyricsService lyrics(directory.path());
    auto *network = lyrics.findChild<QNetworkAccessManager *>();
    QVERIFY(network);
    network->setProxy(QNetworkProxy(QNetworkProxy::HttpProxy, QStringLiteral("127.0.0.1"), proxy.serverPort()));
    TrackRecord online;
    online.id = 1;
    online.source = QStringLiteral("wy");
    online.providerId = QStringLiteral("pending-fixture");
    lyrics.load(online);
    QTRY_VERIFY(proxy.hasPendingConnections());
    QVERIFY(lyrics.loading());
    auto *reply = network->findChild<QNetworkReply *>();
    QVERIFY(reply);
    QSignalSpy finished(reply, &QNetworkReply::finished);
    TrackRecord replacement;
    replacement.id = 2;
    replacement.path = directory.filePath(QStringLiteral("replacement.wav"));
    lyrics.load(replacement);
    QCOMPARE(finished.size(), 1);
    QCOMPARE(lyrics.loadedTrackId(), 2);
    QVERIFY(!lyrics.loading());
    QVERIFY(lyrics.errorMessage().isEmpty());
    QCOMPARE(lyrics.lines().size(), 1);
    QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
    QCOMPARE(lyrics.lines().first().toMap().value(QStringLiteral("text")).toString(), QStringLiteral("Replacement lyric"));
}

void MusicCoreTest::cancellingPendingSearchDoesNotReportFailure()
{
    QTcpServer proxy;
    QVERIFY(proxy.listen(QHostAddress::LocalHost));
    const auto originalProxy = QNetworkProxy::applicationProxy();
    const auto restoreProxy = qScopeGuard([originalProxy] { QNetworkProxy::setApplicationProxy(originalProxy); });
    QNetworkProxy::setApplicationProxy(QNetworkProxy(QNetworkProxy::HttpProxy, QStringLiteral("127.0.0.1"), proxy.serverPort()));
    OnlineMusicProvider provider;
    provider.search(QStringLiteral("pending fixture"));
    QTRY_VERIFY(proxy.hasPendingConnections());
    QVERIFY(provider.searching());
    QSignalSpy errors(&provider, &OnlineMusicProvider::errorMessageChanged);
    QSignalSpy results(&provider, &OnlineMusicProvider::resultsReady);
    provider.search({});
    QVERIFY(!provider.searching());
    QVERIFY(provider.errorMessage().isEmpty());
    QCOMPARE(errors.size(), 0);
    QCOMPARE(results.size(), 1);
}

QTEST_GUILESS_MAIN(MusicCoreTest)

#include "MusicCoreTest.moc"
