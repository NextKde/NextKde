#include <QtEndian>
#include "media/media_stream_proxy.h"
#include <cmath>
#include <atomic>
#include <thread>
#include "qmlbridge/collection_service.h"
#include "qmlbridge/download_service.h"
#include "qmlbridge/portable_session.h"
#include "qmlbridge/cover_image_provider.h"
#include <QBuffer>
#include "online/kuwo_lyrics.h"
#include "online/platform_catalog.h"
#include "online/lyric_matching.h"
#include "online/lyric_sources.h"
#include <taglib/fileref.h>
#include <taglib/tpropertymap.h>
#include <taglib/tvariant.h>
#include <QImage>
#include "infrastructure/database/repositories.h"
#include <QApplication>
#include <QDirIterator>
#include <QSettings>
#include <QTcpServer>
#include <QTcpSocket>
#include <QRegularExpression>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QElapsedTimer>
#include <QTimer>
#include <chrono>
#include <cstdio>
#include <taglib/mpegfile.h>
#include <QTemporaryDir>
#include <QTest>
#include <QSignalSpy>
#include <QAbstractItemModelTester>
#include <qmmp/qmmp.h>
#include <qmmp/soundcore.h>
#include <qmmp/inputsource.h>
#include <QtConcurrent>
#ifdef Q_OS_WIN
#include <objbase.h>
#endif

using namespace listenfree;
class PortableTests : public QObject {
    Q_OBJECT
    QTemporaryDir temporary_;
    QString mp3_, flac_, third_, originalPcm_;
    QVariantMap local(const QString& path) { return {{"trackId", path}, {"title", QFileInfo(path).completeBaseName()}, {"localPath", path}}; }
private slots:
    void catalogReloadPublishesReentrantLatestSnapshot() {
        infrastructure::database::Database db;
        const auto path = temporary_.filePath("catalog-reentrant.sqlite");
        QVERIFY(db.open(path));
        QVERIFY(db.migrate());
        QVERIFY(db.setSetting("library.metadataRelationsVersion", "1"));
        const auto makeTrack = [](const char* id, const char* title) {
            domain::Track track;
            track.id = domain::TrackId(id);
            track.title = title;
            track.artists.push_back({"fixture-artist", "Fixture Artist"});
            track.album = domain::Album{"fixture-album", "Fixture Album", std::nullopt};
            track.remoteUrl = std::string("https://example.invalid/") + id;
            return track;
        };
        QVERIFY(db.upsertTrack(makeTrack("catalog-a", "A")));
        infrastructure::database::SettingsRepository repo(db);
        qmlbridge::SourceController source(&repo);
        qmlbridge::PortableSession player(db, path, source);
        QTRY_VERIFY_WITH_TIMEOUT(player.ready() && player.songs().size() == 1, 8000);
        QSignalSpy published(&player, &qmlbridge::PortableSession::catalogChanged);
        bool requestedDuringPublish = false;
        connect(&player, &qmlbridge::PortableSession::catalogChanged, &player, [&] {
            if (requestedDuringPublish) return;
            requestedDuringPublish = true;
            QVERIFY(db.upsertTrack(makeTrack("catalog-b", "B")));
            player.reloadCatalogChanges();
        });
        player.reload();
        QTRY_COMPARE_WITH_TIMEOUT(published.size(), 2, 8000);
        QCOMPARE(player.songs().size(), 2);
        QCOMPARE(player.tracksModel()->snapshotRows(), player.songs());
        QCOMPARE(player.albums().size(), 1);
        QCOMPARE(player.albums().first().toMap().value("count").toInt(), 2);
        QCOMPARE(player.artists().size(), 1);
        QCOMPARE(player.artists().first().toMap().value("albumCount").toInt(), 1);
    }

    void catalogReloadUpdatesOnlyChangedMetadataRow() {
        infrastructure::database::Database db;
        const auto path = temporary_.filePath("catalog-metadata-update.sqlite");
        QVERIFY(db.open(path));
        QVERIFY(db.migrate());
        QVERIFY(db.setSetting("library.metadataRelationsVersion", "1"));
        const auto makeTrack = [](const char* id, const char* title, int duration) {
            domain::Track track;
            track.id = domain::TrackId(id);
            track.title = title;
            track.duration = std::chrono::milliseconds(duration);
            track.remoteUrl = std::string("https://example.invalid/") + id;
            return track;
        };
        QVERIFY(db.upsertTrack(makeTrack("metadata-a", "A", 1000)));
        QVERIFY(db.upsertTrack(makeTrack("metadata-b", "B", 2000)));
        QVERIFY(db.upsertTrack(makeTrack("metadata-c", "C", 3000)));
        infrastructure::database::SettingsRepository repo(db);
        qmlbridge::SourceController source(&repo);
        qmlbridge::PortableSession player(db, path, source);
        QTRY_VERIFY_WITH_TIMEOUT(player.ready() && player.songs().size() == 3, 8000);
        auto* model = player.tracksModel();
        const QPersistentModelIndex anchored(model->index(1, 0));
        QSignalSpy published(&player, &qmlbridge::PortableSession::catalogChanged);
        QSignalSpy reset(model, &QAbstractItemModel::modelReset);
        QSignalSpy updated(model, &QAbstractItemModel::dataChanged);
        QSignalSpy inserted(model, &QAbstractItemModel::rowsInserted);
        QSignalSpy removed(model, &QAbstractItemModel::rowsRemoved);
        QVERIFY(db.upsertTrack(makeTrack("metadata-b", "B", 2500)));
        player.reloadCatalogChanges();
        QTRY_COMPARE_WITH_TIMEOUT(published.size(), 1, 8000);
        QCOMPARE(reset.size(), 0);
        QCOMPARE(inserted.size(), 0);
        QCOMPARE(removed.size(), 0);
        QCOMPARE(updated.size(), 1);
        QCOMPARE(updated.at(0).at(0).toModelIndex().row(), 1);
        QVERIFY(anchored.isValid());
        QCOMPARE(model->data(anchored, qmlbridge::TrackListModel::TrackIdRole).toString(), QString("metadata-b"));
        QCOMPARE(model->data(anchored, qmlbridge::TrackListModel::DurationRole).toInt(), 2500);
        QCOMPARE(model->snapshotRows(), player.songs());
        QVERIFY(player.lastCatalogUsedDelta());
        QCOMPARE(player.lastCatalogHydratedRows(), qsizetype(1));

        // The reader sorts by title, so this edit changes row identity order.
        // The bounded metadata path must safely return to the reset contract.
        published.clear();
        QVERIFY(db.upsertTrack(makeTrack("metadata-b", "Z", 2500)));
        player.reloadCatalogChanges();
        QTRY_COMPARE_WITH_TIMEOUT(published.size(), 1, 8000);
        QCOMPARE(reset.size(), 1);
        QVERIFY(!player.lastCatalogUsedDelta());
        QCOMPARE(model->snapshotRows(), player.songs());
        QCOMPARE(model->get(2).value("trackId").toString(), QString("metadata-b"));

        player.sortTracks(QStringLiteral("title"), QStringLiteral("descending"));
        QCOMPARE(model->get(0).value("trackId").toString(), QString("metadata-b"));
        published.clear();
        QVERIFY(db.upsertTrack(makeTrack("metadata-a", "A", 1500)));
        player.reloadCatalogChanges();
        QTRY_COMPARE_WITH_TIMEOUT(published.size(), 1, 8000);
        QVERIFY(!player.lastCatalogUsedDelta());
        QCOMPARE(model->get(0).value("trackId").toString(), QString("metadata-a"));
    }

    void catalogDeltaUpdatesSharedRelationsAndFallsBackForDeletion() {
        infrastructure::database::Database db;
        const auto path = temporary_.filePath("catalog-shared-relations.sqlite");
        QVERIFY(db.open(path));
        QVERIFY(db.setSetting("library.metadataRelationsVersion", "1"));
        const auto makeTrack = [](const char* id, const char* title, const char* artistId,
                                  const char* artistName, const char* albumId,
                                  const char* albumTitle, const char* artwork) {
            domain::Track track;
            track.id = domain::TrackId(id);
            track.title = title;
            track.remoteUrl = std::string("https://example.invalid/") + id;
            track.artists.push_back({artistId, artistName});
            track.album = domain::Album{albumId, albumTitle, std::string(artwork)};
            return track;
        };
        QVERIFY(db.upsertTrack(makeTrack("shared-a", "A", "shared-artist", "Old Artist",
                                         "shared-album", "Old Album", "https://example.invalid/old.jpg")));
        QVERIFY(db.upsertTrack(makeTrack("shared-b", "B", "shared-artist", "Old Artist",
                                         "shared-album", "Old Album", "https://example.invalid/old.jpg")));
        QVERIFY(db.upsertTrack(makeTrack("other-c", "C", "other-artist", "Other Artist",
                                         "other-album", "Other Album", "https://example.invalid/other.jpg")));
        infrastructure::database::SettingsRepository repo(db);
        qmlbridge::SourceController source(&repo);
        qmlbridge::PortableSession player(db, path, source);
        QTRY_VERIFY_WITH_TIMEOUT(player.ready() && player.songs().size() == 3, 8000);
        QSignalSpy published(&player, &qmlbridge::PortableSession::catalogChanged);
        QSignalSpy reset(player.tracksModel(), &QAbstractItemModel::modelReset);
        QSignalSpy updated(player.tracksModel(), &QAbstractItemModel::dataChanged);
        QVERIFY(db.upsertTrack(makeTrack("shared-a", "A", "shared-artist", "New Artist",
                                         "shared-album", "New Album", "https://example.invalid/new.jpg")));
        player.reloadCatalogChanges();
        QTRY_COMPARE_WITH_TIMEOUT(published.size(), 1, 8000);
        QVERIFY(player.lastCatalogUsedDelta());
        QCOMPARE(player.lastCatalogHydratedRows(), qsizetype(2));
        QCOMPARE(reset.size(), 0);
        QVERIFY(!updated.isEmpty());
        for (int row = 0; row < 2; ++row) {
            const auto values = player.songs().at(row).toMap();
            QCOMPARE(values.value("artist").toString(), QString("New Artist"));
            QCOMPARE(values.value("album").toString(), QString("New Album"));
            QCOMPARE(values.value("artwork").toString(), QString("https://example.invalid/new.jpg"));
        }
        QCOMPARE(player.albums().size(), 2);
        QCOMPARE(player.albums().first().toMap().value("count").toInt(), 2);
        QCOMPARE(player.artists().first().toMap().value("albumCount").toInt(), 1);
        published.clear();
        QVERIFY(db.removeTrack("shared-b"));
        player.reloadCatalogChanges();
        QTRY_COMPARE_WITH_TIMEOUT(published.size(), 1, 8000);
        QVERIFY(!player.lastCatalogUsedDelta());
        QCOMPARE(player.songs().size(), 2);
        QCOMPARE(reset.size(), 1);
    }

    void catalogExplicitReloadRefreshesLocalArtworkVersion() {
        infrastructure::database::Database db;
        const auto path = temporary_.filePath("catalog-artwork-version.sqlite");
        QVERIFY(db.open(path));
        QVERIFY(db.setSetting("library.metadataRelationsVersion", "1"));
        const auto mediaPath = temporary_.filePath("catalog-artwork-version.mp3");
        QFile media(mediaPath);
        QVERIFY(media.open(QIODevice::WriteOnly));
        QCOMPARE(media.write("a"), qint64(1));
        media.close();
        domain::Track track;
        track.id = domain::TrackId("artwork-version");
        track.title = "Artwork Version";
        track.localPath = mediaPath.toStdString();
        QVERIFY(db.upsertTrack(track));
        infrastructure::database::SettingsRepository repo(db);
        qmlbridge::SourceController source(&repo);
        qmlbridge::PortableSession player(db, path, source);
        QTRY_VERIFY_WITH_TIMEOUT(player.ready() && player.songs().size() == 1, 8000);
        const auto before = player.songs().first().toMap().value("artwork").toString();
        QVERIFY(media.open(QIODevice::WriteOnly | QIODevice::Append));
        QCOMPARE(media.write("bc"), qint64(2));
        media.close();
        QSignalSpy published(&player, &qmlbridge::PortableSession::catalogChanged);
        player.reload();
        QTRY_COMPARE_WITH_TIMEOUT(published.size(), 1, 8000);
        QVERIFY(!player.lastCatalogUsedDelta());
        const auto after = player.songs().first().toMap().value("artwork").toString();
        QVERIFY(!after.isEmpty());
        QVERIFY(after != before);
    }

    void catalogKnownCommitWithoutChangesSkipsReload() {
        infrastructure::database::Database db;
        const auto path = temporary_.filePath("catalog-noop-scan.sqlite");
        QVERIFY(db.open(path));
        QVERIFY(db.setSetting("library.metadataRelationsVersion", "1"));
        domain::Track track;
        track.id = domain::TrackId("catalog-stable");
        track.title = "Stable";
        QVERIFY(db.upsertTrack(track));
        infrastructure::database::SettingsRepository repo(db);
        qmlbridge::SourceController source(&repo);
        qmlbridge::PortableSession player(db, path, source);
        QTRY_VERIFY_WITH_TIMEOUT(player.ready() && player.songs().size() == 1, 8000);
        QSignalSpy published(&player, &qmlbridge::PortableSession::catalogChanged);
        QSignalSpy reset(player.tracksModel(), &QAbstractItemModel::modelReset);
        player.reloadCatalogChanges();
        QTest::qWait(800);
        QCOMPARE(published.size(), 0);
        QCOMPARE(reset.size(), 0);
        track.duration = std::chrono::milliseconds(2500);
        QVERIFY(db.upsertTrack(track));
        player.reloadCatalogChanges();
        QTRY_COMPARE_WITH_TIMEOUT(published.size(), 1, 8000);
        QVERIFY(player.lastCatalogUsedDelta());
        QCOMPARE(player.lastCatalogHydratedRows(), qsizetype(1));
        QCOMPARE(player.songs().first().toMap().value("durationMs").toLongLong(), qint64(2500));
    }

    void catalogReloadGuiLatencyBenchmark() {
        const int count = qEnvironmentVariableIntValue("LISTENFREE_CATALOG_BENCH_ROWS");
        if (count <= 0) QSKIP("Set LISTENFREE_CATALOG_BENCH_ROWS to run the isolated catalog benchmark");
        // The sampler uses these emitted wall-clock boundaries to label its
        // timestamped memory samples. Flush so even a failed test retains the
        // last completed phase; validation and settling stay out of loadMs.
        const auto phase = [](const char* name) {
            const auto epochNs = std::chrono::duration_cast<std::chrono::nanoseconds>(
                std::chrono::system_clock::now().time_since_epoch()).count();
            std::fprintf(stdout, "LF_BENCH_PHASE|%s|%lld\n", name, static_cast<long long>(epochNs));
            std::fflush(stdout);
        };
        phase("fixture_start");
        const auto path = temporary_.filePath("catalog-reload-benchmark.sqlite");
        infrastructure::database::Database db;
        QVERIFY(db.open(path));
        QVERIFY(db.migrate());
        QVERIFY(db.setSetting("library.metadataRelationsVersion", "1"));
        std::vector<domain::Track> fixtures;
        fixtures.reserve(static_cast<std::size_t>(count));
        for (int i = 0; i < count; ++i) {
            domain::Track track;
            track.id = domain::TrackId(QStringLiteral("benchmark-%1").arg(i, 7, 10, QLatin1Char('0')).toStdString());
            track.title = QStringLiteral("Track %1").arg(i, 7, 10, QLatin1Char('0')).toStdString();
            const auto artist = QStringLiteral("Artist %1").arg(i % 60, 3, 10, QLatin1Char('0')).toStdString();
            const auto album = QStringLiteral("Album %1").arg(i % 300, 3, 10, QLatin1Char('0')).toStdString();
            track.artists.push_back({artist, artist});
            track.album = domain::Album{album, album, std::nullopt};
            track.localPath = temporary_.filePath(QStringLiteral("music/%1.flac").arg(i)).toStdString();
            track.duration = std::chrono::milliseconds(180000 + i % 1000);
            fixtures.push_back(std::move(track));
        }
        QVERIFY(db.upsertTracks(fixtures));
        fixtures.clear();
        fixtures.shrink_to_fit();

        infrastructure::database::SettingsRepository repo(db);
        qmlbridge::SourceController source(&repo);
        phase("fixture_end");
        phase("preSteady_start");
        QTest::qWait(800);
        phase("preSteady_end");
        phase("cold_start");
        QElapsedTimer elapsed;
        elapsed.start();
        qint64 lastTickNs = elapsed.nsecsElapsed();
        qint64 maxGapNs = 0;
        int heartbeatTicks = 0;
        QTimer heartbeat;
        heartbeat.setTimerType(Qt::PreciseTimer);
        heartbeat.setInterval(1);
        connect(&heartbeat, &QTimer::timeout, this, [&] {
            const auto now = elapsed.nsecsElapsed();
            maxGapNs = std::max(maxGapNs, now - lastTickNs);
            lastTickNs = now;
            ++heartbeatTicks;
        });
        heartbeat.start();
        qmlbridge::PortableSession player(db, path, source);
        QTRY_VERIFY_WITH_TIMEOUT(player.ready() && player.songs().size() == count, 60000);
        heartbeat.stop();
        maxGapNs = std::max(maxGapNs, elapsed.nsecsElapsed() - lastTickNs);
        const auto coldLoadMs = elapsed.elapsed();
        phase("cold_end");
        phase("coldValidation_start");
        QCOMPARE(player.tracksModel()->rowCount(), count);
        QCOMPARE(player.artists().size(), 60);
        QCOMPARE(player.albums().size(), 300);
        const auto validateProjection = [&](int changedIndex, qint64 changedDuration) {
            const auto songs = player.songs();
            const auto modelRows = player.tracksModel()->snapshotRows();
            if (songs.size() != count || modelRows != songs) return false;
            for (int i = 0; i < count; ++i) {
                const auto row = songs.at(i).toMap();
                const auto id = QStringLiteral("benchmark-%1").arg(i, 7, 10, QLatin1Char('0'));
                const auto title = QStringLiteral("Track %1").arg(i, 7, 10, QLatin1Char('0'));
                const auto artist = QStringLiteral("Artist %1").arg(i % 60, 3, 10, QLatin1Char('0'));
                const auto album = QStringLiteral("Album %1").arg(i % 300, 3, 10, QLatin1Char('0'));
                const auto duration = i == changedIndex ? changedDuration : 180000 + i % 1000;
                if (row.value("trackId").toString() != id || row.value("title").toString() != title ||
                    row.value("artist").toString() != artist || row.value("album").toString() != album ||
                    row.value("durationMs").toLongLong() != duration ||
                    row.value("localPath").toString() != temporary_.filePath(QStringLiteral("music/%1.flac").arg(i)) ||
                    player.tracksModel()->data(player.tracksModel()->index(i, 0),
                                                qmlbridge::TrackListModel::TrackIdRole).toString() != id)
                    return false;
            }
            return true;
        };
        QVERIFY(validateProjection(-1, 0));
        phase("coldValidation_end");
        QJsonObject metrics{{"rows", count}, {"loadMs", coldLoadMs},
                            {"maxGuiGapMs", double(maxGapNs) / 1000000.0},
                            {"heartbeatTicks", heartbeatTicks},
                            {"coldProjectionCheckedRows", count},
                            {"coldHydratedRows", static_cast<qint64>(player.lastCatalogHydratedRows())},
                            {"coldUsedDelta", player.lastCatalogUsedDelta()}};
        if (qEnvironmentVariableIntValue("LISTENFREE_CATALOG_BENCH_WARM") == 1) {
            phase("warm_start");
            const int target = count / 2;
            const auto id = domain::TrackId(QStringLiteral("benchmark-%1").arg(target, 7, 10, QLatin1Char('0')).toStdString());
            auto changedTrack = db.findTrack(id);
            QVERIFY(changedTrack.has_value());
            changedTrack->duration += std::chrono::milliseconds(1000);
            const auto expectedMs = changedTrack->duration.count();
            QVERIFY(db.upsertTrack(*changedTrack));
            QSignalSpy published(&player, &qmlbridge::PortableSession::catalogChanged);
            QSignalSpy reset(player.tracksModel(), &QAbstractItemModel::modelReset);
            QSignalSpy updated(player.tracksModel(), &QAbstractItemModel::dataChanged);
            QSignalSpy inserted(player.tracksModel(), &QAbstractItemModel::rowsInserted);
            QSignalSpy removed(player.tracksModel(), &QAbstractItemModel::rowsRemoved);
            elapsed.start();
            lastTickNs = elapsed.nsecsElapsed();
            maxGapNs = 0;
            heartbeatTicks = 0;
            heartbeat.start();
            player.reloadCatalogChanges();
            QTRY_COMPARE_WITH_TIMEOUT(published.size(), 1, 60000);
            heartbeat.stop();
            maxGapNs = std::max(maxGapNs, elapsed.nsecsElapsed() - lastTickNs);
            const auto warmLoadMs = elapsed.elapsed();
            phase("warm_end");
            phase("warmValidation_start");
            QCOMPARE(player.songs().at(target).toMap().value("durationMs").toLongLong(), expectedMs);
            QCOMPARE(player.tracksModel()->rowCount(), count);
            QVERIFY(validateProjection(target, expectedMs));
            metrics["warmReloadMs"] = warmLoadMs;
            metrics["warmMaxGuiGapMs"] = double(maxGapNs) / 1000000.0;
            metrics["warmHeartbeatTicks"] = heartbeatTicks;
            metrics["warmModelResets"] = reset.size();
            metrics["warmDataChanges"] = updated.size();
            metrics["warmRowsInserted"] = inserted.size();
            metrics["warmRowsRemoved"] = removed.size();
            metrics["warmProjectionCheckedRows"] = count;
            metrics["warmHydratedRows"] = static_cast<qint64>(player.lastCatalogHydratedRows());
            metrics["warmUsedDelta"] = player.lastCatalogUsedDelta();
            phase("warmValidation_end");
        }
        phase("postSteady_start");
        QTest::qWait(800);
        phase("postSteady_end");
        const auto reportPath = qEnvironmentVariable("LISTENFREE_CATALOG_BENCH_REPORT");
        if (!reportPath.isEmpty()) {
            QFile report(reportPath);
            QVERIFY(report.open(QIODevice::WriteOnly | QIODevice::Truncate));
            report.write(QJsonDocument(metrics).toJson());
        }
        qInfo().noquote() << QJsonDocument(metrics).toJson(QJsonDocument::Compact);
    }

    void sourceReconnectWaitsForSlowShutdown() {
        qputenv("LISTENFREE_FAULT_MODE", "ignore-stop");
        qmlbridge::SourceController source(nullptr,
            QCoreApplication::applicationDirPath()+"/listenfree-sourcehost-fault-host.exe", true);
        QTRY_VERIFY_WITH_TIMEOUT(source.hostReady(), 5000);
        QSignalSpy changes(&source, &qmlbridge::SourceController::hostChanged);
        source.restartHost();
        source.restartHost(); // Repeated clicks must share one restart.
        QVERIFY(!source.hostReady());
        QTRY_VERIFY_WITH_TIMEOUT(source.hostReady(), 5000);
        QVERIFY(changes.count() >= 3);
    }

