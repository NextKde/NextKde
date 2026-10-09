#include "app/linux_media_session.h"
#include "app/nextkde_theme.h"
#include "qmlbridge/account_service.h"
#include "qmlbridge/source_controller.h"
#include "qmlbridge/portable_session.h"
#include "qmlbridge/controllers.h"
#include "qmlbridge/collection_service.h"
#include "infrastructure/database/repositories.h"
#include "infrastructure/library/library_scanner.h"
#include "online/platform_catalog.h"
#include "online/track_origin.h"
#include <QApplication>
#include <QTest>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QSaveFile>
#include <QDataStream>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDBusVariant>
#include <QDBusArgument>
#include <QDBusConnectionInterface>
#include <QDBusPendingCallWatcher>
#include <QNetworkReply>
#include <QImage>
#include <QProcess>
#include <qmmp/qmmp.h>

using namespace listenfree;
using namespace listenfree::qmlbridge;
class TestReply : public QNetworkReply {
public:
    TestReply(const QNetworkRequest& request, QObject* parent) : QNetworkReply(parent) { setRequest(request);setUrl(request.url());open(QIODevice::ReadOnly); }
    void finish(const QByteArray& data) { if(isFinished())return;bytes=data;setFinished(true);emit readyRead();emit finished(); }
    void abort() override { setError(OperationCanceledError,"cancelled");finish({}); }
protected:
    qint64 readData(char* out,qint64 size) override {const auto n=qMin<qint64>(size,bytes.size()-offset);if(n<=0)return -1;memcpy(out,bytes.constData()+offset,n);offset+=n;return n;}
private:
    QByteArray bytes; qint64 offset=0;
};
class TestNetwork : public QNetworkAccessManager {
public:
    QPointer<TestReply> reply; QNetworkRequest last;
protected:
    QNetworkReply* createRequest(Operation,const QNetworkRequest& request,QIODevice*) override { last=request;reply=new TestReply(request,this);return reply; }
};
class NextKdeTests : public QObject {
    Q_OBJECT
    static void write(const QString& path,const QByteArray& data) {QSaveFile file(path);QVERIFY(file.open(QIODevice::WriteOnly));QCOMPARE(file.write(data),data.size());QVERIFY(file.commit());}
private slots:
    void linuxScannerKeepsCaseDistinctFolders() {
        QTemporaryDir dir;
        const auto upper=dir.filePath("Music"),lower=dir.filePath("music");
        QVERIFY(QDir().mkpath(upper));QVERIFY(QDir().mkpath(lower));
        write(upper+"/song.mp3","first recording");write(lower+"/song.mp3","second recording");
        infrastructure::library::LibraryScanner scanner;
        QVector<domain::Track> found;
        connect(&scanner,&infrastructure::library::LibraryScanner::tracksFound,&scanner,[&](const QVector<domain::Track>& tracks){found+=tracks;});
        QSignalSpy finished(&scanner,&infrastructure::library::LibraryScanner::finished);
        scanner.start({upper,lower},std::make_shared<infrastructure::library::BasicMetadataReader>());
        QVERIFY(finished.wait(5000));QCOMPARE(found.size(),2);
        QVERIFY(found[0].localPath!=found[1].localPath);
    }
    void themeFollowsAtomicReplacements() {
        QTemporaryDir directory;
        const auto path=directory.filePath("appearance.json");
        write(path,R"({"themeMode":"light"})");
        NextKdeTheme theme(nullptr,path);QSignalSpy changes(&theme,&NextKdeTheme::changed);
        QVERIFY(!theme.dark());
        write(path,R"({"themeMode":"dark"})");QTRY_VERIFY(theme.dark());
        write(path,R"({"themeMode":"light"})");QTRY_VERIFY(!theme.dark());
        QVERIFY(changes.count()>=2);
        QVERIFY(NextKdeTheme::resolve("Dark","light",false));
        QVERIFY(!NextKdeTheme::resolve("Light","dark",true));
        QVERIFY(NextKdeTheme::resolve("System","system",true));
        QVERIFY(!NextKdeTheme::resolve("System","light",true));
    }
    void sourceDefaultSurvivesTemporarySwitchAndDeletion() {
        QTemporaryDir dir;qApp->setProperty("listenfreeDataDir",dir.path());
        infrastructure::database::Database db;QVERIFY(db.open(dir.filePath("library.sqlite")));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);
        SourceController source(&repo);
        write(dir.filePath("第一.js"),"// first source\n");write(dir.filePath("第二.js"),"// second source\n");
        QVERIFY(source.importLocalFile(dir.filePath("第一.js")));const auto first=source.activeId();
        QVERIFY(source.importLocalFile(dir.filePath("第二.js")));const auto second=source.activeId();
        QVERIFY(first!=second);QCOMPARE(source.defaultId(),first);
        QVERIFY(source.setDefaultSource(second));QVERIFY(source.selectSource(first));
        source.setUpdatePrompt(first,false); // Other writes must not persist the temporary selection.
        { SourceController restarted(&repo);QCOMPARE(restarted.activeId(),second);QCOMPARE(restarted.defaultId(),second); }
        QVERIFY(!source.setDefaultSource("missing"));QCOMPARE(source.defaultId(),second);
        QVERIFY(source.removeSource(second));QCOMPARE(source.defaultId(),first);
        { SourceController restarted(&repo);QCOMPARE(restarted.activeId(),first); }
        QVERIFY(source.removeSource(first));QVERIFY(source.defaultId().isEmpty());QVERIFY(source.activeId().isEmpty());
    }
    void nativeHostLoadsAdjacentExecutable() {
        QTemporaryDir dir;qApp->setProperty("listenfreeDataDir",dir.path());
        infrastructure::database::Database db;QVERIFY(db.open(dir.filePath("library.sqlite")));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);
        SourceController source(&repo,QString{},true);
        QVERIFY(source.hostAvailable());QTRY_VERIFY_WITH_TIMEOUT(source.hostReady(),10000);
        write(dir.filePath("洛雪.js"),R"(/** @name Native fixture */
lx.on(lx.EVENT_NAMES.request, ({action}) => Promise.resolve('https://example.invalid/fixture.mp3'));
lx.send(lx.EVENT_NAMES.inited, {status:true,sources:{kw:{name:'Kuwo',type:'music',actions:['musicUrl'],qualitys:['128k']}}});)");
        QVERIFY(source.importLocalFile(dir.filePath("洛雪.js")));
        QTRY_VERIFY_WITH_TIMEOUT(source.sources().last().toMap().value("hostReady").toBool(),10000);
        QSignalSpy resolution(&source,&SourceController::resolutionFinished);
        const auto id=source.resolveMusicUrl(source.activeId(),"128k",{{"source","kw"},{"songmid","1"},{"id","1"}});
        QVERIFY(!id.isEmpty());QTRY_COMPARE_WITH_TIMEOUT(resolution.size(),1,5000);
        QVERIFY2(resolution.first().last().toString().isEmpty(),qPrintable(resolution.first().last().toString()));
    }
    void scriptSearchAndPlaybackKeepTheirOrigin() {
        QTemporaryDir dir; qApp->setProperty("listenfreeDataDir", dir.path());
        infrastructure::database::Database db;
        const auto dbPath = dir.filePath("library.sqlite");
        QVERIFY(db.open(dbPath)); QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);
        SourceController source(&repo, QString{}, true);
        QTRY_VERIFY_WITH_TIMEOUT(source.hostReady(), 10000);
        const auto fixture = QByteArray(R"(/**
 * @name Script FIXTURE_TOKEN
 * @version 2.1
 * @author Fixture author
 * @description A searchable source
 */
lx.on(lx.EVENT_NAMES.request, ({action, info}) => {
    if (action === 'search') {
        if (info.keyword !== 'fixture' || info.page !== 1) throw new Error('bad search arguments');
        return Promise.resolve({rows: [{songmid: 'same-id', name: 'Song FIXTURE_TOKEN', singer: 'Artist', interval:'03:21', opaqueToken: 'FIXTURE_TOKEN', localPath:'/tmp/never-open', remoteUrl:'https://example.invalid/bypass.mp3'}], total: 1});
    }
    if (action === 'musicUrl' && info.musicInfo.opaqueToken === 'FIXTURE_TOKEN')
        return Promise.resolve('https://example.invalid/FIXTURE_TOKEN.mp3');
    if (action === 'lyric' && info.musicInfo.opaqueToken === 'FIXTURE_TOKEN')
        return Promise.resolve({lyric: '[00:00.00]Lyrics FIXTURE_TOKEN'});
    throw new Error('wrong script metadata');
});
lx.send(lx.EVENT_NAMES.inited, {status:true,sources:{custom:{name:'Catalog',type:'music',actions:['search','musicUrl','lyric'],qualitys:['128k']}}});)");
        write(dir.filePath("a.js"), QByteArray(fixture).replace("FIXTURE_TOKEN", "A"));
        write(dir.filePath("b.js"), QByteArray(fixture).replace("FIXTURE_TOKEN", "B"));
        QVERIFY(source.importLocalFile(dir.filePath("a.js"))); const auto first = source.activeId();
        QVERIFY(source.importLocalFile(dir.filePath("b.js"))); const auto second = source.activeId();
        QCOMPARE(source.sources().first().toMap().value("name").toString(), QString("Script A"));
        QCOMPARE(source.sources().first().toMap().value("version").toString(), QString("2.1"));
        QSignalSpy resolved(&source, &SourceController::resolutionFinished);
        const auto search = source.searchScript(first, "fixture"); QVERIFY(!search.isEmpty());
        QTRY_COMPARE_WITH_TIMEOUT(resolved.size(), 1, 10000);
        QCOMPARE(resolved.first()[0].toString(), search);
        QVERIFY2(resolved.first().last().toString().isEmpty(), qPrintable(resolved.first().last().toString()));
        auto rows = resolved.first()[3].toMap().value("rows").toList(); QCOMPARE(rows.size(), 1);
        const auto track = rows.first().toMap(); QCOMPARE(track.value("originSourceId").toString(), first);
        QCOMPARE(track.value("source").toString(), QString("custom"));
        QVERIFY(online::isScriptTrack(track));
        QVERIFY(!track.contains("localPath")); QVERIFY(!track.contains("remoteUrl"));
        QCOMPARE(track.value("durationMs").toLongLong(), 201000);
        const auto info = online::sourceMusicInfo(track);
        QCOMPARE(info.value("opaqueToken").toString(), QString("A"));
        resolved.clear();
        const auto playback = source.resolveMusicUrl(second, "flac", info);
        QVERIFY(!playback.isEmpty()); QTRY_COMPARE_WITH_TIMEOUT(resolved.size(), 1, 10000);
        QVERIFY2(resolved.first().last().toString().isEmpty(), qPrintable(resolved.first().last().toString()));
        QCOMPARE(resolved.first()[3].toMap().value("url").toString(), QString("https://example.invalid/A.mp3"));
        QCOMPARE(source.activeId(), second);
        resolved.clear();
        QVERIFY(!source.resolveLyric(second, info).isEmpty());
        QTRY_COMPARE_WITH_TIMEOUT(resolved.size(), 1, 10000);
        QCOMPARE(resolved.first()[3].toMap().value("lyric").toString(), QString("[00:00.00]Lyrics A"));
        resolved.clear();
        const auto cancelled = source.searchScript(first, "fixture");
        QVERIFY(source.cancelResolution(cancelled));
        const auto continuing = source.searchScript(second, "fixture");
        QTRY_COMPARE_WITH_TIMEOUT(resolved.size(), 1, 10000);
        QCOMPARE(resolved.first()[0].toString(), continuing);
        auto other = track; other["originSourceId"] = second; other["trackId"] = online::scriptTrackKey(other);
        QVERIFY(online::scriptTrackKey(other) != online::scriptTrackKey(track));
        {
            CollectionService favorites(db);
            favorites.toggleTrackLiked(track);
            QVERIFY(favorites.isTrackLiked(track)); QVERIFY(!favorites.isTrackLiked(other));
            favorites.toggleTrackLiked(other);
            QVERIFY(favorites.isTrackLiked(other));
            favorites.toggleTrackLiked(track);
            QVERIFY(!favorites.isTrackLiked(track)); QVERIFY(favorites.isTrackLiked(other));
        }
        {
            PortableSession player(db, dbPath, source);
            QVERIFY(player.enqueueTrack(track)); QVERIFY(player.enqueueTrack(other));
            QCOMPARE(player.queueSongs().size(), 2); player.shutdown();
        }
        {
            PortableSession player(db, dbPath, source);
            QCOMPARE(player.queueSongs().size(), 2);
            QCOMPARE(player.queueSongs().first().toMap().value("originSourceId").toString(), first);
            player.setSearchSourceId(first);
            QVERIFY(source.removeSource(first));
            QCOMPARE(player.searchSourceId(), source.defaultId());
            player.shutdown();
        }
        QVERIFY(source.resolveMusicUrl(second, "128k", info).isEmpty());
        QVERIFY(source.lastError().contains("已移除"));
    }
    void resolverOnlySourceDoesNotPretendToSearch() {
        QTemporaryDir dir; qApp->setProperty("listenfreeDataDir", dir.path());
        infrastructure::database::Database db; QVERIFY(db.open(dir.filePath("db"))); QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);
        SourceController source(&repo, QString{}, true);
        QTRY_VERIFY_WITH_TIMEOUT(source.hostReady(), 10000);
        write(dir.filePath("resolver.js"), R"(/** @name Resolver */
lx.on(lx.EVENT_NAMES.request, () => Promise.resolve('https://example.invalid/a.mp3'));
lx.send(lx.EVENT_NAMES.inited, {sources:{kw:{name:'Kuwo',type:'music',actions:['musicUrl'],qualitys:['128k']}}});)");
        QVERIFY(source.importLocalFile(dir.filePath("resolver.js")));
        QSignalSpy resolved(&source, &SourceController::resolutionFinished);
        QVERIFY(!source.searchScript(source.activeId(), "fixture").isEmpty());
        QTRY_COMPARE_WITH_TIMEOUT(resolved.size(), 1, 10000);
        QVERIFY(resolved.first().last().toString().contains("未提供搜索"));
        QVERIFY(!source.sources().first().toMap().value("searchSupported").toBool());
    }
    void accountContractsAndCancellation() {
        QCOMPARE(AccountService::providers().size(),5);
        QVERIFY(AccountService::cookieDomainAllowed("netease",".music.163.com"));
        QVERIFY(!AccountService::cookieDomainAllowed("netease","music.163.com.attacker.invalid"));
        QVERIFY(!AccountService::cookieDomainAllowed("unknown","qq.com"));
        QVERIFY(AccountService::hasLoginCookie("qqmusic","uin=123; qqmusic_key=test"));
        QVERIFY(!AccountService::hasLoginCookie("qqmusic","uin=123"));
        QVERIFY(AccountService::hasLoginCookie("kuwo","userid=123; sid=test"));
        QVERIFY(AccountService::hasLoginCookie("kugou","KuGoo=KugooID=123&t=test"));
        QVERIFY(!AccountService::hasLoginCookie("netease","MUSIC_U=test\nInjected: x"));
        QCOMPARE(AccountService::parseProfile("qqmusic",R"({"code":0,"data":{"creator":{"uin":123,"nick":"Fixture"}}})").value("name").toString(),QString("Fixture"));
        QVERIFY(AccountService::parseProfile("qqmusic",R"({"code":1000,"data":{"creator":{"uin":123,"nick":"Fixture"}}})").isEmpty());
        QTemporaryDir dir;TestNetwork network;AccountService accounts(dir.path(),nullptr,&network);
        QSignalSpy finished(&accounts,&AccountService::loginFinished);
        accounts.login("bilibili","SESSDATA=fixture");QVERIFY(network.reply);
        QCOMPARE(network.last.url().host(),QString("api.bilibili.com"));
        QCOMPARE(network.last.attribute(QNetworkRequest::RedirectPolicyAttribute).toInt(),int(QNetworkRequest::ManualRedirectPolicy));
        accounts.cancelLogin("bilibili");QVERIFY(!accounts.accounts().value("bilibili").toMap().value("busy").toBool());
        QVERIFY(accounts.accounts().value("bilibili").toMap().value("id").toString().isEmpty());
        QCOMPARE(finished.size(),0);QVERIFY(accounts.cookieForRequest("bilibili").isEmpty());
        network.reply->finish(R"({"code":0,"data":{"isLogin":true,"mid":1,"uname":"late"}})");
        QVERIFY(accounts.accounts().value("bilibili").toMap().value("id").toString().isEmpty());
    }
    void platformCookiesStayOnOfficialEndpoints() {
        TestNetwork network;network.setProperty("listenfree.cookie.wy",QByteArray("MUSIC_U=fixture"));
        auto* reply=online::platformRequest(network,"wy","search","test");QVERIFY(reply);
        QCOMPARE(network.last.rawHeader("Cookie"),QByteArray("MUSIC_U=fixture"));
        QCOMPARE(network.last.attribute(QNetworkRequest::RedirectPolicyAttribute).toInt(),int(QNetworkRequest::ManualRedirectPolicy));
        reply->abort();reply->deleteLater();
        reply=online::platformRequest(network,"kw","search","test");QVERIFY(reply);
        QVERIFY(network.last.rawHeader("Cookie").isEmpty());reply->abort();reply->deleteLater();
    }
    void mediaSessionPlaybackLyricsAndControls() {
        QTemporaryDir dir;qApp->setProperty("listenfreeDataDir",dir.path());
        Qmmp::setConfigDir(dir.filePath("qmmp"));
        infrastructure::database::Database db;const auto dbPath=dir.filePath("library.sqlite");QVERIFY(db.open(dbPath));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);SettingsController settings(repo);SourceController source(&repo);
        PortableSession player(db,dbPath,source);
        LinuxMediaSession media(player,settings,nullptr);QVERIFY(media.registered());
        QDBusInterface root("org.mpris.MediaPlayer2.listenfree","/org/mpris/MediaPlayer2","org.mpris.MediaPlayer2");
        QDBusInterface remote("org.mpris.MediaPlayer2.listenfree","/org/mpris/MediaPlayer2","org.mpris.MediaPlayer2.Player");
        QCOMPARE(root.property("DesktopEntry").toString(),QString("listenfree"));
        QVERIFY(media.metadata().isEmpty());
        const auto audio=dir.filePath("测试歌曲.wav");
        QFile file(audio);QVERIFY(file.open(QIODevice::WriteOnly));QDataStream out(&file);out.setByteOrder(QDataStream::LittleEndian);
        const quint32 size=44100*2*8;
        out.writeRawData("RIFF",4);out<<quint32(size+36);out.writeRawData("WAVEfmt ",8);out<<quint32(16)<<quint16(1)<<quint16(1)<<quint32(44100)<<quint32(88200)<<quint16(2)<<quint16(16);out.writeRawData("data",4);out<<size;file.write(QByteArray(size,0));file.close();
        write(dir.filePath("测试歌曲.lrc"),"[00:00.00]第一行\n[00:02.00]第二行\n[00:04.00]第三行\n");
        QImage cover(64,64,QImage::Format_RGB32);cover.fill(Qt::red);QVERIFY(cover.save(dir.filePath("cover.jpg")));
        const auto call=[&](const QString& method,const QVariantList& args=QVariantList{}) {
            QDBusPendingCallWatcher watcher(remote.asyncCallWithArgumentList(method,args));
            QSignalSpy done(&watcher,&QDBusPendingCallWatcher::finished);
            if(!watcher.isFinished())QVERIFY(done.wait(5000));
            QVERIFY2(!watcher.isError(),qPrintable(watcher.error().message()));
        };
        call("OpenUri",{QUrl::fromLocalFile(audio).toString()});
        QTRY_COMPARE_WITH_TIMEOUT(player.state(),QString("Playing"),5000);
        QTRY_COMPARE(media.metadata().value("kos:currentLyric").toString(),QString("第一行"));
        QCOMPARE(media.metadata().value("kos:nextLyric").toString(),QString("第二行"));
        QCOMPARE(media.metadata().value("mpris:trackid").value<QDBusObjectPath>(),media.trackPath());
        for (const auto& value : media.metadata()) QVERIFY(value.isValid()); // D-Bus a{sv} cannot marshal an invalid QVariant.
        QProcess wireProbe;
        wireProbe.start(QCoreApplication::applicationFilePath(),{"--wire-read"});
        QTRY_COMPARE_WITH_TIMEOUT(wireProbe.state(),QProcess::NotRunning,5000);
        QCOMPARE(wireProbe.exitCode(),0);
        QCOMPARE(wireProbe.exitStatus(),QProcess::NormalExit);
        QTRY_VERIFY(!media.metadata().value("mpris:artUrl").toString().isEmpty());
        QVERIFY(QFileInfo::exists(QUrl(media.metadata().value("mpris:artUrl").toString()).toLocalFile()));
        call("Pause");QTRY_COMPARE(player.state(),QString("Paused"));
        QVERIFY(remote.setProperty("Volume",.25));QTRY_VERIFY(qAbs(player.volume()-.25f)<.02);
        QVERIFY(remote.setProperty("LoopStatus",QString("Track")));QCOMPARE(player.playbackMode(),QString("singleLoop"));
        QVERIFY(remote.setProperty("Shuffle",true));QCOMPARE(player.playbackMode(),QString("shuffle"));
        const auto before=player.position();call("SetPosition",{QVariant::fromValue(QDBusObjectPath("/wrong/track")),QVariant::fromValue<qlonglong>(4000000)});QCOMPARE(player.position(),before);
        QSignalSpy seeks(&media,&LinuxMediaSession::seeked);
        call("SetPosition",{QVariant::fromValue(media.trackPath()),QVariant::fromValue<qlonglong>(4000000)});
        QTRY_VERIFY(player.position()>=3900);QVERIFY(!seeks.isEmpty());
        QTRY_COMPARE(media.metadata().value("kos:currentLyric").toString(),QString("第三行"));
        settings.setValue("nextkde.lyricsEnabled",false);
        QVERIFY(!media.metadata().value("kos:lockscreenLyricsEnabled").toBool());
        QVERIFY(media.metadata().value("kos:desktopLyricsEnabled").toBool());
        QVERIFY(!media.metadata().value("kos:currentLyric").toString().isEmpty());
        settings.setValue("nextkde.desktopLyricsEnabled",false);
        QVERIFY(!media.metadata().value("kos:desktopLyricsEnabled").toBool());
        settings.setValue("nextkde.desktopLyricsEnabled",true);
        settings.setValue("nextkde.lyricsEnabled",true);
        const auto secondAudio=dir.filePath("下一首.wav");QVERIFY(QFile::copy(audio,secondAudio));
        QVERIFY(player.enqueueTrack({{"trackId",secondAudio},{"title","下一首"},{"localPath",secondAudio}}));
        QVERIFY(remote.setProperty("LoopStatus",QString("Playlist")));
        call("Next");QTRY_COMPARE(player.currentTrack().value("title").toString(),QString("下一首"));
        QVERIFY(media.metadata().value("kos:currentLyric").toString().isEmpty());
        call("Previous");QTRY_VERIFY(player.currentTrack().value("title").toString()!=QString("下一首"));
        call("Play");QTRY_COMPARE(player.state(),QString("Playing"));
        call("Stop");QTRY_VERIFY(player.state()!="Playing");
        settings.setValue("nextkde.mediaEnabled",false);QVERIFY(!media.registered());
        settings.setValue("nextkde.mediaEnabled",true);QVERIFY(media.registered());
        player.shutdown();
    }
};
int main(int argc,char** argv) {
    qputenv("LISTENFREE_QMMP_OUTPUT","null");QApplication app(argc,argv);QCoreApplication::setApplicationName("ListenFreeNextKdeTests");
    if (app.arguments().contains("--wire-read")) {
        QDBusInterface properties("org.mpris.MediaPlayer2.listenfree","/org/mpris/MediaPlayer2","org.freedesktop.DBus.Properties");
        QDBusReply<QVariantMap> reply=properties.call("GetAll",QString("org.mpris.MediaPlayer2.Player"));
        if(!reply.isValid())return 2;
        const auto value=reply.value().value("Metadata");
        const auto metadata=value.metaType()==QMetaType::fromType<QDBusArgument>() ? qdbus_cast<QVariantMap>(value) : value.toMap();
        return metadata.value("xesam:title").toString().isEmpty() || !metadata.contains("xesam:album") ? 3 : 0;
    }
    NextKdeTests tests;return QTest::qExec(&tests,argc,argv);
}
#include "nextkde_integration_tests.moc"
