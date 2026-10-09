#include "qmlbridge/collection_service.h"
#include <QJsonArray>
#include <QJsonDocument>
#include <QTemporaryDir>
#include <QTest>
#include <QTimer>
#include <QSignalSpy>
#include <QUrlQuery>
#include <cstring>
#ifdef Q_OS_WIN
#include <qt_windows.h>
#include <psapi.h>
#endif

using namespace listenfree;
namespace {
QJsonObject track(const QString &provider, int id) {
    if (provider == "wy") return {{"id", id}, {"name", QString("Song %1").arg(id)}, {"dt", 180000}};
    return {{"audio_id", id}, {"hash", QString("hash-%1").arg(id)},
            {"filename", QString("Artist - Song %1").arg(id)}, {"duration", 180},
            {"sqhash", QString("flac-%1").arg(id)}};
}
QJsonArray tracks(const QString &provider, int first, int last) {
    QJsonArray result;
    for (int i = first; i <= last; ++i) result.append(track(provider, i));
    return result;
}
class Reply final : public QNetworkReply {
public:
    Reply(const QNetworkRequest &request, QObject *parent) : QNetworkReply(parent) {
        setRequest(request); setUrl(request.url()); open(ReadOnly);
    }
    void complete(const QJsonObject &object, bool failed = false) {
        if (isFinished()) return;
        bytes_ = QJsonDocument(object).toJson(QJsonDocument::Compact);
        if (failed) setError(TemporaryNetworkFailureError, "fixture network failure");
        setFinished(true); emit readyRead(); emit finished();
    }
    void abort() override {
        if (isFinished()) return;
        setError(OperationCanceledError, "cancelled"); complete({});
    }
    qint64 bytesAvailable() const override { return bytes_.size() - cursor_ + QNetworkReply::bytesAvailable(); }
protected:
    qint64 readData(char *data, qint64 length) override {
        const auto count = qMin(length, qint64(bytes_.size() - cursor_));
        if (count <= 0) return -1;
        std::memcpy(data, bytes_.constData() + cursor_, count); cursor_ += count; return count;
    }
private:
    QByteArray bytes_;
    qint64 cursor_{0};
};
class Network final : public QNetworkAccessManager {
public:
    int total{237}, preview{10}, missingFirst{0}, missingLast{0}, badKugouId{0}, alternateVersion{0};
    int failPage{0}, songBatches{0}, repeatPage{0};
    bool holdSongs{false}, logicalFailure{false};
    QList<QUrl> requests;
    QPointer<Reply> held;
    QList<int> pages;
    QList<QStringList> batches;
protected:
    QNetworkReply *createRequest(Operation, const QNetworkRequest &request, QIODevice *) override {
        requests.append(request.url());
        auto *reply = new Reply(request, this);
        const auto path = request.url().path();
        const QUrlQuery query(request.url());
        QJsonObject object;
        bool failed = false;
        if (path.contains("/playlist/detail")) {
            QJsonArray ids;
            for (int i = 1; i <= total; ++i) ids.append(QJsonObject{{"id", i}});
            object = {{"code", 200}, {"playlist", QJsonObject{{"name", "Fixture"}, {"trackCount", total},
                {"trackIds", ids}, {"tracks", tracks("wy", 1, qMin(total, preview))}}}};
        } else if (path.contains("/song/detail")) {
            ++songBatches;
            const auto raw = QJsonDocument::fromJson(query.queryItemValue("ids", QUrl::FullyDecoded).toUtf8()).array();
            QStringList ids; QJsonArray songs;
            for (auto i = raw.size(); i > 0; --i) {
                const int id = raw[i - 1].toInt(); ids.prepend(QString::number(id));
                if (id >= missingFirst && id <= missingLast) continue;
                songs.append(track("wy", id)); // Detail order need not match playlist order.
            }
            batches.append(ids);
            songs.append(track("wy", 999999)); // Unrequested rows must not leak into the playlist.
            failed = failPage == songBatches;
            object = {{"code", failed && logicalFailure ? 403 : 200}, {"songs", songs}};
            if (holdSongs) { held = reply; return reply; }
        } else if (path.startsWith("/plist/list/")) {
            object = {{"info", QJsonObject{{"list", QJsonObject{{"specialname", "Fixture"}, {"imgurl", "https://example.com/{size}.jpg"}}}}},
                {"list", QJsonObject{{"list", QJsonObject{{"total", total}, {"info", tracks("kg", 1, qMin(total, preview))}}}}}};
        } else if (path.endsWith("/special/song")) {
            const int number = query.queryItemValue("page").toInt();
            const int size = query.queryItemValue("pagesize").toInt();
            pages.append(number);
            const int page = number == repeatPage ? number - 1 : number;
            auto songs = tracks("kg", (page - 1) * size + 1, qMin(total, page * size));
            const int invalid = badKugouId - ((page - 1) * size + 1);
            if (invalid >= 0 && invalid < songs.size()) songs[invalid] = QJsonObject{{"filename", "Unavailable"}};
            const int alternate = alternateVersion - ((page - 1) * size + 1);
            if (alternate >= 0 && alternate < songs.size()) {
                auto row = songs[alternate].toObject(); row["audio_id"] = 1; songs[alternate] = row;
            }
            failed = failPage == number;
            object = {{"status", failed && logicalFailure ? 0 : 1}, {"data", QJsonObject{{"total", total}, {"info", songs}}}};
            if (holdSongs) { held = reply; return reply; }
        }
        QTimer::singleShot(0, reply, [reply, object, failed, logical = logicalFailure] { reply->complete(object, failed && !logical); });
        return reply;
    }
};
QVariantMap card(const QString &provider) {
    return {{"id", "fixture"}, {"source", provider}, {"kind", "playlist"}, {"title", "Fixture"},
            {"tracks", QVariantList{QVariantMap{{"rid", "stale"}, {"title", "Old preview"}}}}};
}
QVariantMap favoriteTrack(int id) {
    QVariantMap row{{"trackId", QString("track-%1").arg(id)}, {"title", QString("Favorite %1").arg(id)},
        {"artist", "Fixture artist"}, {"album", "Fixture album"}, {"durationMs", 180000}};
    if (id%2) row.insert("localPath", QString("C:/Fixture/Music/Artist/Album/Track %1.flac").arg(id));
    else { row.insert("source", "wy"); row.insert("rid", QString::number(id)); }
    return row;
}
QVariantList favoriteSnapshot(const QVariantList& tracks) {
    return {QVariantMap{{"id", "liked-tracks"}, {"title", "我喜欢的音乐"}, {"kind", "Local"}, {"tracks", tracks}}};
}
bool storeCollections(infrastructure::database::Database& db, const QVariantList& lists) {
    return db.setSetting("collections.v1", QString::fromUtf8(QJsonDocument(QJsonArray::fromVariantList(lists)).toJson(QJsonDocument::Compact)));
}
}