    void selectingSourceRecoversStoppedHost() {
        qputenv("LISTENFREE_FAULT_MODE", "bad-handshake");
        infrastructure::database::Database db;
        QVERIFY(db.open(temporary_.filePath("source-recovery.sqlite")));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);
        qmlbridge::SourceController source(&repo,
            QCoreApplication::applicationDirPath()+"/listenfree-sourcehost-fault-host.exe", true);
        QFile script(temporary_.filePath("source-recovery.js"));QVERIFY(script.open(QIODevice::WriteOnly));
        script.write("// isolated source recovery fixture\n");script.close();
        QVERIFY(source.importLocalFile(script.fileName()));
        QTRY_COMPARE_WITH_TIMEOUT(source.hostState(), QStringLiteral("已停止"), 5000);
        QVERIFY(source.sources().last().toMap().value("status").toString().contains(QStringLiteral("连接已断开")));
        qputenv("LISTENFREE_FAULT_MODE", "normal");
        QVERIFY(source.selectSource(source.activeId()));
        QTRY_VERIFY_WITH_TIMEOUT(source.hostReady(), 5000);
    }

    void unavailableSourceDoesNotSkipSelectedSong() {
        infrastructure::database::Database db;const auto path=temporary_.filePath("source-unavailable.sqlite");
        QVERIFY(db.open(path));QVERIFY(db.migrate());db.setSetting("playback.skipOnError","true");
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);
        qmlbridge::PortableSession player(db,path,source);
        const QVariantMap song{{"trackId","kw:465071414"},{"rid","465071414"},{"source","kw"},{"title","Online fixture"}};
        player.playAll({local(mp3_),song});
        QTRY_VERIFY_WITH_TIMEOUT(player.state()=="Playing" && player.position()>250,8000);
        QSignalSpy notices(&player,&qmlbridge::PortableSession::notice);
        player.next();
        QTRY_VERIFY(!player.errorMessage().isEmpty());
        QTest::qWait(1200);
        QCOMPARE(player.currentTrackId(),QString("kw:465071414"));
        QCOMPARE(player.currentQueueIndex(),1);
        QVERIFY(!notices.isEmpty());
        player.stop();
    }

    void sourceKeepsSpecificRemoteError() {
        qmlbridge::SourceController source(nullptr,
            QCoreApplication::applicationDirPath()+"/listenfree-sourcehost.exe", true);
        QTRY_VERIFY_WITH_TIMEOUT(source.hostReady(), 5000);
        QFile script(temporary_.filePath("specific-error.js"));
        QVERIFY(script.open(QIODevice::WriteOnly));
        script.write(R"JS(
lx.send(lx.EVENT_NAMES.inited,{sources:{kw:{type:'music',actions:['musicUrl'],qualitys:['128k']}}});
lx.on(lx.EVENT_NAMES.request,async()=>{throw Error('fixture-authentication-rejected');});
)JS");
        script.close();
        QVERIFY(source.importLocalFile(script.fileName()));
        QTRY_VERIFY_WITH_TIMEOUT(source.sources().last().toMap().value("hostReady").toBool(),5000);
        QSignalSpy results(&source,&qmlbridge::SourceController::resolutionFinished);
        QVERIFY(!source.resolveMusicUrl(source.activeId(),"128k",{{"source","kw"},{"songmid","450444"}}).isEmpty());
        QTRY_COMPARE_WITH_TIMEOUT(results.size(),1,5000);
        QVERIFY(results.first().at(4).toString().contains("fixture-authentication-rejected"));
        QVERIFY(source.sources().last().toMap().value("hostReady").toBool());
    }

    void sourceUsesLegacyOperationBudget() {
        qmlbridge::SourceController source(nullptr,
            QCoreApplication::applicationDirPath()+"/listenfree-sourcehost.exe", true);
        QTRY_VERIFY_WITH_TIMEOUT(source.hostReady(),5000);
        QFile script(temporary_.filePath("slow-legacy-source.js"));
        QVERIFY(script.open(QIODevice::WriteOnly));
        script.write(R"JS(
setTimeout(()=>lx.send(lx.EVENT_NAMES.inited,{sources:{kw:{type:'music',actions:['musicUrl'],qualitys:['128k']}}}),20);
lx.on(lx.EVENT_NAMES.request,()=>new Promise(resolve=>setTimeout(()=>resolve('https://media.invalid/slow.mp3'),16000)));
)JS");
        script.close();
        QVERIFY(source.importLocalFile(script.fileName()));
        QVERIFY(source.resolveMusicUrl(source.activeId(),"128k",{{"source","kw"},{"songmid","450444"}}).isEmpty());
        QTRY_VERIFY_WITH_TIMEOUT(source.sources().last().toMap().value("hostReady").toBool(),5000);
        QSignalSpy results(&source,&qmlbridge::SourceController::resolutionFinished);
        QVERIFY(!source.resolveMusicUrl(source.activeId(),"128k",{{"source","kw"},{"songmid","450444"}}).isEmpty());
        QTRY_COMPARE_WITH_TIMEOUT(results.size(),1,20000);
        QVERIFY2(results.first().at(4).toString().isEmpty(),qPrintable(results.first().at(4).toString()));
        QCOMPARE(results.first().at(3).toMap().value("url").toString(),QString("https://media.invalid/slow.mp3"));
    }

    void sourceImportsSameFilenameWithoutOverwrite() {
        qmlbridge::SourceController source;
        const auto firstDir = temporary_.filePath("import-first");
        const auto secondDir = temporary_.filePath("import-second");
        QVERIFY(QDir().mkpath(firstDir));QVERIFY(QDir().mkpath(secondDir));
        const auto write = [](const QString& path,const QByteArray& data) {
            QFile file(path);return file.open(QIODevice::WriteOnly) && file.write(data)==data.size();
        };
        const auto first = firstDir+"/script.js", second = secondDir+"/script.js";
        QVERIFY(write(first,"// first source"));QVERIFY(write(second,"// second source"));
        QVERIFY(source.importLocalFile(first));const auto firstId=source.activeId();
        QVERIFY(source.importLocalFile(second));QVERIFY(firstId!=source.activeId());
        QCOMPARE(source.sources().size(),2);
        for(const auto& row:source.sources()) {
            const auto map=row.toMap();QFile stored(map.value("path").toString());
            QVERIFY(stored.open(QIODevice::ReadOnly));
            QCOMPARE(stored.readAll(),map.value("id").toString()==firstId ? QByteArray("// first source") : QByteArray("// second source"));
        }
        QVERIFY(write(first,"// updated first source"));QVERIFY(source.importLocalFile(first));
        QCOMPARE(source.sources().size(),2);QCOMPARE(source.activeId(),firstId);
    }

    void sourceMusicInfoPreservesPlatformContract() {
        const QJsonObject kgSong{{"Audioid",123},{"FileHash","base"},{"HQFileHash","high"},
            {"SQFileHash","lossless"},{"ResFileHash","hires"},{"MixSongID",456},{"SongName","song"}};
        const auto kg=online::sourceMusicInfo(online::platformSongs("kg",{{"data",QJsonObject{{"lists",QJsonArray{kgSong}}}}}).first().toMap());
        QCOMPARE(kg.value("songmid").toString(),QString("123"));
        QCOMPARE(kg.value("albumAudioId").toInt(),456);
        QCOMPARE(kg.value("hash").toString(),QString("base"));
        QCOMPARE(kg.value("_types").toMap().value("flac24bit").toMap().value("hash").toString(),QString("hires"));
        QCOMPARE(kg.value("types").toList().size(),4);
        const QJsonObject txSong{{"id",789},{"mid","song-mid"},{"title","song"},
            {"album",QJsonObject{{"mid","album-mid"}}},
            {"file",QJsonObject{{"media_mid","media-mid"},{"size_128mp3",1234},{"size_hires",9999}}}};
        const auto txRows=online::platformSongs("tx",{{"req",QJsonObject{{"data",QJsonObject{{"body",QJsonObject{{"song",QJsonObject{{"list",QJsonArray{txSong}}}}}}}}}}});
        QVERIFY(!txRows.isEmpty());const auto tx=online::sourceMusicInfo(txRows.first().toMap());
        QCOMPARE(tx.value("songmid").toString(),QString("song-mid"));QCOMPARE(tx.value("songId").toInt(),789);
        QCOMPARE(tx.value("strMediaMid").toString(),QString("media-mid"));
        QCOMPARE(tx.value("albumId").toString(),QString("album-mid"));QCOMPARE(tx.value("types").toList().size(),2);
    }

    void positionTicksOnlyNotifyProgressBindings() {
        infrastructure::database::Database db;
        const auto path=temporary_.filePath("progress-notify.sqlite");
        QVERIFY(db.open(path));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);
        qmlbridge::SourceController source(&repo);
        qmlbridge::PortableSession player(db,path,source);
        player.playAll({local(mp3_)});
        QTRY_VERIFY_WITH_TIMEOUT(player.state()=="Playing" && player.position()>250,8000);
        QSignalSpy progress(&player,&qmlbridge::PortableSession::progressChanged);
        QSignalSpy broad(&player,&qmlbridge::PortableSession::changed);
        const auto before=player.position();
        QTRY_VERIFY_WITH_TIMEOUT(player.position()>before+600,3000);
        QVERIFY(progress.size()>=2);
        QCOMPARE(broad.size(),0);
        player.stop();
    }

    void realSourceReconnectAndPlayback() {
        const auto script=qEnvironmentVariable("LISTENFREE_TEST_SCRIPT");
        if(script.isEmpty())QSKIP("Requires a user-selected source script");
        infrastructure::database::Database db;const auto path=temporary_.filePath("source-live-recovery.sqlite");
        QVERIFY(db.open(path));QVERIFY(db.migrate());db.setSetting("playback.skipOnError","true");
        infrastructure::database::SettingsRepository repo(db);
        qmlbridge::SourceController source(&repo,QCoreApplication::applicationDirPath()+"/listenfree-sourcehost.exe",true);
        QTRY_VERIFY_WITH_TIMEOUT(source.hostReady(),10000);
        QVERIFY(source.importLocalFile(script));
        QTRY_VERIFY_WITH_TIMEOUT(source.sources().last().toMap().value("hostReady").toBool(),35000);
        qmlbridge::PortableSession player(db,path,source);
        QVariantMap song{{"trackId","kw:465071414"},{"rid","465071414"},{"source","kw"},
            {"title",QStringLiteral("起风了（DJ旋律）")},{"durationMs",240000}};
        const auto reportedPath=qEnvironmentVariable("LISTENFREE_TEST_TRACK");
        if(!reportedPath.isEmpty()) {
            QFile reported(reportedPath);QVERIFY(reported.open(QIODevice::ReadOnly));
            const auto document=QJsonDocument::fromJson(reported.readAll());QVERIFY(document.isObject());
            song=document.object().toVariantMap();QVERIFY(!song.value("rid").toString().isEmpty());
        }
        const auto trackId=song.value("trackId").toString();
        for(int cycle=0;cycle<2;++cycle) {
            source.restartHost();
            QTRY_VERIFY_WITH_TIMEOUT(source.hostReady() && source.sources().last().toMap().value("hostReady").toBool(),35000);
            player.playAll({local(mp3_),song});
            QTRY_VERIFY_WITH_TIMEOUT(player.state()=="Playing" && player.position()>250,8000);
            player.next();
            QTRY_VERIFY2_WITH_TIMEOUT(player.currentTrackId()==trackId && player.state()=="Playing" && player.position()>1200,
                                     qPrintable(player.errorMessage()),35000);
            player.pause();QTRY_COMPARE(player.state(),QString("Paused"));
            player.seek(10000);player.play();
            QTRY_VERIFY_WITH_TIMEOUT(player.position()>11200 && player.state()=="Playing",20000);
            QCOMPARE(player.currentTrackId(),trackId);
            player.previous();
            QTRY_VERIFY_WITH_TIMEOUT(player.state()=="Playing" && player.currentQueueIndex()==0 && player.position()>250,10000);
            player.stop();
        }
    }

    void kugouPlaylistTrackArtwork() {
        // Mobile playlist rows put album artwork inside trans_param.
        const QJsonObject metadata{{"union_cover","https://imge.kugou.com/stdmusic/{size}/album.jpg"}};
        const QJsonArray songs{
            QJsonObject{{"hash","fixture-hash"},{"filename","Artist - Song"},{"duration",249},{"trans_param",metadata}},
            QJsonObject{{"hash","direct-hash"},{"filename","Artist - Direct"},
                {"imgurl","https://imgessl.kugou.com/direct.jpg"},{"trans_param",metadata}}};
        const QJsonObject payload{{"list",QJsonObject{{"list",QJsonObject{{"info",songs}}}}}};
        const auto rows=online::platformSongs("kg",payload);
        QCOMPARE(rows.size(),2);
        QCOMPARE(rows[0].toMap().value("artwork").toString(),QString("https://imge.kugou.com/stdmusic/400/album.jpg"));
        QCOMPARE(rows[1].toMap().value("artwork").toString(),QString("https://imgessl.kugou.com/direct.jpg"));
    }
    void soundPresetsAndPersistence() {
        infrastructure::database::Database db;const auto path=temporary_.filePath("sound-presets.sqlite");
        QVERIFY(db.open(path));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);
        QString id;
        {
            qmlbridge::PortableSession player(db,path,source);
            QVERIFY(player.audioEffectsAvailable());QCOMPARE(player.equalizerPresets().size(),14);
            player.selectEqualizerPreset("vocal");QVERIFY(player.equalizerEnabled());QCOMPARE(player.equalizerGains()[6].toDouble(),5.0);
            QCOMPARE(player.equalizerEffectivePreamp(),-5.0);
            player.setEqualizerPreamp(1);QCOMPARE(player.equalizerPreset(),QString("custom"));
            QCOMPARE(player.equalizerEffectivePreamp(),-4.0);
            QVERIFY(player.saveEqualizerPreset("我的人声"));id=player.equalizerPreset();QVERIFY(id.startsWith("user-"));
            player.setEqualizerBand(3,1.5);QCOMPARE(player.equalizerPreset(),QString("custom"));
            QVERIFY(!player.saveEqualizerPreset("我的人声"));
            QVERIFY(player.saveEqualizerPreset("我的人声",true));QCOMPARE(player.equalizerPreset(),id);
            QVERIFY(!player.saveEqualizerPreset("人声",true));
            player.deleteEqualizerPreset("vocal");QCOMPARE(player.equalizerPresets().size(),15);
            player.setReverbPreset("hall");player.setAudioEffect("surroundEnabled",true);player.setAudioEffect("period",7);
            player.setAudioEffect("width",1.3);player.setAudioEffect("balance",-.2);
        }
        {
            qmlbridge::PortableSession player(db,path,source);
            QCOMPARE(player.equalizerPreset(),id);QCOMPARE(player.equalizerGains()[3].toDouble(),1.5);QCOMPARE(player.equalizerPreamp(),1.0);
            QVERIFY(player.audioEffects().value("reverbEnabled").toBool());QVERIFY(player.audioEffects().value("surroundEnabled").toBool());
            QCOMPARE(player.audioEffects().value("period").toDouble(),7.0);QCOMPARE(player.audioEffects().value("width").toDouble(),1.3);
            player.deleteEqualizerPreset(id);QCOMPARE(player.equalizerPreset(),QString("custom"));QCOMPARE(player.equalizerPresets().size(),14);
            player.resetAudioEffects();QVERIFY(!player.audioEffects().value("surroundEnabled").toBool());QCOMPARE(player.audioEffects().value("width").toDouble(),1.0);
            player.resetEqualizer();QCOMPARE(player.equalizerEffectivePreamp(),0.0);
        }
    }
    void volumeMuteRemembersLevel() {
        infrastructure::database::Database db;const auto path=temporary_.filePath("mute-memory.sqlite");
        QVERIFY(db.open(path));QVERIFY(db.migrate());db.setSetting("player.volume","0.42");
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);
        {
            qmlbridge::PortableSession player(db,path,source);
            QVERIFY(qAbs(player.volume()-.42f)<.005f);
            player.toggleMute();QCOMPARE(player.volume(),0.f);
        }
        {
            qmlbridge::PortableSession player(db,path,source);
            QCOMPARE(player.volume(),0.f);
            player.toggleMute();QVERIFY(qAbs(player.volume()-.42f)<.005f);
            player.setVolume(.17f);player.toggleMute();QCOMPARE(player.volume(),0.f);
            player.toggleMute();QVERIFY(qAbs(player.volume()-.17f)<.005f);
            player.setVolume(0.f);player.toggleMute();QVERIFY(qAbs(player.volume()-.17f)<.005f);
        }
    }
    void collectionArtworkFallback_data() {
        QTest::addColumn<int>("validIndex");
        QTest::newRow("last-song-has-no-cover") << 0;
        QTest::newRow("first-song-has-no-cover") << 1;
    }
    void collectionArtworkFallback() {
        QFETCH(int,validIndex);
        QTemporaryDir mediaDir;QVERIFY(mediaDir.isValid());
        QImage expected(64,32,QImage::Format_RGB32);expected.fill(QColor("#da3020"));
        QByteArray picture;QBuffer buffer(&picture);QVERIFY(buffer.open(QIODevice::WriteOnly));QVERIFY(expected.save(&buffer,"PNG"));
        infrastructure::database::Database db;const auto dbPath=mediaDir.filePath("library.sqlite");
        QVERIFY(db.open(dbPath));QVERIFY(db.migrate());db.setSetting("library.metadataRelationsVersion","1");
        for(int i=0;i<2;++i) {
            const auto path=mediaDir.filePath(QString::number(i)+".mp3");QVERIFY(QFile::copy(mp3_,path));
            {
                TagLib::MPEG::File file(path.toStdWString().c_str(),false);QVERIFY(file.isValid());
                auto* tag=file.ID3v2Tag(true);tag->removeFrames("APIC");
                if(i==validIndex){
                    auto* frame=new TagLib::ID3v2::AttachedPictureFrame;
                    frame->setType(TagLib::ID3v2::AttachedPictureFrame::FrontCover);frame->setMimeType("image/png");
                    frame->setPicture(TagLib::ByteVector(picture.constData(),picture.size()));tag->addFrame(frame);
                }
                QVERIFY(file.save());
            }
            domain::Track track;track.id=domain::TrackId(path.toStdString());track.localPath=path.toStdString();
            track.title=i==0?"A":"Z";track.artists={{"artist","Artist"}};track.album=domain::Album{"album","Album",std::nullopt};
            QVERIFY(db.upsertTrack(track));
        }
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);
        qmlbridge::PortableSession player(db,dbPath,source);QTRY_VERIFY(player.ready());
        CoverImageProvider covers(player.collectionCoverIndex());
        for(const auto& collection:{player.albums(),player.artists()}){
            QCOMPARE(collection.size(),1);
            const auto url=collection.front().toMap().value("artwork").toString();
            QVERIFY(url.startsWith("image://covers/collection-index/"));
            QVERIFY2(url.size()<128,"A collection URL must not retain all candidate file paths");
            QCOMPARE(player.collectionCoverIndex()->candidates(url.mid(15)).size(),2);
            const auto image=covers.requestImage(url.mid(QString("image://covers/").size()),nullptr,QSize(64,64));
            QVERIFY2(image.width()>1,"A collection must find artwork in another song when its representative has none");
            QCOMPARE(image.pixelColor(image.width()/2,image.height()/2),QColor("#da3020"));
            // QML Image with only sourceSize.width can request height 0.
            const auto widthOnly=covers.requestImage(url.mid(QString("image://covers/").size()),nullptr,QSize(2048,0));
            QVERIFY2(widthOnly.width()>1 && widthOnly.height()>1,"A width-only hero request must retain the embedded song cover");
            // A 64x32 embedded PNG must not become an 8 MiB hero allocation.
            QCOMPARE(widthOnly,expected);
            QCOMPARE(covers.requestImage(url.mid(15),nullptr,QSize(0,1024)),expected);
            QCOMPARE(covers.requestImage(url.mid(15),nullptr,QSize(0,0)),expected);
            QSize actual;
            const auto thumbnail=covers.requestImage(url.mid(15),&actual,QSize(16,16));
            QCOMPARE(actual,QSize(16,8));
            QCOMPARE(thumbnail.size(),actual);
            QCOMPARE(thumbnail.pixelColor(8,4),QColor("#da3020"));
            QCOMPARE(covers.requestImage(url.mid(15),nullptr,QSize(0,8)).size(),QSize(16,8));
            // Saved image URLs from before the index migration remain readable.
            QJsonArray legacyCandidates;
            for (int i=1;i>=0;--i) legacyCandidates.append(player.songs().at(i).toMap().value("artwork").toString().mid(15));
            const auto legacy=QStringLiteral("collection/")+QString::fromLatin1(
                QJsonDocument(legacyCandidates).toJson(QJsonDocument::Compact).toBase64(
                    QByteArray::Base64UrlEncoding|QByteArray::OmitTrailingEquals));
            QCOMPARE(covers.requestImage(legacy,nullptr,QSize(64,64)).pixelColor(32,16),QColor("#da3020"));
        }
    }
    void collectionArtworkIndexInvalidatesOnMembershipAndFileChange() {
        QTemporaryDir mediaDir;QVERIFY(mediaDir.isValid());
        infrastructure::database::Database db;const auto dbPath=mediaDir.filePath("library.sqlite");
        QVERIFY(db.open(dbPath));QVERIFY(db.migrate());QVERIFY(db.setSetting("library.metadataRelationsVersion","1"));
        const auto writeCover=[&](const QString& path,const QColor& color,int width) {
            QImage image(width,32,QImage::Format_RGB32);image.fill(color);
            QByteArray picture;QBuffer buffer(&picture);if(!buffer.open(QIODevice::WriteOnly) || !image.save(&buffer,"PNG"))return false;
            TagLib::MPEG::File file(path.toStdWString().c_str(),false);if(!file.isValid())return false;
            auto* tag=file.ID3v2Tag(true);tag->removeFrames("APIC");
            auto* frame=new TagLib::ID3v2::AttachedPictureFrame;
            frame->setType(TagLib::ID3v2::AttachedPictureFrame::FrontCover);frame->setMimeType("image/png");
            frame->setPicture(TagLib::ByteVector(picture.constData(),picture.size()));tag->addFrame(frame);
            return file.save();
        };
        const auto insert=[&](int number,bool cover,const QColor& color=QColor("#da3020")) {
            const auto path=mediaDir.filePath(QString::number(number)+".mp3");
            if(!QFile::copy(mp3_,path))return false;
            if(cover) { if(!writeCover(path,color,64))return false; }
            else {
                TagLib::MPEG::File file(path.toStdWString().c_str(),false);if(!file.isValid())return false;
                file.ID3v2Tag(true)->removeFrames("APIC");if(!file.save())return false;
            }
            domain::Track track;track.id=domain::TrackId(path.toStdString());track.localPath=path.toStdString();
            track.title=QString::number(number).toStdString();track.artists={{"artist","Artist"}};
            track.album=domain::Album{"album","Album",std::nullopt};
            return db.upsertTrack(track);
        };
        QVERIFY(insert(0,true));QVERIFY(insert(1,false));
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);
        qmlbridge::PortableSession player(db,dbPath,source);QTRY_VERIFY_WITH_TIMEOUT(player.ready(),8000);
        CoverImageProvider covers(player.collectionCoverIndex());
        const auto albumUrl=[&] {return player.albums().first().toMap().value("artwork").toString();};
        const auto colorAt=[&](const QString& url) {
            const auto image=covers.requestImage(url.mid(15),nullptr,QSize(64,64));
            return image.pixelColor(image.width()/2,image.height()/2);
        };
        const auto initial=albumUrl();
        QVERIFY(initial.startsWith("image://covers/collection-index/"));
        QCOMPARE(colorAt(initial),QColor("#da3020"));
        // Exercise the actual QML Image URL path, including provider ID parsing.
        {
            QQmlEngine engine;
            engine.addImageProvider("covers",new CoverImageProvider(player.collectionCoverIndex()));
            QQmlComponent component(&engine);
            component.setData(QByteArray("import QtQuick\nImage { asynchronous: true; source: '")
                +initial.toUtf8()+QByteArray("' }"),QUrl());
            std::unique_ptr<QObject> image(component.create());
            QVERIFY2(image,qPrintable(component.errorString()));
            QTRY_COMPARE_WITH_TIMEOUT(image->property("status").toInt(),1,8000);
            QVERIFY2(image->property("implicitWidth").toDouble()>1,
                     "QML Image must resolve the indexed group to real artwork");
        }

        QSignalSpy published(&player,&qmlbridge::PortableSession::catalogChanged);
        QVERIFY(insert(2,true,QColor("#2040da")));
        player.reloadCatalogChanges();QTRY_COMPARE_WITH_TIMEOUT(published.size(),1,8000);
        const auto added=albumUrl();QVERIFY(added!=initial);
        QCOMPARE(colorAt(added),QColor("#2040da"));
        QCOMPARE(colorAt(initial),QColor("#2040da"));

        const auto newest=mediaDir.filePath("2.mp3");
        QVERIFY(writeCover(newest,QColor("#20a050"),80));
        published.clear();player.reload();QTRY_COMPARE_WITH_TIMEOUT(published.size(),1,8000);
        const auto changed=albumUrl();QVERIFY(changed!=added);
        QCOMPARE(colorAt(changed),QColor("#20a050"));
        QCOMPARE(colorAt(added),QColor("#20a050"));

        QVERIFY(db.removeTrack(newest));
        published.clear();player.reloadCatalogChanges();QTRY_COMPARE_WITH_TIMEOUT(published.size(),1,8000);
        const auto removed=albumUrl();QVERIFY(removed!=changed);
        QCOMPARE(colorAt(removed),QColor("#da3020"));
        QCOMPARE(colorAt(changed),QColor("#da3020"));

        QVERIFY(db.removeTrack(mediaDir.filePath("1.mp3")));
        published.clear();player.reloadCatalogChanges();QTRY_COMPARE_WITH_TIMEOUT(published.size(),1,8000);
        const auto single=albumUrl();QVERIFY(single.startsWith("image://covers/"));
        QVERIFY(!single.startsWith("image://covers/collection-index/"));
        QCOMPARE(colorAt(single),QColor("#da3020"));
        QCOMPARE(colorAt(changed),QColor("#da3020"));
        QCOMPARE(player.collectionCoverIndex()->candidates(changed.mid(15)).size(),1);

        QVERIFY(db.removeTrack(mediaDir.filePath("0.mp3")));
        published.clear();player.reloadCatalogChanges();QTRY_COMPARE_WITH_TIMEOUT(published.size(),1,8000);
        QVERIFY(player.albums().isEmpty());
        QVERIFY(player.collectionCoverIndex()->candidates(changed.mid(15)).isEmpty());
    }
    void localMediaContentDetection_data() {
        QTest::addColumn<bool>("reported");
        QTest::newRow("large-id3-wrong-extension")<<false;
        if(!qEnvironmentVariable("LISTENFREE_TEST_REPORTED_MEDIA").isEmpty())QTest::newRow("reported-song")<<true;
    }
    void localMediaContentDetection() {
        QFETCH(bool,reported);
        const auto original=qEnvironmentVariable("LISTENFREE_TEST_REPORTED_MEDIA");
        const auto media=temporary_.filePath(reported?QFileInfo(original).fileName():QString("large-id3.flac"));
        if(reported)QVERIFY(QFile::copy(original,media));
        else {
            TagLib::MPEG::File tags(mp3_.toStdWString().c_str(),false);
            const auto offset=tags.firstFrameOffset();QVERIFY(offset>=0);
            QFile sourceFile(mp3_);QVERIFY(sourceFile.open(QIODevice::ReadOnly));QVERIFY(sourceFile.seek(offset));
            QFile sample(media);QVERIFY(sample.open(QIODevice::WriteOnly));
            const int padding=1024*1024;QByteArray header(10,0);header.replace(0,3,"ID3");header[3]=4;
            for(int i=0;i<4;++i)header[6+i]=char((padding>>((3-i)*7))&127);
            sample.write(header);sample.write(QByteArray(padding,0));sample.write(sourceFile.readAll());
        }
        infrastructure::database::Database db;const auto path=temporary_.filePath("reported-media.sqlite");
        QVERIFY(db.open(path));QVERIFY(db.migrate());db.setSetting("playback.skipOnError","false");
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);qmlbridge::PortableSession player(db,path,source);
        QVERIFY(player.openTrack(local(media)));
        QTRY_VERIFY_WITH_TIMEOUT(player.state()=="Playing"||player.state()=="Error",8000);
        QVERIFY2(player.state()=="Playing",qPrintable(player.errorMessage()));
        QTRY_VERIFY_WITH_TIMEOUT(player.position()>=500,4000);
        const auto target=qMin(player.duration()/2,qint64(30000));QVERIFY(target>0);
        player.seek(target);QTRY_VERIFY_WITH_TIMEOUT(qAbs(player.position()-target)<1500,4000);
        QCOMPARE(player.state(),QString("Playing"));
        player.stop();
    }
    void onlineSelectionPublishesBeforeMediaLoads_data() {
        QTest::addColumn<bool>("resolveUrl");
        QTest::newRow("direct-url") << false;
        QTest::newRow("source-resolution") << true;
    }
    void onlineSelectionPublishesBeforeMediaLoads() {
        QFETCH(bool,resolveUrl);
        // Hold the media response so the UI contract cannot accidentally pass
        // because this machine happened to finish buffering quickly.
        QFile mediaFile(mp3_);QVERIFY(mediaFile.open(QIODevice::ReadOnly));const auto media=mediaFile.readAll();
        bool releaseMedia=false;
        QTcpServer server;QVERIFY(server.listen(QHostAddress::LocalHost));
        connect(&server,&QTcpServer::newConnection,this,[&] {
            while(server.hasPendingConnections()) {
                auto* socket=server.nextPendingConnection();
                auto request=std::make_shared<QByteArray>();
                connect(socket,&QTcpSocket::readyRead,socket,[&,socket,request]{
                    *request+=socket->readAll();if(!request->contains("\r\n\r\n")||socket->property("responding").toBool())return;
                    socket->setProperty("responding",true);
                    if(request->startsWith("GET /resolve")) {
                        QTimer::singleShot(700,socket,[socket]{socket->write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok");socket->disconnectFromHost();});
                        return;
                    }
                    const auto range=QRegularExpression("Range: bytes=(\\d+)-",QRegularExpression::CaseInsensitiveOption).match(QString::fromLatin1(*request));
                    const auto offset=range.hasMatch()?range.captured(1).toLongLong():0;
                    auto* timer=new QTimer(socket);timer->setInterval(20);
                    connect(timer,&QTimer::timeout,socket,[&,socket,timer,offset]{
                        if(!releaseMedia)return;
                        timer->stop();QByteArray header=offset?"HTTP/1.1 206 Partial Content\r\n":"HTTP/1.1 200 OK\r\n";
                        header+="Content-Type: audio/mpeg\r\nAccept-Ranges: bytes\r\nConnection: close\r\nContent-Length: "+QByteArray::number(media.size()-offset)+"\r\n";
                        if(offset)header+="Content-Range: bytes "+QByteArray::number(offset)+"-"+QByteArray::number(media.size()-1)+"/"+QByteArray::number(media.size())+"\r\n";
                        socket->write(header+"\r\n");socket->write(media.mid(offset));socket->disconnectFromHost();
                    });timer->start();
                });
                connect(socket,&QTcpSocket::disconnected,socket,&QObject::deleteLater);
            }
        });
        infrastructure::database::Database db;const auto path=temporary_.filePath(QString("immediate-online-%1.sqlite").arg(resolveUrl));
        QVERIFY(db.open(path));QVERIFY(db.migrate());db.setSetting("playback.transition.mode","Gapless");
        db.setSetting("playback.skipOnError","false");
        infrastructure::database::SettingsRepository repo(db);
        qmlbridge::SourceController source(&repo,QCoreApplication::applicationDirPath()+"/listenfree-sourcehost.exe",true);
        if(resolveUrl) {
            QTRY_VERIFY_WITH_TIMEOUT(source.hostReady(),10000);
            QFile script(temporary_.filePath("pending-playback.js"));QVERIFY(script.open(QIODevice::WriteOnly));
            script.write(QString("lx.on(lx.EVENT_NAMES.request, () => new Promise((resolve,reject) => lx.request('http://127.0.0.1:%1/resolve', {}, err => err ? reject(err) : resolve('http://127.0.0.1:%1/media.mp3'))));lx.send(lx.EVENT_NAMES.inited,{status:true,sources:{kw:{type:'music',actions:['musicUrl'],qualitys:['128k']}}});").arg(server.serverPort()).toUtf8());
            script.close();QVERIFY(source.importLocalFile(script.fileName()));
            QTRY_VERIFY_WITH_TIMEOUT(source.sources().last().toMap().value("hostReady").toBool(),10000);
            db.setSetting("playback.quality","128k");
        }
        qmlbridge::PortableSession player(db,path,source);
        player.playAll({local(mp3_)});
        QTRY_VERIFY_WITH_TIMEOUT(player.state()=="Playing"&&player.position()>500,8000);
        QVariantMap online{{"trackId","pending-online"},{"title","Pending online song"},{"artist","Fixture artist"},
            {"artwork","file:///fixture-cover.png"},{"remoteUrl",QString("http://127.0.0.1:%1/media.mp3").arg(server.serverPort())}};
        if(resolveUrl){online.remove("remoteUrl");online["source"]="kw";online["rid"]="pending-online";}
        QSignalSpy currentChanged(&player,&qmlbridge::PortableSession::currentTrackChanged);
        QVERIFY(player.openTrack(online));
        QCOMPARE(player.queueSongs().size(),2);
        QCOMPARE(player.currentTrackId(),QString("pending-online"));
        QCOMPARE(player.currentQueueIndex(),1);
        QCOMPARE(player.currentTrack().value("artwork"),online.value("artwork"));
        QVERIFY(!currentChanged.isEmpty());
        QCOMPARE(player.position(),0);QCOMPARE(player.duration(),0);QVERIFY(!player.seekable());
        QVERIFY2(player.state()=="Loading"||player.state()=="Buffering",qPrintable(player.errorMessage()));
        QTest::qWait(200);QCOMPARE(player.currentTrackId(),QString("pending-online"));
        QVERIFY(player.openTrack(local(flac_)));
        QTRY_VERIFY_WITH_TIMEOUT(player.currentTrack().value("localPath")==flac_&&player.state()=="Playing",8000);
        QTest::qWait(800);QCOMPARE(player.currentTrack().value("localPath").toString(),flac_);
        QVERIFY(player.openTrack(online));
        QCOMPARE(player.currentTrackId(),QString("pending-online"));
        player.stop();QCOMPARE(player.state(),QString("Stopped"));
        QCOMPARE(player.position(),0);QCOMPARE(player.duration(),0);QVERIFY(!player.seekable());
        QVERIFY(player.openTrack(online));
        QTest::qWait(850); // Resolution finished, but the media server still holds its response.
        QVERIFY2(player.errorMessage().isEmpty(),qPrintable(player.errorMessage()));
        QCOMPARE(player.position(),0);QCOMPARE(player.duration(),0);
        releaseMedia=true;
        QTRY_VERIFY_WITH_TIMEOUT(player.state()=="Playing"&&player.position()>0&&player.duration()>0,8000);
        QCOMPARE(player.currentTrackId(),QString("pending-online"));
        QCOMPARE(player.queueSongs().size(),3);
        player.stop();
    }
    void httpCacheReturnsExactBytesAcrossDisjointRanges_data() {
        QTest::addColumn<bool>("frontierOnly");
        QTest::newRow("disjoint-ranges")<<false;
        QTest::newRow("full-buffer-frontier")<<true;
    }
    void httpCacheReturnsExactBytesAcrossDisjointRanges() {
        QFETCH(bool,frontierOnly);
        SoundCore core; // Transport prebuffer notifications require its StateHandler.
        QByteArray bytes(12*1024*1024, Qt::Uninitialized);
        for(qsizetype i=0;i<bytes.size();++i)bytes[i]=char((i*31)^(i>>8)^(i>>17));
        QTcpServer server; QVERIFY(server.listen(QHostAddress::LocalHost));
        std::atomic_int requests{0};
        connect(&server,&QTcpServer::newConnection,this,[&] {
            while(server.hasPendingConnections()) {
                auto* socket=server.nextPendingConnection();
                connect(socket,&QTcpSocket::disconnected,socket,&QObject::deleteLater);
                connect(socket,&QTcpSocket::readyRead,socket,[&,socket] {
                    const auto request=socket->property("request").toByteArray()+socket->readAll();
                    socket->setProperty("request",request);
                    if(!request.contains("\r\n\r\n")||socket->property("sent").toBool())return;
                    socket->setProperty("sent",true);++requests;
                    const auto match=QRegularExpression("Range: bytes=(\\d+)-",QRegularExpression::CaseInsensitiveOption).match(QString::fromLatin1(request));
                    const auto offset=match.hasMatch()?match.captured(1).toLongLong():0;
                    socket->write("HTTP/1.1 206 Partial Content\r\nContent-Type: audio/mpeg\r\nAccept-Ranges: bytes\r\nContent-Range: bytes "+QByteArray::number(offset)+"-"+QByteArray::number(bytes.size()-1)+"/"+QByteArray::number(bytes.size())+"\r\nContent-Length: "+QByteArray::number(bytes.size()-offset)+"\r\nConnection: close\r\n\r\n");
                    auto* pump=new QTimer(socket);pump->setInterval(20);
                    connect(pump,&QTimer::timeout,socket,[&,socket,pump,at=offset]()mutable {
                        if(socket->bytesToWrite()>65536)return;
                        const auto count=qMin<qint64>(65536,bytes.size()-at);
                        socket->write(bytes.constData()+at,count);at+=count;
                        if(at==bytes.size()){pump->stop();socket->disconnectFromHost();}
                    });pump->start();
                });
            }
        });
        std::unique_ptr<InputSource> source(InputSource::create(QString("http://127.0.0.1:%1/cache.mp3").arg(server.serverPort()),this));
        QVERIFY(source);
        connect(source.get(),&InputSource::ready,this,[&]{source->ioDevice()->open(QIODevice::ReadOnly);});
        QVERIFY(source->initialize());
        QTRY_VERIFY_WITH_TIMEOUT(source->isReady(),5000);
        if(frontierOnly)QTRY_VERIFY_WITH_TIMEOUT(source->ioDevice()->bytesAvailable()>=4*1024*1024,5000);
        int cacheStep=0;
        auto future=QtConcurrent::run([&] {
            auto* device=source->ioDevice();
            const auto readAt=[&](qint64 offset,qint64 size) {
                if(!device->seek(offset)){qWarning("Seek failed at %lld",offset);return false;}
                QByteArray actual;
                while(actual.size()<size) {
                    const auto part=device->read(size-actual.size());
                    if(part.isEmpty()){qWarning("Empty read at %lld after %lld bytes",offset,actual.size());return false;}
                    actual+=part;
                }
                if(actual!=bytes.mid(offset,size)||device->pos()!=offset+size){qWarning("Byte comparison at %lld: got %lld bytes, position %lld",offset,actual.size(),device->pos());return false;}
                return true;
            };
            // Seeking exactly to a full read-ahead buffer's frontier consumes
            // all available bytes and must wake the blocked producer itself.
            if(frontierOnly) {
                const bool ok=readAt(device->bytesAvailable(),8192);
                source->stop();return ok;
            }
            cacheStep=1;
            if(!readAt(100,8192)||!readAt(4096,50000))return false;
            cacheStep=2;
            const int cachedRequests=requests;
            if(!readAt(100,8192)||requests!=cachedRequests)return false;
            cacheStep=3;
            if(!readAt(8*1024*1024,90000)||!readAt(3*1024*1024,90000))return false;
            cacheStep=4;
            const int disjointRequests=requests;
            if(!readAt(8*1024*1024-40,100000)||requests!=disjointRequests)return false;
            cacheStep=5;
            if(!readAt(3*1024*1024-40,50000)||requests!=disjointRequests)return false;
            cacheStep=6;
            if(!readAt(bytes.size()-2000,2000)||!device->atEnd())return false;
            cacheStep=7;
            if(!readAt(8*1024*1024,10000))return false;
            cacheStep=8;
            source->stop();
            return !device->seek(3*1024*1024);
        });
        QTRY_VERIFY_WITH_TIMEOUT(future.isFinished(),10000);
        QVERIFY2(future.result(),qPrintable(QString("HTTP cache check failed at step %1").arg(cacheStep)));
    }
    void playbackModesCycleAndMigrateSequential() {
        infrastructure::database::Database db;
        const auto path = temporary_.filePath("four-modes.sqlite");
        QVERIFY(db.open(path)); QVERIFY(db.migrate());
        db.setSetting("playback.defaultMode", "Sequential");
        infrastructure::database::SettingsRepository repo(db); qmlbridge::SourceController source(&repo);
        qmlbridge::PortableSession player(db, path, source);
        QCOMPARE(player.playbackMode(), QString("listLoop"));
        QCOMPARE(db.getSetting("playback.defaultMode").value_or(""), std::string("LoopAll"));
        for (const auto& expected : QStringList{"singleLoop", "shuffle", "stopAfterCurrent", "listLoop"}) {
            player.cyclePlaybackMode(); QCOMPARE(player.playbackMode(), expected);
        }
        player.setPlaybackMode("shuffle"); player.setPlaybackMode("sequential");
        QCOMPARE(player.playbackMode(), QString("listLoop"));
        player.setPlaybackMode("endless");
        QCOMPARE(player.playbackMode(), QString("endless"));
        QCOMPARE(db.getSetting("playback.defaultMode").value_or(""), std::string("Endless"));
        player.cyclePlaybackMode();
        QCOMPARE(player.playbackMode(), QString("listLoop"));
    }
    void throttledOnlineSeekKeepsGuiResponsive_data() {
        QTest::addColumn<bool>("flac");
        QTest::addColumn<int>("responseDelay");
        QTest::newRow("mp3")<<false<<0;QTest::newRow("flac")<<true<<0;
        QTest::newRow("flac-cdn-latency")<<true<<150;
    }
    void throttledOnlineSeekKeepsGuiResponsive() {
        QFETCH(bool,flac);
        QFETCH(int,responseDelay);
        // Serve more media than the transport can prebuffer; Range requests
        // must be processed by the same event loop as the playback controls.
        QFile file(flac?flac_:mp3_);QVERIFY(file.open(QIODevice::ReadOnly));const auto media=file.readAll();file.close();
        QTcpServer upstream;QVERIFY(upstream.listen(QHostAddress::LocalHost));int ranges=0;
        connect(&upstream,&QTcpServer::newConnection,this,[&] {
            while(upstream.hasPendingConnections()) {
                auto* socket=upstream.nextPendingConnection();
                connect(socket,&QTcpSocket::disconnected,socket,&QObject::deleteLater);
                connect(socket,&QTcpSocket::readyRead,socket,[&,socket] {
                    const auto request=socket->property("request").toByteArray()+socket->readAll();socket->setProperty("request",request);
                    if(!request.contains("\r\n\r\n")||socket->property("sent").toBool())return;
                    socket->setProperty("sent",true);
                    const auto match=QRegularExpression("Range: bytes=(\\d+)-",QRegularExpression::CaseInsensitiveOption).match(QString::fromLatin1(request));
                    const int offset=match.hasMatch()?match.captured(1).toInt():0;
                    if(offset>0)++ranges;
                    socket->write("HTTP/1.1 206 Partial Content\r\nContent-Type: "+QByteArray(flac?"audio/flac":"audio/mpeg")+"\r\nAccept-Ranges: bytes\r\nContent-Range: bytes "+QByteArray::number(offset)+"-"+QByteArray::number(media.size()-1)+"/"+QByteArray::number(media.size())+"\r\nContent-Length: "+QByteArray::number(media.size()-offset)+"\r\nConnection: close\r\n\r\n");
                    auto* pump=new QTimer(socket);pump->setInterval(10);
                    connect(pump,&QTimer::timeout,socket,[&,socket,pump,at=offset]()mutable {
                        if(socket->bytesToWrite()>65536)return;
                        const int count=qMin(16384,int(media.size())-at);
                        socket->write(media.constData()+at,count);at+=count;
                        if(at==media.size()){pump->stop();socket->disconnectFromHost();}
                    });QTimer::singleShot(responseDelay,pump,[pump]{pump->start();});
                });
            }
        });
        std::atomic<qint64> heartbeat{QDateTime::currentMSecsSinceEpoch()};
        QTimer pulse;pulse.setInterval(25);
        connect(&pulse,&QTimer::timeout,this,[&]{heartbeat=QDateTime::currentMSecsSinceEpoch();});pulse.start();
        std::jthread watchdog([&](std::stop_token stop){
            while(!stop.stop_requested()) {
                if(QDateTime::currentMSecsSinceEpoch()-heartbeat.load()>5000)
                    qFatal("Online seek blocked the GUI event loop for over 5 seconds");
                std::this_thread::sleep_for(std::chrono::milliseconds(50));
            }
        });
        infrastructure::database::Database db;const auto path=temporary_.filePath(flac?"throttled-flac.sqlite":"throttled-mp3.sqlite");
        QVERIFY(db.open(path));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);
        qmlbridge::PortableSession player(db,path,source);
        const QVariantMap track{{"trackId","online-seek"},{"title","Online seek"},{"durationMs",90000},
            {"remoteUrl",QString("http://127.0.0.1:%1/seek.%2").arg(upstream.serverPort()).arg(flac?"flac":"mp3")}};
        player.setPlaybackMode("stopAfterCurrent");player.playAll({track});
        QTRY_VERIFY_WITH_TIMEOUT(player.state()=="Playing"&&player.position()>500,12000);
        QVERIFY(player.seekable());
        qInfo("Seeking into unbuffered online media");
        const int rangesBefore=ranges;QElapsedTimer seekClock;seekClock.start();
        player.seek(58000);QTest::qWait(50);player.seek(60000);
        QTRY_VERIFY_WITH_TIMEOUT(player.position()>60250&&player.position()<65000,12000);
        qInfo("Forward seek to first advancing playback: %lld ms; Range reconnects: %d",seekClock.elapsed(),ranges-rangesBefore);
        if(responseDelay)QVERIFY2(seekClock.elapsed()<4000,"150 ms RTT must not turn one seek into many seconds of reconnects");
        QTRY_VERIFY_WITH_TIMEOUT(player.position()>61200&&player.position()<65000,4000);
        if(flac) QVERIFY(ranges>0);
        QCOMPARE(player.currentTrackId(),QString("online-seek"));
        player.seek(5000);
        QTRY_VERIFY_WITH_TIMEOUT(player.position()>6200&&player.position()<10000,12000);
        player.pause();QTRY_COMPARE(player.state(),QString("Paused"));
        player.seek(30000);player.play();
        QTRY_VERIFY_WITH_TIMEOUT(player.position()>31200&&player.position()<35000,12000);
        for(int i=0;i<5;++i){player.seek(10000+i*7000);QTest::qWait(60);}
        QTRY_VERIFY_WITH_TIMEOUT(player.position()>39200&&player.position()<43000,12000);
        player.stop();
    }
    void matchedLyricsRetainWordTranslationAndRomanization() {
        const QJsonObject response{
            {"lrc",QJsonObject{{"lyric","[00:01.000]Hello world\n[00:03.000]Goodbye"}}},
            {"yrc",QJsonObject{{"lyric","[1000,2000](1000,500,0)Hello (1500,1500,0)world\n[3000,500](3000,500,0)Goodbye"}}},
            {"tlyric",QJsonObject{{"lyric","[00:01.000]你好世界\n[00:03.000]再见"}}},
            {"romalrc",QJsonObject{{"lyric","[00:01.000]he lo\n[00:03.000]gu de bai"}}}
        };
        const auto bundle=online::matchedLyricBundle(response);
        const auto rows=online::parseTimedLyrics(bundle);
        QCOMPARE(rows.size(),2);
        const auto first=rows.first().toMap();
        QCOMPARE(first.value("text").toString(),"Hello world");
        QCOMPARE(first.value("translation").toString(),"你好世界");
        QCOMPARE(first.value("romanization").toString(),"he lo");
        QCOMPARE(first.value("words").toList().size(),2);
        QCOMPARE(first.value("words").toList().last().toMap().value("startMs").toLongLong(),1500);
        QCOMPARE(online::matchedLyricFeatures(bundle),(QStringList{"逐字","翻译","罗马音"}));
        QCOMPARE(online::matchedLyricFeatures(online::matchedLyricBundle({{"lrc",response.value("lrc")}})),QStringList{"逐行"});
        QCOMPARE(online::matchedLyricFeatures(online::matchedLyricBundle({})),QStringList{"无歌词"});
    }
    void realLyricMatchingAndRematching() {
        infrastructure::database::Database db;const auto path=temporary_.filePath("lyric-match.sqlite");
        QVERIFY(db.open(path));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);
        qmlbridge::PortableSession player(db,path,source);
        const auto media=temporary_.filePath("matched.mp3");QVERIFY(QFile::copy(mp3_,media));
        auto track=local(media);track["title"]="红色高跟鞋";track["artist"]="蔡健雅";
        for(const auto& query:QStringList{"红色高跟鞋 蔡健雅","达尔文 蔡健雅"}) {
            player.searchLyricMatches(track,query,"wy");
            QTRY_VERIFY_WITH_TIMEOUT(!player.lyricMatchBusy(),55000);
            QVERIFY2(!player.lyricCandidates().isEmpty(),qPrintable(player.lyricMatchError()));
            QCOMPARE(player.lyricCandidates().first().toMap().value("title").toString(),query.section(' ',0,0));
            player.previewLyricMatch(0);QTRY_VERIFY_WITH_TIMEOUT(!player.lyricMatchBusy(),20000);
            QVERIFY2(player.lyricPreview().contains("["),qPrintable(player.lyricMatchError()));
            QVERIFY(player.applyLyricMatch(track,player.lyricPreview()));
            QCOMPARE(player.readTrackTags(track).value("lyrics").toString(),player.lyricPreview());
        }
        player.searchLyricMatches(track,"取消请求");player.cancelLyricMatch();
        QTest::qWait(300);QVERIFY(!player.lyricMatchBusy());QVERIFY(player.lyricCandidates().isEmpty());
    }
    void mixedHttpTransitions_data() {
        QTest::addColumn<bool>("firstHttp");QTest::addColumn<bool>("secondHttp");
        QTest::addColumn<int>("rate");QTest::addColumn<int>("delay");
        QTest::newRow("local-to-http")<<false<<true<<44100<<0;
        QTest::newRow("http-to-http")<<true<<true<<44100<<0;
        QTest::newRow("http-to-local-48k")<<true<<false<<48000<<0;
        QTest::newRow("slow-next-http")<<false<<true<<44100<<4200;
    }
    void mixedHttpTransitions() {
        QFETCH(bool,firstHttp);QFETCH(bool,secondHttp);QFETCH(int,rate);QFETCH(int,delay);
        const auto wav=[](int sampleRate) {
            QByteArray data(sampleRate*3*4,0);
            for(int i=0;i<sampleRate*3;++i)for(int c=0;c<2;++c)
                qToLittleEndian<qint16>(qint16(3000*std::sin(2*3.141592653589793*997*i/sampleRate)),data.data()+i*4+c*2);
            QByteArray header("RIFF");const auto append=[&](quint32 v){char b[4];qToLittleEndian(v,b);header.append(b,4);};
            append(quint32(data.size()+36));header+="WAVEfmt ";append(16);header.append("\1\0\2\0",4);
            append(sampleRate);append(sampleRate*4);header.append("\4\0\20\0",4);header+="data";append(quint32(data.size()));
            return header+data;
        };
        const QList<QByteArray> media{wav(44100),wav(rate)};
        QTcpServer upstream;QVERIFY(upstream.listen(QHostAddress::LocalHost));int secondRequests=0;
        connect(&upstream,&QTcpServer::newConnection,this,[&] {
            while(upstream.hasPendingConnections()) {
                auto* socket=upstream.nextPendingConnection();connect(socket,&QTcpSocket::disconnected,socket,&QObject::deleteLater);
                connect(socket,&QTcpSocket::readyRead,socket,[&,socket] {
                    const auto request=socket->property("request").toByteArray()+socket->readAll();socket->setProperty("request",request);
                    if(!request.contains("\r\n\r\n")||socket->property("sent").toBool())return;
                    socket->setProperty("sent",true);const int index=request.startsWith("GET /1.wav")?1:0;
                    if(index==1)++secondRequests;
                    const auto match=QRegularExpression("Range: bytes=(\\d+)-",QRegularExpression::CaseInsensitiveOption).match(QString::fromLatin1(request));
                    const auto offset=match.hasMatch()?match.captured(1).toInt():0;
                    const auto data=media[index];
                    QTimer::singleShot(index==1?delay:0,socket,[socket,data,offset] {
                        if(socket->state()!=QAbstractSocket::ConnectedState)return;
                        const auto body=data.sliced(qMin(offset,int(data.size())));
                        socket->write("HTTP/1.1 206 Partial Content\r\nContent-Type: audio/wav\r\nAccept-Ranges: bytes\r\nContent-Range: bytes "+QByteArray::number(offset)+"-"+QByteArray::number(data.size()-1)+"/"+QByteArray::number(data.size())+"\r\nContent-Length: "+QByteArray::number(body.size())+"\r\nConnection: close\r\n\r\n"+body);
                        socket->disconnectFromHost();
                    });
                });
            }
        });
        QVariantList tracks;
        for(int index=0;index<2;++index) {
            const auto name=temporary_.filePath(QString(QTest::currentDataTag())+QString::number(index)+".wav");
            QFile file(name);QVERIFY(file.open(QIODevice::WriteOnly));file.write(media[index]);file.close();
            auto track=local(name);track["durationMs"]=3000;
            if(index==0?firstHttp:secondHttp){track.remove("localPath");track["remoteUrl"]=QString("http://127.0.0.1:%1/%2.wav").arg(upstream.serverPort()).arg(index);}
            tracks.append(track);
        }
        infrastructure::database::Database db;const auto path=temporary_.filePath(QString(QTest::currentDataTag())+".sqlite");
        QVERIFY(db.open(path));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);qmlbridge::PortableSession player(db,path,source);
        player.playAll(tracks);player.setPlaybackMode("listLoop");
        QTRY_VERIFY_WITH_TIMEOUT(player.state()=="Playing"&&player.position()>500,6000);
        QTRY_VERIFY_WITH_TIMEOUT(player.currentQueueIndex()==1&&player.state()=="Playing"&&player.position()>250,18000);
        if(secondHttp)QVERIFY(secondRequests>0);
        player.setPlaybackMode("stopAfterCurrent");
        QTRY_COMPARE_WITH_TIMEOUT(player.state(),QString("Stopped"),8000);
        QVERIFY(player.errorMessage().isEmpty());
    }
    void metadataAndLyricsPersist_data() {
        QTest::addColumn<bool>("flac");
        QTest::newRow("mp3")<<false;QTest::newRow("flac")<<true;
    }
    void metadataCoverPersists_data() { metadataAndLyricsPersist_data(); }
    void metadataCoverPersists() {
        QFETCH(bool,flac);
        const auto media=temporary_.filePath(flac?"cover.flac":"cover.mp3");
        QVERIFY(QFile::copy(flac?flac_:mp3_,media));
        QImage backImage(24,24,QImage::Format_RGB32);backImage.fill(Qt::blue);
        QByteArray back;QBuffer buffer(&back);buffer.open(QIODevice::WriteOnly);QVERIFY(backImage.save(&buffer,"PNG"));
        {
            TagLib::FileRef file(media.toStdWString().c_str(),false);
            auto pictures=file.complexProperties("PICTURE");
            pictures.append({{"data",TagLib::ByteVector(back.constData(),unsigned(back.size()))},{"pictureType","Back Cover"},{"mimeType","image/png"}});
            QVERIFY(file.setComplexProperties("PICTURE",pictures));QVERIFY(file.save());
        }
        infrastructure::database::Database db;const auto path=temporary_.filePath(flac?"cover-flac.sqlite":"cover-mp3.sqlite");
        QVERIFY(db.open(path));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);
        qmlbridge::PortableSession player(db,path,source);auto track=local(media);
        track["title"]="桃花诺";track["artist"]="G.E.M.邓紫棋";
        const auto before=player.readTrackTags(track);const auto modified=QFileInfo(media).lastModified();
        player.searchMetadataMatches(track,"桃花诺 邓紫棋",flac?"tx":"wy");
        QTRY_VERIFY_WITH_TIMEOUT(!player.metadataMatchBusy(),20000);QVERIFY(!player.metadataCandidates().isEmpty());
        player.previewMetadataArtwork(0);
        QTRY_VERIFY_WITH_TIMEOUT(!player.metadataArtwork().value("busy").toBool(),25000);
        QVERIFY2(!player.metadataArtwork().value("url").toString().isEmpty(),qPrintable(player.metadataArtwork().value("error").toString()));
        const auto cover=player.metadataMatchValues(0,{"artwork"});QCOMPARE(cover.size(),1);
        QVERIFY(!player.metadataMatchValues(0,{"title"}).contains("artwork"));
        QCOMPARE(QFileInfo(media).lastModified(),modified);QCOMPARE(player.readTrackTags(track),before);
        const auto coverPath=cover.value("artwork").toUrl().toLocalFile();QFile imageFile(coverPath);QVERIFY(imageFile.open(QIODevice::ReadOnly));const auto imageBytes=imageFile.readAll();
        player.previewMetadataArtwork(0);player.cancelMetadataMatch();QTest::qWait(150);
        QVERIFY(player.metadataArtwork().isEmpty());
        // Closing the search keeps the accepted draft available until the editor saves.
        QVERIFY(player.saveTrackTags(track,cover));QVERIFY(player.saveTrackTags(track,cover));
        const auto after=player.readTrackTags(track);
        for(const auto& key:QStringList{"title","artist","album","year","lyrics","durationMs"})QCOMPARE(after.value(key),before.value(key));
        QVERIFY(after.value("artwork")!=before.value("artwork"));
        QVERIFY(player.saveTrackTags(track,{{"comment","unchanged cover"}}));
        TagLib::FileRef file(media.toStdWString().c_str(),false);
        int fronts=0;bool hasBack=false;
        for(const auto& picture:file.complexProperties("PICTURE")) {
            const auto bytes=picture["data"].toByteVector();const QByteArray actual(bytes.data(),int(bytes.size()));
            if(picture["pictureType"].toString()=="Front Cover"){++fronts;QCOMPARE(actual,imageBytes);}
            if(picture["pictureType"].toString()=="Back Cover" && actual==back)hasBack=true;
        }
        QCOMPARE(fronts,1);QVERIFY(hasBack);
        const auto savedModified=QFileInfo(media).lastModified();
        QVERIFY(!player.saveTrackTags(track,{{"artwork","https://example.invalid/not-a-draft.jpg"}}));
        QCOMPARE(QFileInfo(media).lastModified(),savedModified);
    }
    void externalLyricFormats() {
        const auto read=[](const QString& path){QFile file(path);if(!file.open(QIODevice::ReadOnly))return QByteArray{};return file.readAll();};
        // QRC fixture generated by the independent LDDC Python implementation.
        const auto qrc=online::qrcWordLyrics(online::decodeQrc(QString::fromLatin1(read(QFINDTESTDATA("fixtures/lyrics/synthetic.qrc.hex")))));
        auto rows=online::parseTimedLyrics(qrc);QCOMPARE(rows.size(),2);
        auto first=rows.first().toMap();QCOMPARE(first.value("text").toString(),QString("Hello world"));
        QCOMPARE(first.value("words").toList().last().toMap().value("startMs").toLongLong(),1400);
        QCOMPARE(first.value("words").toList().last().toMap().value("endMs").toLongLong(),1900);
        const QStringList bundles{online::krcLyricBundle(read(QFINDTESTDATA("fixtures/lyrics/synthetic.krc"))),online::ttmlLyricBundle(read(QFINDTESTDATA("fixtures/lyrics/synthetic.ttml")))};
        for(const auto& bundle:bundles) {
            rows=online::parseTimedLyrics(bundle);QCOMPARE(rows.size(),2);first=rows.first().toMap();
            QCOMPARE(first.value("text").toString(),QString("Hello world"));
            QCOMPARE(first.value("translation").toString(),QString("你好世界"));
            QCOMPARE(first.value("romanization").toString(),QString("he lo"));
            QCOMPARE(first.value("words").toList().last().toMap().value("startMs").toLongLong(),1400);
            QCOMPARE(rows.last().toMap().value("translation").toString(),QString("再次"));
            QCOMPARE(rows.last().toMap().value("romanization").toString(),QString("a gain"));
            QCOMPARE(online::matchedLyricFeatures(bundle),(QStringList{"逐字","翻译","罗马音"}));
        }
        QVERIFY(online::decodeQrc("invalid").isEmpty());QVERIFY(online::krcLyricBundle("not a krc").isEmpty());QVERIFY(online::ttmlLyricBundle("<tt><p>").isEmpty());
    }
    void realAdditionalLyricSources_data() {
        QTest::addColumn<QString>("provider");QTest::addColumn<QString>("title");QTest::addColumn<QString>("artist");
        QTest::newRow("qq")<<QString("tx")<<QString("Animals")<<QString("Maroon 5");
        QTest::newRow("kugou")<<QString("kg")<<QString("红色高跟鞋")<<QString("蔡健雅");
        QTest::newRow("kuwo")<<QString("kw")<<QString("红色高跟鞋")<<QString("蔡健雅");
        QTest::newRow("migu")<<QString("mg")<<QString("红色高跟鞋")<<QString("蔡健雅");
        QTest::newRow("lrclib")<<QString("lrclib")<<QString("Animals")<<QString("Maroon 5");
        QTest::newRow("amll")<<QString("amll")<<QString("アイドル")<<QString("YOASOBI");
    }
    void realAdditionalLyricSources() {
        QFETCH(QString,provider);QFETCH(QString,title);QFETCH(QString,artist);
        infrastructure::database::Database db;const auto path=temporary_.filePath(provider+"-lyrics.sqlite");QVERIFY(db.open(path));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);qmlbridge::PortableSession player(db,path,source);
        const QVariantMap track{{"title",title},{"artist",artist}};
        player.searchLyricMatches(track,title+" "+artist,provider);QTRY_VERIFY_WITH_TIMEOUT(!player.lyricMatchBusy(),55000);
        QVERIFY2(!player.lyricCandidates().isEmpty(),qPrintable(player.lyricMatchError()));
        for(int i=0;i<qMin(6,int(player.lyricCandidates().size()));++i) {
            QCOMPARE(player.lyricCandidates()[i].toMap().value("lyricSource").toString(),provider);
            player.previewLyricMatch(i);QTRY_VERIFY_WITH_TIMEOUT(!player.lyricMatchBusy(),20000);
            if(!player.lyricPreviewLines().isEmpty())break;
        }
        QVERIFY2(!player.lyricPreviewLines().isEmpty(),qPrintable(player.lyricMatchError()));
        const auto features=online::matchedLyricFeatures(player.lyricPreview());
        qInfo()<<provider<<"candidates"<<player.lyricCandidates().size()<<"lines"<<player.lyricPreviewLines().size()<<"words"<<features.contains("逐字")<<"translation"<<features.contains("翻译")<<"romanization"<<features.contains("罗马音");
        if(provider=="amll")QVERIFY(online::matchedLyricFeatures(player.lyricPreview()).contains("翻译"));
        player.searchLyricMatches(track,title,"wy");player.searchLyricMatches(track,title,"invalid");
        QTest::qWait(350);QVERIFY(!player.lyricMatchBusy());QVERIFY(player.lyricCandidates().isEmpty());
    }
    void missingMetadataRelationsAreRepaired_data() { metadataAndLyricsPersist_data(); }
    void missingMetadataRelationsAreRepaired() {
        QFETCH(bool,flac);
        const auto media=temporary_.filePath(flac?"repair.flac":"repair.mp3");
        QVERIFY(QFile::copy(flac?flac_:mp3_,media));
        {
            TagLib::FileRef file(media.toStdWString().c_str(),false);QVERIFY(!file.isNull());
            auto properties=file.file()->properties();
            properties.replace("ARTIST",TagLib::StringList("Repair Artist"));
            properties.replace("ALBUM",TagLib::StringList("Repair Album"));
            file.file()->setProperties(properties);QVERIFY(file.save());
        }
        const auto modified=QFileInfo(media).lastModified();
        const auto size=QFileInfo(media).size();
        infrastructure::database::Database db;const auto path=temporary_.filePath(flac?"repair-flac.sqlite":"repair-mp3.sqlite");
        QVERIFY(db.open(path));QVERIFY(db.migrate());
        auto track=local(media);track["title"]="Existing title";
        domain::Track broken;broken.id=domain::TrackId(media.toStdString());broken.title="Existing title";broken.localPath=media.toStdString();
        QVERIFY(db.upsertTrack(broken));
        const auto fingerprint=db.loadLocalFiles().front();
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);
        qmlbridge::CollectionService lists(db);lists.toggleTrackLiked(track);
        qmlbridge::PortableSession player(db,path,source);
        connect(&player,&qmlbridge::PortableSession::trackMetadataChanged,&lists,&qmlbridge::CollectionService::updateTrackMetadata);
        player.enqueueTrack(track);
        QTRY_VERIFY(player.ready());
        const auto repaired=db.findTrack(broken.id);QVERIFY(repaired);
        QCOMPARE(repaired->artists.size(),std::size_t(1));QCOMPARE(repaired->artists.front().name,std::string("Repair Artist"));
        QVERIFY(repaired->album);QCOMPARE(repaired->album->title,std::string("Repair Album"));
        QCOMPARE(repaired->title,std::string("Existing title"));
        QCOMPARE(player.songs().first().toMap().value("artist").toString(),QString("Repair Artist"));
        QCOMPARE(player.queueSongs().first().toMap().value("artist").toString(),QString("Repair Artist"));
        QCOMPARE(lists.playlists().first().toMap().value("tracks").toList().first().toMap().value("artist").toString(),QString("Repair Artist"));
        QCOMPARE(db.getSetting("library.metadataRelationsVersion").value_or(""),std::string("1"));
        QCOMPARE(QFileInfo(media).lastModified(),modified);QCOMPARE(QFileInfo(media).size(),size);
        QCOMPARE(db.loadLocalFiles().front().modifiedMs,fingerprint.modifiedMs);
        // A late repair cannot replace a newer edit or resurrect a removed row.
        auto newer=*repaired;newer.artists={{"New Artist","New Artist"}};QVERIFY(db.upsertTrack(newer));
        QVERIFY(db.restoreMissingRelations(std::array{*repaired}));
        QCOMPARE(db.findTrack(broken.id)->artists.front().name,std::string("New Artist"));
        QVERIFY(db.removeTrack(QString::fromStdString(broken.id.value())));
        QVERIFY(db.restoreMissingRelations(std::array{*repaired}));QVERIFY(!db.findTrack(broken.id));
    }
    void realMetadataSearchPreviewAndCancel() {
        infrastructure::database::Database db;const auto path=temporary_.filePath("metadata-search.sqlite");
        QVERIFY(db.open(path));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);
        qmlbridge::PortableSession player(db,path,source);
        const auto media=temporary_.filePath("metadata-preview.mp3");QVERIFY(QFile::copy(mp3_,media));
        auto track=local(media);track["title"]="桃花诺";track["artist"]="G.E.M.邓紫棋";
        const auto before=player.readTrackTags(track);const auto modified=QFileInfo(media).lastModified();
        for (const auto& platform:QStringList{"wy","tx"}) {
            player.searchMetadataMatches(track,"桃花诺 邓紫棋",platform);
            QTRY_VERIFY_WITH_TIMEOUT(!player.metadataMatchBusy(),20000);
            QVERIFY2(!player.metadataCandidates().isEmpty(),qPrintable(platform+": "+player.metadataMatchError()));
            const auto values=player.metadataMatchValues(0,{"title","artist","album","year","trackId","localPath","source","lyrics"});
            QVERIFY(!values.value("title").toString().isEmpty());QVERIFY(!values.value("artist").toString().isEmpty());
            for(const auto& key:values.keys())QVERIFY((QStringList{"title","artist","album"}).contains(key));
            const auto artistOnly=player.metadataMatchValues(0,{"artist"});QCOMPARE(artistOnly.size(),1);QVERIFY(artistOnly.contains("artist"));
            QVERIFY(player.metadataMatchValues(0,{}).isEmpty());QVERIFY(player.metadataMatchValues(-1,{"title"}).isEmpty());
            QCOMPARE(player.readTrackTags(track),before);QCOMPARE(QFileInfo(media).lastModified(),modified);
            QVERIFY(player.searchResults().isEmpty());QVERIFY(player.lastQuery().isEmpty());QVERIFY(player.lyricCandidates().isEmpty());
        }
        player.searchMetadataMatches(track,"达尔文 蔡健雅","wy");player.cancelMetadataMatch();
        QTest::qWait(350);QVERIFY(!player.metadataMatchBusy());QVERIFY(player.metadataCandidates().isEmpty());
        player.searchMetadataMatches(track,"桃花诺","wy");player.searchMetadataMatches({},"","invalid");
        QTest::qWait(350);QVERIFY(player.metadataCandidates().isEmpty());QVERIFY(!player.metadataMatchError().isEmpty());
    }
    void lyricRematchPreservesPlayback_data() {
        QTest::addColumn<bool>("flac");QTest::addColumn<bool>("paused");
        QTest::newRow("mp3-playing")<<false<<false;QTest::newRow("flac-playing")<<true<<false;
        QTest::newRow("mp3-paused")<<false<<true;QTest::newRow("flac-paused")<<true<<true;
    }
    void lyricCandidatesContainOnlyUsableLyrics_data() {
        QTest::addColumn<QString>("title");QTest::addColumn<QString>("artist");
        QTest::newRow("animals")<<QString("Animals")<<QString("Maroon 5");
        QTest::newRow("thank-you-for-dears")<<QString("Thank you for dears.")<<QString("GET IN THE RING");
        QTest::newRow("filename-only")<<QString("Animals - Maroon 5")<<QString{};
    }
    void unusableLyricResponsesAreRejected() {
        for(const auto& text:QStringList{"", "  \n\t", "[00:00.00]", "[ar:Someone]\n[ti:Title]",
                "[00:00.00]纯音乐，请欣赏", "[00:00.00]暂无歌词", "Instrumental", "No lyrics available.",
                "[00:00.00]作词：某人\n[00:01.00]作曲：某人"})
            QVERIFY2(!online::hasUsableMatchedLyrics(text),qPrintable(text));
        for(const auto& text:QStringList{"A real lyric line", "[00:01.00]ありがとう", "[ar:Someone]\n[00:01.00]Hello world",
                online::packLyricTracks({},"[00:01.00]<0,500>Hello",{},{}),
                "[00:00.00]作词：某人\n[00:01.00]歌词正文"})
            QVERIFY2(online::hasUsableMatchedLyrics(text),qPrintable(text));
        const QString lyrics="[00:01.00]Hello world";
        QCOMPARE(online::matchedLyricIdentity("[ar:One]\n"+lyrics),online::matchedLyricIdentity("[ar:Two]\n"+lyrics));
        QVERIFY(online::matchedLyricIdentity(lyrics)!=online::matchedLyricIdentity(online::packLyricTracks(lyrics,{},"[00:01.00]你好世界",{})));
        QVERIFY(online::matchedLyricIdentity(lyrics)!=online::matchedLyricIdentity(online::packLyricTracks(lyrics,"[00:01.00]<0,500>Hello <500,500>world",{},{})));
    }
    void sampleFileLyricSearch() {
        const QString media="E:/Music/new/Thank you for dears. - GET IN THE RING.flac";
        if(!QFileInfo::exists(media))QSKIP("Optional local sample is absent");
        const auto modified=QFileInfo(media).lastModified();
        infrastructure::database::Database db;const auto path=temporary_.filePath("sample-lyric.sqlite");
        QVERIFY(db.open(path));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);qmlbridge::PortableSession player(db,path,source);
        const auto seed=player.lyricMatchSeed({{"localPath",media}});
        qInfo()<<"sample tags"<<seed.value("title")<<seed.value("artist")<<seed.value("album")<<seed.value("durationMs");
        player.searchLyricMatches(seed,seed.value("query").toString());
        QTRY_VERIFY_WITH_TIMEOUT(!player.lyricMatchBusy(),45000);
        QVERIFY2(!player.lyricCandidates().isEmpty(),qPrintable(player.lyricMatchError()));
        for(int i=0;i<player.lyricCandidates().size();++i) {
            player.previewLyricMatch(i);QVERIFY(online::hasUsableMatchedLyrics(player.lyricPreview()));
            const auto row=player.lyricCandidates()[i].toMap();
            qInfo()<<row.value("sourceLabel")<<row.value("title")<<row.value("score")<<row.value("features")<<"lines"<<player.lyricPreviewLines().size();
        }
        QCOMPARE(QFileInfo(media).lastModified(),modified);
    }
    void lyricCandidatesContainOnlyUsableLyrics() {
        QFETCH(QString,title);QFETCH(QString,artist);
        infrastructure::database::Database db;const auto path=temporary_.filePath(title+"-usable.sqlite");
        QVERIFY(db.open(path));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);qmlbridge::PortableSession player(db,path,source);
        const QVariantMap track=artist.isEmpty()?player.lyricMatchSeed({{"localPath","C:/missing/"+title+".mp3"}}):QVariantMap{{"title",title},{"artist",artist}};
        player.searchLyricMatches(track,title+" "+artist);
        QTRY_VERIFY_WITH_TIMEOUT(!player.lyricMatchBusy(),45000);
        QVERIFY2(!player.lyricCandidates().isEmpty(),qPrintable(player.lyricMatchError()));
        const auto results=player.lyricCandidates();
        qInfo()<<title<<"visible candidates"<<results.size();
        int previous=101;QSet<QString> identities;QHash<QString,int> counts;
        for(int i=0;i<results.size();++i) {
            const auto row=results[i].toMap();const auto features=row.value("features").toStringList();
            QVERIFY(++counts[row.value("lyricSource").toString()]<=3);
            QVERIFY2(!features.contains("待读取")&&!features.contains("待查收录")&&!features.contains("读取失败")&&!features.contains("未收录")&&!features.contains("无歌词"),qPrintable(row.value("sourceLabel").toString()+":"+features.join(',')));
            QVERIFY(row.value("score").toInt()<=previous);previous=row.value("score").toInt();
            player.previewLyricMatch(i);
            QVERIFY(!player.lyricMatchBusy()); // Every visible result is already verified and cached.
            QVERIFY(!player.lyricPreview().trimmed().isEmpty());
            QVERIFY(!player.lyricPreviewLines().isEmpty());
            QVERIFY(online::hasUsableMatchedLyrics(player.lyricPreview()));
            const auto identity=row.value("lyricSource").toString()+QChar(0x1f)+online::matchedLyricIdentity(player.lyricPreview());
            QVERIFY(!identities.contains(identity));identities.insert(identity);
            qInfo()<<row.value("sourceLabel").toString()<<row.value("title").toString()<<row.value("artist").toString()<<row.value("score").toInt()<<features<<"lines"<<player.lyricPreviewLines().size();
        }
    }
    void lyricRematchPreservesPlayback() {
        QFETCH(bool,flac);QFETCH(bool,paused);
        const auto stem=QString("rematch-%1-%2").arg(flac).arg(paused);
        const auto media=temporary_.filePath(stem+(flac?".flac":".mp3"));
        QVERIFY(QFile::copy(flac?flac_:mp3_,media));
        const auto modified=QFileInfo(media).lastModified();
        infrastructure::database::Database db;const auto path=temporary_.filePath(stem+".sqlite");
        QVERIFY(db.open(path));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);
        qmlbridge::PortableSession player(db,path,source);
        QVERIFY(player.enqueueTrack(local(media)));QVERIFY(player.enqueueTrack(local(third_)));
        QVERIFY(player.selectQueue(0,true));QTRY_VERIFY_WITH_TIMEOUT(player.position()>700,8000);
        player.seek(12000);QTRY_VERIFY_WITH_TIMEOUT(player.position()>11500,8000);
        if(paused){player.pause();QTRY_COMPARE(player.state(),QString("Paused"));}
        const auto entry=player.currentTrack().value("entryId");const auto before=player.position();
        QString lyric;
        for(int i=0;i<160;++i)lyric+=QString("[%1:%2.00]Rematched lyric %3, preserve the current recording and playback position.\n").arg(i/60,2,10,QChar('0')).arg(i%60,2,10,QChar('0')).arg(i);
        for(int i=0;i<2;++i) {
            const auto text=lyric+QString("[03:00.00]Match %1").arg(i);
            if(i==0)QVERIFY(player.applyLyricMatch(player.currentTrack(),text));
            else {
                const auto tags=player.readTrackTags(player.currentTrack());
                QVERIFY(player.saveTrackTags(player.currentTrack(),{{"title",tags.value("title")},{"artist",tags.value("artist")},{"album",tags.value("album")},{"lyrics",text}}));
            }
            QTest::qWait(1400);
            QCOMPARE(player.currentTrack().value("entryId"),entry);
            QCOMPARE(player.state(),paused?QString("Paused"):QString("Playing"));
            QVERIFY(player.position()>=before-200);QVERIFY(player.position()<before+9000);
        }
        QVERIFY(player.readTrackTags(local(media)).value("lyrics").toString().contains("Rematched lyric"));
        QVERIFY(!player.lyrics().isEmpty());
        QCOMPARE(QFileInfo(media).lastModified(),modified);
        if(paused) {
            player.play();QTRY_COMPARE(player.state(),QString("Playing"));QTest::qWait(1800);
            QCOMPARE(player.currentTrack().value("entryId"),entry);
            QVERIFY(player.position()>before);QVERIFY(player.position()<before+9000);
        }
        if(paused)player.stop();else player.next();
        // Wait for the writer to release the file before opening another TagLib
        // handle: FileRef also requests write access on Windows.
        QTRY_COMPARE_WITH_TIMEOUT(db.getSetting("lyrics.pendingEmbedded").value_or("{}"),std::string("{}"),10000);
        const auto embedded=[&] {
            TagLib::FileRef file(media.toStdWString().c_str(),false);
            return file.isNull()?QString{}:QString::fromStdString(file.file()->properties()["LYRICS"].toString("\n").to8Bit(true));
        };
        QVERIFY(embedded().contains("Match 1"));
        QVERIFY(!QFileInfo::exists(temporary_.filePath(stem+".lrc")));
    }
    void lyricMatchSeedUsesTagsThenFilename() {
        infrastructure::database::Database db;const auto path=temporary_.filePath("lyric-seed.sqlite");
        QVERIFY(db.open(path));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);
        qmlbridge::PortableSession player(db,path,source);
        const auto media=temporary_.filePath("文件名歌曲 - 文件名艺术家.mp3");QVERIFY(QFile::copy(mp3_,media));
        auto track=local(media);track["title"]="陈旧的列表标题";track["artist"]="未知艺术家";
        QVERIFY(player.saveTrackTags(track,{{"title","标签标题"},{"artist","标签艺术家"},{"album","标签专辑"}}));
        auto seed=player.lyricMatchSeed(track);
        QCOMPARE(seed.value("query").toString(),QString("标签标题 标签艺术家"));
        QCOMPARE(seed.value("album").toString(),QString("标签专辑"));
        QVERIFY(player.saveTrackTags(track,{{"title",""},{"artist",""}}));
        seed=player.lyricMatchSeed(track);
        QCOMPARE(seed.value("query").toString(),QString("文件名歌曲 - 文件名艺术家"));
        QCOMPARE(seed.value("title"),seed.value("query"));
        QVERIFY(seed.value("artist").toString().isEmpty());
        QCOMPARE(player.lyricMatchSeed({{"title","Online title"},{"artist","Online artist"}}).value("query").toString(),QString("Online title Online artist"));
    }
    void embeddedLyricsOnFinishAndExit_data() {
        QTest::addColumn<bool>("flac");QTest::addColumn<bool>("exit");
        QTest::newRow("mp3-finish")<<false<<false;QTest::newRow("flac-finish")<<true<<false;
        QTest::newRow("mp3-exit")<<false<<true;QTest::newRow("flac-exit")<<true<<true;
    }
    void embeddedLyricsResumePersistedJob() {
        const auto media=temporary_.filePath("lyric-persisted.mp3");QVERIFY(QFile::copy(mp3_,media));
        infrastructure::database::Database db;const auto path=temporary_.filePath("lyric-persisted.sqlite");
        QVERIFY(db.open(path));QVERIFY(db.migrate());
        const QString lyric="[00:00.00]Recovered pending lyrics";
        QVERIFY(db.setSetting("lyrics.pendingEmbedded",QString::fromUtf8(QJsonDocument(QJsonObject{{QFileInfo(media).absoluteFilePath(),lyric}}).toJson(QJsonDocument::Compact))));
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);
        qmlbridge::PortableSession player(db,path,source);
        QCOMPARE(player.readTrackTags(local(media)).value("lyrics").toString(),lyric);
        QTRY_COMPARE_WITH_TIMEOUT(db.getSetting("lyrics.pendingEmbedded").value_or("{}"),std::string("{}"),10000);
        TagLib::FileRef file(media.toStdWString().c_str(),false);QVERIFY(!file.isNull());
        QCOMPARE(QString::fromStdString(file.file()->properties()["LYRICS"].toString().to8Bit(true)),lyric);
        QVERIFY(!QFileInfo::exists(temporary_.filePath("lyric-persisted.lrc")));
    }
    void embeddedLyricsOnFinishAndExit() {
        QFETCH(bool,flac);QFETCH(bool,exit);
        const auto stem=QString("lyric-release-%1-%2").arg(flac).arg(exit);
        const auto media=temporary_.filePath(stem+(flac?".flac":".mp3"));QVERIFY(QFile::copy(flac?flac_:mp3_,media));
        infrastructure::database::Database db;const auto path=temporary_.filePath(stem+".sqlite");
        QVERIFY(db.open(path));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);
        {
            qmlbridge::PortableSession player(db,path,source);
            player.playAll({local(media),local(third_)});QTRY_VERIFY_WITH_TIMEOUT(player.position()>500,8000);
            QVERIFY(player.applyLyricMatch(player.currentTrack(),"[00:00.00]Embedded after release"));
            if(!exit) {
                player.seek(player.duration()-700);
                QTRY_COMPARE_WITH_TIMEOUT(db.getSetting("lyrics.pendingEmbedded").value_or("{}"),std::string("{}"),10000);
            }
        }
        TagLib::FileRef file(media.toStdWString().c_str(),false);QVERIFY(!file.isNull());
        QVERIFY(QString::fromStdString(file.file()->properties()["LYRICS"].toString().to8Bit(true)).contains("Embedded after release"));
        QCOMPARE(db.getSetting("lyrics.pendingEmbedded").value_or("{}"),std::string("{}"));
        QVERIFY(!QFileInfo::exists(temporary_.filePath(stem+".lrc")));
    }
    void metadataAndLyricsPersist() {
        QFETCH(bool,flac);
        const auto media=temporary_.filePath(flac?"metadata.flac":"metadata.mp3");
        QVERIFY(QFile::copy(flac?flac_:mp3_,media));
        const auto sidecar=temporary_.filePath("metadata.lrc");
        { QFile file(sidecar);QVERIFY(file.open(QIODevice::WriteOnly));file.write("[00:01.00]Original sidecar"); }
        infrastructure::database::Database db;const auto path=temporary_.filePath(flac?"tags-flac.sqlite":"tags-mp3.sqlite");
        QVERIFY(db.open(path));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);
        auto track=local(media);
        domain::Track stored;stored.id=domain::TrackId(media.toStdString());stored.title="Original";stored.localPath=media.toStdString();QVERIFY(db.upsertTrack(stored));
        qmlbridge::PortableSession player(db,path,source);
        qmlbridge::CollectionService lists(db);lists.toggleTrackLiked(track);
        connect(&player,&qmlbridge::PortableSession::trackMetadataChanged,&lists,&qmlbridge::CollectionService::updateTrackMetadata);
        player.enqueueTrack(track);
        // An indexed song becomes editable after the startup library load.
        QTRY_VERIFY_WITH_TIMEOUT(player.ready(),10000);
        const auto initial=player.readTrackTags(track);
        QVERIFY(initial.value("sampleRate").toInt()>0);QVERIFY(initial.value("fileSize").toLongLong()>0);
        QVariantMap tags{{"title","标签保存测试"},{"artist","测试艺术家"},{"album","测试专辑"},{"track","3/12"},{"disc","1/2"},{"year","2026"},{"genre","Test"},{"albumArtist","专辑艺术家"},{"composer","作曲者"},{"comment","保留封面"},{"lyrics","[00:01.00]已保存歌词\n[00:02.00]第二行"}};
        QSignalSpy updated(&player,&qmlbridge::PortableSession::trackMetadataChanged);
        QVERIFY(player.saveTrackTags(track,tags));QCOMPARE(updated.count(),1);
        auto actual=player.readTrackTags(track);
        for(auto it=tags.begin();it!=tags.end();++it)QCOMPARE(actual.value(it.key()).toString(),it.value().toString());
        QCOMPARE(player.queueSongs().first().toMap().value("title").toString(),QString("标签保存测试"));
        QCOMPARE(QString::fromStdString(db.findTrack(stored.id)->title),QString("标签保存测试"));
        const auto savedTrack=db.findTrack(stored.id);
        QCOMPARE(savedTrack->artists.size(),std::size_t(1));
        QCOMPARE(QString::fromStdString(savedTrack->artists.front().name),QString("测试艺术家"));
        QVERIFY(savedTrack->album.has_value());
        QCOMPARE(QString::fromStdString(savedTrack->album->title),QString("测试专辑"));
        qmlbridge::CollectionService restoredLists(db);
        QCOMPARE(restoredLists.playlists().first().toMap().value("tracks").toList().first().toMap().value("title").toString(),QString("标签保存测试"));
        QVERIFY(player.applyLyricMatch(track,"[00:01.00]重新匹配的歌词"));
        const auto lyricsSavedTrack=db.findTrack(stored.id);
        QCOMPARE(lyricsSavedTrack->artists.size(),std::size_t(1));
        QCOMPARE(QString::fromStdString(lyricsSavedTrack->artists.front().name),QString("测试艺术家"));
        QVERIFY(lyricsSavedTrack->album.has_value());
        QCOMPARE(QString::fromStdString(lyricsSavedTrack->album->title),QString("测试专辑"));
        QCOMPARE(player.readTrackTags(track).value("lyrics").toString(),QString("[00:01.00]重新匹配的歌词"));
        QTRY_COMPARE_WITH_TIMEOUT(db.getSetting("lyrics.pendingEmbedded").value_or("{}"),std::string("{}"),10000);
        { QFile file(sidecar);QVERIFY(file.open(QIODevice::ReadOnly));QCOMPARE(QString::fromUtf8(file.readAll()),QString("[00:01.00]重新匹配的歌词")); }
        TagLib::FileRef reopened(media.toStdWString().c_str(),false);QVERIFY(!reopened.isNull());
        QCOMPARE(QString::fromStdString(reopened.file()->properties()["TITLE"].front().to8Bit(true)),QString("标签保存测试"));
        QCOMPARE(online::lyricCandidateScore(tags,tags),90); // Duration is deliberately unknown.
        tags["durationMs"]=180000;
        QCOMPARE(online::lyricCandidateScore(tags,tags),100);
        auto wrong=tags;wrong["title"]="完全不同的标题";QVERIFY(online::lyricCandidateScore(tags,wrong)<80);
    }
    void equalizerPcmAndPersistence() {
        const auto base=qEnvironmentVariable("LISTENFREE_TEST_PCM");if(base.isEmpty())QSKIP("Requires isolated PCM output");
        QByteArray pcm;const int rate=44100,frames=rate*3;pcm.resize(frames*4);
        for(int i=0;i<frames;++i)for(int c=0;c<2;++c)qToLittleEndian<qint16>(qint16((c?-3000:3000)*std::sin(2*3.141592653589793*1000*i/rate)),pcm.data()+i*4+c*2);
        const auto wave=temporary_.filePath("eq.wav");
        QFile wav(wave);QVERIFY(wav.open(QIODevice::WriteOnly));
        QByteArray header(44,0);memcpy(header.data(),"RIFF",4);qToLittleEndian<quint32>(36+quint32(pcm.size()),header.data()+4);memcpy(header.data()+8,"WAVEfmt ",8);
        qToLittleEndian<quint32>(16,header.data()+16);qToLittleEndian<quint16>(1,header.data()+20);qToLittleEndian<quint16>(2,header.data()+22);
        qToLittleEndian<quint32>(rate,header.data()+24);qToLittleEndian<quint32>(rate*4,header.data()+28);qToLittleEndian<quint16>(4,header.data()+32);qToLittleEndian<quint16>(16,header.data()+34);
        memcpy(header.data()+36,"data",4);qToLittleEndian<quint32>(quint32(pcm.size()),header.data()+40);wav.write(header);wav.write(pcm);wav.close();
        infrastructure::database::Database db;const auto path=temporary_.filePath("eq.sqlite");QVERIFY(db.open(path));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);
        double rms[5]{};
        for(int pass=0;pass<5;++pass) {
            const auto output=base+"-eq-"+QString::number(pass);qputenv("LISTENFREE_TEST_PCM",output.toUtf8());
            qmlbridge::PortableSession player(db,path,source);player.resetEqualizer();player.setEqualizerAutoHeadroom(false);player.setEqualizerBand(5,pass==2?-6:pass>=3?6:0);player.setEqualizerEnabled(pass!=0);
            if(pass==4)player.setAudioEffect("mono",true);
            player.setPlaybackMode("stopAfterCurrent");player.setVolume(1);player.playAll({local(wave)});
            QTRY_VERIFY_WITH_TIMEOUT(player.position()>700,5000);
            player.pause();QTRY_COMPARE(player.state(),QString("Paused"));player.play();
            QTRY_COMPARE_WITH_TIMEOUT(player.state(),QString("Stopped"),6000);
            QTRY_VERIFY_WITH_TIMEOUT(QFileInfo(output).size()>rate*8,5000);
            QFile capture(output);QVERIFY(capture.open(QIODevice::ReadOnly));const auto bytes=capture.readAll();QVERIFY(bytes.size()>rate*8);
            double energy=0;int count=0;
            for(qsizetype i=rate*4;i<rate*8;i+=4){double sample=qFromLittleEndian<qint16>(bytes.constData()+i);energy+=sample*sample;++count;}
            rms[pass]=std::sqrt(energy/count);
        }
        for(int i=1;i<4;++i) { const double measuredDb=20*std::log10(rms[i]/rms[0]); const double expected=i==1?0:i==2?-6:6; qInfo("EQ case %d: %.5f dB",i,measuredDb); QVERIFY2(std::abs(measuredDb-expected)<.15,qPrintable(QString("Expected %1 dB, got %2").arg(expected).arg(measuredDb))); }
        // Antiphase stereo cancels only if the deployed sound Effect is actually
        // processing the playback chain, rather than merely accepting UI values.
        QVERIFY2(rms[4]<1,"The sound-effects mono control must reach real PCM output");
        {qmlbridge::PortableSession restored(db,path,source);QVERIFY(restored.equalizerEnabled());QCOMPARE(restored.equalizerGains()[5].toDouble(),6.0);restored.setEqualizerEnabled(false);restored.resetAudioEffects();}
        qputenv("LISTENFREE_TEST_PCM",base.toUtf8());
    }
    void changingModeDoesNotRestartAudio() {
        const auto capture=qEnvironmentVariable("LISTENFREE_TEST_PCM");
        if(capture.isEmpty())QSKIP("Requires isolated PCM output");
        infrastructure::database::Database db;
        const auto path=temporary_.filePath("mode-continuity.sqlite");
        QVERIFY(db.open(path)); QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);
        qmlbridge::SourceController source(&repo);
        qmlbridge::PortableSession player(db,path,source);
        player.playAll({local(mp3_),local(flac_)});
        QTRY_VERIFY_WITH_TIMEOUT(player.state()=="Playing" && player.position()>800,10000);
        player.seek(player.duration()-9000);
        QTest::qWait(1200);
        QFile before(capture+".format"); QVERIFY(before.open(QIODevice::ReadOnly));
        const auto outputs=before.readAll().count('\n');before.close();
        player.setPlaybackMode("stopAfterCurrent");
        QTest::qWait(800);
        QFile after(capture+".format");QVERIFY(after.open(QIODevice::ReadOnly));
        QCOMPARE(after.readAll().count('\n'),outputs);
        QCOMPARE(player.currentQueueIndex(),0);
        player.stop();
    }
    void likedSongsPersistAndToggleByIdentity() {
        infrastructure::database::Database db;
        QVERIFY(db.open(temporary_.filePath("liked.sqlite"))); QVERIFY(db.migrate());
        QVariantMap track{{"trackId","kw:450444"},{"source","kw"},{"rid","450444"},{"title","红色高跟鞋"},{"resolvedUrl","http://localhost/ephemeral"}};
        qmlbridge::CollectionService lists(db);
        QVERIFY(!lists.isTrackLiked(track)); lists.toggleTrackLiked(track); QVERIFY(lists.isTrackLiked(track));
        QCOMPARE(lists.playlists().first().toMap().value("title").toString(),QString("我喜欢的音乐"));
        QVERIFY(!lists.playlists().first().toMap().value("tracks").toList().first().toMap().contains("resolvedUrl"));
        qmlbridge::CollectionService restored(db); QVERIFY(restored.isTrackLiked(track));
        auto other=track;other["source"]="wy";other["trackId"]="wy:450444"; restored.toggleTrackLiked(other);
        QCOMPARE(restored.playlists().first().toMap().value("tracks").toList().size(),2);
        restored.toggleTrackLiked(track); QVERIFY(!restored.isTrackLiked(track)); QVERIFY(restored.isTrackLiked(other));
        auto file=local(mp3_);restored.toggleTrackLiked(file); QVERIFY(restored.isTrackLiked(file));
        file["localPath"]=QDir::toNativeSeparators(mp3_).toUpper(); restored.toggleTrackLiked(file); QVERIFY(!restored.isTrackLiked(local(mp3_)));
    }
    void initTestCase() {
        originalPcm_=qEnvironmentVariable("LISTENFREE_TEST_PCM");
        QVERIFY(temporary_.isValid());
        QCoreApplication::setOrganizationName("ListenFreePortableTests");
        QCoreApplication::instance()->setProperty("listenfreeDataDir", temporary_.path());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, temporary_.path());
        QSettings::setPath(QSettings::IniFormat, QSettings::SystemScope, temporary_.path());
        Qmmp::setConfigDir(temporary_.filePath("qmmp"));
