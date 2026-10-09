#include "qmlbridge/portable_session.h"
#include "infrastructure/database/repositories.h"
#include <qmmp/soundcore.h>
#include <qmmp/qmmp.h>
#include <plugins/Effect/crossfade/crossfadeplugin.h>
#include <QTest>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QSettings>
#include <QTcpServer>
#include <QTcpSocket>
#include <QtEndian>
#include <cmath>
#include <algorithm>
#include <vector>
using namespace listenfree;
class SmartMixDspTests : public QObject {
    Q_OBJECT
    QTemporaryDir temp;
    QString makeWave(QString name,int channel,int rate=44100,int seconds=12) {
        const int frames=rate*seconds;
        QByteArray bytes(44+frames*4,0);
        memcpy(bytes.data(),"RIFF",4);qToLittleEndian<quint32>(quint32(bytes.size()-8),bytes.data()+4);
        memcpy(bytes.data()+8,"WAVEfmt ",8);qToLittleEndian<quint32>(16,bytes.data()+16);
        qToLittleEndian<quint16>(1,bytes.data()+20);qToLittleEndian<quint16>(2,bytes.data()+22);
        qToLittleEndian<quint32>(rate,bytes.data()+24);qToLittleEndian<quint32>(rate*4,bytes.data()+28);
        qToLittleEndian<quint16>(4,bytes.data()+32);qToLittleEndian<quint16>(16,bytes.data()+34);
        memcpy(bytes.data()+36,"data",4);qToLittleEndian<quint32>(frames*4,bytes.data()+40);
        for(int i=0;i<frames;++i)qToLittleEndian<qint16>(qint16(12000*std::sin(i*2*3.141592653589793*440/rate)),bytes.data()+44+i*4+channel*2);
        QFile file(temp.filePath(name));if(!file.open(QIODevice::WriteOnly))return {};file.write(bytes);return file.fileName();
    }
    QVariantMap track(const QString& path,QString album={}) {
        return {{"localPath",path},{"trackId",path},{"title",QFileInfo(path).baseName()},{"artist","fixture"},{"album",album},{"durationMs",12000}};
    }
private slots:
    void initTestCase() {
        QVERIFY(temp.isValid());QCoreApplication::setOrganizationName("ListenFreeSmartMixTests");
        QCoreApplication::instance()->setProperty("listenfreeDataDir",temp.path());
        QSettings::setDefaultFormat(QSettings::IniFormat);QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,temp.path());
        Qmmp::setConfigDir(temp.filePath("qmmp"));
    }
    void announcement_data() {
        QTest::addColumn<bool>("manual");QTest::addColumn<bool>("backward");
        QTest::newRow("manual")<<true<<false;QTest::newRow("previous")<<true<<true;QTest::newRow("natural")<<false<<false;
    }
    void announcement() {
        QFETCH(bool,manual);QFETCH(bool,backward);
        const auto a=makeWave("announce-a.wav",0,44100,20),b=makeWave("announce-b.wav",1,44100,20);
        const auto key=QString("announce-")+QTest::currentDataTag();
        qputenv("LISTENFREE_TEST_PCM",temp.filePath(key+".pcm").toUtf8());
        infrastructure::database::Database db;const auto path=temp.filePath(key+".sqlite");QVERIFY(db.open(path));QVERIFY(db.migrate());db.setSetting("playback.transition.smart","true");
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);qmlbridge::PortableSession player(db,path,source);
        player.playAll({track(a,"A"),track(b,"B")});QTRY_VERIFY(player.position()>300);
        QElapsedTimer elapsed;elapsed.start();
        if(manual){
            if(backward)player.previous();else player.next();
            QVERIFY2(player.mixing(),"Both manual directions must immediately show Mixing on A");
        } else {
            player.seek(10500);QTRY_VERIFY_WITH_TIMEOUT(player.mixing(),6000);
            QCOMPARE(player.currentQueueIndex(),0);
            QTest::qWait(250);QCOMPARE(player.currentQueueIndex(),0);QVERIFY(player.mixing());
        }
        // Allow the existing output recycler to drain. The 0.8s belongs to the
        // actual mixed output, not the time since clicking or decoder handoff.
        int both=0;QElapsedTimer audioWait;audioWait.start();
        while(player.currentQueueIndex()==0 && audioWait.elapsed()<6000 && both<100) {
            QTest::qWait(20);QFile recording(temp.filePath(key+".pcm"));
            if(!recording.open(QIODevice::ReadOnly))continue;
            const auto pcm=recording.readAll();both=0;
            for(qsizetype i=0;i+3<pcm.size();i+=4)
                if(std::abs(qFromLittleEndian<qint16>(pcm.constData()+i))>100 && std::abs(qFromLittleEndian<qint16>(pcm.constData()+i+2))>10)++both;
        }
        QVERIFY2(both>=100,"A+B must already be audible while the primary track is still A");
        QCOMPARE(player.currentQueueIndex(),0);QVERIFY(player.mixing());
        QCOMPARE(player.duration(),20000);
        QTRY_COMPARE_WITH_TIMEOUT(player.currentQueueIndex(),1,6000);
        if(manual)QVERIFY(elapsed.elapsed()>=750);
        QVERIFY2(player.position()>=780 && player.position()<1100,"B must commit at its already played 0.8s position");
        QVERIFY(player.mixing());
        QTRY_VERIFY(SoundCore::instance()->crossfadeDuration()>0);
        const auto actual=SoundCore::instance()->crossfadeDuration();
        qInfo("Announcement %s: handoff %lldms, envelope %lldms",manual?"manual":"natural",elapsed.elapsed(),actual);
        QVERIFY(actual>(manual?3800:5800) && actual<(manual?4200:6200));
        player.stop();QVERIFY(!player.mixing());
    }
    void cancelAnnouncement() {
        const auto a=makeWave("announce-cancel-a.wav",0),b=makeWave("announce-cancel-b.wav",1);
        qputenv("LISTENFREE_TEST_PCM",temp.filePath("announce-cancel.pcm").toUtf8());
        infrastructure::database::Database db;const auto path=temp.filePath("announce-cancel.sqlite");QVERIFY(db.open(path));QVERIFY(db.migrate());db.setSetting("playback.transition.smart","true");
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);qmlbridge::PortableSession player(db,path,source);
        player.playAll({track(a),track(b)});QTRY_VERIFY(player.position()>300);
        player.next();QVERIFY(player.mixing());player.setSmartTransition(false);
        QVERIFY(!player.mixing());QTest::qWait(1100);QCOMPARE(player.currentQueueIndex(),0);
        player.setSmartTransition(true);player.next();QVERIFY(player.mixing());player.pause();
        QTRY_COMPARE(player.state(),QString("Paused"));QVERIFY(!player.mixing());QTest::qWait(1100);QCOMPARE(player.currentQueueIndex(),0);
        player.stop();
    }
    void duringOverlap_data() {
        QTest::addColumn<QString>("action");
        for(const auto* action:{"pause","seek","next","previous","stop","disable"})QTest::newRow(action)<<QString(action);
    }
    void duringOverlap() {
        QFETCH(QString,action);
        const auto a=makeWave("during-a.wav",0,44100,20),b=makeWave("during-b.wav",1,44100,20),c=makeWave("during-c.wav",0,44100,20);
        qputenv("LISTENFREE_TEST_PCM",temp.filePath("during-"+action+".pcm").toUtf8());
        infrastructure::database::Database db;const auto path=temp.filePath("during-"+action+".sqlite");QVERIFY(db.open(path));QVERIFY(db.migrate());db.setSetting("playback.transition.smart","true");
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);qmlbridge::PortableSession player(db,path,source);
        player.playAll({track(a),track(b),track(c)});QTRY_VERIFY(player.position()>300);
        QSignalSpy progress(SoundCore::instance(),&SoundCore::outputTrackProgress);
        player.next();
        auto heard=[&](){for(const auto &event:progress)if(event[1].toString()==b && event[2].toLongLong()>=200)return true;return false;};
        QTRY_VERIFY_WITH_TIMEOUT(heard(),4000);QCOMPARE(player.currentQueueIndex(),0);QVERIFY(player.mixing());
        if(action=="pause") {
            player.pause();QTRY_COMPARE(player.state(),QString("Paused"));QVERIFY(!player.mixing());
            QTest::qWait(1100);QCOMPARE(player.currentQueueIndex(),0);
            player.play();QTRY_COMPARE(player.currentQueueIndex(),1);QVERIFY(player.position()>=780);
        } else if(action=="seek") {
            player.seek(5000);QTRY_COMPARE(player.currentQueueIndex(),0);QTRY_VERIFY(player.position()>=5000);
            QTest::qWait(1100);QCOMPARE(player.currentQueueIndex(),0);
        } else if(action=="next") {
            player.next();QTRY_COMPARE(player.currentQueueIndex(),2);QTest::qWait(1100);QCOMPARE(player.currentQueueIndex(),2);
        } else if(action=="previous") {
            player.previous();QTRY_COMPARE(player.currentQueueIndex(),0);QTest::qWait(1100);QCOMPARE(player.currentQueueIndex(),0);
        } else if(action=="stop") {
            player.stop();QTest::qWait(1100);QVERIFY(player.state()!="Playing");QVERIFY(!player.mixing());
        } else {
            player.setSmartTransition(false);QVERIFY(!player.mixing());QCOMPARE(player.currentQueueIndex(),1);
            QTest::qWait(1100);QCOMPARE(player.currentQueueIndex(),1);
        }
        player.stop();
    }
    void envelopeAndBudget_data() {
        QTest::addColumn<int>("rate");QTest::addColumn<int>("channels");
        for(int rate:{44100,48000,96000,192000})for(int channels:{2,8})QTest::newRow(qPrintable(QString("%1-%2").arg(rate).arg(channels)))<<rate<<channels;
    }
    void envelopeAndBudget() {
        QFETCH(int,rate);QFETCH(int,channels);
        SoundCore core;QSettings().setValue("Crossfade/overlap",6000);
        CrossfadePlugin plugin;plugin.configure(rate,ChannelMap(channels));
        const size_t n=size_t(rate)*channels*6;
        QVERIFY(plugin.m_buffer_size>=n);QVERIFY(plugin.m_buffer_size<=n+1024*channels);
        std::fill_n(plugin.m_buffer,n,.99f);plugin.m_buffer_at=n;plugin.prepareEnvelope();
        QCOMPARE(plugin.m_buffer_at,n);
        std::vector<float> output(n,.99f);plugin.mix(output.data(),plugin.m_buffer,n);
        for(float sample:output){QVERIFY(std::isfinite(sample));QVERIFY(std::abs(sample-.99f)<1e-6f);}
        // Neither stereo channel independence nor block partitioning may alter gains.
        std::fill_n(plugin.m_buffer,n,0.f);for(size_t i=0;i<n;i+=channels)plugin.m_buffer[i]=.8f;
        std::fill(output.begin(),output.end(),0.f);for(size_t i=0;i<n;i+=channels)output[i+1]=.6f;
        auto chunked=output;plugin.m_buffer_at=n;plugin.m_mix_total=n;plugin.mix(output.data(),plugin.m_buffer,n);
        plugin.m_buffer_at=n;
        for(size_t i=0;i<n;i+=512*channels){auto count=std::min(n-i,size_t(512*channels));plugin.mix(chunked.data()+i,plugin.m_buffer+i,count);plugin.m_buffer_at-=count;}
        QCOMPARE(output,chunked);QVERIFY(output[n/2/channels*channels]>.3f);QVERIFY(output[n/2/channels*channels+1]>.2f);
        // Near-silence can shorten a tail; quiet but audible music is retained.
        std::fill_n(plugin.m_buffer,n,.002f);plugin.m_buffer_at=n;plugin.prepareEnvelope();QCOMPARE(plugin.m_buffer_at,n);
        std::fill_n(plugin.m_buffer+n-size_t(rate)*channels/2,size_t(rate)*channels/2,0.f);
        plugin.m_buffer_at=n;plugin.prepareEnvelope();QVERIFY(plugin.m_buffer_at<n-size_t(rate)*channels/3);
        QElapsedTimer clock;clock.start();
        for(int pass=0;pass<100;++pass){plugin.m_buffer_at=n;plugin.prepareEnvelope();plugin.mix(output.data(),plugin.m_buffer,plugin.m_buffer_at);}
        qInfo("DSP %d Hz/%d ch: %.3f ms per 6s tail; capacity %zu bytes",rate,channels,double(clock.nsecsElapsed())/1e6/100,plugin.m_buffer_size*sizeof(float));
        QVERIFY(clock.elapsed()<4000);
    }
    void naturalPcm_data() {
        QTest::addColumn<bool>("enabled");QTest::addColumn<bool>("album");QTest::addColumn<int>("rate");
        QTest::newRow("smart")<<true<<false<<44100;
        QTest::newRow("manual")<<true<<false<<44100;
        QTest::newRow("off")<<false<<false<<44100;
        QTest::newRow("album")<<true<<true<<44100;
        QTest::newRow("format-change")<<true<<false<<48000;
    }
    void naturalPcm() {
        QFETCH(bool,enabled);QFETCH(bool,album);QFETCH(int,rate);
        const auto capture=temp.filePath(QString(QTest::currentDataTag())+".pcm");qputenv("LISTENFREE_TEST_PCM",capture.toUtf8());
        const auto a=makeWave("a.wav",0),b=makeWave("b.wav",1,rate,20);
        infrastructure::database::Database db;auto dbPath=temp.filePath(QString(QTest::currentDataTag())+".sqlite");QVERIFY(db.open(dbPath));QVERIFY(db.migrate());
        db.setSetting("playback.transition.smart",enabled?"true":"false");
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);qmlbridge::PortableSession player(db,dbPath,source);
        player.setVolume(1);QSignalSpy committed(&player,&qmlbridge::PortableSession::smartMixCommitted);
        player.playAll({track(a,album?"continuous":"A"),track(b,album?"continuous":"B")});
        QTRY_VERIFY_WITH_TIMEOUT(player.position()>300,5000);
        if(QString(QTest::currentDataTag())=="manual")player.next();else player.seek(6500);
        QTRY_COMPARE_WITH_TIMEOUT(player.currentQueueIndex(),1,9000);
        const bool expectMix=enabled && !album && rate==44100;
        if(expectMix)QTRY_VERIFY_WITH_TIMEOUT(player.mixing(),1500);else QVERIFY(!player.mixing());
        QTRY_VERIFY_WITH_TIMEOUT(player.position()>6500,9000);
        QVERIFY(!player.mixing());player.stop();QVERIFY(!player.mixing());
        if(enabled){QCOMPARE(committed.size(),1);QCOMPARE(committed.first().first().toBool(),expectMix);}
        QFile pcm(capture);QVERIFY(pcm.open(QIODevice::ReadOnly));auto data=pcm.readAll();
        int overlapFrames=0;qsizetype first=-1,last=-1;
        for(qsizetype i=0;i+3<data.size();i+=4)if(std::abs(qFromLittleEndian<qint16>(data.constData()+i))>500 && std::abs(qFromLittleEndian<qint16>(data.constData()+i+2))>500){++overlapFrames;if(first<0)first=i/4;last=i/4;}
        qInfo("Captured overlap: %d frames; span %.3f s",overlapFrames,first<0?0.0:double(last-first+1)/44100);
        if(expectMix)QVERIFY2(last-first>44100*(QString(QTest::currentDataTag())=="manual"?.8:2.0),"Audible overlap is too short");else QCOMPARE(overlapFrames,0);
    }
    void tailProbeSafety_data() {
        QTest::addColumn<QString>("kind");
        for(const auto* kind:{"trailing","quiet-outro","middle-pause","all-silent","antiphase","window-seek"})QTest::newRow(kind)<<QString(kind);
    }
    void tailProbeSafety() {
        QFETCH(QString,kind);
        const int seconds=kind=="window-seek"?45:12;
        const auto a=makeWave("probe-"+kind+".wav",0,44100,seconds);
        QFile file(a);QVERIFY(file.open(QIODevice::ReadWrite));auto bytes=file.readAll();
        for(int i=0;i<seconds*44100;++i){
            if(kind=="all-silent" || (kind=="window-seek" && i>=37*44100) || (kind=="trailing" && i>=6*44100) || (kind=="middle-pause" && i>=5*44100 && i<10*44100))qToLittleEndian<qint16>(0,bytes.data()+44+i*4);
            if(kind=="quiet-outro" && i>=6*44100)qToLittleEndian<qint16>(qint16(60*std::sin(i*2*3.141592653589793*440/44100)),bytes.data()+44+i*4);
            if(kind=="antiphase")qToLittleEndian<qint16>(-qFromLittleEndian<qint16>(bytes.constData()+44+i*4),bytes.data()+44+i*4+2);
        }
        file.seek(0);file.write(bytes);file.close();
        media::AudioTailProbe probe;QSignalSpy result(&probe,&media::AudioTailProbe::finished);
        probe.request(a,seconds*1000);QTRY_COMPARE_WITH_TIMEOUT(result.size(),1,4500);
        const auto end=result.first().first().toLongLong();
        if(kind=="trailing")QVERIFY(end>=6000 && end<=6250);else if(kind=="window-seek")QVERIFY(end>=37000 && end<=37250);else QCOMPARE(end,-1);
        result.clear();probe.request(a,seconds*1000);probe.cancel();QTest::qWait(200);QVERIFY(result.isEmpty());
    }
    void tailProbeReplacement() {
        const auto a=makeWave("probe-stale.wav",0),b=makeWave("probe-new.wav",1);
        QFile file(a);QVERIFY(file.open(QIODevice::ReadWrite));file.seek(44+6*44100*4);file.write(QByteArray(6*44100*4,0));file.close();
        media::AudioTailProbe probe;QSignalSpy result(&probe,&media::AudioTailProbe::finished);
        probe.request(a,12000);probe.request(b,12000);
        QTRY_COMPARE_WITH_TIMEOUT(result.size(),1,4500);QCOMPARE(result.first().first().toLongLong(),-1);
        QTest::qWait(200);QCOMPARE(result.size(),1);
    }
    void naturalSilentTail() {
        const auto a=makeWave("silent-tail-a.wav",0),b=makeWave("silent-tail-b.wav",1,44100,20);
        QFile wav(a);QVERIFY(wav.open(QIODevice::ReadWrite));QVERIFY(wav.seek(44+6*44100*4));
        wav.write(QByteArray(6*44100*4,0));wav.close();
        const auto capture=temp.filePath("silent-tail.pcm");qputenv("LISTENFREE_TEST_PCM",capture.toUtf8());
        infrastructure::database::Database db;const auto path=temp.filePath("silent-tail.sqlite");QVERIFY(db.open(path));QVERIFY(db.migrate());db.setSetting("playback.transition.smart","true");
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);qmlbridge::PortableSession player(db,path,source);
        player.setVolume(1);player.playAll({track(a,"A"),track(b,"B")});
        QTRY_COMPARE_WITH_TIMEOUT(player.currentQueueIndex(),1,14000);
        QTRY_VERIFY(player.mixing());
        const auto actualMix=SoundCore::instance()->crossfadeDuration();
        qInfo("Actual mix envelope after silence removal: %lld ms",actualMix);
        QVERIFY(actualMix>=3500 && actualMix<=6200);
        QTRY_VERIFY_WITH_TIMEOUT(player.position()>6500,9000);player.stop();
        QFile pcm(capture);QVERIFY(pcm.open(QIODevice::ReadOnly));const auto data=pcm.readAll();
        int overlap=0,quiet=0,longestQuiet=0;
        for(qsizetype i=0;i+3<data.size();i+=4){
            const auto l=std::abs(qFromLittleEndian<qint16>(data.constData()+i));
            const auto r=std::abs(qFromLittleEndian<qint16>(data.constData()+i+2));
            if(l>500&&r>500)++overlap;
            if(l<100&&r<100)longestQuiet=std::max(longestQuiet,++quiet);else quiet=0;
        }
        qInfo("Silent tail: overlap %.3fs, longest silence %.3fs",double(overlap)/44100,double(longestQuiet)/44100);
        QVERIFY2(longestQuiet<44100/4,"Trailing silence must not create a gap before the incoming music");
        QVERIFY2(overlap>44100/2,"Natural mix must overlap audible music, not only a silent tail");
    }
    void httpPreload_data() {
        QTest::addColumn<bool>("fails");QTest::addColumn<bool>("currentTail");
        QTest::newRow("buffered-http")<<false<<false;QTest::newRow("failed-http")<<true<<false;
        QTest::newRow("http-silent-tail")<<false<<true;
    }
    void httpPreload() {
        QFETCH(bool,fails);QFETCH(bool,currentTail);
        const auto a=makeWave("http-a.wav",0),b=makeWave("http-b.wav",1,44100,20);
        if(currentTail){QFile file(a);QVERIFY(file.open(QIODevice::ReadWrite));file.seek(44+6*44100*4);file.write(QByteArray(6*44100*4,0));}
        QFile tailFile(a);QVERIFY(tailFile.open(QIODevice::ReadOnly));const auto tailWav=tailFile.readAll();
        QFile body(b);QVERIFY(body.open(QIODevice::ReadOnly));const auto wav=body.readAll();
        QTcpServer server;QVERIFY(server.listen(QHostAddress::LocalHost));int requests=0;
        connect(&server,&QTcpServer::newConnection,this,[&]{
            while(auto* socket=server.nextPendingConnection()) {
                connect(socket,&QTcpSocket::disconnected,socket,&QObject::deleteLater);
                connect(socket,&QTcpSocket::readyRead,socket,[&,socket]{
                    auto request=socket->property("request").toByteArray()+socket->readAll();socket->setProperty("request",request);
                    if(!request.contains("\r\n\r\n") || socket->property("sent").toBool())return;
                    socket->setProperty("sent",true);++requests;
                    if(fails){socket->write("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");socket->disconnectFromHost();return;}
                    qsizetype offset=0;auto start=request.toLower().indexOf("range: bytes=");
                    if(start>=0)offset=request.mid(start+13).split('-').first().toLongLong();
                    const auto& response=request.contains("GET /tail.wav ")?tailWav:wav;
                    offset=std::clamp(offset,qsizetype(0),response.size());auto bytes=response.mid(offset);
                    QByteArray headers=offset>0?"HTTP/1.1 206 Partial Content\r\n":"HTTP/1.1 200 OK\r\n";
                    headers+="Content-Type: audio/wav\r\nAccept-Ranges: bytes\r\nContent-Length: "+QByteArray::number(bytes.size())+"\r\n";
                    if(offset>0)headers+="Content-Range: bytes "+QByteArray::number(offset)+"-"+QByteArray::number(response.size()-1)+"/"+QByteArray::number(response.size())+"\r\n";
                    socket->write(headers+"Connection: close\r\n\r\n"+bytes);socket->disconnectFromHost();
                });
            }
        });
        qputenv("LISTENFREE_TEST_PCM",temp.filePath(QString(QTest::currentDataTag())+".pcm").toUtf8());
        infrastructure::database::Database db;auto path=temp.filePath(QString(QTest::currentDataTag())+".sqlite");QVERIFY(db.open(path));QVERIFY(db.migrate());db.setSetting("playback.transition.smart","true");db.setSetting("playback.skipOnError","false");
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);qmlbridge::PortableSession player(db,path,source);
        auto remote=track(b);remote.remove("localPath");remote["remoteUrl"]=QString("http://127.0.0.1:%1/song.wav").arg(server.serverPort());
        QSignalSpy committed(&player,&qmlbridge::PortableSession::smartMixCommitted);
        auto outgoing=track(a);
        if(currentTail){outgoing.remove("localPath");outgoing["remoteUrl"]=QString("http://127.0.0.1:%1/tail.wav").arg(server.serverPort());}
        player.setVolume(1); // PCM thresholds use the same fixed gain as local fixtures.
        player.playAll({outgoing,remote});QTRY_VERIFY(player.position()>300);if(!currentTail)player.seek(6500);
        QTRY_VERIFY_WITH_TIMEOUT(requests>0,3000);
        if(fails){QTest::qWait(800);QCOMPARE(player.currentQueueIndex(),0);QCOMPARE(player.state(),QString("Playing"));QVERIFY(player.errorMessage().isEmpty());}
        else {QTRY_COMPARE_WITH_TIMEOUT(player.currentQueueIndex(),1,9000);QTRY_VERIFY(player.position()>1500);QCOMPARE(committed.size(),1);QVERIFY(committed.first().first().toBool());}
        if(currentTail){
            const auto envelope=SoundCore::instance()->crossfadeDuration();
            qInfo("HTTP envelope %lld ms, volume %.3f",envelope,player.volume());
            QVERIFY(envelope>=3500 && envelope<=6200);
            QTRY_VERIFY_WITH_TIMEOUT(player.position()>6500,9000);player.stop();
            QFile captured(temp.filePath(QString(QTest::currentDataTag())+".pcm"));QVERIFY(captured.open(QIODevice::ReadOnly));const auto data=captured.readAll();
            int quiet=0,longest=0,overlap=0;
            for(qsizetype i=0;i+3<data.size();i+=4){
                const int l=std::abs(qFromLittleEndian<qint16>(data.constData()+i)),r=std::abs(qFromLittleEndian<qint16>(data.constData()+i+2));
                if(l<100&&r<100)longest=std::max(longest,++quiet);else quiet=0;
                if(l>500&&r>500)++overlap;
            }
            qInfo("HTTP tail: overlap %.3fs, longest silence %.3fs",double(overlap)/44100,double(longest)/44100);
            QVERIFY(longest<44100/4);QVERIFY(overlap>44100/2);
        }
        player.stop();
    }
    void backwardShuffleHistory() {
        const auto a=makeWave("history-a.wav",0,44100,20),b=makeWave("history-b.wav",1,44100,20),c=makeWave("history-c.wav",0,44100,20);
        qputenv("LISTENFREE_TEST_PCM",temp.filePath("history.pcm").toUtf8());
        infrastructure::database::Database db;const auto path=temp.filePath("history.sqlite");QVERIFY(db.open(path));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);qmlbridge::PortableSession player(db,path,source);
        player.playAll({track(a),track(b),track(c)});player.setPlaybackMode("shuffle");QTRY_VERIFY(player.position()>300);
        player.next();QTRY_VERIFY(player.position()>300);const auto previous=player.currentTrack().value("localPath");
        player.next();QTRY_VERIFY(player.position()>300);const auto current=player.currentTrack().value("localPath");QVERIFY(previous!=current);
        player.setSmartTransition(true);QSignalSpy committed(&player,&qmlbridge::PortableSession::smartMixCommitted);
        player.previous();QVERIFY(player.mixing());QCOMPARE(player.currentTrack().value("localPath"),current);
        QTRY_COMPARE_WITH_TIMEOUT(player.currentTrack().value("localPath"),previous,6000);
        QVERIFY(!committed.isEmpty()&&committed.first().first().toBool());
        // Once the backward overlap is complete, Next must replay the history
        // entry we just came from, not advance past it during commit.
        QTRY_VERIFY_WITH_TIMEOUT(player.position()>4400,6000);
        player.next();QVERIFY(player.mixing());QTRY_COMPARE_WITH_TIMEOUT(player.currentTrack().value("localPath"),current,6000);
        player.stop();
    }
    void delayedResolvedOnlinePreload_data() {
        QTest::addColumn<bool>("earlyResolution");
        QTest::addColumn<bool>("natural");
        QTest::newRow("manual-next") << false << false;
        QTest::newRow("early-url-only") << true << false;
        QTest::newRow("natural-next") << true << true;
    }
    void delayedResolvedOnlinePreload() {
        QFETCH(bool,earlyResolution);
        QFETCH(bool,natural);
        const auto capture=temp.filePath(QString("delayed-resolve-%1.pcm").arg(QTest::currentDataTag()));
        qputenv("LISTENFREE_TEST_PCM",capture.toUtf8());
        const auto a=makeWave("delayed-resolve-a.wav",0,44100,35);
        const auto b=makeWave("delayed-resolve-b.wav",1,44100,20);
        QFile mediaFile(b);QVERIFY(mediaFile.open(QIODevice::ReadOnly));
        const auto media=mediaFile.readAll();
        QTcpServer server;QVERIFY(server.listen(QHostAddress::LocalHost));
        int resolves=0,mediaRequests=0;
        connect(&server,&QTcpServer::newConnection,this,[&] {
            while (auto* socket=server.nextPendingConnection()) {
                connect(socket,&QTcpSocket::disconnected,socket,&QObject::deleteLater);
                connect(socket,&QTcpSocket::readyRead,socket,[&,socket] {
                    auto request=socket->property("request").toByteArray()+socket->readAll();
                    socket->setProperty("request",request);
                    if (!request.contains("\r\n\r\n") || socket->property("sent").toBool()) return;
                    socket->setProperty("sent",true);
                    if (request.startsWith("GET /resolve")) {
                        ++resolves;
                        QTimer::singleShot(700,socket,[socket] {
                            socket->write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok");
                            socket->disconnectFromHost();
                        });
                        return;
                    }
                    ++mediaRequests;
                    const auto marker=request.toLower().indexOf("range: bytes=");
                    const auto offset=marker>=0 ? request.mid(marker+13).split('-').first().toLongLong() : 0;
                    const auto start=std::clamp<qint64>(offset,0,media.size());
                    QByteArray header=start>0 ? "HTTP/1.1 206 Partial Content\r\n" : "HTTP/1.1 200 OK\r\n";
                    header+="Content-Type: audio/wav\r\nAccept-Ranges: bytes\r\nContent-Length: "+QByteArray::number(media.size()-start)+"\r\n";
                    if (start>0) header+="Content-Range: bytes "+QByteArray::number(start)+"-"+
                        QByteArray::number(media.size()-1)+"/"+QByteArray::number(media.size())+"\r\n";
                    socket->write(header+"Connection: close\r\n\r\n"+media.mid(start));
                    socket->disconnectFromHost();
                });
            }
        });
        infrastructure::database::Database db;
        const auto path=temp.filePath(QString("delayed-resolve-%1.sqlite").arg(QTest::currentDataTag()));
        QVERIFY(db.open(path));QVERIFY(db.migrate());
        db.setSetting("playback.transition.smart","true");db.setSetting("playback.quality","128k");
        db.setSetting("playback.skipOnError","false");
        infrastructure::database::SettingsRepository repo(db);
        qmlbridge::SourceController source(&repo,QCoreApplication::applicationDirPath()+"/listenfree-sourcehost.exe",true);
        QTRY_VERIFY_WITH_TIMEOUT(source.hostReady(),10000);
        QFile script(temp.filePath("delayed-resolve-source.js"));QVERIFY(script.open(QIODevice::WriteOnly));
        script.write(QString("lx.on(lx.EVENT_NAMES.request, () => new Promise((resolve,reject) => lx.request('http://127.0.0.1:%1/resolve', {}, err => err ? reject(err) : resolve('http://127.0.0.1:%1/media.wav'))));lx.send(lx.EVENT_NAMES.inited,{status:true,sources:{kw:{type:'music',actions:['musicUrl'],qualitys:['128k']}}});")
            .arg(server.serverPort()).toUtf8());
        script.close();QVERIFY(source.importLocalFile(script.fileName()));
        QTRY_VERIFY_WITH_TIMEOUT(source.sources().last().toMap().value("hostReady").toBool(),10000);
        qmlbridge::PortableSession player(db,path,source);
        auto online=track(b);online.remove("localPath");
        online["trackId"]="resolved-online";online["source"]="kw";online["rid"]="resolved-online";
        QSignalSpy committed(&player,&qmlbridge::PortableSession::smartMixCommitted);
        player.playAll({track(a),online});
        QTRY_VERIFY_WITH_TIMEOUT(player.state()=="Playing" && player.position()>300,5000);
        if (earlyResolution) {
            player.seek(natural?20000:12000);
            QTRY_VERIFY_WITH_TIMEOUT(player.position()>=(natural?19500:11500),3000);
            QTRY_VERIFY_WITH_TIMEOUT(resolves==1,3000);
            QTest::qWait(900);
            QCOMPARE(mediaRequests,0); // A URL can be cached without allocating the B decoder/buffer.
        }
        if (!natural) {
            player.next();
            QVERIFY(player.mixing());
            QTest::qWait(500);
            QCOMPARE(player.currentQueueIndex(),0); // 350 ms was too short for the 700 ms resolver.
        }
        QTRY_COMPARE_WITH_TIMEOUT(player.currentQueueIndex(),1,natural?16000:8000);
        QCOMPARE(committed.size(),1);
        QVERIFY(committed.first().first().toBool());
        QVERIFY(player.duration()>0);
        QVERIFY(mediaRequests>0);
        QTRY_VERIFY_WITH_TIMEOUT(player.position()>4500,7000);
        player.stop();
        QFile captured(capture);QVERIFY(captured.open(QIODevice::ReadOnly));
        const auto pcm=captured.readAll();
        int overlap=0;
        for (qsizetype i=0;i+3<pcm.size();i+=4)
            if (std::abs(qFromLittleEndian<qint16>(pcm.constData()+i))>500 &&
                std::abs(qFromLittleEndian<qint16>(pcm.constData()+i+2))>500) ++overlap;
        QVERIFY2(overlap>44100/2,"Resolved online B must audibly overlap local A");
    }
    void manualCancellation() {
        const auto a=makeWave("manual-a.wav",0),b=makeWave("manual-b.wav",1),c=makeWave("manual-c.wav",0);
        qputenv("LISTENFREE_TEST_PCM",temp.filePath("manual.pcm").toUtf8());
        infrastructure::database::Database db;auto path=temp.filePath("manual.sqlite");QVERIFY(db.open(path));QVERIFY(db.migrate());db.setSetting("playback.transition.smart","true");
        infrastructure::database::SettingsRepository repo(db);qmlbridge::SourceController source(&repo);qmlbridge::PortableSession player(db,path,source);
        player.playAll({track(a),track(b),track(c)});QTRY_VERIFY(player.position()>300);
        QSignalSpy committed(&player,&qmlbridge::PortableSession::smartMixCommitted);
        player.next();QTRY_COMPARE_WITH_TIMEOUT(player.currentQueueIndex(),1,4000);
        QVERIFY(!committed.isEmpty());QVERIFY(committed.first().first().toBool());
        QTRY_VERIFY(player.mixing());
        player.pause();QTRY_COMPARE(player.state(),QString("Paused"));QVERIFY(!player.mixing());auto position=player.position();QTest::qWait(200);QVERIFY(std::abs(player.position()-position)<150);
        player.play();player.seek(5000);QVERIFY(!player.mixing());QTRY_VERIFY(player.position()>=5000);
        player.next();player.next();QTRY_COMPARE_WITH_TIMEOUT(player.currentQueueIndex(),0,5000);
        QTRY_VERIFY(player.position()>300);player.selectQueue(1);player.selectQueue(2);QTRY_COMPARE_WITH_TIMEOUT(player.currentQueueIndex(),2,5000);
        // Below the mix cooldown, queue edits must not resurrect a stale transition.
        player.seek(2000);QTest::qWait(250);player.setSmartTransition(false);player.removeFromQueue(0);
        QTest::qWait(250);QCOMPARE(player.currentTrack().value("localPath").toString(),c);
        player.stop();QTest::qWait(400);QVERIFY(player.state()!="Playing");
    }
};
QTEST_MAIN(SmartMixDspTests)
#include "smart_mix_tests.moc"
