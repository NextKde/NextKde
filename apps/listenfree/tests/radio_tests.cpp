#include "online/radio_catalog.h"
#include "qmlbridge/radio_service.h"
#include "qmlbridge/portable_session.h"
#include "infrastructure/database/repositories.h"
#include <QApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QSettings>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
#include <QTcpSocket>
#include <qmmp/qmmp.h>
using namespace listenfree;

class RadioTests : public QObject {
    Q_OBJECT
private slots:
    void programMetadataIsReadable_data() {
        QTest::addColumn<QString>("metadata"); QTest::addColumn<QString>("expected");
        QTest::newRow("reported-kiis") << QString("text=\"Drop Dead\" song_spot=\"M\" MediaBaseId=\"12345\" itunesTrackId=\"0\"") << QString("Drop Dead");
        QTest::newRow("plain-song") << QString("Artist - Song") << QString("Artist - Song");
        QTest::newRow("plain-program") << QString("晚间新闻") << QString("晚间新闻");
        QTest::newRow("adjacent-fields") << QString("text=\"Evening Show\"amgTrackId=\"9876543\"") << QString("Evening Show");
        QTest::newRow("artist-title") << QString("title=\"Song\" artist=\"Artist\" song_spot=\"M\"") << QString("Artist - Song");
        QTest::newRow("escaped-quotes") << QString("text=\"Say \\\"Hello\\\"\" song_spot=\"M\"") << QString("Say \"Hello\"");
        QTest::newRow("ads-without-title") << QString("adContext=\"tracking-data\" song_spot=\"A\"") << QString();
        QTest::newRow("empty-title") << QString("text=\"\" song_spot=\"M\" MediaBaseId=\"0\"") << QString();
        QTest::newRow("incomplete-title") << QString("text=\"unfinished song_spot=\"M\"") << QString();
        QTest::newRow("empty") << QString() << QString();
    }
    void programMetadataIsReadable() {
        QFETCH(QString, metadata); QFETCH(QString, expected);
        QCOMPARE(online::radioProgramTitle(metadata), expected);
    }
    void icecastRejectsMissingAddressesAndDuplicates() {
        const QByteArray xml=R"(<directory><entry><server_name>Missing</server_name></entry><entry><server_name>Beta</server_name><listen_url>https://example.org/b</listen_url><genre>Jazz</genre></entry><entry><server_name>Duplicate</server_name><listen_url>https://example.org/b</listen_url></entry><entry><server_name>Local</server_name><listen_url>file:///secret</listen_url></entry><entry><server_name>Alpha</server_name><listen_url>https://example.org/a</listen_url></entry></directory>)";
        QString error;const auto rows=online::icecastStations(xml,&error);
        QVERIFY(error.isEmpty());QCOMPARE(rows.size(),2);QCOMPARE(rows.first().title,"Alpha");
        QCOMPARE(rows.last().tags,"Jazz");QVERIFY(online::radioTrack(rows.first(),"icecast").value("isLive").toBool());
        QVERIFY(online::icecastStations("<broken>",&error).isEmpty());QVERIFY(!error.isEmpty());
    }
    void sourcesPreserveIdentityAndProgramDuration() {
        const auto browser=online::radioBrowserStations("[{\"stationuuid\":\"uuid-1\",\"name\":\"Station\",\"url_resolved\":\"https://example.org/live\",\"country\":\"China\",\"codec\":\"MP3\",\"favicon\":\"file:///invalid\"}]");
        QCOMPARE(browser.size(),1);QCOMPARE(browser.first().toMap().value("radioId").toString(),"uuid-1");QVERIFY(browser.first().toMap().value("artwork").toString().isEmpty());
        const auto root=QJsonDocument::fromJson(R"({"programs":[{"id":8,"mainTrackId":42,"name":"Episode","duration":65000,"radio":{"name":"Podcast"},"dj":{"nickname":"Host"}}]})").object();
        const auto row=online::neteasePrograms(root).first().toMap();QCOMPARE(row.value("radioId").toString(),"42");QCOMPARE(row.value("duration").toString(),"1:05");QVERIFY(!row.value("isLive").toBool());
    }
    void favoritesPersistWithoutStartingDirectory() {
        QTemporaryDir dir;infrastructure::database::Database db;QVERIFY(db.open(dir.filePath("radio.sqlite")));QVERIFY(db.migrate());
        const QVariantMap station{{"radioProvider","netease-broadcast"},{"radioId","1203"},{"title","Radio"},{"remoteUrl","https://expires.example.org/stream"}};
        {qmlbridge::RadioService service(db);QVERIFY(!service.busy());QVERIFY(service.rows().isEmpty());service.toggleFavorite(station);QVERIFY(service.isFavorite(station));}
        qmlbridge::RadioService service(db);QVERIFY(service.isFavorite(station));
        service.setFavoritesOnly(true);service.setProvider("netease");QCOMPARE(service.rows().size(),1);
        QVERIFY(!service.rows().first().toMap().contains("remoteUrl"));service.toggleFavorite(station);QVERIFY(service.rows().isEmpty());
        const QVariantMap podcast{{"radioProvider","netease-podcast"},{"radioId","336355127"},{"title","代码时间"},{"kind","podcast"}};
        service.toggleFavorite(podcast);service.openPodcast(podcast);
        QVERIFY(!service.favoritesOnly());QCOMPARE(service.podcast().value("radioId"),podcast.value("radioId"));
    }
    void proxyForwardsIcyMetadataContract() {
        QTcpServer upstream;QVERIFY(upstream.listen(QHostAddress::LocalHost,0));QByteArray request;
        connect(&upstream,&QTcpServer::newConnection,this,[&] {
            auto* client=upstream.nextPendingConnection();connect(client,&QTcpSocket::disconnected,client,&QObject::deleteLater);
            connect(client,&QTcpSocket::readyRead,this,[&,client] {
                request+=client->readAll();if(!request.contains("\r\n\r\n"))return;
                client->write("HTTP/1.0 200 OK\r\nContent-Type: audio/mpeg\r\nicy-metaint: 16000\r\nicy-name: Test Station\r\nContent-Length: 5\r\n\r\nhello");client->disconnectFromHost();
            });
        });
        media::MediaStreamProxy proxy;QNetworkAccessManager network;
        QNetworkRequest query(proxy.publish(QUrl(QString("http://127.0.0.1:%1/live").arg(upstream.serverPort()))));query.setRawHeader("Icy-MetaData","1");
        auto* reply=network.get(query);QSignalSpy done(reply,&QNetworkReply::finished);QVERIFY(done.wait(3000));
        QCOMPARE(reply->readAll(),QByteArray("hello"));QCOMPARE(reply->rawHeader("icy-metaint"),QByteArray("16000"));QCOMPARE(reply->rawHeader("icy-name"),QByteArray("Test Station"));
        QVERIFY(request.toLower().contains("icy-metadata: 1"));reply->deleteLater();
    }
    void favoritesExposeAllSourcesAndKeepQueueIdentity() {
        QTemporaryDir dir;infrastructure::database::Database db;QVERIFY(db.open(dir.filePath("favorites.sqlite")));QVERIFY(db.migrate());
        const QVariantMap icecast{{"radioProvider","icecast"},{"radioId","same"},{"title","Same title"},{"remoteUrl","https://example.org/live"},{"isLive",true}};
        const QVariantMap browser{{"radioProvider","radiobrowser"},{"radioId","same"},{"title","Same title"},{"remoteUrl","https://example.org/other"},{"isLive",true}};
        const QVariantMap program{{"radioProvider","netease-program"},{"radioId","42"},{"title","Episode"},{"durationMs",65000},{"remoteUrl","https://expires.example.org/temporary"}};
        {
            qmlbridge::RadioService service(db);service.toggleFavorite(icecast);service.toggleFavorite(browser);service.toggleFavorite(program);
            QCOMPARE(service.property("favorites").toList().size(),3);
            auto queued=browser;queued["entryId"]="different-queue-entry";queued["trackId"]="radio:radiobrowser:same";
            QVERIFY(service.isFavorite(queued));service.toggleFavorite(queued);
            QVERIFY(!service.isFavorite(browser));QVERIFY(service.isFavorite(icecast));
        }
        qmlbridge::RadioService restored(db);QVERIFY(!restored.busy());
        const auto rows=restored.property("favorites").toList();QCOMPARE(rows.size(),2);
        QCOMPARE(rows.first().toMap().value("durationMs").toInt(),65000);
        QVERIFY(!rows.first().toMap().contains("remoteUrl"));QVERIFY(!rows.first().toMap().contains("entryId"));
        QVERIFY(restored.isFavorite(icecast));QVERIFY(restored.isFavorite(program));
    }
    void savedPodcastOpensFromAnotherSource() {
        QTemporaryDir dir;infrastructure::database::Database db;QVERIFY(db.open(dir.filePath("podcast.sqlite")));QVERIFY(db.migrate());
        qmlbridge::RadioService service(db);
        const QVariantMap podcast{{"radioProvider","netease-podcast"},{"radioId","336355127"},{"title","代码时间"},{"kind","podcast"}};
        service.toggleFavorite(podcast);service.openPodcast(podcast);
        QCOMPARE(service.provider(),QString("netease"));QCOMPARE(service.mode(),QString("podcast"));
        QCOMPARE(service.podcast().value("radioId"),podcast.value("radioId"));
    }
    void realFavoriteViewPreservesDirectory() {
        if(!qEnvironmentVariableIsSet("LISTENFREE_RADIO_LIVE_TEST"))QSKIP("Explicit directory-switch test");
        QTemporaryDir dir;infrastructure::database::Database db;QVERIFY(db.open(dir.filePath("views.sqlite")));QVERIFY(db.migrate());
        qmlbridge::RadioService service(db);service.activate();QTRY_VERIFY_WITH_TIMEOUT(!service.busy(),40000);
        QVERIFY2(service.error().isEmpty(),qPrintable(service.error()));const auto original=service.rows();QCOMPARE(original.size(),30);
        service.toggleFavorite(original.first().toMap());service.setFavoritesOnly(true);QCOMPARE(service.rows().size(),1);
        service.setProvider("radiobrowser");service.setFavoritesOnly(false);service.setProvider("icecast");
        QTRY_VERIFY_WITH_TIMEOUT(!service.busy(),10000);QCOMPARE(service.rows(),original);
    }
    void realDirectoryAndPagination() {
        if(!qEnvironmentVariableIsSet("LISTENFREE_RADIO_LIVE_TEST"))QSKIP("Explicit public-directory test");
        QTemporaryDir dir;infrastructure::database::Database db;QVERIFY(db.open(dir.filePath("radio.sqlite")));QVERIFY(db.migrate());
        qmlbridge::RadioService service(db);service.activate();QTRY_VERIFY_WITH_TIMEOUT(!service.busy(),40000);
        QVERIFY2(service.error().isEmpty(),qPrintable(service.error()));QCOMPARE(service.rows().size(),30);QVERIFY(service.total()>100);
        service.search("Anime");QTRY_VERIFY_WITH_TIMEOUT(!service.busy(),3000);QVERIFY(!service.rows().isEmpty());
        service.setProvider("radiobrowser");QTRY_VERIFY_WITH_TIMEOUT(!service.busy(),30000);QVERIFY2(service.error().isEmpty(),qPrintable(service.error()));QVERIFY(!service.rows().isEmpty());
        service.setProvider("netease");QTRY_VERIFY_WITH_TIMEOUT(!service.busy(),30000);QVERIFY2(service.error().isEmpty(),qPrintable(service.error()));QVERIFY(!service.rows().isEmpty());QVERIFY(service.rows().size()<=30);
        const auto first=service.rows().first().toMap().value("radioId");service.goToPage(2);QTRY_VERIFY_WITH_TIMEOUT(!service.busy(),20000);QVERIFY(!service.rows().isEmpty());QVERIFY(service.rows().first().toMap().value("radioId")!=first);
        service.goToPage(1);QTRY_VERIFY_WITH_TIMEOUT(!service.busy(),20000);QCOMPARE(service.rows().first().toMap().value("radioId"),first);
        service.setMode("podcast");QTRY_VERIFY_WITH_TIMEOUT(!service.busy(),20000);QVERIFY(!service.rows().isEmpty());
        service.openPodcast({{"radioId","336355127"},{"title","代码时间"}});QTRY_VERIFY_WITH_TIMEOUT(!service.busy(),20000);QCOMPARE(service.rows().size(),30);QVERIFY(!service.rows().first().toMap().value("isLive").toBool());
    }
    void realPlayback_data() {
        QTest::addColumn<QVariantMap>("station");
        QTest::newRow("icecast-mp3")<<QVariantMap{{"radioProvider","icecast"},{"radioId","anime"},{"title","Anime Nexus"},{"remoteUrl","https://cast.animenexus.net/listen/animenexus/animenexus"},{"isLive",true}};
        QTest::newRow("radiobrowser-mp3")<<QVariantMap{{"radioProvider","radiobrowser"},{"radioId","cnr1"},{"title","中国之声"},{"remoteUrl","https://lhttp.qtfm.cn/live/15318317/64k.mp3"},{"isLive",true}};
        QTest::newRow("netease-hls")<<QVariantMap{{"radioProvider","netease-broadcast"},{"radioId","1203"},{"title","网易云广播"},{"isLive",true}};
        QTest::newRow("netease-podcast")<<QVariantMap{{"radioProvider","netease-program"},{"radioId","530692704"},{"title","代码时间"},{"durationMs",3626266},{"isLive",false}};
    }
    void realPlayback() {
        if(!qEnvironmentVariableIsSet("LISTENFREE_RADIO_LIVE_TEST"))QSKIP("Explicit public-stream test");
        QFETCH(QVariantMap,station);QTemporaryDir dir;infrastructure::database::Database db;
        const auto path=dir.filePath("radio.sqlite");QVERIFY(db.open(path));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository settings(db);qmlbridge::SourceController source(&settings);
        qmlbridge::PortableSession player(db,path,source);
        connect(&player,&qmlbridge::PortableSession::notice,this,[](const QString& message){qInfo().noquote()<<message;});
        QElapsedTimer elapsed;elapsed.start();QVERIFY(player.openTrack(station));QVERIFY(player.isCurrentTrack(station));
        QTRY_VERIFY_WITH_TIMEOUT(player.state()=="Playing" && player.position()>1200,45000);
        qInfo("Radio first advancing playback: %lld ms",elapsed.elapsed());
        if(station.value("isLive").toBool()) {QVERIFY(player.live());QVERIFY(!player.seekable());QCOMPARE(player.duration(),0);player.seek(60000);QTest::qWait(300);QVERIFY(player.position()<15000);}
        else {QVERIFY(!player.live());QVERIFY(player.duration()>60000);QVERIFY(player.seekable());}
        player.stop();QTest::qWait(200);QVERIFY(player.state()!="Playing");
    }
};
int main(int argc,char** argv) {
    QApplication app(argc,argv);QTemporaryDir config;QSettings::setDefaultFormat(QSettings::IniFormat);QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,config.path());
    app.setOrganizationName("ListenFreeRadioTests");app.setApplicationName("ListenFreeRadioTests");Qmmp::setConfigDir(config.path());
    RadioTests tests;return QTest::qExec(&tests,argc,argv);
}
#include "radio_tests.moc"