class CollectionTests final : public QObject {
    Q_OBJECT
private slots:
    void releaseDetailKeepsSavedSongsAndPlaybackSnapshot() {
        QTemporaryDir dir; infrastructure::database::Database db;
        QVERIFY(db.open(dir.filePath("detail.sqlite"))); QVERIFY(db.migrate());
        Network network; qmlbridge::CollectionService service(db, nullptr, &network);
        const QVariantList rows{favoriteTrack(1),favoriteTrack(2)};
        const auto id=service.create("Saved list",rows); QVERIFY(!id.isEmpty());
        const auto saved=service.playlists(); service.open(saved.first().toMap());
        const auto playbackSnapshot=service.detail().value("tracks").toList();
        QSignalSpy changed(&service,&qmlbridge::CollectionService::detailChanged);
        service.releaseDetail(); QVERIFY(service.detail().isEmpty()); QVERIFY(!service.detailBusy());
        QCOMPARE(playbackSnapshot,rows); QCOMPARE(service.playlists(),saved); QCOMPARE(changed.size(),1);
        service.releaseDetail(); QCOMPARE(changed.size(),1); // Repeated route cleanup is inert.
        service.openTitle("Saved list"); QCOMPARE(service.detail().value("tracks").toList(),rows);
        service.open({{"id","empty"},{"kind","Local"},{"tracks",QVariantList{}}});
        service.releaseDetail(); QVERIFY(service.detail().isEmpty());
    }
    void releaseDetailCancelsPending_data() {
        QTest::addColumn<QString>("provider");
        QTest::newRow("wy") << QString("wy"); QTest::newRow("kg") << QString("kg");
    }
    void releaseDetailCancelsPending() {
        QFETCH(QString,provider);
        QTemporaryDir dir; infrastructure::database::Database db;
        QVERIFY(db.open(dir.filePath("detail.sqlite"))); QVERIFY(db.migrate());
        Network network; network.holdSongs=true;
        qmlbridge::CollectionService service(db,nullptr,&network); service.open(card(provider));
        QTRY_VERIFY(network.held); const auto pending=network.held;
        service.releaseDetail(); QVERIFY(pending && pending->isFinished());
        QVERIFY(service.detail().isEmpty()); QVERIFY(!service.detailBusy());
        const auto requests=network.requests.size(); QTest::qWait(20);
        QCOMPARE(network.requests.size(),requests); QVERIFY(service.detail().isEmpty());
        network.holdSongs=false; service.open(card(provider)); QTRY_VERIFY(!service.detailBusy());
        QCOMPARE(service.detail().value("tracks").toList().size(),network.total);
    }
    void favoriteIdentityMatchesStoredSemantics() {
        QTemporaryDir dir; infrastructure::database::Database db;
        QVERIFY(db.open(dir.filePath("favorites.sqlite"))); QVERIFY(db.migrate());
        const QVariantMap local{{"localPath", "C:\\Music\\Album\\Track.FLAC"}, {"trackId", "old-local-id"}};
        const QVariantMap remote{{"source", "WY"}, {"rid", "ABC"}, {"trackId", "old-remote-id"}};
        const QVariantList rows{local, local, remote, QVariantMap{{"trackId", "legacy-id"}}, QVariantMap{}};
        QVERIFY(storeCollections(db, favoriteSnapshot(rows)));
        Network network; qmlbridge::CollectionService service(db, nullptr, &network);
        QVERIFY(service.isTrackLiked({{"localPath", "c:/music/album/track.flac"}, {"trackId", "new-local-id"}}));
        QVERIFY(service.isTrackLiked({{"source", "wy"}, {"rid", "ABC"}, {"trackId", "new-remote-id"}}));
        QVERIFY(!service.isTrackLiked({{"source", "tx"}, {"rid", "ABC"}}));
        QVERIFY(!service.isTrackLiked({{"source", "wy"}, {"rid", "abc"}}));
        QVERIFY(service.isTrackLiked({{"trackId", "legacy-id"}}));
        QVERIFY(!service.isTrackLiked({}));
        QCOMPARE(service.playlists().first().toMap().value("tracks").toList(), rows);
        service.toggleTrackLiked(local); // All duplicate identities must be removed.
        QVERIFY(!service.isTrackLiked(local));
        QVERIFY(service.isTrackLiked(remote));
    }
    void favoriteMembershipFollowsEveryWriteEntry() {
        QTemporaryDir dir; infrastructure::database::Database db;
        QVERIFY(db.open(dir.filePath("favorites.sqlite"))); QVERIFY(db.migrate());
        Network network; qmlbridge::CollectionService service(db, nullptr, &network);
        const auto a=favoriteTrack(1), b=favoriteTrack(2);
        QSignalSpy changed(&service, &qmlbridge::CollectionService::likedTracksChanged);
        service.toggleTrackLiked(a); QVERIFY(service.isTrackLiked(a)); QCOMPARE(changed.size(),1);
        service.toggleTrackLiked(a); QVERIFY(!service.isTrackLiked(a)); QCOMPARE(changed.size(),2);
        service.addTracks("liked-tracks",{a,b});
        QVERIFY(service.isTrackLiked(a)); QVERIFY(service.isTrackLiked(b)); QCOMPARE(changed.size(),3);
        service.removeTrack("liked-tracks",0);
        QVERIFY(!service.isTrackLiked(a)); QVERIFY(service.isTrackLiked(b)); QCOMPARE(changed.size(),4);
        service.remove("liked-tracks"); QVERIFY(!service.isTrackLiked(b)); QCOMPARE(changed.size(),5);
        // Imported/local collection snapshots can also arrive through toggleSaved.
        const auto snapshot=favoriteSnapshot({a}).first().toMap();
        service.toggleSaved(snapshot); QVERIFY(service.isTrackLiked(a)); QCOMPARE(changed.size(),6);
        service.toggleSaved(snapshot); QVERIFY(!service.isTrackLiked(a)); QCOMPARE(changed.size(),7);
        service.toggleTrackLiked(b); QVERIFY(service.isTrackLiked(b)); QCOMPARE(changed.size(),8);
        service.clear(); QVERIFY(!service.isTrackLiked(b)); QCOMPARE(changed.size(),9);
    }
    void favoriteNotificationsIgnoreMetadataAndUnrelatedPlaylists() {
        QTemporaryDir dir; infrastructure::database::Database db;
        QVERIFY(db.open(dir.filePath("favorites.sqlite"))); QVERIFY(db.migrate());
        const auto a=favoriteTrack(1), b=favoriteTrack(2);
        QVERIFY(storeCollections(db, favoriteSnapshot({a,b})));
        Network network; qmlbridge::CollectionService service(db, nullptr, &network);
        QSignalSpy favorites(&service, &qmlbridge::CollectionService::likedTracksChanged);
        QSignalSpy playlists(&service, &qmlbridge::CollectionService::playlistsChanged);
        const auto revision=service.likedTracksRevision();
        service.rename("liked-tracks","Renamed favorite list");
        const auto unrelated=service.create("Other list",{a}); QVERIFY(!unrelated.isEmpty());
        service.addTracks(unrelated,{b}); service.rename(unrelated,"Other title");
        auto edited=a; edited["title"]="New track title"; service.updateTrackMetadata(edited);
        service.remove(unrelated);
        QVERIFY(playlists.size()>=6); QCOMPARE(favorites.size(),0);
        QCOMPARE(service.likedTracksRevision(),revision);
        QVERIFY(service.isTrackLiked(a)); QVERIFY(service.isTrackLiked(b));
        QVERIFY(storeCollections(db,favoriteSnapshot({b,edited,a})));
        service.reloadSaved(); // Reordering/duplicates do not change membership.
        QCOMPARE(favorites.size(),0); QCOMPARE(service.likedTracksRevision(),revision);
        QVERIFY(storeCollections(db,favoriteSnapshot({b})));
        service.reloadSaved(); QCOMPARE(favorites.size(),1);
        QVERIFY(!service.isTrackLiked(a)); QVERIFY(service.isTrackLiked(b));
        QVERIFY(storeCollections(db,{})); service.reloadSaved();
        QVERIFY(!service.isTrackLiked(b)); QCOMPARE(favorites.size(),2);
    }
    void failedFavoriteSaveKeepsPublishedMembership() {
        QTemporaryDir dir; infrastructure::database::Database db;
        QVERIFY(db.open(dir.filePath("favorites.sqlite"))); QVERIFY(db.migrate());
        const auto a=favoriteTrack(1), b=favoriteTrack(2);
        QVERIFY(storeCollections(db,favoriteSnapshot({a})));
        Network network; qmlbridge::CollectionService service(db, nullptr, &network);
        QSignalSpy favorites(&service, &qmlbridge::CollectionService::likedTracksChanged);
        QSignalSpy playlists(&service, &qmlbridge::CollectionService::playlistsChanged);
        QSignalSpy notices(&service, &qmlbridge::CollectionService::notice);
        const auto revision=service.likedTracksRevision();
        db.close(); service.toggleTrackLiked(a); service.toggleTrackLiked(b); service.clear();
        QVERIFY(service.isTrackLiked(a)); QVERIFY(!service.isTrackLiked(b));
        QCOMPARE(favorites.size(),0); QCOMPARE(playlists.size(),0); QCOMPARE(notices.size(),3);
        QCOMPARE(service.likedTracksRevision(),revision);
    }
    void favoriteLookupBenchmark_data() {
        QTest::addColumn<int>("count");
        for (int count : {100, 1000, 10000}) QTest::newRow(qPrintable(QString::number(count))) << count;
    }
    void favoriteLookupBenchmark() {
        if (!qEnvironmentVariableIsSet("LISTENFREE_BENCH_FAVORITES")) QSKIP("Opt-in favorite lookup benchmark");
        QFETCH(int, count);
        QTemporaryDir dir; infrastructure::database::Database db;
        QVERIFY(db.open(dir.filePath("favorites.sqlite"))); QVERIFY(db.migrate());
        QVariantList rows;
        for (int i=0; i<count; ++i) rows.append(favoriteTrack(i));
        QVERIFY(storeCollections(db, favoriteSnapshot(rows)));
        Network network;
#ifdef Q_OS_WIN
        PROCESS_MEMORY_COUNTERS_EX before{}, after{};
        GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&before), sizeof(before));
