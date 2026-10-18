#include "qmlbridge/portable_session.h"
#include "qmlbridge/controllers.h"
#include "qmlbridge/download_service.h"
#include "qmlbridge/settings_schema.h"
#include "online/track_identity.h"
#include "infrastructure/database/repositories.h"
#include "test_executable.h"
#include <QApplication>
#include <QDataStream>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSettings>
#include <QSignalSpy>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QTest>
#include <qmmp/qmmp.h>

using namespace listenfree;
class TrackManagementTests : public QObject {
    Q_OBJECT
    QTemporaryDir profile_;
    QString script(const QString& name, const QString& body) {
        const auto path=profile_.filePath(name+".js");
        QFile file(path);
        if(!file.open(QIODevice::WriteOnly)) return {};
        file.write(("/* @name "+name+" */\nlx.on(lx.EVENT_NAMES.request, ({info}) => {"+body+"});\n"
            "lx.send(lx.EVENT_NAMES.inited,{status:true,sources:{tx:{type:'music',actions:['musicUrl'],qualitys:['flac','320k','128k']}}});").toUtf8());
        return path;
    }
    QVariantMap song(const QString& source="tx") {
        return {{"source",source},{"rid","42"},{"trackId","legacy-id"},{"title","Same title"},
            {"artwork","qrc:/fixture.png"},{"durationMs",10000}};
    }
    QByteArray audioFixture() {
        QByteArray pcm(44100*2*2*10, '\0'), wav;
        QDataStream stream(&wav,QIODevice::WriteOnly); stream.setByteOrder(QDataStream::LittleEndian);
        stream.writeRawData("RIFF",4);stream<<quint32(36+pcm.size());stream.writeRawData("WAVEfmt ",8);
        stream<<quint32(16)<<quint16(1)<<quint16(2)<<quint32(44100)<<quint32(176400)<<quint16(4)<<quint16(16);
        stream.writeRawData("data",4);stream<<quint32(pcm.size());wav.append(pcm);
        return wav;
    }
private slots:
    void initTestCase() {
        QVERIFY(profile_.isValid());
        QCoreApplication::setOrganizationName("ListenFreeTrackManagementTests");
        QCoreApplication::instance()->setProperty("listenfreeDataDir",profile_.path());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,profile_.path());
        QSettings::setPath(QSettings::IniFormat,QSettings::SystemScope,profile_.path());
        Qmmp::setConfigDir(profile_.filePath("qmmp"));
        qputenv("LISTENFREE_QMMP_OUTPUT","null");
    }
    void defaultsPreserveExistingQuality() {
        infrastructure::database::Database db;
        QVERIFY(db.open(profile_.filePath("settings.sqlite"))); QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);
        qmlbridge::SettingsController settings(repo);
        QCOMPARE(QJsonDocument::fromJson(settingsSchema).object().value("playback.quality").toObject().value("default").toString(),QString("128k"));
        settings.setValue("playback.quality","flac");
        qmlbridge::SettingsController restored(repo);
        QCOMPARE(restored.value("playback.quality").toString(),QString("flac"));
    }
    void queueIdsSurviveRestartAndStaleCommandsDoNotRetarget() {
        const auto path=profile_.filePath("queue.sqlite");
        infrastructure::database::Database db; QVERIFY(db.open(path)); QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db); qmlbridge::SourceController sources(&repo);
        QVariantMap selected;
        {
            qmlbridge::PortableSession player(db,path,sources);
            for(const auto& source:{"kw","kg","tx","wy","mg","bili"}) QVERIFY(player.enqueueTrack(song(source)));
            QVERIFY(player.enqueueTrack(song("tx"))); QCOMPARE(player.queueSongs().size(),6);
            selected=player.queueSongs()[2].toMap();
            QVERIFY(!selected.value("trackUid").toString().isEmpty());
            QVERIFY(player.moveQueue(2,5)); QCOMPARE(player.queueIndexFor(selected),5);
            QVERIFY(player.selectQueue(5,false)); player.shutdown();
        }
        {
            qmlbridge::PortableSession player(db,path,sources);
            QCOMPARE(player.queueSongs().size(),6);
            QCOMPARE(player.currentTrack().value("entryId"),selected.value("entryId"));
            QCOMPARE(player.currentTrack().value("trackUid"),selected.value("trackUid"));
            QCOMPARE(player.queueIndexFor(selected),5);
            QVERIFY(player.removeFromQueue(5)); QVERIFY(player.enqueueTrack(selected));
            QCOMPARE(player.queueIndexFor(selected),-1);
            QVERIFY(!player.isCurrentTrack(selected));
            QCOMPARE(player.queueIndexFor(song("tx")),5);
        }
    }
    void downloadsUsePlatformIdentityInsteadOfLegacyIds() {
        infrastructure::database::Database db;
        QVERIFY(db.open(profile_.filePath("downloads.sqlite"))); QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repo(db);
        qmlbridge::SettingsController settings(repo); settings.setValue("download.enabled",true);
        qmlbridge::SourceController sources(&repo);
        qmlbridge::DownloadService downloads(db,sources,settings);
        downloads.add({song("tx"),song("wy"),song("tx")},"128k");
        QCOMPARE(downloads.rowCount(),2);
        QSet<QString> identities;
        for(const auto& value:downloads.tasks())
            identities.insert(value.toMap().value("track").toMap().value("trackUid").toString());
        QCOMPARE(identities.size(),2); QVERIFY(!identities.contains(QString{}));
    }
    void localFileTakesPrecedenceOverOnlineTags() {
        const auto audio=profile_.filePath("downloaded.wav");
        QFile file(audio); QVERIFY(file.open(QIODevice::WriteOnly)); file.write(audioFixture()); file.close();
        const auto path=profile_.filePath("local-tags.sqlite");
        infrastructure::database::Database db; QVERIFY(db.open(path)); QVERIFY(db.migrate());
        db.setSetting("lyrics.autoMatchEnabled","false");
        infrastructure::database::SettingsRepository repo(db); qmlbridge::SourceController sources(&repo);
        qmlbridge::PortableSession player(db,path,sources);
        auto downloaded=song(); downloaded["localPath"]=audio;
        QVERIFY(player.openTrack(downloaded));
        QTRY_COMPARE_WITH_TIMEOUT(player.state(),QString("Playing"),5000);
        QCOMPARE(player.currentTrack().value("source").toString(),QString("local"));
        QVERIFY(!player.currentTrack().contains("playbackSourceId")); player.stop();
    }
    void playbackFallsBackAcrossSourcesAndQualities() {
        QTcpServer server; QVERIFY(server.listen(QHostAddress::LocalHost));
        const auto wav = audioFixture();
        connect(&server,&QTcpServer::newConnection,this,[&]{
            while(server.hasPendingConnections()) {
                auto* socket=server.nextPendingConnection();
                connect(socket,&QTcpSocket::readyRead,socket,[socket,wav]{
                    const auto request=socket->readAll(); if(!request.contains("\r\n\r\n"))return;
                    socket->write("HTTP/1.1 200 OK\r\nContent-Type: audio/wav\r\nContent-Length: "+QByteArray::number(wav.size())+"\r\nConnection: close\r\n\r\n"+wav);
                    socket->disconnectFromHost();
                });
                connect(socket,&QTcpSocket::disconnected,socket,&QObject::deleteLater);
            }
        });
        const auto path=profile_.filePath("fallback.sqlite");
        infrastructure::database::Database db; QVERIFY(db.open(path)); QVERIFY(db.migrate());
        db.setSetting("playback.quality","flac"); db.setSetting("lyrics.autoMatchEnabled","false");
        infrastructure::database::SettingsRepository repo(db);
        qmlbridge::SourceController sources(&repo,testExecutable("listenfree-sourcehost"),true);
        const auto url=QString("http://127.0.0.1:%1/audio.wav").arg(server.serverPort());
        QVERIFY(sources.importLocalFile(script("fallback-good","if(info.type !== '128k') return undefined; return '"+url+"';")));
        QTRY_VERIFY_WITH_TIMEOUT(sources.hostReady() && sources.sources().last().toMap().value("hostReady").toBool(),10000);
        const auto good=sources.activeId();
        QVERIFY(sources.importLocalFile(script("fallback-bad","return undefined;")));
        QTRY_VERIFY_WITH_TIMEOUT(sources.hostReady() && sources.activeId()!=good && sources.sources().last().toMap().value("hostReady").toBool(),10000);
        const auto active=sources.activeId();
        QSignalSpy resolutions(&sources,&qmlbridge::SourceController::resolutionFinished);
        qmlbridge::PortableSession player(db,path,sources);
        QVERIFY(player.openTrack(song()));
        const auto entry=player.currentTrack().value("entryId");
        QCOMPARE(player.state(),QString("Loading"));
        QTRY_COMPARE_WITH_TIMEOUT(player.state(),QString("Playing"),20000);
        QCOMPARE(player.currentTrack().value("entryId"),entry);
        QCOMPARE(player.currentTrack().value("source").toString(),QString("tx"));
        QCOMPARE(player.currentTrack().value("playbackSourceId").toString(),good);
        QCOMPARE(player.currentTrack().value("playbackQuality").toString(),QString("128k"));
        QCOMPARE(sources.activeId(),active);
        QVERIFY(resolutions.size()>=3); QCOMPARE(player.queueSongs().size(),1);
        player.stop();
    }
    void stopCancelsRetryAndCannotRestartOldEntry() {
        const auto path=profile_.filePath("cancel.sqlite");
        infrastructure::database::Database db; QVERIFY(db.open(path)); QVERIFY(db.migrate());
        db.setSetting("lyrics.autoMatchEnabled","false");
        infrastructure::database::SettingsRepository repo(db);
        qmlbridge::SourceController sources(&repo,testExecutable("listenfree-sourcehost"),true);
        QVERIFY(sources.importLocalFile(script("cancel-bad","throw new Error(info.type + '-requested');")));
        QTRY_VERIFY_WITH_TIMEOUT(sources.hostReady() && sources.sources().last().toMap().value("hostReady").toBool(),10000);
        QSignalSpy resolutions(&sources,&qmlbridge::SourceController::resolutionFinished);
        qmlbridge::PortableSession player(db,path,sources);
        QVERIFY(player.openTrack(song()));
        QTRY_VERIFY_WITH_TIMEOUT(!resolutions.isEmpty(),5000);
        QCOMPARE(player.state(),QString("Loading"));
        QVERIFY(resolutions.first().at(4).toString().contains("128k-requested"));
        player.clearQueue(); const auto completed=resolutions.size();
        QTest::qWait(1500);
        QCOMPARE(resolutions.size(),completed); QVERIFY(player.queueSongs().isEmpty());
        QVERIFY(player.state()!="Loading");
    }
};
QTEST_MAIN(TrackManagementTests)
#include "track_management_tests.moc"
