#include "online/bilibili_client.h"
#include "qmlbridge/collection_service.h"
#include "qmlbridge/portable_session.h"
#include "qmlbridge/controllers.h"
#include "infrastructure/database/repositories.h"
#include <QApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QSignalSpy>
#include <QSettings>
#include <QTemporaryDir>
#include <QTest>
#include <QTimer>
#include <QUrlQuery>
#include <QTcpServer>
#include <QTcpSocket>
#include <QtEndian>
#include <cmath>
#include <qmmp/qmmp.h>
#ifdef Q_OS_WIN
#include <objbase.h>
#endif

using namespace listenfree;
using online::BilibiliClient;
namespace {
QString bvid(int index) { return QString("BV%1").arg(index,10,10,QChar('0')); }
QJsonObject view(int index, int count=1) {
    QJsonArray pages;
    for (int p=count;p>0;--p) pages.append(QJsonObject{{"cid",index*100+p},{"page",p},{"part",QString("Part %1").arg(p)},{"duration",180+p}});
    return {{"bvid",bvid(index)},{"title","<em>Music</em> &amp; song"},{"pic","//i0.hdslb.com/cover.jpg"},
            {"owner",QJsonObject{{"name","Singer"}}},{"pages",pages}};
}
QJsonObject playInfo() {
    return {{"dash",QJsonObject{{"audio",QJsonArray{
        QJsonObject{{"id",30216},{"bandwidth",67000},{"base_url","https://cdn.example/low.m4s"}},
        QJsonObject{{"id",30280},{"bandwidth",320000},{"baseUrl","https://cdn.example/high.m4s"}},
        QJsonObject{{"id",30232},{"bandwidth",132000},{"baseUrl","https://cdn.example/medium.m4s"}}
    }}}}};
}
class Reply final : public QNetworkReply {
public:
    Reply(const QNetworkRequest& request,QObject* parent):QNetworkReply(parent) {
        setRequest(request);setUrl(request.url());open(ReadOnly);
    }
    void complete(QJsonObject root) {
        if(isFinished())return;
        bytes_=QJsonDocument(root).toJson(QJsonDocument::Compact);
        setFinished(true);emit readyRead();emit finished();
    }
    void abort() override { if(!isFinished()){setError(OperationCanceledError,"cancelled");complete({});} }
    qint64 bytesAvailable() const override { return bytes_.size()-cursor_+QNetworkReply::bytesAvailable(); }
protected:
    qint64 readData(char* data,qint64 length) override {
        const auto count=qMin(length,qint64(bytes_.size()-cursor_));if(count<=0)return -1;
        memcpy(data,bytes_.constData()+cursor_,count);cursor_+=count;return count;
    }
private:
    QByteArray bytes_;qint64 cursor_{0};
};
class Network final : public QNetworkAccessManager {
public:
    QList<QNetworkRequest> requests;
    int activeViews{0},peakViews{0},videoCount{8},failure{-1};
    bool holdViews{false},searchFailure{false};
protected:
    QNetworkReply* createRequest(Operation,const QNetworkRequest& request,QIODevice*) override {
        requests.append(request);auto* reply=new Reply(request,this);
        const auto path=request.url().path();QUrlQuery query(request.url());QJsonObject data;
        int code=0,delay=0;
        if(path.endsWith("/nav")) {
            code=-101;data={{"wbi_img",QJsonObject{{"img_url","https://i.example/abcdefghijklmnopqrstuvwxyz012345.png"},
                {"sub_url","https://i.example/ABCDEFGHIJKLMNOPQRSTUVWXYZ678901.png"}}}};
        } else if(path.endsWith("/spi")) data={{"b_3","test-visitor"},{"b_4","test-visitor4"}};
        else if(path.endsWith("/search/type")) {
            QJsonArray rows;for(int i=1;i<=videoCount;++i)rows.append(QJsonObject{{"bvid",bvid(i)}});
            data={{"result",rows},{"numPages",7}};if(searchFailure)code=-352;
        } else if(path.endsWith("/view")) {
            ++activeViews;peakViews=qMax(peakViews,activeViews);
            connect(reply,&QNetworkReply::finished,this,[this]{--activeViews;});
            if(holdViews)return reply;
            int index=query.queryItemValue("bvid").mid(2).toInt();
            data=view(index,index%2==0?3:1);delay=index%2==0?2:12;if(index==failure)code=-404;
        } else if(path.endsWith("/playurl")) data=playInfo();
        else code=-404;
        QTimer::singleShot(delay,reply,[reply,data,code]{reply->complete({{"code",code},{"data",data}});});
        return reply;
    }
};
}
class BilibiliTests final : public QObject {
    Q_OBJECT
    QTemporaryDir profile_;
private slots:
    void initTestCase() {
        QCoreApplication::setOrganizationName("ListenFreeBilibiliTests");
        QCoreApplication::instance()->setProperty("listenfreeDataDir",profile_.path());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,profile_.path());
        QSettings::setPath(QSettings::IniFormat,QSettings::SystemScope,profile_.path());
        Qmmp::setConfigDir(profile_.filePath("qmmp"));
#ifdef Q_OS_WIN
        CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);