#endif
        qmlbridge::CollectionService service(db, nullptr, &network);
        QVariantList queries;
        for (int i=0; i<64; ++i) {
            const int index = i%4==0 ? 0 : i%4==1 ? count/2+i/4 : i%4==2 ? count-1-i/4 : count+i;
            queries.append(favoriteTrack(index));
        }
        int matched=0;
        QBENCHMARK {
            matched=0;
            for (const auto& query : queries) matched += service.isTrackLiked(query.toMap()) ? 1 : 0;
        }
        QCOMPARE(matched,48);
#ifdef Q_OS_WIN
        GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&after), sizeof(after));
        qInfo().noquote() << "FAVORITE_MEMORY" << count << "privateBytes" << after.PrivateUsage
            << "serviceDeltaBytes" << qint64(after.PrivateUsage)-qint64(before.PrivateUsage);
#endif
    }
    void fullPlaylist_data() {
        QTest::addColumn<QString>("provider"); QTest::addColumn<int>("total");
        for (const auto &provider : {QString("wy"), QString("kg")})
            for (int total : {0, 7, 10, 237, 5011})
                QTest::newRow(qPrintable(provider + QString::number(total))) << provider << total;
    }
    void fullPlaylist() {
        QFETCH(QString, provider); QFETCH(int, total);
        QTemporaryDir dir; infrastructure::database::Database db;
        QVERIFY(db.open(dir.filePath("lists.sqlite"))); QVERIFY(db.migrate());
        Network network; network.total = total;
        qmlbridge::CollectionService service(db, nullptr, &network);
        service.open(card(provider));
        QTRY_VERIFY_WITH_TIMEOUT(!service.detailBusy(), 5000);
        const auto detail = service.detail(); const auto rows = detail.value("tracks").toList();
        QCOMPARE(detail.value("total").toInt(), total); QCOMPARE(rows.size(), qMin(total, 5000));
        for (int i = 0; i < rows.size(); ++i) {
            QCOMPARE(rows[i].toMap().value("rid").toString(), QString::number(i + 1));
            QCOMPARE(rows[i].toMap().value("source").toString(), provider);
        }
        QCOMPARE(detail.value("error").toString().isEmpty(), total <= 5000);
        if (provider == "wy") {
            for (const auto &batch : network.batches) {
                QVERIFY(batch.size() <= 100);
                for (const auto &id : batch) QVERIFY(id.toInt() > network.preview);
            }
        } else {
            QCOMPARE(network.pages.size(), qMax(1, (qMin(total, 5000) + 99) / 100));
            for (int i = 0; i < network.pages.size(); ++i) QCOMPARE(network.pages[i], i + 1);
            if (!rows.isEmpty()) QCOMPARE(rows[0].toMap().value("_types").toMap().value("flac").toMap().value("hash").toString(), "flac-1");
        }
        // Reopening a loaded collection must not append the snapshot twice.
        service.open(detail); QTRY_VERIFY_WITH_TIMEOUT(!service.detailBusy(), 5000);
        QCOMPARE(service.detail().value("tracks").toList(), rows);
    }
    void missingSongsDoNotStopLaterPages_data() {
        QTest::addColumn<QString>("provider");
        QTest::newRow("wy-empty-middle-batch") << QString("wy");
        QTest::newRow("kg-missing-identity") << QString("kg");
    }
    void completeNeteaseResponseNeedsNoExtraRequests() {
        QTemporaryDir dir; infrastructure::database::Database db;
        QVERIFY(db.open(dir.filePath("lists.sqlite"))); QVERIFY(db.migrate());
        Network network; network.preview = network.total;
        qmlbridge::CollectionService service(db, nullptr, &network); service.open(card("wy"));
        QTRY_VERIFY_WITH_TIMEOUT(!service.detailBusy(), 5000);
        QCOMPARE(service.detail().value("tracks").toList().size(), network.total);
        QCOMPARE(network.songBatches, 0);
    }
    void missingSongsDoNotStopLaterPages() {
        QFETCH(QString, provider);
        QTemporaryDir dir; infrastructure::database::Database db;
        QVERIFY(db.open(dir.filePath("lists.sqlite"))); QVERIFY(db.migrate());
        Network network; network.missingFirst = 101; network.missingLast = 200; network.badKugouId = 100;
        qmlbridge::CollectionService service(db, nullptr, &network); service.open(card(provider));
        QTRY_VERIFY_WITH_TIMEOUT(!service.detailBusy(), 5000);
        const auto detail = service.detail(); const auto rows = detail.value("tracks").toList();
        QCOMPARE(rows.size(), provider == "wy" ? 137 : 236);
        QCOMPARE(rows.last().toMap().value("rid").toString(), "237");
        QCOMPARE(detail.value("total").toInt(), 237); QVERIFY(!detail.value("error").toString().isEmpty());
    }
    void failuresPreservePartialResults_data() {
        QTest::addColumn<QString>("provider"); QTest::addColumn<bool>("logical");
        for (const auto &provider : {QString("wy"), QString("kg")})
            for (bool logical : {false, true}) QTest::newRow(qPrintable(provider + QString::number(logical))) << provider << logical;
    }
    void failuresPreservePartialResults() {
        QFETCH(QString, provider); QFETCH(bool, logical);
        QTemporaryDir dir; infrastructure::database::Database db;
        QVERIFY(db.open(dir.filePath("lists.sqlite"))); QVERIFY(db.migrate());
        Network network; network.failPage = 2; network.logicalFailure = logical;
        qmlbridge::CollectionService service(db, nullptr, &network); service.open(card(provider));
        QTRY_VERIFY_WITH_TIMEOUT(!service.detailBusy(), 5000);
        QCOMPARE(service.detail().value("tracks").toList().size(), 100);
        QVERIFY(!service.detail().value("error").toString().isEmpty());
        network.failPage = 0; service.open(card(provider));
        QTRY_VERIFY_WITH_TIMEOUT(!service.detailBusy(), 5000);
        QCOMPARE(service.detail().value("tracks").toList().size(), 237);
        QVERIFY(service.detail().value("error").toString().isEmpty());
    }
    void repeatedKugouPageStops() {
        QTemporaryDir dir; infrastructure::database::Database db;
        QVERIFY(db.open(dir.filePath("lists.sqlite"))); QVERIFY(db.migrate());
        Network network; network.repeatPage = 2;
        qmlbridge::CollectionService service(db, nullptr, &network); service.open(card("kg"));
        QTRY_VERIFY_WITH_TIMEOUT(!service.detailBusy(), 5000);
        QCOMPARE(network.pages, QList<int>({1, 2}));
        QCOMPARE(service.detail().value("tracks").toList().size(), 100);
        QVERIFY(!service.detail().value("error").toString().isEmpty());
    }
    void kugouPreservesDifferentVersionsWithSameAudioId() {
        QTemporaryDir dir; infrastructure::database::Database db;
        QVERIFY(db.open(dir.filePath("lists.sqlite"))); QVERIFY(db.migrate());
        Network network; network.alternateVersion = 125;
        qmlbridge::CollectionService service(db, nullptr, &network); service.open(card("kg"));
        QTRY_VERIFY_WITH_TIMEOUT(!service.detailBusy(), 5000);
        const auto rows = service.detail().value("tracks").toList();
        QCOMPARE(rows.size(), 237);
        QCOMPARE(rows[0].toMap().value("rid"), rows[124].toMap().value("rid"));
        QCOMPARE(rows[0].toMap().value("hash").toString(), "hash-1");
        QCOMPARE(rows[124].toMap().value("hash").toString(), "hash-125");
        QVERIFY(service.detail().value("error").toString().isEmpty());
    }
    void cancellation_data() {
        QTest::addColumn<QString>("provider");
        QTest::newRow("wy") << QString("wy"); QTest::newRow("kg") << QString("kg");
    }
    void cancellation() {
        QFETCH(QString, provider);
        QTemporaryDir dir; infrastructure::database::Database db;
        QVERIFY(db.open(dir.filePath("lists.sqlite"))); QVERIFY(db.migrate());
        Network network; network.holdSongs = true;
        qmlbridge::CollectionService service(db, nullptr, &network); service.open(card(provider));
        QTRY_VERIFY(network.held);
        const auto oldReply = network.held;
        const QVariantList localRows{QVariantMap{{"rid", "local-song"}}};
        service.open({{"id", "local"}, {"kind", "Local"}, {"tracks", localRows}});
        QVERIFY(oldReply->isFinished()); QVERIFY(!service.detailBusy());
        const int requests = network.requests.size();
        QTest::qWait(20); QCOMPARE(network.requests.size(), requests);
        QCOMPARE(service.detail().value("id").toString(), "local");
        QCOMPARE(service.detail().value("tracks").toList(), localRows);
    }
    void livePlaylists_data() {
        QTest::addColumn<QString>("provider"); QTest::addColumn<QString>("id");
        QTest::newRow("wy-recommendation") << QString("wy") << QString("8232491318");
        QTest::newRow("wy-playlist") << QString("wy") << QString("514947114");
        QTest::newRow("wy-discovery-chart") << QString("wy") << QString("3778678");
        QTest::newRow("kg-large") << QString("kg") << QString("3823475");
        QTest::newRow("kg-second-page") << QString("kg") << QString("9126490");
    }
    void livePlaylists() {
        if (!qEnvironmentVariableIsSet("LISTENFREE_TEST_ONLINE")) QSKIP("Opt-in live catalog verification");
        QFETCH(QString, provider); QFETCH(QString, id);
        QTemporaryDir dir; infrastructure::database::Database db;
        QVERIFY(db.open(dir.filePath("lists.sqlite"))); QVERIFY(db.migrate());
        qmlbridge::CollectionService service(db); auto input = card(provider); input["id"] = id; service.open(input);
        QTRY_VERIFY_WITH_TIMEOUT(!service.detailBusy(), 90000);
        const auto detail = service.detail(); const auto rows = detail.value("tracks").toList();
        qInfo() << provider << id << "loaded" << rows.size() << "total" << detail.value("total") << detail.value("error");
        QVERIFY2(detail.value("error").toString().isEmpty(), qPrintable(detail.value("error").toString()));
        QVERIFY(rows.size() > 10); QCOMPARE(rows.size(), detail.value("total").toInt());
        for (const auto &value : rows) {
            const auto row = value.toMap(); QVERIFY(!row.value("rid").toString().isEmpty());
            QVERIFY(!row.value("title").toString().isEmpty()); QCOMPARE(row.value("source").toString(), provider);
        }
    }
    void liveDiscoveryOpensFullPlaylists() {
        if (!qEnvironmentVariableIsSet("LISTENFREE_TEST_ONLINE")) QSKIP("Opt-in live discovery verification");
        QTemporaryDir dir; infrastructure::database::Database db;
        QVERIFY(db.open(dir.filePath("lists.sqlite"))); QVERIFY(db.migrate());
        qmlbridge::CollectionService service(db); service.refreshHome(true);
        QTRY_VERIFY_WITH_TIMEOUT(!service.homeBusy(), 40000);
        QVERIFY(!service.homeRecommendations().isEmpty());
        const auto previews = service.homePreviews(); const auto recommendations = service.homeRecommendations();
        QCOMPARE(previews.first().toMap().value("tracks").toList().size(), 5);
        for (const auto &input : {recommendations.first().toMap(), previews.first().toMap()}) {
            service.open(input); QTRY_VERIFY_WITH_TIMEOUT(!service.detailBusy(), 60000);
            const auto detail = service.detail(); const auto rows = detail.value("tracks").toList();
            qInfo() << "discovery" << detail.value("id") << "loaded" << rows.size() << "total" << detail.value("total");
            QVERIFY2(detail.value("error").toString().isEmpty(), qPrintable(detail.value("error").toString()));
            QVERIFY(rows.size() > 10); QCOMPARE(rows.size(), detail.value("total").toInt());
        }
        QCOMPARE(service.platform(), "kw");
        QCOMPARE(service.homePreviews(), previews); QCOMPARE(service.homeRecommendations(), recommendations);
    }
};
QTEST_GUILESS_MAIN(CollectionTests)
#include "collection_tests.moc"