#ifdef Q_OS_WIN
        CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
#endif
        QDirIterator files(qEnvironmentVariable("LISTENFREE_TEST_MUSIC_ROOT", "E:/Music"), {"*.mp3", "*.flac"}, QDir::Files, QDirIterator::Subdirectories);
        while (files.hasNext() && (mp3_.isEmpty() || flac_.isEmpty())) {
            const auto path = files.next();
            if (path.endsWith(".mp3", Qt::CaseInsensitive) && mp3_.isEmpty()) mp3_ = path;
            if (path.endsWith(".flac", Qt::CaseInsensitive) && flac_.isEmpty()) flac_ = path;
        }
        QVERIFY(!mp3_.isEmpty()); QVERIFY(!flac_.isEmpty());
        third_=temporary_.filePath("third-track.mp3");QVERIFY(QFile::copy(mp3_,third_));
    }
    void cleanup() { qputenv("LISTENFREE_TEST_PCM",originalPcm_.toUtf8()); qunsetenv("LISTENFREE_FAULT_MODE"); }
    void lyricTimingAndTranslation() {
        const auto rows=online::parseTimedLyrics("[kuwo:072]\n[00:01.00]<800,-800>Hello <2200,-200>world\n[00:01.00]译文\n[00:05.00]Next");
        QCOMPARE(rows.size(),2);
        QCOMPARE(rows[0].toMap().value("translation").toString(),QStringLiteral("译文"));
        const auto words=rows[0].toMap().value("words").toList();
        QCOMPARE(words.size(),2);
        QCOMPARE(words[0].toMap().value("startMs").toLongLong(),1000);
        QCOMPARE(words[0].toMap().value("endMs").toLongLong(),1100);
        QCOMPARE(words[1].toMap().value("startMs").toLongLong(),1200);
        QCOMPARE(words[1].toMap().value("endMs").toLongLong(),1350);
        QVERIFY(online::decodeKuwoLyrics("not lyrics").isEmpty());
    }
    void embeddedAizoWords() {
        const QString path="E:/Music/new/AIZO - King Gnu.flac";
        if(!QFileInfo::exists(path))QSKIP("User verification media unavailable");
        TagLib::FileRef file(path.toStdWString().c_str(),false);QVERIFY(!file.isNull());
        const auto raw=file.file()->properties()["LYRICS"].front();
        const auto rows=online::parseTimedLyrics(QString::fromStdString(raw.to8Bit(true)));
        int words=0,translations=0;bool luv=false;
        for(const auto& v:rows){const auto row=v.toMap();words+=row.value("words").toList().size();if(!row.value("translation").toString().isEmpty())++translations;
            if(row.value("timeMs").toLongLong()==10104){const auto w=row.value("words").toList();QCOMPARE(w.size(),4);QCOMPARE(w[1].toMap().value("startMs").toLongLong(),10336);luv=true;}}
        QVERIFY(luv);QVERIFY(words>500);QVERIFY(translations>30);
    }
    void appleArtistVisuals() {
        online::AppleDynamicArtworkProvider provider;
        bool done=false;QVariantMap visual;
        provider.fetchArtist("Taylor Swift",[&](QVariantMap result){visual=result;done=true;});
        QTRY_VERIFY_WITH_TIMEOUT(done,45000);
        QVERIFY2(!visual.value("hero").toString().isEmpty(),"Apple artist artwork unavailable");
        QCOMPARE(visual.value("source").toString(), QString("apple"));
        QCOMPARE(visual.value("id").toString(), QString("159260351"));
        QCOMPARE(visual.value("heroKind").toString(), QString("centeredFullscreenBackground"));
        QCOMPARE(visual.value("signatureKind").toString(), QString("musicContentColorLogoTrimmed"));
        QNetworkAccessManager network;
        for (const auto& key : QStringList{"hero", "signature"}) {
            auto* reply = network.get(QNetworkRequest(visual.value(key).toUrl()));
            QSignalSpy finished(reply, &QNetworkReply::finished);
            QTRY_VERIFY_WITH_TIMEOUT(!finished.isEmpty(),20000);
            QCOMPARE(reply->error(), QNetworkReply::NoError);
            const auto image = QImage::fromData(reply->readAll()); reply->deleteLater();
            QVERIFY(!image.isNull());
            if (key == "signature") QVERIFY(image.hasAlphaChannel());
        }
        done=false;
        provider.fetchArtist("Natalie Taylor",[&](QVariantMap result){visual=result;done=true;});
        QTRY_VERIFY_WITH_TIMEOUT(done,35000);
        QCOMPARE(visual.value("source").toString(),QString("apple"));
        QCOMPARE(visual.value("id").toString(),QString("400555769"));
        QVERIFY(!visual.value("hero").toString().isEmpty());
        QVERIFY(visual.value("signature").toString().isEmpty());
    }
    void onlineFavoritesStoreReferences() {
        infrastructure::database::Database db;QVERIFY(db.open(temporary_.filePath("references.sqlite")));QVERIFY(db.migrate());
        qmlbridge::CollectionService service(db);
        const QVariantMap first{{"id","42"},{"source","kw"},{"kind","playlist"},{"title","收藏"},{"tracks",QVariantList{local(mp3_)}}};
        auto second=first;second["source"]="wy";
        service.toggleSaved(first);service.toggleSaved(second);
        QCOMPARE(service.playlists().size(),2);
        service.addTracks(service.playlists()[0].toMap().value("id").toString(),{local(mp3_)});
        QVERIFY(!service.playlists()[0].toMap().contains("tracks"));
        QVERIFY(service.isSaved(first));QVERIFY(service.isSaved(second));
        for(const auto& v:service.playlists()){const auto row=v.toMap();QVERIFY(!row.contains("tracks"));QCOMPARE(row.value("playlistId").toString(),QString("42"));QVERIFY(!row.value("url").toString().isEmpty());}
        QVERIFY(service.playlists()[0].toMap().value("id")!=service.playlists()[1].toMap().value("id"));
        service.toggleSaved(first);QVERIFY(!service.isSaved(first));QVERIFY(service.isSaved(second));
        qmlbridge::CollectionService restored(db);QVERIFY(restored.isSaved(second));
        QVERIFY(service.create("  ").isEmpty());
    }
    void replacingSearchDoesNotPublishCancelledReply() {
        infrastructure::database::Database db;
        const auto path=temporary_.filePath("search-cancel.sqlite");
        QVERIFY(db.open(path));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);
        qmlbridge::SourceController sources(&repo);
        qmlbridge::PortableSession player(db,path,sources);
        QSignalSpy notices(&player,&qmlbridge::PortableSession::notice);
        // Exercise both reply-handler branches without waiting for any remote
        // response: abort must be harmless even when finished is synchronous.
        for(const auto& platform:QStringList{"kw","wy"}) {
            player.setPlatform(platform);
            player.search("cancelled search first");QVERIFY(player.busy());
            player.search("cancelled search replacement");QVERIFY(player.busy());
            QCOMPARE(player.lastQuery(),QString("cancelled search replacement"));
            player.search("   ");
            QVERIFY(!player.busy());QVERIFY(player.lastQuery().isEmpty());
            QVERIFY(player.searchResults().isEmpty());
            QTest::qWait(50);
            QCOMPARE(notices.size(),0);
            QVERIFY(!player.busy());QVERIFY(player.searchResults().isEmpty());
        }
    }
    void realPlatformSearchAndSuggestions() {
        infrastructure::database::Database db;const auto path=temporary_.filePath("platforms.sqlite");QVERIFY(db.open(path));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController sources(&repo);qmlbridge::PortableSession player(db,path,sources);
        for(const auto& provider:QStringList{"wy","kg","tx","mg"}) {
            qInfo() << "Verifying platform" << provider;player.setPlatform(provider);player.search(QStringLiteral("周杰伦"));QTRY_VERIFY_WITH_TIMEOUT(!player.busy(),18000);
            QVERIFY2(!player.searchResults().isEmpty(),qPrintable(provider+" search returned no tracks"));
            for(const auto& row:player.searchResults())QCOMPARE(row.toMap().value("source").toString(),provider);
            player.suggest(QStringLiteral("周杰"));QTRY_VERIFY_WITH_TIMEOUT(!player.suggestions().isEmpty(),18000);
        }
    }
    void paginatedSearchAndCategories_data() {
        QTest::addColumn<QString>("provider");QTest::addColumn<QString>("category");
        for(const auto& p:QStringList{"kw","kg","tx","wy","mg"})
            for(const auto& c:QStringList{"songs","playlists","albums"}) QTest::newRow(qPrintable(p+"-"+c))<<p<<c;
    }
    void paginatedSearchAndCategories() {
        QFETCH(QString,provider);QFETCH(QString,category);
        infrastructure::database::Database db;const auto path=temporary_.filePath(provider+category+"-pages.sqlite");QVERIFY(db.open(path));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController sources(&repo);qmlbridge::PortableSession player(db,path,sources);
        player.setPlatform(provider);player.setSearchCategory(category);player.search("Taylor Swift");
        QTRY_VERIFY_WITH_TIMEOUT(!player.busy(),18000);
        QCOMPARE(player.searchPage(),1);QVERIFY(!player.searchResults().isEmpty() && player.searchResults().size()<=30);QVERIFY(player.searchTotal()>30);
        const auto firstPage=player.searchResults();
        player.goToSearchPage(2);QCOMPARE(player.searchPage(),2);
        QTRY_VERIFY_WITH_TIMEOUT(!player.busy(),18000);QVERIFY(!player.searchResults().isEmpty() && player.searchResults().size()<=30);
        QVERIFY(player.searchResults()!=firstPage);
        QSet<QString> firstIds;const auto idKey=category=="songs" ? "trackId" : "id";
        for(const auto& v:firstPage)firstIds.insert(v.toMap().value(idKey).toString());
        bool newResult=false;
        for(const auto& v:player.searchResults()) {
            const auto row=v.toMap();QCOMPARE(row.value("source").toString(),provider);
            QVERIFY(!row.value(idKey).toString().isEmpty());QVERIFY(!row.value("title").toString().isEmpty());
            newResult|=!firstIds.contains(row.value(idKey).toString());
            if(category!="songs"){QCOMPARE(row.value("kind").toString(),category=="albums"?QString("album"):QString("playlist"));QVERIFY(!row.value("artwork").toString().isEmpty());}
        }
        QVERIFY(newResult);
        player.goToSearchPage(0);QCOMPARE(player.searchPage(),2);
        player.goToSearchPage(player.searchPageCount()+1);QCOMPARE(player.searchPage(),2);
        player.setSearchCategory(category=="songs"?"albums":"songs");QCOMPARE(player.searchPage(),1);
        player.search("");QVERIFY(!player.busy());QVERIFY(player.searchResults().isEmpty());QTest::qWait(30);QVERIFY(player.searchResults().isEmpty());
    }
    void onlineAlbumDetails_data() {
        QTest::addColumn<QString>("provider");QTest::addColumn<QString>("id");
        QTest::newRow("kw")<<QString("kw")<<QString("58640693");
        QTest::newRow("wy")<<QString("wy")<<QString("2565175");
        QTest::newRow("kg")<<QString("kg")<<QString("502254");
        QTest::newRow("tx")<<QString("tx")<<QString("003Q7qEe3SgYAe");
        QTest::newRow("mg")<<QString("mg")<<QString("1140307480");
    }
    void onlineAlbumDetails() {
        QFETCH(QString,provider);QFETCH(QString,id);
        infrastructure::database::Database db;QVERIFY(db.open(temporary_.filePath(provider+"-album.sqlite")));QVERIFY(db.migrate());
        qmlbridge::CollectionService service(db);service.open({{"id",id},{"source",provider},{"kind","album"},{"title","Album"}});
        QTRY_VERIFY_WITH_TIMEOUT(!service.detailBusy(),18000);
        const auto rows=service.detail().value("tracks").toList();QVERIFY2(rows.size()>1,qPrintable(service.detail().value("error").toString()));
        for(const auto& v:rows){const auto row=v.toMap();QCOMPARE(row.value("source").toString(),provider);QVERIFY(!row.value("trackId").toString().isEmpty());QVERIFY(!row.value("title").toString().isEmpty());}
        const auto album=service.detail();service.toggleSaved(album);auto playlist=album;playlist["kind"]="playlist";service.toggleSaved(playlist);
        QCOMPARE(service.playlists().size(),2);QVERIFY(service.isSaved(album));QVERIFY(service.isSaved(playlist));
        service.toggleSaved(album);QVERIFY(!service.isSaved(album));QVERIFY(service.isSaved(playlist));
    }
    void realPlatformListsAndDetails() {
        QNetworkAccessManager network;
        for(const auto& provider:QStringList{"wy","kg","tx","mg"}) {
            qInfo() << "Verifying playlists" << provider;
            auto* reply=online::platformRequest(network,provider,"lists",{});
            QVERIFY(reply);QTRY_VERIFY_WITH_TIMEOUT(reply->isFinished(),18000);
            const auto lists=online::platformPlaylists(provider,online::platformJson(reply->readAll()));reply->deleteLater();
            QVERIFY2(!lists.isEmpty(),qPrintable(provider+" playlists returned no cards"));
            const auto first=lists.first().toMap();QVERIFY(!first.value("artwork").toString().isEmpty());
            reply=online::platformRequest(network,provider,"detail",first.value("id").toString());
            QVERIFY(reply);QTRY_VERIFY_WITH_TIMEOUT(reply->isFinished(),18000);
            const auto raw=reply->readAll();
            const auto tracks=online::platformSongs(provider,online::platformJson(raw));reply->deleteLater();
            QVERIFY2(!tracks.isEmpty(),qPrintable(provider+" playlist has no tracks"));
            for(const auto& row:tracks){QCOMPARE(row.toMap().value("source").toString(),provider);QVERIFY(!row.toMap().value("title").toString().isEmpty());}
        }
    }
    void realNianxinFlac() {
        const auto script=qEnvironmentVariable("LISTENFREE_TEST_NIANXIN","E:/下载/v260507/v260507/new/(推荐)念心音源 v1.0.1.js");
        if(!QFileInfo::exists(script))QSKIP("User source unavailable");
        infrastructure::database::Database db;const auto path=temporary_.filePath("nianxin.sqlite");QVERIFY(db.open(path));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController sources(&repo,QCoreApplication::applicationDirPath()+"/listenfree-sourcehost.exe",true);
        QTRY_VERIFY_WITH_TIMEOUT(sources.hostReady(),10000);QVERIFY(sources.importLocalFile(script));
        QTRY_VERIFY_WITH_TIMEOUT(!sources.sources().isEmpty()&&sources.sources().last().toMap().value("hostReady").toBool(),35000);
        qmlbridge::PortableSession player(db,path,sources);player.search("https://music.163.com/#/song?id=2738143852");QTRY_VERIFY_WITH_TIMEOUT(!player.busy(),18000);
        QCOMPARE(player.platform(),QString("wy"));QVERIFY(!player.searchResults().isEmpty());const auto song=player.searchResults().first().toMap();
        QCOMPARE(song.value("songmid").toString(),QString("2738143852"));QVERIFY(!song.value("artwork").toString().isEmpty());
        QSignalSpy resolved(&sources,&qmlbridge::SourceController::resolutionFinished);
        QVERIFY(!sources.resolveMusicUrl(sources.activeId(),"flac",online::sourceMusicInfo(song)).isEmpty());QTRY_COMPARE_WITH_TIMEOUT(resolved.size(),1,20000);
        const auto result=resolved.takeFirst();QVERIFY2(result[4].toString().isEmpty(),qPrintable(result[4].toString()));
        QNetworkAccessManager network;QNetworkRequest request{QUrl(result[3].toMap().value("url").toString())};request.setRawHeader("Range","bytes=0-4095");request.setTransferTimeout(15000);
        auto* reply=network.get(request);QByteArray header;
        connect(reply,&QIODevice::readyRead,this,[reply,&header]{header+=reply->read(4096-header.size());if(header.size()>=4096)reply->abort();});
        QTRY_VERIFY_WITH_TIMEOUT(reply->isFinished(),18000);QVERIFY2(header.contains("fLaC"),"Real returned stream must have FLAC signature");reply->deleteLater();
        player.openTrack(song);QTRY_VERIFY_WITH_TIMEOUT(player.state()=="Playing"&&player.position()>1000,25000);QVERIFY(player.seekable());player.stop();
        qmlbridge::SettingsController settings(repo);
        settings.setValue("download.enabled",true);settings.setValue("download.folder",temporary_.filePath("nianxin-download"));
        settings.setValue("download.embedContent.Lyrics",false);settings.setValue("download.embedContent.Artwork",false);
        qmlbridge::DownloadService downloads(db,sources,settings);
        const auto specifications=downloads.specifications({song});
        QVERIFY(std::any_of(specifications.begin(),specifications.end(),[](const auto& v){return v.toMap().value("value")=="flac";}));
        downloads.add({song},"flac");
        QTRY_VERIFY_WITH_TIMEOUT(downloads.tasks().first().toMap().value("state")=="completed" || downloads.tasks().first().toMap().value("state")=="error",90000);
        const auto task=downloads.tasks().first().toMap();
        QVERIFY2(task.value("state")=="completed",qPrintable(task.value("error").toString()));
        QVERIFY(task.value("path").toString().endsWith(".flac"));QFile saved(task.value("path").toString());QVERIFY(saved.open(QIODevice::ReadOnly));QCOMPARE(saved.read(4),QByteArray("fLaC"));
    }
    void libraryHydrationSurvivesVectorGrowth() {
        infrastructure::database::Database db;
        QVERIFY(db.open(temporary_.filePath("hydration.sqlite"))); QVERIFY(db.migrate());
        std::vector<domain::Track> tracks;
        for (int index = 0; index < 1100; ++index) {
            domain::Track track;
            const auto id = std::to_string(index);
            track.id = domain::TrackId("track-" + id); track.title = "song-" + id;
            track.artists.push_back({"artist-" + id, "artist name " + id});
            track.album = domain::Album{"album-" + id, "album name " + id, "https://example.test/cover/" + id};
            tracks.push_back(std::move(track));
        }
        QVERIFY(db.upsertTracks(tracks));
        const auto loaded = db.loadTracks(); QCOMPARE(loaded.size(), tracks.size());
        for (const auto& track : loaded) {
            const auto id = track.id.value().substr(6);
            QCOMPARE(track.artists.size(), std::size_t(1));
            QCOMPARE(track.artists.front().name, "artist name " + id);
            QVERIFY(track.album.has_value()); QCOMPARE(track.album->title, "album name " + id);
            QCOMPARE(track.album->artworkUrl.value_or(""), "https://example.test/cover/" + id);
        }
    }
    void upstreamQueueIdentityAndRestore() {
        infrastructure::database::Database db;
        const auto path = temporary_.filePath("queue.sqlite");
        QVERIFY(db.open(path)); QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository settings(db);
        qmlbridge::SourceController sources(&settings);
        {
            qmlbridge::PortableSession player(db, path, sources);
            QVERIFY(player.enqueueTrack(local(mp3_))); QVERIFY(player.enqueueTrack(local(flac_))); QVERIFY(player.enqueueTrack(local(mp3_)));
            QCOMPARE(player.queueSongs().size(), 2);
            const auto first = player.queueSongs()[0].toMap().value("entryId");
            auto alias=local(QDir::toNativeSeparators(mp3_).toUpper());
            QVERIFY(player.enqueueTrack(alias));QCOMPARE(player.queueSongs().size(),2);
            QVERIFY(player.selectQueue(0, false)); QVERIFY(player.moveQueue(0, 1));
            QCOMPARE(player.currentQueueIndex(), 1); QCOMPARE(player.currentTrack().value("entryId"), first);
            const auto removedEntryId = player.queueSongs().first().toMap().value("entryId");
            QVERIFY(player.removeFromQueue(0)); QCOMPARE(player.currentQueueIndex(), 0);
            QCOMPARE(player.queueModel()->rowCount(), 1);
            QVERIFY(player.queueSongs().first().toMap().value("entryId") != removedEntryId);
            QCOMPARE(player.queueSongs().first().toMap().value("entryId"), player.currentTrack().value("entryId"));
            player.setPlaybackMode("shuffle");
            player.shutdown();
        }
        {
            qmlbridge::PortableSession player(db, path, sources);
            QCOMPARE(player.queueSongs().size(), 1); QCOMPARE(player.currentQueueIndex(), 0); QCOMPARE(player.playbackMode(), QString("shuffle"));
            QVERIFY(player.state() != "Playing");
            player.clearQueue(); QCOMPARE(player.queueSongs().size(), 0);
        }
    }

    void ordinaryQueueAppendKeepsModelRows() {
        infrastructure::database::Database db;
        const auto path = temporary_.filePath("queue-append.sqlite");
        QVERIFY(db.open(path));
        QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);
        qmlbridge::SourceController source(&repo);
        qmlbridge::PortableSession player(db, path, source);
        auto* model = player.queueModel();
        QSignalSpy inserted(model, &QAbstractItemModel::rowsInserted);
        QSignalSpy reset(model, &QAbstractItemModel::modelReset);
        QSignalSpy changed(&player, &qmlbridge::PortableSession::queueContentsChanged);

        QVERIFY(player.enqueueTrack(local(mp3_)));
        QCOMPARE(inserted.size(), 1);
        QCOMPARE(inserted.at(0).at(1).toInt(), 0);
        QCOMPARE(reset.size(), 0);
        QCOMPARE(model->snapshotRows(), player.queueSongs());

        QVERIFY(player.enqueueTrack(local(flac_)));
        QCOMPARE(inserted.size(), 2);
        QCOMPARE(inserted.at(1).at(1).toInt(), 1);
        QCOMPARE(reset.size(), 0);
        QCOMPARE(model->snapshotRows(), player.queueSongs());
        QCOMPARE(changed.size(), 2);

        QVERIFY(player.enqueueTrack(local(flac_)));
        QCOMPARE(inserted.size(), 2);
        QCOMPARE(changed.size(), 2);
        QVERIFY(player.enqueueTrack(local(third_), true));
        QCOMPARE(model->snapshotRows(), player.queueSongs());
        QCOMPARE(model->rowCount(), 3);
    }

    void ordinaryQueueMoveKeepsModelRowsAndCurrentTrack() {
        infrastructure::database::Database db;
        const auto path = temporary_.filePath("queue-move.sqlite");
        QVERIFY(db.open(path));
        QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);
        qmlbridge::SourceController source(&repo);
        qmlbridge::PortableSession player(db, path, source);
        QVERIFY(player.enqueueTrack(local(mp3_)));
        QVERIFY(player.enqueueTrack(local(flac_)));
        QVERIFY(player.enqueueTrack(local(third_)));
        QVERIFY(player.selectQueue(0, false));
        const auto currentEntryId = player.currentTrack().value("entryId");
        auto* model = player.queueModel();
        QPersistentModelIndex persistentFirst(model->index(0, 0));
        QSignalSpy moved(model, &QAbstractItemModel::rowsMoved);
        QSignalSpy reset(model, &QAbstractItemModel::modelReset);
        QSignalSpy contents(&player, &qmlbridge::PortableSession::queueContentsChanged);
        QSignalSpy changed(&player, &qmlbridge::PortableSession::queueChanged);

        QVERIFY(player.moveQueue(0, 2));
        QCOMPARE(moved.size(), 1);
        QCOMPARE(moved.at(0).at(1).toInt(), 0);
        QCOMPARE(moved.at(0).at(4).toInt(), 3);
        QCOMPARE(reset.size(), 0);
        QCOMPARE(contents.size(), 1);
        QCOMPARE(changed.size(), 1);
        QCOMPARE(persistentFirst.row(), 2);
        QCOMPARE(player.currentQueueIndex(), 2);
        QCOMPARE(model->currentIndex(), 2);
        QCOMPARE(player.currentTrack().value("entryId"), currentEntryId);
        QCOMPARE(model->snapshotRows(), player.queueSongs());

        QVERIFY(player.moveQueue(2, 0));
        QCOMPARE(moved.size(), 2);
        QCOMPARE(moved.at(1).at(1).toInt(), 2);
        QCOMPARE(moved.at(1).at(4).toInt(), 0);
        QCOMPARE(reset.size(), 0);
        QCOMPARE(contents.size(), 2);
        QCOMPARE(changed.size(), 2);
        QCOMPARE(persistentFirst.row(), 0);
        QCOMPARE(player.currentQueueIndex(), 0);
        QCOMPARE(model->currentIndex(), 0);
        QCOMPARE(model->snapshotRows(), player.queueSongs());

        // Same-position moves still persist and notify the queue state.
        QVERIFY(player.moveQueue(0, 0));
        QCOMPARE(moved.size(), 2);
        QCOMPARE(reset.size(), 0);
        QCOMPARE(contents.size(), 2);
        QCOMPARE(changed.size(), 3);
        QVERIFY(!player.moveQueue(-1, 0));
        QCOMPARE(changed.size(), 3);
        const auto saved = QJsonDocument::fromJson(QByteArray::fromStdString(
            db.getSetting("portable.queue").value_or("{}"))).object();
        QCOMPARE(saved.value("index").toInt(), 0);
        QCOMPARE(saved.value("items").toArray().at(0).toObject().value("entryId").toString(),
                 currentEntryId.toString());

        // An unexpected model state falls back to a complete synchronization.
        model->setRows({});
        QCOMPARE(model->rowCount(), 0);
        QVERIFY(player.moveQueue(0, 1));
        QCOMPARE(moved.size(), 2);
        QCOMPARE(reset.size(), 2); // deliberate disturbance plus fallback
        QCOMPARE(model->snapshotRows(), player.queueSongs());
        QCOMPARE(model->currentIndex(), player.currentQueueIndex());
    }

    void replacingQueueUsesVisibleListAndSelectedSong() {
        infrastructure::database::Database db;
        const auto path = temporary_.filePath("play-action.sqlite");
        QVERIFY(db.open(path)); QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);
        qmlbridge::SettingsController settings(repo);
        settings.setValue("playback.playActionBehavior", "ReplaceCurrentList");
        QCOMPARE(settings.value("playback.playActionBehavior").toString(), QString("ReplaceCurrentList"));
        QCOMPARE(db.getSetting("playback.playActionBehavior").value_or(""), std::string("ReplaceCurrentList"));

        qmlbridge::SourceController source(&repo);
        qmlbridge::PortableSession player(db, path, source);
        QVERIFY(player.enqueueTrack(local(third_)));
        const QVariantList visible{local(mp3_), local(flac_), local(mp3_)};
        QVERIFY(player.replaceQueueWithList(visible, local(flac_)));
        QCOMPARE(player.queueSongs().size(), 2); // The source list uses normal queue deduplication.
        QCOMPARE(player.queueSongs()[0].toMap().value("localPath").toString(), mp3_);
        QCOMPARE(player.queueSongs()[1].toMap().value("localPath").toString(), flac_);
        QCOMPARE(player.currentQueueIndex(), 1);
        QCOMPARE(player.currentTrack().value("localPath").toString(), flac_);

        // Repeated appearances of one song map to the queue's first identity.
        QVERIFY(player.replaceQueueWithList(visible, local(mp3_)));
        QCOMPARE(player.queueSongs().size(), 2);
        QCOMPARE(player.currentQueueIndex(), 0);

        // An explicit queue action keeps the replacement list and adds only its song.
        QVERIFY(player.enqueueTrack(local(third_)));
        QCOMPARE(player.queueSongs().size(), 3);
        QVERIFY(!player.replaceQueueWithList({local(mp3_)}, local(third_)));
        QCOMPARE(player.queueSongs().size(), 3); // Stale or mismatched context cannot erase it.
        player.stop();
    }


    void duplicateMergeRedirectKeepsQueueIdentity() {
        infrastructure::database::Database db;
        const auto path=temporary_.filePath("duplicate-redirect.sqlite");QVERIFY(db.open(path));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);
        qmlbridge::PortableSession player(db,path,source);
        QVERIFY(player.enqueueTrack(local(third_)));QVERIFY(player.enqueueTrack(local(flac_)));
        QVERIFY(player.selectQueue(0,false));
        const auto identity=player.currentTrack().value("entryId");
        const QVariantMap from{{"path",QDir::fromNativeSeparators(third_)},{"id","duplicate"}};
        const QVariantMap to{{"path",QDir::fromNativeSeparators(mp3_)},{"id","keeper"}};
        player.redirectDuplicates({QVariantMap{{"from",from},{"to",to}}});
        QCOMPARE(player.queueSongs().size(),2);QCOMPARE(player.currentQueueIndex(),0);
        QCOMPARE(player.currentTrack().value("entryId"),identity);
        QCOMPARE(player.currentTrack().value("localPath").toString(),to.value("path").toString());
        QCOMPARE(player.currentTrack().value("trackId").toString(),QString("keeper"));
        QVERIFY(player.state()!="Playing");QVERIFY(QFileInfo::exists(third_));
        player.shutdown();
        const auto saved=QJsonDocument::fromJson(QByteArray::fromStdString(db.getSetting("portable.queue").value_or("{}"))).object();
        QCOMPARE(saved.value("items").toArray()[0].toObject().value("localPath").toString(),to.value("path").toString());
    }

    void currentTrackIdentityAcrossLists() {
        infrastructure::database::Database db;
        const auto path=temporary_.filePath("current-marker.sqlite");QVERIFY(db.open(path));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);
        qmlbridge::PortableSession player(db,path,source);
        QVERIFY(!player.isCurrentTrack({}));QVERIFY(!player.isCurrentTrack(local(mp3_)));
        QVERIFY(player.enqueueTrack(local(mp3_)));QVERIFY(player.enqueueTrack(local(flac_)));
        QVERIFY(player.selectQueue(0,false));QVERIFY(player.isCurrentTrack(local(mp3_)));
        auto alias=local(QDir::toNativeSeparators(mp3_).toUpper());alias["trackId"]="different-library-id";
        QVERIFY(player.isCurrentTrack(alias)); // Same file in a saved playlist.
        auto other=local(flac_);other["title"]=local(mp3_).value("title");
        QVERIFY(!player.isCurrentTrack(other)); // Identical title is insufficient.
        QVERIFY(player.moveQueue(0,1));QVERIFY(player.isCurrentTrack(alias));
        QVERIFY(player.selectQueue(0,false));QVERIFY(!player.isCurrentTrack(alias));QVERIFY(player.isCurrentTrack(other));
        player.clearQueue();QVERIFY(!player.isCurrentTrack(other));

        QVariantMap online{{"trackId","kw:450444"},{"source","kw"},{"rid","450444"}};
        QVERIFY(player.enqueueTrack(online));QVERIFY(player.selectQueue(0,false));
        auto result=online;result["source"]="KW";result["trackId"]="search-row";result["remoteUrl"]="https://example.invalid/new-signed-url";
        QVERIFY(player.isCurrentTrack(result));
        result["source"]="wy";QVERIFY(!player.isCurrentTrack(result)); // Platform namespaces cannot collide.
        QVERIFY(player.isCurrentTrack({{"trackId","kw:450444"}})); // ID-only model role.
        QVERIFY(!player.isCurrentTrack({{"title",""}}));
        player.clearQueue();QVERIFY(!player.isCurrentTrack(online));
    }

    void duplicateQueueRestoreAndPlayNext() {
        infrastructure::database::Database db;const auto path=temporary_.filePath("dedup.sqlite");QVERIFY(db.open(path));QVERIFY(db.migrate());
        QVariantMap online{{"trackId","kw:450444"},{"source","kw"},{"rid","450444"}};
        QVariantList items{local(mp3_),local(mp3_),local(flac_),online};
        db.setSetting("portable.queue",QString::fromUtf8(QJsonDocument(QJsonObject{{"items",QJsonArray::fromVariantList(items)},{"index",2}}).toJson()));
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);qmlbridge::PortableSession player(db,path,source);
        QCOMPARE(player.queueSongs().size(),3);QCOMPARE(player.currentTrack().value("localPath").toString(),flac_);
        const auto current=player.currentTrack().value("entryId");
        QVERIFY(player.enqueueTrack(local(mp3_),true));QCOMPARE(player.queueSongs().size(),3);QCOMPARE(player.currentTrack().value("entryId"),current);
        QCOMPARE(player.queueSongs()[player.currentQueueIndex()+1].toMap().value("localPath").toString(),mp3_);
        auto other=online;other["source"]="wy";other["trackId"]="wy:450444";QVERIFY(player.enqueueTrack(other));QCOMPARE(player.queueSongs().size(),4);
        player.clearQueue();QVERIFY(player.openTrack(local(mp3_)));QTRY_VERIFY_WITH_TIMEOUT(player.position()>700,8000);
        const auto position=player.position();QVERIFY(player.openTrack(local(mp3_)));QTest::qWait(500);
        QCOMPARE(player.queueSongs().size(),1);QVERIFY(player.position()>=position);player.stop();
    }
    void localArtworkAndFileActions() {
        infrastructure::database::Database db;const auto path=temporary_.filePath("file-actions.sqlite");QVERIFY(db.open(path));QVERIFY(db.migrate());
        const auto copy=temporary_.filePath("中文 标签测试.mp3");QVERIFY(QFile::copy(mp3_,copy));
        domain::Track track;track.id=domain::TrackId("tag-test");track.title="Original";track.localPath=copy.toStdString();QVERIFY(db.upsertTrack(track));
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);qmlbridge::PortableSession player(db,path,source);
        QTRY_VERIFY(player.ready());auto row=player.songs().first().toMap();
        auto* model=player.tracksModel();const auto role=model->roleNames().key("artwork");
        QVERIFY(model->data(model->index(0,0),role).toString().startsWith("image://covers/"));
        QVERIFY(player.saveTrackTags(row,{{"title",QStringLiteral("测试歌曲")},{"artist","Test Artist"},{"genre","Pop"},{"year","2026"},{"lyrics","[00:01.00]Test lyric"}}));
        const auto tags=player.readTrackTags(row);QCOMPARE(tags.value("title").toString(),QStringLiteral("测试歌曲"));QCOMPARE(tags.value("lyrics").toString(),QString("[00:01.00]Test lyric"));
        QVERIFY(player.saveTrackTags(row,{{"title","Changed"}}));QCOMPARE(player.readTrackTags(row).value("genre").toString(),QString("Pop"));
        player.reload();
        QVERIFY(player.removeLibraryTrack(row));QVERIFY(QFileInfo::exists(copy));QVERIFY(!db.findTrack(track.id));
        QTRY_VERIFY(player.songs().isEmpty());QCOMPARE(player.tracksModel()->rowCount(),0);
        QVERIFY(player.albums().isEmpty());QVERIFY(player.artists().isEmpty());
        QVERIFY(player.enqueueTrack(row));QVERIFY(player.removeLibraryTrack(row,true));QVERIFY(!QFileInfo::exists(copy));QVERIFY(player.queueSongs().isEmpty());
        QVERIFY(!player.showInExplorer(row));
    }
    void localNeteaseCommentsAndSearchArtwork() {
        infrastructure::database::Database db;const auto path=temporary_.filePath("comments-artwork.sqlite");QVERIFY(db.open(path));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);qmlbridge::PortableSession player(db,path,source);
        auto song=local(mp3_);song["title"]="Shape of You";song["artist"]="Ed Sheeran";song["durationMs"]=233000;
        QVERIFY(player.enqueueTrack(song));player.requestComments("hot");QTRY_VERIFY_WITH_TIMEOUT(!player.commentsBusy(),30000);
        QVERIFY2(player.commentsError().isEmpty(),qPrintable(player.commentsError()));QVERIFY(!player.comments().isEmpty());
        QCOMPARE(player.platform(),QString("kw"));QVERIFY(player.lastQuery().isEmpty());QVERIFY(player.searchResults().isEmpty());
        player.requestComments("latest");QTRY_VERIFY_WITH_TIMEOUT(!player.commentsBusy(),20000);QVERIFY(!player.comments().isEmpty());
        const auto count=player.comments().size();player.requestComments("latest",true);QTRY_VERIFY_WITH_TIMEOUT(!player.commentsBusy(),20000);QVERIFY(player.comments().size()>count);
        player.search("蔡健雅");QTRY_VERIFY_WITH_TIMEOUT(!player.busy(),15000);QVERIFY(player.searchResults().size()>2);
        const auto second=player.searchResults()[1].toMap();player.requestTrackArtwork(second);
        QTRY_VERIFY_WITH_TIMEOUT(!player.searchResults()[1].toMap().value("artwork").toString().isEmpty(),12000);
        player.setPlatform("wy");player.search("Shape of You");QTRY_VERIFY_WITH_TIMEOUT(!player.busy(),15000);QVERIFY(player.searchResults().size()>1);
        player.requestTrackArtwork(player.searchResults()[1].toMap());QTRY_VERIFY_WITH_TIMEOUT(!player.searchResults()[1].toMap().value("artwork").toString().isEmpty(),15000);
        player.setPlatform("kg");player.search("AIZO");QTRY_VERIFY_WITH_TIMEOUT(!player.busy(),15000);QVERIFY(!player.searchResults().isEmpty());
        QVERIFY(!player.searchResults().first().toMap().value("artwork").toString().isEmpty());
    }

    void unavailableOutputFallsBack_data() {
        QTest::addColumn<bool>("unavailable");
        QTest::newRow("default-device") << false;
        QTest::newRow("disconnected-saved-device") << true;
    }
    void unavailableOutputFallsBack() {
        QFETCH(bool,unavailable);
        const auto disconnected=qEnvironmentVariable("LISTENFREE_TEST_UNAVAILABLE_DEVICE");
        if(unavailable && disconnected.isEmpty())QSKIP("Set a real disconnected Windows endpoint for this regression");
        QSettings preferences;const auto original=preferences.value("WASAPI/device","default");
        preferences.setValue("WASAPI/device",unavailable?disconnected:QString("default"));
        infrastructure::database::Database db;const auto path=temporary_.filePath(QString("output-")+QTest::currentDataTag()+".sqlite");
        QVERIFY(db.open(path));QVERIFY(db.migrate());db.setSetting("playback.skipOnError","true");
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController sources(&repo);qmlbridge::PortableSession player(db,path,sources);
        QSignalSpy notices(&player,&qmlbridge::PortableSession::notice);
        player.playAll({local(mp3_),local(flac_)});
        QTRY_VERIFY2_WITH_TIMEOUT(player.state()=="Playing" && player.position()>600,qPrintable(player.errorMessage()),6000);
        QCOMPARE(player.currentQueueIndex(),0);QCOMPARE(player.queueSongs().size(),2);QCOMPARE(notices.size(),0);
        QCOMPARE(player.outputDevice(),QString("default"));
        if(unavailable) {
            player.pause();QTRY_COMPARE(player.state(),QString("Paused"));const auto paused=player.position();
            preferences.setValue("WASAPI/device",disconnected);player.play();
            QTRY_VERIFY_WITH_TIMEOUT(player.state()=="Playing" && player.position()>=paused,6000);
            QCOMPARE(player.outputDevice(),QString("default"));QCOMPARE(player.currentQueueIndex(),0);QCOMPARE(notices.size(),0);
        }
        player.stop();preferences.setValue("WASAPI/device",original);
    }

    void outputFailureDoesNotSkipQueue() {
        infrastructure::database::Database db;const auto path=temporary_.filePath("output-fatal.sqlite");QVERIFY(db.open(path));QVERIFY(db.migrate());
        db.setSetting("playback.skipOnError","true");
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController sources(&repo);qmlbridge::PortableSession player(db,path,sources);
        player.enqueueTrack(local(mp3_));player.enqueueTrack(local(flac_));
        const auto entry=player.currentTrack().value("entryId");QSignalSpy notices(&player,&qmlbridge::PortableSession::notice);
        // Inject the output backend's real failure signal at its adapter boundary.
        SoundCore::instance()->stateChanged(Qmmp::FatalError);
        QTRY_COMPARE(notices.size(),1);QTest::qWait(900);
        QCOMPARE(player.currentTrack().value("entryId"),entry);QCOMPARE(player.queueSongs().size(),2);
        QCOMPARE(player.state(),QString("Error"));QCOMPARE(notices.size(),1);
        QVERIFY(!player.errorMessage().contains(QStringLiteral("连续失败")));
    }

    void nextKeepsAdvancing_data() {
        QTest::addColumn<QString>("mode");
        QTest::newRow("normal") << QString("Normal");
        QTest::newRow("gapless") << QString("Gapless");
        QTest::newRow("crossfade") << QString("Crossfade");
    }
    void nextKeepsAdvancing() {
        QFETCH(QString, mode);
        infrastructure::database::Database db;
        const auto path = temporary_.filePath("advancing-" + mode + ".sqlite");
        QVERIFY(db.open(path)); QVERIFY(db.migrate());
        db.setSetting("playback.transition.smart",mode=="Normal"?"false":"true");
        db.setSetting("playback.transition.crossfadeSeconds", "1");
        infrastructure::database::SettingsRepository repo(db);
        qmlbridge::SourceController source(&repo);
        qmlbridge::PortableSession player(db, path, source);
        player.playAll({local(QDir::toNativeSeparators(mp3_)), local(QDir::toNativeSeparators(flac_)), local(QDir::toNativeSeparators(third_))});
        QTRY_VERIFY_WITH_TIMEOUT(player.state() == "Playing" && player.position() > 500, 8000);
        player.next();
        QTRY_COMPARE_WITH_TIMEOUT(player.currentQueueIndex(), 1, 10000);
        QTRY_VERIFY_WITH_TIMEOUT(player.position() > 500, 8000);
        const auto entry = player.currentTrack().value("entryId");
        auto previous = player.position();
        for (int sample = 0; sample < 30; ++sample) {
            QTest::qWait(250);
            QCOMPARE(player.currentTrack().value("entryId"), entry);
            QVERIFY2(player.position() + 100 >= previous,
                     qPrintable(QString("New track restarted: %1 -> %2 ms").arg(previous).arg(player.position())));
            previous = player.position();
        }
        QTRY_VERIFY_WITH_TIMEOUT(player.position() > 6500,4000);
        player.stop();
    }
    void naturalQueueModes_data() {
        QTest::addColumn<QString>("mode");QTest::addColumn<QString>("transition");
        for(const auto& transition:QStringList{"Normal","Gapless"})for(const auto& mode:QStringList{"singleLoop","listLoop","stopAfterCurrent"})
            QTest::newRow(qPrintable(transition+"-"+mode))<<mode<<transition;
    }
    void endlessModeAppendsLocalSongAtQueueEnd() {
        infrastructure::database::Database db;
        const auto path = temporary_.filePath("endless-mode.sqlite");
        QVERIFY(db.open(path)); QVERIFY(db.migrate());
        domain::Track localSong;
        localSong.id = domain::TrackId("endless-local");
        localSong.title = "Endless local";
        localSong.localPath = mp3_.toStdString();
        QVERIFY(db.upsertTrack(localSong));
        infrastructure::database::SettingsRepository repo(db);
        qmlbridge::SourceController source(&repo);
        qmlbridge::PortableSession player(db, path, source);
        QTRY_VERIFY_WITH_TIMEOUT(player.ready() && player.songs().size() == 1, 8000);
        player.playAll({local(flac_)});
        player.setPlaybackMode("endless");
        QTRY_VERIFY_WITH_TIMEOUT(player.state() == "Playing" && player.duration() > 5000, 10000);
        player.seek(player.duration() - 900);
        QTRY_VERIFY_WITH_TIMEOUT(player.currentQueueIndex() == 1 && player.state() == "Playing", 9000);
        QCOMPARE(player.queueSongs().size(), 2);
        QCOMPARE(player.currentTrack().value("localPath").toString(), mp3_);
        const auto firstEntry = player.currentTrack().value("entryId");
        QTRY_VERIFY_WITH_TIMEOUT(player.duration() > 5000, 8000);
        player.seek(player.duration() - 900);
        QTRY_VERIFY_WITH_TIMEOUT(player.currentQueueIndex() == 2 && player.state() == "Playing", 9000);
        QCOMPARE(player.queueSongs().size(), 3);
        QCOMPARE(player.currentTrack().value("localPath").toString(), mp3_);
        QVERIFY(player.currentTrack().value("entryId") != firstEntry);
        player.stop();
    }
    void naturalQueueModes() {
        QFETCH(QString,mode);QFETCH(QString,transition);
        infrastructure::database::Database db;const auto path=temporary_.filePath("natural-"+QString(QTest::currentDataTag())+".sqlite");
        QVERIFY(db.open(path));QVERIFY(db.migrate());db.setSetting("playback.transition.smart",transition=="Normal"?"false":"true");
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);qmlbridge::PortableSession player(db,path,source);
        player.playAll({local(mp3_),local(flac_)});player.setPlaybackMode(mode);player.selectQueue(1);
        QTRY_VERIFY_WITH_TIMEOUT(player.position()>500 && player.duration()>5000,10000);
        const auto identity=player.currentTrack().value("entryId");player.seek(player.duration()-900);
        if(mode=="stopAfterCurrent")QTRY_COMPARE_WITH_TIMEOUT(player.state(),QString("Stopped"),9000);
        else {
            QTRY_VERIFY_WITH_TIMEOUT(player.position()<5000 && player.state()=="Playing",9000);
            QCOMPARE(player.currentQueueIndex(),mode=="singleLoop"?1:0);
            if(mode=="singleLoop")QCOMPARE(player.currentTrack().value("entryId"),identity);
        }
        player.stop();
    }
    void manualShuffleFollowsUpstreamHistory() {
        infrastructure::database::Database db;const auto path=temporary_.filePath("manual-shuffle.sqlite");QVERIFY(db.open(path));QVERIFY(db.migrate());
        db.setSetting("playback.transition.smart","true");db.setSetting("playback.clearShuffleHistory","false");
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);qmlbridge::PortableSession player(db,path,source);
        player.playAll({local(mp3_),local(flac_),local(third_)});player.setPlaybackMode("shuffle");
        QTRY_VERIFY_WITH_TIMEOUT(player.state()=="Playing"&&player.position()>250,8000);
        const auto first=player.currentTrack().value("entryId");player.next();
        QTRY_VERIFY_WITH_TIMEOUT(player.currentTrack().value("entryId")!=first,8000);const auto second=player.currentTrack().value("entryId");
        QTRY_VERIFY_WITH_TIMEOUT(player.state()=="Playing"&&player.position()>250,8000);player.next();
        QTRY_VERIFY_WITH_TIMEOUT(player.currentTrack().value("entryId")!=second,8000);QVERIFY(player.currentTrack().value("entryId")!=first);
        QTRY_VERIFY_WITH_TIMEOUT(player.state()=="Playing"&&player.position()>250,8000);player.previous();
        QTRY_COMPARE_WITH_TIMEOUT(player.currentTrack().value("entryId"),second,8000);player.stop();
    }
    void pauseResumeAfterTrackChange() {
        infrastructure::database::Database db;const auto path=temporary_.filePath("pause-transition.sqlite");QVERIFY(db.open(path));QVERIFY(db.migrate());
        db.setSetting("playback.transition.mode","Gapless");
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);qmlbridge::PortableSession player(db,path,source);
        player.playAll({local(mp3_),local(flac_)});
        QTRY_VERIFY_WITH_TIMEOUT(player.position()>500,8000);
        player.next();QTRY_VERIFY_WITH_TIMEOUT(player.state()=="Playing"&&player.position()>0,5000);player.pause();
        QTRY_COMPARE_WITH_TIMEOUT(player.state(),QString("Paused"),5000);
        player.play();
        QTRY_COMPARE_WITH_TIMEOUT(player.currentQueueIndex(),1,5000);
        QTRY_VERIFY_WITH_TIMEOUT(player.position()>500,5000);player.stop();
    }
    void shuffleHistoryCycleAndDeviceSelection() {
        infrastructure::database::Database db;const auto path=temporary_.filePath("shuffle-device.sqlite");QVERIFY(db.open(path));QVERIFY(db.migrate());
        db.setSetting("playback.clearShuffleHistory","false");infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);
        qmlbridge::PortableSession player(db,path,source);player.playAll({local(mp3_),local(flac_),local(third_)});player.setPlaybackMode("shuffle");
        QStringList cycle;for(int n=0;n<6;++n){cycle.append(player.currentTrack().value("entryId").toString());player.next();}
        QCOMPARE(cycle.mid(0,3),cycle.mid(3,3));QCOMPARE(QSet<QString>(cycle.begin(),cycle.begin()+3).size(),3);
        player.setPlaybackMode("listLoop");player.selectQueue(0);QTRY_COMPARE_WITH_TIMEOUT(player.state(),QString("Playing"),10000);
        player.seek(10000);QTRY_VERIFY_WITH_TIMEOUT(player.position()>=10000,5000);player.pause();
        const auto inventory=player.outputDevices();QString device;for(const auto& v:inventory)if(v.toMap().value("value")!="default"){device=v.toMap().value("value").toString();break;}
        QVERIFY(!device.isEmpty());QVERIFY(player.selectOutput(device));QTRY_COMPARE_WITH_TIMEOUT(player.state(),QString("Paused"),10000);QVERIFY(player.position()>=9500);
        QVERIFY(player.selectOutput("default"));QTRY_COMPARE_WITH_TIMEOUT(player.state(),QString("Paused"),10000);QVERIFY(player.position()>=9500);player.stop();
    }
    void destroyingActiveProxyClosesBothConnections() {
        QTcpServer upstream;QVERIFY(upstream.listen(QHostAddress::LocalHost));
        QPointer<QTcpSocket> upstreamSocket;
        connect(&upstream,&QTcpServer::newConnection,this,[&] {
            upstreamSocket=upstream.nextPendingConnection();
            connect(upstreamSocket,&QTcpSocket::readyRead,upstreamSocket,[&] {
                upstreamSocket->readAll();
                upstreamSocket->write("HTTP/1.1 200 OK\r\nContent-Length: 1000000\r\n\r\npartial");
            });
        });
        QNetworkAccessManager network;
        for(int i=0;i<12;++i) {
            auto proxy=std::make_unique<media::MediaStreamProxy>();
            auto* reply=network.get(QNetworkRequest(proxy->publish(QUrl(QString("http://127.0.0.1:%1/stream").arg(upstream.serverPort())))));
            QTRY_VERIFY_WITH_TIMEOUT(reply->bytesAvailable()>0,5000);
            QVERIFY(upstreamSocket);QVERIFY(!reply->isFinished());
            proxy.reset();
            QTRY_VERIFY_WITH_TIMEOUT(reply->isFinished(),5000);
            QTRY_COMPARE(upstreamSocket->state(),QAbstractSocket::UnconnectedState);
            delete upstreamSocket;reply->deleteLater();
        }
    }
    void proxyFollowsRedirectBeforeSendingMediaHeaders() {
        QTcpServer upstream;QVERIFY(upstream.listen(QHostAddress::LocalHost));
        connect(&upstream,&QTcpServer::newConnection,this,[&] {
            while(upstream.hasPendingConnections()){
                auto* socket=upstream.nextPendingConnection();
                connect(socket,&QTcpSocket::disconnected,socket,&QObject::deleteLater);
                connect(socket,&QTcpSocket::readyRead,socket,[socket] {
                    auto request=socket->property("request").toByteArray()+socket->readAll();socket->setProperty("request",request);
                    if(!request.contains("\r\n\r\n"))return;
                    if(request.startsWith("GET /redirect "))socket->write("HTTP/1.1 302 Found\r\nLocation: /audio\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                    else socket->write("HTTP/1.1 206 Partial Content\r\nContent-Type: audio/flac\r\nContent-Range: bytes 0-3/4\r\nContent-Length: 4\r\nConnection: close\r\n\r\nfLaC");
                    socket->disconnectFromHost();
                });
            }
        });
        media::MediaStreamProxy proxy;QNetworkAccessManager network;
        auto* reply=network.get(QNetworkRequest(proxy.publish(QUrl(QString("http://127.0.0.1:%1/redirect").arg(upstream.serverPort())),{})));
        QTRY_VERIFY_WITH_TIMEOUT(reply->isFinished(),5000);
        QCOMPARE(reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt(),206);QCOMPARE(reply->readAll(),QByteArray("fLaC"));reply->deleteLater();
    }
    void mixedListsPersistWithoutLibraryForeignKeys() {
        infrastructure::database::Database db;QVERIFY(db.open(temporary_.filePath("lists.sqlite")));QVERIFY(db.migrate());
        QString id;
        const QVariantMap remote{{"trackId","kw:450444"},{"rid","450444"},{"title","测试在线曲"},{"remoteUrl","https://temporary.invalid/expired"}};
        {
            qmlbridge::CollectionService lists(db);
            id=lists.create("混合歌单",{local(mp3_),remote});QVERIFY(!id.isEmpty());
            lists.addTracks(id,{remote});QCOMPARE(lists.playlists()[0].toMap().value("tracks").toList().size(),2);
            lists.rename(id,"验收歌单");
            QVERIFY(db.clearLibraryIndex());
        }
        qmlbridge::CollectionService restored(db);QCOMPARE(restored.playlists().size(),1);
        const auto row=restored.playlists()[0].toMap();QCOMPARE(row.value("title").toString(),QString("验收歌单"));
        QCOMPARE(row.value("tracks").toList().size(),2);QVERIFY(!row.value("tracks").toList()[1].toMap().contains("remoteUrl"));
        restored.removeTrack(id,0);QCOMPARE(restored.playlists()[0].toMap().value("tracks").toList().size(),1);
        restored.clear();QCOMPARE(restored.playlists().size(),0);
    }
    void realNeteaseDiscoveryHome() {
        infrastructure::database::Database db;QVERIFY(db.open(temporary_.filePath("netease-home.sqlite")));QVERIFY(db.migrate());
        qmlbridge::CollectionService home(db);
        QSignalSpy detailSignals(&home,&qmlbridge::CollectionService::detailChanged);
        const auto platform=home.platform();home.refreshHome(true);QVERIFY(home.homeBusy());
        QTRY_VERIFY_WITH_TIMEOUT(!home.homeBusy(),35000);
        QVERIFY2(home.homeError().isEmpty(),qPrintable(home.homeError()));
        QCOMPARE(home.homeRecommendations().size(),12);QVERIFY(home.homeCharts().size()>=10);QCOMPARE(home.homePreviews().size(),2);
        for(const auto& value:home.homePreviews()) {
            const auto row=value.toMap();QCOMPARE(row.value("source").toString(),QString("wy"));
            QCOMPARE(row.value("tracks").toList().size(),5);
        }
        QVERIFY(home.dailyTracks().size()>=10);QVERIFY(home.dailyTracks().size()<=30);
        for(const auto& value:home.dailyTracks()) {
            const auto row=value.toMap();QCOMPARE(row.value("source").toString(),QString("wy"));
            QVERIFY(!row.value("rid").toString().isEmpty());QVERIFY(!row.value("title").toString().isEmpty());
            QVERIFY(!row.value("artwork").toString().isEmpty());QVERIFY(row.value("durationMs").toLongLong()>0);
        }
        QCOMPARE(home.platform(),platform);QCOMPARE(detailSignals.count(),0);QVERIFY(home.recommendations().isEmpty());
        qmlbridge::CollectionService restored(db);
        QCOMPARE(restored.homeRecommendations(),home.homeRecommendations());QCOMPARE(restored.dailyTracks(),home.dailyTracks());
        restored.refreshHome();QVERIFY(!restored.homeBusy());
        home.open(home.homeRecommendations().first().toMap());
        QTRY_VERIFY_WITH_TIMEOUT(!home.detailBusy(),25000);
        QCOMPARE(home.detail().value("source").toString(),QString("wy"));
        QVERIFY2(!home.detail().value("tracks").toList().isEmpty(),qPrintable(home.detail().value("error").toString()));
    }
    void realDiscoverAndPlaylistPagination() {
        infrastructure::database::Database db;QVERIFY(db.open(temporary_.filePath("discover.sqlite")));QVERIFY(db.migrate());
        qmlbridge::CollectionService collections(db);collections.refresh();
        QTRY_VERIFY_WITH_TIMEOUT(!collections.busy(),20000);
        QVERIFY2(!collections.recommendations().isEmpty(),qPrintable(collections.error()));QVERIFY(!collections.charts().isEmpty());QVERIFY(!collections.tags().isEmpty());
        collections.open(collections.recommendations()[0].toMap());
        QTRY_VERIFY_WITH_TIMEOUT(!collections.detailBusy(),60000);
        const auto detail=collections.detail();QVERIFY2(!detail.value("tracks").toList().isEmpty(),qPrintable(detail.value("error").toString()));
        QCOMPARE(detail.value("tracks").toList().size(),detail.value("total").toInt());
        const auto recommended=collections.recommendations();collections.filter("category","chinese");
        QTRY_VERIFY_WITH_TIMEOUT(!collections.busy(),20000);QVERIFY(!collections.recommendations().isEmpty());QVERIFY(collections.recommendations()!=recommended);
        collections.open(collections.charts()[0].toMap());collections.cancelDetail();collections.open(collections.charts()[1].toMap());
        QTRY_VERIFY_WITH_TIMEOUT(!collections.detailBusy(),60000);
        QCOMPARE(collections.detail().value("id"),collections.charts()[1].toMap().value("id"));
        QVERIFY(!collections.detail().value("tracks").toList().isEmpty());
    }
    void downloadModelRestoresAndPreservesIdentity() {
        using Download = qmlbridge::DownloadService;
        infrastructure::database::Database db;
        QVERIFY(db.open(temporary_.filePath("download-model.sqlite"))); QVERIFY(db.migrate());
        QVariantList saved;
        for (const auto &state : {"completed", "downloading", "queued", "finalizing", "error"})
            saved.append(QVariantMap{{"id",QString::fromLatin1(state)}, {"state",QString::fromLatin1(state)},
                {"title",QStringLiteral("History")}, {"received",qint64(5) * 1024 * 1024 * 1024},
                {"track",QVariantMap{{"trackId",QString::fromLatin1(state)}}}});
        QVERIFY(db.setSetting("downloads.v1", QString::fromUtf8(QJsonDocument(QJsonArray::fromVariantList(saved)).toJson())));
        infrastructure::database::SettingsRepository repo(db);
        qmlbridge::SettingsController settings(repo); settings.setValue("download.enabled",true);
        settings.setValue("download.tryAlternateSource",false);
        qmlbridge::SourceController source(&repo);
        Download downloads(db,source,settings);
        auto* model=downloads.taskModel();
        QAbstractItemModelTester tester(model,QAbstractItemModelTester::FailureReportingMode::QtTest);
        QCOMPARE(model->rowCount(),5);
        QCOMPARE(model->rowCount(model->index(0,0)),0);
        QVERIFY(!model->data(QModelIndex(),Download::TitleRole).isValid());
        QCOMPARE(model->data(model->index(0,0),Download::ReceivedRole).toLongLong(),qint64(5)*1024*1024*1024);
        QCOMPARE(model->data(model->index(1,0),Download::StateRole).toString(),QString("paused"));
        QCOMPARE(model->data(model->index(2,0),Download::StateRole).toString(),QString("paused"));
        QCOMPARE(model->data(model->index(3,0),Download::StateRole).toString(),QString("completed"));
        QSignalSpy reset(model,&QAbstractItemModel::modelReset), updated(model,&QAbstractItemModel::dataChanged);
        QSignalSpy inserted(model,&QAbstractItemModel::rowsInserted), removed(model,&QAbstractItemModel::rowsRemoved);
        QPersistentModelIndex anchored(model->index(4,0));
        downloads.add({QVariantMap{{"trackId","new"},{"rid","7"},{"title","New"}}});
        QCOMPARE(model->rowCount(),6); QCOMPARE(inserted.size(),1);
        QCOMPARE(anchored.row(),5); QCOMPARE(anchored.data(Download::TaskIdRole).toString(),QString("error"));
        const auto id=model->data(model->index(0,0),Download::TaskIdRole).toString();
        downloads.pause(id); QCOMPARE(model->data(model->index(0,0),Download::StateRole).toString(),QString("paused"));
        downloads.resume(id); downloads.cancel(id);
        QCOMPARE(model->data(model->index(0,0),Download::StateRole).toString(),QString("cancelled"));
        downloads.deleteFile("completed");
        QCOMPARE(removed.size(),1); QCOMPARE(anchored.row(),4);
        QCOMPARE(anchored.data(Download::TaskIdRole).toString(),QString("error"));
        QCOMPARE(reset.size(),0);
        downloads.clearRecords(); QVERIFY(downloads.tasks().isEmpty()); QVERIFY(!anchored.isValid());
        QCOMPARE(model->rowCount(),0); QCOMPARE(removed.size(),2);
        const auto updatesAtClear=updated.size();
        QTest::qWait(350); QCOMPARE(updated.size(),updatesAtClear);
        downloads.clearRecords(); QCOMPARE(removed.size(),2);
        QCOMPARE(QJsonDocument::fromJson(QByteArray::fromStdString(db.getSetting("downloads.v1").value())).array().size(),0);
    }
    void downloadRangeAndAlternateSource() {
        QFile fixture(mp3_);QVERIFY(fixture.open(QIODevice::ReadOnly));const auto bytes=fixture.readAll();QVERIFY(bytes.size()>200000);
        QTcpServer server;QVERIFY(server.listen(QHostAddress::LocalHost));
        bool ignoreRange=false;QList<qint64> ranges;
        connect(&server,&QTcpServer::newConnection,&server,[&]{
            while(server.hasPendingConnections()) {
                auto* socket=server.nextPendingConnection();auto request=std::make_shared<QByteArray>();
                connect(socket,&QTcpSocket::disconnected,socket,&QObject::deleteLater);
                connect(socket,&QTcpSocket::readyRead,socket,[&,socket,request]{
                    request->append(socket->readAll());if(!request->contains("\r\n\r\n")||socket->property("started").toBool())return;
                    socket->setProperty("started",true);const auto match=QRegularExpression("Range: bytes=(\\d+)-",QRegularExpression::CaseInsensitiveOption).match(QString::fromLatin1(*request));
                    const auto requested=match.hasMatch()?match.captured(1).toLongLong():0;ranges.append(requested);
                    const qint64 offset=ignoreRange?0:requested;auto position=std::make_shared<qint64>(offset);
                    QByteArray header=offset?"HTTP/1.1 206 Partial Content\r\n":"HTTP/1.1 200 OK\r\n";
                    header+="Content-Type: audio/mpeg\r\nETag: \"fixture-v1\"\r\nConnection: close\r\nContent-Length: "+QByteArray::number(bytes.size()-offset)+"\r\n";
                    if(offset)header+="Content-Range: bytes "+QByteArray::number(offset)+"-"+QByteArray::number(bytes.size()-1)+"/"+QByteArray::number(bytes.size())+"\r\n";
                    socket->write(header+"\r\n");auto* timer=new QTimer(socket);timer->setInterval(10);
                    connect(timer,&QTimer::timeout,socket,[&,socket,timer,position]{if(socket->state()!=QAbstractSocket::ConnectedState){timer->stop();return;}const auto chunk=bytes.mid(*position,32768);socket->write(chunk);*position+=chunk.size();if(*position>=bytes.size()){timer->stop();socket->disconnectFromHost();}});timer->start();
                });
            }
        });
        const auto script=[&](const QString& name,bool succeeds){QFile file(temporary_.filePath(name));if(!file.open(QIODevice::WriteOnly))return QString{};
            const auto result=succeeds?QString("Promise.resolve('http://127.0.0.1:%1/audio.mp3')").arg(server.serverPort()):QString("Promise.reject(new Error('fixture unavailable'))");
            file.write(("lx.on(lx.EVENT_NAMES.request, () => "+result+");lx.send(lx.EVENT_NAMES.inited,{status:true,sources:{kw:{type:'music',actions:['musicUrl'],qualitys:['128k']}}});").toUtf8());return file.fileName();};
        infrastructure::database::Database db;QVERIFY(db.open(temporary_.filePath("range.sqlite")));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SettingsController settings(repo);
        settings.setValue("download.enabled",true);settings.setValue("download.folder",temporary_.filePath("range-downloads"));settings.setValue("download.existingFilePolicy","AutoRename");settings.setValue("download.embedContent.Lyrics",false);settings.setValue("download.embedContent.Artwork",false);
        qmlbridge::SourceController source(&repo,QCoreApplication::applicationDirPath()+"/listenfree-sourcehost.exe",true);
        QTRY_VERIFY_WITH_TIMEOUT(source.hostReady(),10000);QVERIFY(source.importLocalFile(script("range-good.js",true)));
        QTRY_VERIFY_WITH_TIMEOUT(source.sources().last().toMap().value("hostReady").toBool(),10000);
        QVERIFY(source.importLocalFile(script("range-bad.js",false)));QTRY_VERIFY_WITH_TIMEOUT(source.sources().last().toMap().value("hostReady").toBool(),10000);const auto original=source.activeId();
        qmlbridge::DownloadService downloads(db,source,settings);
        auto* model=downloads.taskModel();
        QAbstractItemModelTester tester(model,QAbstractItemModelTester::FailureReportingMode::QtTest);
        QSignalSpy reset(model,&QAbstractItemModel::modelReset), updated(model,&QAbstractItemModel::dataChanged);
        for(int pass=0;pass<2;++pass) {
            ignoreRange=pass==1;ranges.clear();
            downloads.add({QVariantMap{{"rid",QString::number(pass+1)},{"title","Range fixture"}}});
            const auto id=downloads.tasks().first().toMap().value("id").toString();
            QTRY_VERIFY_WITH_TIMEOUT(downloads.tasks().first().toMap().value("received").toLongLong()>100000,15000);
            const QPersistentModelIndex first(model->index(0,0));
            updated.clear();
            QTRY_VERIFY_WITH_TIMEOUT(std::any_of(updated.cbegin(),updated.cend(),[](const QList<QVariant>& args){
                return args.at(2).value<QList<int>>()==QList<int>{qmlbridge::DownloadService::ReceivedRole,qmlbridge::DownloadService::TotalRole};
            }),5000);
            QVERIFY(first.isValid());
            QCOMPARE(first.data(qmlbridge::DownloadService::TaskIdRole).toString(),id);
            downloads.pause(id);const auto paused=downloads.tasks().first().toMap();QCOMPARE(paused.value("state").toString(),QString("paused"));
            QCOMPARE(first.data(qmlbridge::DownloadService::StateRole).toString(),QString("paused"));
            const auto partial=paused.value("partial").toString();QVERIFY(QFileInfo(partial).size()>0);
            const auto pausedSize=QFileInfo(partial).size();QTest::qWait(100);QCOMPARE(QFileInfo(partial).size(),pausedSize);
            downloads.resume(id);QTRY_VERIFY_WITH_TIMEOUT(downloads.tasks().first().toMap().value("state")=="completed",25000);
            QVERIFY(ranges.contains(pausedSize));QCOMPARE(source.activeId(),original);
            const auto path=downloads.tasks().first().toMap().value("path").toString();
            TagLib::MPEG::File before(reinterpret_cast<const wchar_t*>(mp3_.utf16())),after(reinterpret_cast<const wchar_t*>(path.utf16()));
            QVERIFY(before.audioProperties());QVERIFY(after.audioProperties());
            QCOMPARE(before.audioProperties()->lengthInMilliseconds(),after.audioProperties()->lengthInMilliseconds());
            QFile saved(path);QVERIFY(saved.open(QIODevice::ReadOnly));const auto actual=saved.readAll();
            const auto audio=bytes.sliced(before.firstFrameOffset(),before.lastFrameOffset()-before.firstFrameOffset());
            QCOMPARE(actual.sliced(after.firstFrameOffset(),after.lastFrameOffset()-after.firstFrameOffset()),audio);
            downloads.clearRecords();QVERIFY(QFile::exists(path));
            QVERIFY(!first.isValid()); QCOMPARE(model->rowCount(),0); QCOMPARE(reset.size(),0);
        }
        downloads.add({QVariantMap{{"rid","3"},{"title","Cancel fixture"}}});
        QTRY_VERIFY_WITH_TIMEOUT(downloads.tasks().first().toMap().value("received").toLongLong()>100000,15000);
        const auto row=downloads.tasks().first().toMap();downloads.cancel(row.value("id").toString());
        QCOMPARE(downloads.tasks().first().toMap().value("state").toString(),QString("cancelled"));QVERIFY(!QFile::exists(row.value("partial").toString()));
        downloads.clearRecords();
        // A clear during finalization must not notify a removed row or restore it.
        bool clearedWhileFinalizing=false;
        connect(model,&QAbstractItemModel::dataChanged,&downloads,[&](const QModelIndex& first){
            if (!clearedWhileFinalizing && first.data(qmlbridge::DownloadService::StateRole).toString()=="finalizing") {
                clearedWhileFinalizing=true; downloads.clearRecords();
            }
        });
        QSignalSpy completed(&downloads,&qmlbridge::DownloadService::fileCompleted);
        downloads.add({QVariantMap{{"rid","4"},{"title","Clear while finalizing"}}});
        QTRY_COMPARE_WITH_TIMEOUT(completed.size(),1,25000);
        QVERIFY(clearedWhileFinalizing); QCOMPARE(model->rowCount(),0);
        QVERIFY(downloads.tasks().isEmpty()); QVERIFY(QFile::exists(completed.first().first().toString()));
        QCOMPARE(reset.size(),0);
    }
    void realDownloadAndClearKeepsAudio() {
        infrastructure::database::Database db;QVERIFY(db.open(temporary_.filePath("download.sqlite")));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SettingsController settings(repo);
        settings.setValue("download.enabled",true);settings.setValue("download.folder",temporary_.filePath("downloads"));settings.setValue("download.lyrics.externalFile",true);
        qmlbridge::SourceController source(&repo,QCoreApplication::applicationDirPath()+"/listenfree-sourcehost.exe",true);
        QTRY_VERIFY_WITH_TIMEOUT(source.hostReady(),10000);QVERIFY(source.importLocalFile(qEnvironmentVariable("LISTENFREE_TEST_SCRIPT")));
        QTRY_VERIFY_WITH_TIMEOUT(!source.sources().isEmpty()&&source.sources().last().toMap().value("hostReady").toBool(),10000);
        qmlbridge::DownloadService downloads(db,source,settings);
        downloads.add({QVariantMap{{"trackId","kw:450444"},{"rid","450444"},{"title","下载验收"},{"artist","测试"}}});
        QCOMPARE(downloads.tasks().size(),1);
        QTRY_VERIFY_WITH_TIMEOUT(downloads.tasks()[0].toMap().value("state")=="completed"||downloads.tasks()[0].toMap().value("state")=="error",90000);
        auto row=downloads.tasks()[0].toMap();QCOMPARE(row.value("state").toString(),QString("completed"));
        const auto path=row.value("path").toString();QVERIFY(QFileInfo(path).size()>100000);
        QFile lrc(QFileInfo(path).path()+"/"+QFileInfo(path).completeBaseName()+".lrc");QVERIFY(lrc.open(QIODevice::ReadOnly));const auto content=QString::fromUtf8(lrc.readAll());QVERIFY(content.contains("[00:"));QVERIFY(content.contains("[01:"));
        downloads.clearRecords();QVERIFY(downloads.tasks().isEmpty());QVERIFY(QFile::exists(path));
    }
    void realSourceProxyAndMixedPlayback() {
        infrastructure::database::Database db;
        const auto path = temporary_.filePath("live.sqlite");
        QVERIFY(db.open(path)); QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository settings(db);
        qmlbridge::SourceController sources(&settings, QCoreApplication::applicationDirPath()+"/listenfree-sourcehost.exe", true);
        QTRY_VERIFY_WITH_TIMEOUT(sources.hostReady(), 10000);
        QVERIFY(sources.importLocalFile(qEnvironmentVariable("LISTENFREE_TEST_SCRIPT")));
        QTRY_VERIFY_WITH_TIMEOUT(!sources.sources().isEmpty() && sources.sources().last().toMap().value("hostReady").toBool(), 10000);
        qmlbridge::PortableSession player(db, path, sources);
        player.search("https://www.kuwo.cn/play_detail/450444");
        QTRY_VERIFY_WITH_TIMEOUT(!player.busy(), 16000);
        QVERIFY2(!player.searchResults().isEmpty(), "Real Kuwo metadata required for duration and persistent identity");
        QTRY_VERIFY_WITH_TIMEOUT(!player.searchResults().first().toMap().value("artwork").toString().isEmpty(), 10000);
        const auto song = player.searchResults().first().toMap();
        QCOMPARE(song.value("rid").toString(), QString("450444"));
        QVERIFY(song.value("durationMs").toLongLong() > 10000);
        player.playAll({local(mp3_), song, local(flac_)});
        QTRY_VERIFY_WITH_TIMEOUT(player.state() == "Playing" && player.position() >= 1200, 20000);
        player.next();
        QTRY_VERIFY_WITH_TIMEOUT(player.state() == "Playing" && player.position() >= 1200 && player.currentTrackId() == "kw:450444", 35000);
        QVERIFY(player.duration() > 10000); QVERIFY(player.seekable());
        QTRY_VERIFY_WITH_TIMEOUT(player.lyrics().size()>10,16000);
        int wordCount=0; for (const auto& row:player.lyrics()) wordCount+=int(row.toMap().value("words").toList().size());
        QVERIFY(wordCount>100);
        player.requestComments(); QTRY_VERIFY_WITH_TIMEOUT(!player.commentsBusy(),16000);
        QVERIFY2(!player.comments().isEmpty(),qPrintable(player.commentsError()));
        // CDN latency may vary independently of GUI responsiveness. Measure
        // event-loop gaps across the real online seek sequence as well.
        QElapsedTimer heartbeatClock;heartbeatClock.start();qint64 maxGuiGap=0;
        QTimer heartbeat;heartbeat.setInterval(25);
        connect(&heartbeat,&QTimer::timeout,this,[&]{maxGuiGap=qMax(maxGuiGap,heartbeatClock.restart());});heartbeat.start();
        player.pause(); QTRY_COMPARE(player.state(), QString("Paused"));
        const auto pausedAt = player.position(); QTest::qWait(250); QVERIFY(qAbs(player.position()-pausedAt)<200);
        player.seek(10000); player.play();
        QTRY_VERIFY_WITH_TIMEOUT(player.state() == "Playing" && player.position() >= 11200, 20000);
        QCOMPARE(player.currentTrackId(),QString("kw:450444"));
        QTest::qWait(1500);QCOMPARE(player.currentTrackId(),QString("kw:450444"));
        QElapsedTimer realSeek; realSeek.start();
        player.seek(60000);QTRY_VERIFY_WITH_TIMEOUT(player.position()>=60250,12000);
        qInfo("Real CDN seek to advancing playback: %lld ms",realSeek.elapsed());
        QTRY_VERIFY_WITH_TIMEOUT(player.position()>=61200,4000);QCOMPARE(player.currentTrackId(),QString("kw:450444"));
        player.seek(5000);QTRY_VERIFY_WITH_TIMEOUT(player.position()>=6200 && player.position()<10000,35000);QCOMPARE(player.currentTrackId(),QString("kw:450444"));
        heartbeat.stop();QVERIFY2(maxGuiGap<1000,qPrintable(QString("Online seek GUI gap: %1 ms").arg(maxGuiGap)));
        qInfo("Online seek maximum GUI event-loop gap: %lld ms",maxGuiGap);
        player.next(); QTRY_VERIFY_WITH_TIMEOUT(player.currentQueueIndex()==2 && player.state() == "Playing" && player.position() >= 1200, 20000);
        QCOMPARE(player.currentQueueIndex(),2);
        QCOMPARE(player.currentTrack().value("localPath").toString(),flac_);
        // Start real resolution, immediately move away and delete that entry.
        QVERIFY(player.selectQueue(1)); QVERIFY(player.selectQueue(2)); QVERIFY(player.removeFromQueue(1));
        QTRY_VERIFY_WITH_TIMEOUT(player.state() == "Playing" && player.position() >= 1200, 20000);
        QTest::qWait(1500); QCOMPARE(player.currentTrack().value("localPath").toString(), flac_);
        player.stop();
        const auto saved = db.getSetting("portable.queue"); QVERIFY(saved.has_value());
        QVERIFY(!QString::fromStdString(*saved).contains("127.0.0.1"));
        QVERIFY(!QString::fromStdString(*saved).contains("resolvedUrl"));
        QVERIFY(player.openTrack(song)); player.stop(); QTest::qWait(1000); QVERIFY(player.state() != "Playing");
    }
};
QTEST_MAIN(PortableTests)
#include "portable_session_tests.moc"