#endif
    }
    void partIdentityAndOrder() {
        const auto collection=BilibiliClient::collectionFromView(view(2,3));const auto tracks=collection.value("tracks").toList();
        QCOMPARE(tracks.size(),3);QCOMPARE(collection.value("kind").toString(),"playlist");
        for(int i=0;i<3;++i) {
            const auto track=tracks[i].toMap();QCOMPARE(track.value("page").toInt(),i+1);
            QCOMPARE(track.value("rid").toString(),bvid(2)+"_"+QString::number(201+i));
            QCOMPARE(track.value("trackId").toString(),"bili:"+track.value("rid").toString());
            QVERIFY(track.value("album").toString().isEmpty());QVERIFY(!track.contains("resolvedUrl"));
        }
        QCOMPARE(BilibiliClient::collectionFromView(view(1)).value("tracks").toList().first().toMap().value("title").toString(),"Music & song");
    }
    void searchClassifiesPreservesOrderAndCachesBothCategories() {
        Network network;BilibiliClient client(nullptr,&network);QVariantMap result;QString error;int finished=0;
        auto done=[&](QVariantMap data,QString message){result=data;error=message;++finished;};
        client.search("music",1,"songs",this,done);QCOMPARE(finished,0);
        QTRY_COMPARE(finished,1);QVERIFY2(error.isEmpty(),qPrintable(error));
        auto rows=result.value("rows").toList();QCOMPARE(rows.size(),4);QCOMPARE(result.value("pages").toInt(),7);
        for(int i=0;i<4;++i)QCOMPARE(rows[i].toMap().value("bvid").toString(),bvid(i*2+1));
        QCOMPARE(network.peakViews,4);QCOMPARE(network.activeViews,0);
        const auto requests=network.requests.size();
        client.search("music",1,"playlists",this,done);QTRY_COMPARE(finished,2);
        QCOMPARE(network.requests.size(),requests);rows=result.value("rows").toList();QCOMPARE(rows.size(),4);
        for(int i=0;i<4;++i){QCOMPARE(rows[i].toMap().value("bvid").toString(),bvid(i*2+2));QVERIFY(!rows[i].toMap().contains("tracks"));}
        client.search("music",2,"songs",this,done);QTRY_COMPARE(finished,3);QVERIFY(network.requests.size()>requests);
    }
    void cancellationStopsEveryInFlightReply() {
        Network network;network.holdViews=true;BilibiliClient client(nullptr,&network);int finished=0;
        auto id=client.search("cancel",1,"songs",this,[&](QVariantMap,QString){++finished;});
        QTRY_COMPARE(network.activeViews,4);QVERIFY(client.cancel(id));
        QCOMPARE(network.activeViews,0);QCOMPARE(finished,0);QVERIFY(!client.cancel(id));
        QObject* context=new QObject;
        client.detail(bvid(3),context,[&](QVariantMap,QString){++finished;});
        QTRY_COMPARE(network.activeViews,1);delete context;
        QCOMPARE(network.activeViews,0);QCOMPARE(finished,0);
    }
    void apiFailureAndEmptyResultsComplete() {
        Network network;network.searchFailure=true;BilibiliClient client(nullptr,&network);int finished=0;QString error;QVariantMap result;
        auto done=[&](QVariantMap data,QString message){result=data;error=message;++finished;};
        client.search("failed",1,"songs",this,done);QTRY_COMPARE(finished,1);QVERIFY(!error.isEmpty());
        network.searchFailure=false;network.videoCount=0;
        client.search("empty",1,"playlists",this,done);QTRY_COMPARE(finished,2);QVERIFY(error.isEmpty());QCOMPARE(result.value("total").toInt(),0);
        client.detail("invalid",this,done);QTRY_COMPARE(finished,3);QVERIFY(!error.isEmpty());
    }
    void mvPrefers1080BeforeCodecAndPreservesActualQuality() {
        const auto video=[](int quality,int width,int height,int codec,const QString& url) {
            return QJsonObject{{"id",quality},{"width",width},{"height",height},{"codecid",codec},{"baseUrl",url}};
        };
        auto rows=QJsonArray{video(32,852,480,7,"https://cdn.example/480"),
            video(80,1920,800,12,"https://cdn.example/1080-hevc"),
            video(120,3840,2160,7,"https://cdn.example/4k")};
        const auto select=[&]{return BilibiliClient::videoFromPlayInfo({{"dash",QJsonObject{{"video",rows}}}});};
        QCOMPARE(select().value("url").toString(),"https://cdn.example/1080-hevc");
        rows.append(video(80,1920,800,7,"https://cdn.example/1080-avc"));
        QCOMPARE(select().value("url").toString(),"https://cdn.example/1080-avc");
        rows=QJsonArray{rows.first()};QCOMPARE(select().value("quality").toInt(),32);
        rows=QJsonArray{video(80,1920,1080,7,"file:///private")};QVERIFY(select().isEmpty());
        QVERIFY(BilibiliClient::videoFromPlayInfo({{"durl",QJsonArray{QJsonObject{{"url","https://cdn.example/1"}},QJsonObject{{"url","https://cdn.example/2"}}}}}).isEmpty());
    }
    void audioSelectionAndCredentialScope() {
        QCOMPARE(BilibiliClient::audioFromPlayInfo(playInfo(),"128k",bvid(1)).value("url").toString(),"https://cdn.example/medium.m4s");
        const auto best=BilibiliClient::audioFromPlayInfo(playInfo(),"flac",bvid(1));
        QCOMPARE(best.value("url").toString(),"https://cdn.example/high.m4s");QCOMPARE(best.value("extension").toString(),"m4a");
        QVERIFY(!best.value("headers").toMap().contains("Cookie"));
        QVERIFY(BilibiliClient::audioFromPlayInfo({{"durl",QJsonArray{QJsonObject{{"url","https://example/part1"}},QJsonObject{{"url","https://example/part2"}}}}},"auto",bvid(1)).isEmpty());
        Network network;BilibiliClient client(nullptr,&network);client.setCookie("SESSDATA=synthetic; buvid3=synthetic");
        int finished=0;QString error;QVariantMap result;
        client.audio({{"source","bili"},{"bvid",bvid(2)},{"cid","202"}},"auto",this,[&](QVariantMap data,QString message){result=data;error=message;++finished;});
        QTRY_COMPARE(finished,1);QVERIFY2(error.isEmpty(),qPrintable(error));
        for(const auto& request:network.requests){QCOMPARE(request.url().host(),"api.bilibili.com");QCOMPARE(request.rawHeader("Cookie"),QByteArray("SESSDATA=synthetic; buvid3=synthetic"));}
        const QUrlQuery params(network.requests.last().url());QCOMPARE(params.queryItemValue("cid"),"202");QVERIFY(!params.queryItemValue("w_rid").isEmpty());
        QVERIFY(!result.value("headers").toMap().contains("Cookie"));
    }
    void collectionUsesNativeDetailAndPersistsParts() {
        QTemporaryDir dir;infrastructure::database::Database db;QVERIFY(db.open(dir.filePath("library.sqlite")));QVERIFY(db.migrate());
        Network network;BilibiliClient client(nullptr,&network);qmlbridge::CollectionService collections(db);collections.setBilibiliClient(&client);
        network.holdViews=true;collections.open({{"source","bili"},{"id",bvid(2)},{"kind","playlist"}});
        QTRY_COMPARE(network.activeViews,1);collections.cancelDetail();QCOMPARE(network.activeViews,0);QVERIFY(!collections.detailBusy());
        network.holdViews=false;collections.open({{"source","bili"},{"id",bvid(2)},{"kind","playlist"}});
        QTRY_VERIFY(!collections.detailBusy());QVERIFY(collections.detail().value("error").toString().isEmpty());
        const auto rows=collections.detail().value("tracks").toList();QCOMPARE(rows.size(),3);
        collections.toggleSaved(collections.detail());QVERIFY(collections.isSaved(collections.detail()));
        qmlbridge::CollectionService restored(db);restored.setBilibiliClient(&client);bool found=false;
        for(const auto& value:restored.playlists())if(value.toMap().value("source")=="bili") {
            found=true;QCOMPARE(value.toMap().value("playlistId").toString(),bvid(2));restored.open(value.toMap());
        }
        QVERIFY(found);
        QTRY_VERIFY(!restored.detailBusy());QCOMPARE(restored.detail().value("tracks").toList(),rows);
        const auto localId=restored.create("My Bili songs",rows);QVERIFY(!localId.isEmpty());
        qmlbridge::CollectionService localReload(db);found=false;
        for(const auto& value:localReload.playlists())if(value.toMap().value("id")==localId) {
            found=true;const auto saved=value.toMap().value("tracks").toList();QCOMPARE(saved.size(),rows.size());
            for(int i=0;i<saved.size();++i)for(const auto* key:{"trackId","rid","source","cid","title","page","durationMs"})
                QCOMPARE(saved[i].toMap().value(key).toString(),rows[i].toMap().value(key).toString());
        }
        QVERIFY(found);
    }
    void switchOnlyControlsDiscoveryAndNativeResolutionIsIndependent() {
        QTemporaryDir dir;infrastructure::database::Database db;const auto path=dir.filePath("library.sqlite");QVERIFY(db.open(path));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController sources(&repo);
        qmlbridge::PortableSession session(db,path,sources);QVERIFY(!session.bilibiliSourceEnabled());
        session.setPlatform("bili");QCOMPARE(session.platform(),"kw");
        session.setSearchCategory("albums");session.setBilibiliSourceEnabled(true);session.setPlatform("bili");
        QCOMPARE(session.platform(),"bili");QCOMPARE(session.searchCategory(),"songs");
        session.setSearchCategory("albums");QCOMPARE(session.searchCategory(),"songs");
        const auto track=BilibiliClient::collectionFromView(view(2,3)).value("tracks").toList().first().toMap();
        QVERIFY(session.enqueueTrack(track));session.setBilibiliSourceEnabled(false);QCOMPARE(session.platform(),"kw");QCOMPARE(session.queueSongs().size(),1);
        const auto request=sources.resolveMusicUrl({},"auto",track);QVERIFY(request.startsWith("bili-"));QVERIFY(sources.cancelResolution(request));
        qmlbridge::SettingsController settings(repo);settings.setValue("account.bilibili.sourceEnabled",true);
        qmlbridge::SettingsController restored(repo);QVERIFY(restored.value("account.bilibili.sourceEnabled",false).toBool());
    }
    void largeHttpAudioBoundsReadAheadAndStillSeeks() {
        // Generate a long WAV incrementally: the test itself never stores the file.
        constexpr qint64 dataSize=64*1024*1024,fileSize=dataSize+44;
        QByteArray header;
        const auto u16=[&](quint16 v){v=qToLittleEndian(v);header.append(reinterpret_cast<const char*>(&v),2);};
        const auto u32=[&](quint32 v){v=qToLittleEndian(v);header.append(reinterpret_cast<const char*>(&v),4);};
        header.append("RIFF");u32(quint32(dataSize+36));header.append("WAVEfmt ");u32(16);u16(1);u16(2);u32(44100);u32(176400);u16(4);u16(16);header.append("data");u32(quint32(dataSize));
        QTcpServer server;QVERIFY(server.listen(QHostAddress::LocalHost));qint64 sent=0;int ranged=0;
        connect(&server,&QTcpServer::newConnection,this,[&]{
            while(server.hasPendingConnections()) {
                auto* socket=server.nextPendingConnection();
                const auto pump=[&,socket]{
                    if(!socket->property("started").toBool() || socket->state()!=QAbstractSocket::ConnectedState)return;
                    auto position=socket->property("position").toLongLong();
                    while(position<fileSize && socket->bytesToWrite()<65536) {
                        const auto length=qMin<qint64>(65536,fileSize-position);QByteArray bytes(int(length),'\0');
                        if(position<header.size())memcpy(bytes.data(),header.constData()+position,size_t(qMin(length,header.size()-position)));
                        socket->write(bytes);position+=length;sent+=length;
                    }
                    socket->setProperty("position",position);
                    if(position==fileSize)socket->disconnectFromHost();
                };
                connect(socket,&QTcpSocket::bytesWritten,socket,pump);
                connect(socket,&QTcpSocket::readyRead,socket,[&,socket,pump]{
                    if(socket->property("started").toBool())return;
                    const auto request=socket->property("request").toByteArray()+socket->readAll();socket->setProperty("request",request);
                    if(!request.contains("\r\n\r\n"))return;
                    const auto match=QRegularExpression("range: bytes=(\\d+)-",QRegularExpression::CaseInsensitiveOption).match(QString::fromLatin1(request));
                    const qint64 offset=match.hasMatch()?match.captured(1).toLongLong():0;
                    if(offset>0)++ranged;
                    QByteArray response=offset>0?"HTTP/1.0 206 Partial Content\r\n":"HTTP/1.0 200 OK\r\n";
                    response+="Content-Type: audio/wav\r\nAccept-Ranges: bytes\r\nContent-Length: "+QByteArray::number(fileSize-offset)+"\r\n";
                    if(offset>0)response+="Content-Range: bytes "+QByteArray::number(offset)+'-'+QByteArray::number(fileSize-1)+'/'+QByteArray::number(fileSize)+"\r\n";
                    socket->write(response+"Connection: close\r\n\r\n");socket->setProperty("position",offset);socket->setProperty("started",true);pump();
                });
                connect(socket,&QTcpSocket::disconnected,socket,&QObject::deleteLater);
            }
        });
        QTemporaryDir dir;infrastructure::database::Database db;const auto path=dir.filePath("library.sqlite");QVERIFY(db.open(path));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController sources(&repo);qmlbridge::PortableSession session(db,path,sources);
        session.setVolume(0);QSettings().setValue("HTTP/buffer_size",512);
        QVERIFY(session.openTrack({{"trackId","bounded-http"},{"source","bili"},{"title","streaming fixture"},
            {"remoteUrl",QString("http://127.0.0.1:%1/long.wav").arg(server.serverPort())}}));
        QTRY_VERIFY_WITH_TIMEOUT(session.position()>300 || !session.errorMessage().isEmpty(),10000);
        QVERIFY2(session.errorMessage().isEmpty(),qPrintable(session.errorMessage()));session.pause();QTest::qWait(25000);
        qInfo()<<"HTTP bytes sent before seek"<<sent;
        QVERIFY2(sent<16*1024*1024,"Paused playback must not download the entire 64 MiB file into RAM");
        bool upstreamConnected=false;
        for(auto* socket:server.findChildren<QTcpSocket*>())upstreamConnected|=socket->state()==QAbstractSocket::ConnectedState;
        QVERIFY2(upstreamConnected,"Application backpressure must not be mistaken for a stalled network during pause");
        session.seek(200000);session.play();QTRY_VERIFY_WITH_TIMEOUT(ranged>0,10000);
        QTRY_VERIFY_WITH_TIMEOUT(session.position()>=201000,10000);
        session.seek(0);QTRY_VERIFY_WITH_TIMEOUT(session.position()<2000,10000);
        QElapsedTimer clock;clock.start();session.stop();QVERIFY(clock.elapsed()<1500);
    }
    void completeAudioSmallerThanPrebufferStillStarts() {
        // A complete 2-second WAV is much smaller than the 512 KiB prebuffer.
        // It must become ready at EOF, without changing global buffer settings.
        QByteArray wave;const auto u16=[&](quint16 v){v=qToLittleEndian(v);wave.append(reinterpret_cast<const char*>(&v),2);};
        const auto u32=[&](quint32 v){v=qToLittleEndian(v);wave.append(reinterpret_cast<const char*>(&v),4);};
        wave.append("RIFF");u32(64000+36);wave.append("WAVEfmt ");u32(16);u16(1);u16(1);u32(16000);u32(32000);u16(2);u16(16);wave.append("data");u32(64000);
        for(int i=0;i<32000;++i)u16(quint16(qint16(4000*std::sin(i*2*3.141592653589793*440/16000))));
        QTcpServer server;QVERIFY(server.listen(QHostAddress::LocalHost));
        connect(&server,&QTcpServer::newConnection,this,[&]{
            while(server.hasPendingConnections()) {
                auto* socket=server.nextPendingConnection();
                connect(socket,&QTcpSocket::readyRead,socket,[socket,wave]{
                    auto request=socket->property("request").toByteArray()+socket->readAll();socket->setProperty("request",request);
                    if(!request.contains("\r\n\r\n") || socket->property("sent").toBool())return;
                    socket->setProperty("sent",true);socket->write("HTTP/1.0 200 OK\r\nContent-Type: audio/wav\r\nContent-Length: "+QByteArray::number(wave.size())+"\r\nConnection: close\r\n\r\n");
                    socket->write(wave);socket->disconnectFromHost();
                });
                connect(socket,&QTcpSocket::disconnected,socket,&QObject::deleteLater);
            }
        });
        QTemporaryDir dir;infrastructure::database::Database db;const auto path=dir.filePath("library.sqlite");QVERIFY(db.open(path));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController sources(&repo);qmlbridge::PortableSession session(db,path,sources);
        session.setVolume(0);QSettings().setValue("HTTP/buffer_size",512);
        QVERIFY(session.openTrack({{"trackId","short-clip"},{"source","bili"},{"title","short clip"},
            {"remoteUrl",QString("http://127.0.0.1:%1/short.wav").arg(server.serverPort())}}));
        QTRY_VERIFY_WITH_TIMEOUT(session.position()>=250 || !session.errorMessage().isEmpty(),10000);
        QVERIFY2(session.errorMessage().isEmpty(),qPrintable(session.errorMessage()));QVERIFY(session.position()>=250);session.stop();
    }
    void livePublicSearchAndPlayback() {
        if(!qEnvironmentVariableIsSet("LISTENFREE_BILI_LIVE"))QSKIP("Opt-in real Bilibili service test");
        QTemporaryDir dir;infrastructure::database::Database db;const auto path=dir.filePath("library.sqlite");
        QVERIFY(db.open(path));QVERIFY(db.migrate());db.setSetting("player.volume","0");
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController sources(&repo);
        qmlbridge::PortableSession session(db,path,sources);session.setVolume(0);
        session.setBilibiliSourceEnabled(true);session.setPlatform("bili");session.search(QStringLiteral("洛天依"));
        QCOMPARE(session.platform(),"bili");QCOMPARE(session.searchCategory(),"songs");
        QTRY_VERIFY_WITH_TIMEOUT(!session.busy(),35000);
        QVERIFY2(session.searchError().isEmpty(),qPrintable(session.searchError()));
        const auto songs=session.searchResults();
        qInfo()<<"Live search"<<session.lastQuery()<<session.searchTotal()<<session.searchPageCount()<<songs.size();
        QVERIFY(!songs.isEmpty());
        qInfo("Real Bilibili: %lld single-P songs, %d server pages",qint64(songs.size()),session.searchPageCount());
        QVERIFY(session.openTrack(songs.first().toMap()));
        QTRY_VERIFY_WITH_TIMEOUT(session.state()=="Playing" || !session.errorMessage().isEmpty(),35000);
        QVERIFY2(session.errorMessage().isEmpty(),qPrintable(session.errorMessage()));
        QTRY_VERIFY_WITH_TIMEOUT(session.position()>=1000,12000);QVERIFY(session.duration()>10000);
        session.seek(10000);QTRY_VERIFY_WITH_TIMEOUT(session.position()>=11000,12000);
        qInfo("Real Bilibili: muted Qmmp playback advances; duration=%lld ms, seek=%lld ms",session.duration(),session.position());session.stop();
        session.setSearchCategory("playlists");QTRY_VERIFY_WITH_TIMEOUT(!session.busy(),35000);
        QVERIFY2(session.searchError().isEmpty(),qPrintable(session.searchError()));
        if(session.searchResults().isEmpty()) {session.search(QStringLiteral("音乐合集"));QTRY_VERIFY_WITH_TIMEOUT(!session.busy(),35000);}
        QVERIFY2(!session.searchResults().isEmpty(),qPrintable(session.searchError()));
        qmlbridge::CollectionService collection(db);collection.setBilibiliClient(&sources.bilibili());collection.open(session.searchResults().first().toMap());
        QTRY_VERIFY_WITH_TIMEOUT(!collection.detailBusy(),35000);
        QVERIFY2(collection.detail().value("error").toString().isEmpty(),qPrintable(collection.detail().value("error").toString()));
        const auto parts=collection.detail().value("tracks").toList();QVERIFY(parts.size()>1);
        qInfo("Real Bilibili: multi-P playlist has %lld parts",qint64(parts.size()));
        QVERIFY(session.openTrack(parts[1].toMap()));
        QTRY_VERIFY_WITH_TIMEOUT(session.state()=="Playing" || !session.errorMessage().isEmpty(),35000);
        QVERIFY2(session.errorMessage().isEmpty(),qPrintable(session.errorMessage()));
        QTRY_VERIFY_WITH_TIMEOUT(session.position()>=1000,12000);QCOMPARE(session.currentTrack().value("cid"),parts[1].toMap().value("cid"));
        session.stop();qInfo("Real Bilibili: second part plays with its own CID");
    }
};
QTEST_MAIN(BilibiliTests)
#include "bilibili_source_tests.moc"
