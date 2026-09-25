#include "MusicController.h"
#include "AudioCache.h"
#include <QProcess>
#include <QScopeGuard>

#include <QDBusConnection>
#include <QDBusArgument>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>
#include <QDataStream>
#include <QDir>
#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTcpServer>
#include <QTcpSocket>
#include <QUrl>
#include <QVariantMap>
#include <QtTest>

namespace {

constexpr auto serviceName = "org.mpris.MediaPlayer2.kosmusic";
constexpr auto objectPath = "/org/mpris/MediaPlayer2";
constexpr auto rootInterface = "org.mpris.MediaPlayer2";
constexpr auto playerInterface = "org.mpris.MediaPlayer2.Player";
constexpr auto propertiesInterface = "org.freedesktop.DBus.Properties";

bool writeTestWave(const QString &path, int seconds = 3)
{
    constexpr quint32 sampleRate = 16000;
    constexpr quint16 channels = 1;
    constexpr quint16 bitsPerSample = 16;
    QByteArray samples(static_cast<qsizetype>(sampleRate * seconds * channels
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

QDBusMessage call(const QString &interface, const QString &method,
                  const QVariantList &arguments = {})
{
    QDBusMessage message = QDBusMessage::createMethodCall(
        QString::fromLatin1(serviceName), QString::fromLatin1(objectPath),
        interface, method);
    message.setArguments(arguments);
    QDBusPendingCallWatcher watcher(QDBusConnection::sessionBus().asyncCall(message));
    if (!watcher.isFinished()) {
        QSignalSpy finished(&watcher, &QDBusPendingCallWatcher::finished);
        if (!finished.wait(5000))
            return QDBusMessage::createError(QDBusError::NoReply,
                                             QStringLiteral("Timed out"));
    }
    return watcher.reply();
}

QVariant mprisProperty(const QString &interface, const QString &name)
{
    const QDBusMessage reply = call(QString::fromLatin1(propertiesInterface),
                                    QStringLiteral("Get"),
                                    {interface, name});
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty())
        return {};
    const QVariant value = reply.arguments().constFirst();
    return value.canConvert<QDBusVariant>()
        ? value.value<QDBusVariant>().variant() : value;
}

QDBusMessage setMprisProperty(const QString &interface, const QString &name,
                              const QVariant &value)
{
    return call(QString::fromLatin1(propertiesInterface), QStringLiteral("Set"),
                {interface, name, QVariant::fromValue(QDBusVariant(value))});
}

QVariantMap dbusMap(const QVariant &value)
{
    if (value.metaType() == QMetaType::fromType<QDBusArgument>())
        return qdbus_cast<QVariantMap>(value.value<QDBusArgument>());
    return value.toMap();
}

} // namespace

class MusicMprisTest : public QObject {
    Q_OBJECT

private slots:
    void exposesPropertiesAndControlsPlayback();
    void playbackModesPersist();
    void onlineQueueAttemptsResolveAfterRestart();
    void onlineQualityPersistsAndRejectsInvalid();
    void onlineCacheResumesWithoutResolvingAgain();
    void localPositionSurvivesRestart();
    void lyricsSwitchPersistsAndHidesMetadata();
    void sourceFallback_data();
    void sourceFallback();
    void failedQueueRecovery_data();
    void failedQueueRecovery();
    void deleteMusic_data();
    void deleteMusic();
    void queueNextMovesWithoutDuplicating();
};

void MusicMprisTest::exposesPropertiesAndControlsPlayback()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    qputenv("KOS_MUSIC_FAKE_AUDIO", "1");
    qputenv("KOS_MUSIC_DATA_DIR", directory.filePath(QStringLiteral("data")).toUtf8());
    qputenv("KOS_MUSIC_CACHE_DIR", directory.filePath(QStringLiteral("cache")).toUtf8());
    const QString inputPath = directory.filePath(QStringLiteral("mpris-tone.wav"));
    QVERIFY(writeTestWave(inputPath));
    QFile lyricFile(directory.filePath(QStringLiteral("mpris-tone.lrc")));
    QVERIFY(lyricFile.open(QIODevice::WriteOnly));
    QCOMPARE(lyricFile.write("[00:00.00]First lyric\n[00:01.00]Second lyric\n"),
             qint64(45));
    lyricFile.close();

    MusicController controller;
    // Database open and MPRIS registration are deferred to the event loop.
    QTRY_VERIFY_WITH_TIMEOUT(controller.ready(), 3000);
    QVERIFY2(controller.mprisRegistered(), "MPRIS service did not register");
    QCOMPARE(mprisProperty(QString::fromLatin1(rootInterface), QStringLiteral("Identity"))
                 .toString(),
             QStringLiteral("KOS Music"));

    const QDBusMessage opened = call(QString::fromLatin1(playerInterface),
                                     QStringLiteral("OpenUri"),
                                     {QUrl::fromLocalFile(inputPath).toString()});
    QCOMPARE(opened.type(), QDBusMessage::ReplyMessage);
    QTRY_VERIFY_WITH_TIMEOUT(controller.currentTrackId() > 0, 3000);
    QTRY_COMPARE_WITH_TIMEOUT(controller.playbackState(), QStringLiteral("Playing"), 5000);

    const QVariantMap metadata = dbusMap(
        mprisProperty(QString::fromLatin1(playerInterface),
                      QStringLiteral("Metadata")));
    QCOMPARE(metadata.value(QStringLiteral("xesam:title")).toString(),
             QStringLiteral("mpris-tone"));
    QTRY_COMPARE_WITH_TIMEOUT(controller.currentLyric(), QStringLiteral("First lyric"), 3000);
    QVariantMap lyricMetadata = dbusMap(
        mprisProperty(QString::fromLatin1(playerInterface), QStringLiteral("Metadata")));
    QCOMPARE(lyricMetadata.value(QStringLiteral("xesam:asText")).toString(),
             QStringLiteral("First lyric"));
    QCOMPARE(lyricMetadata.value(QStringLiteral("kos:nextLyric")).toString(),
             QStringLiteral("Second lyric"));
    controller.seek(1500);
    QTRY_COMPARE_WITH_TIMEOUT(controller.currentLyric(), QStringLiteral("Second lyric"), 3000);
    lyricMetadata = dbusMap(
        mprisProperty(QString::fromLatin1(playerInterface), QStringLiteral("Metadata")));
    QCOMPARE(lyricMetadata.value(QStringLiteral("xesam:asText")).toString(),
             QStringLiteral("Second lyric"));
    QCOMPARE(mprisProperty(QString::fromLatin1(playerInterface),
                           QStringLiteral("PlaybackStatus")).toString(),
             QStringLiteral("Playing"));

    QCOMPARE(call(QString::fromLatin1(playerInterface), QStringLiteral("Pause")).type(),
             QDBusMessage::ReplyMessage);
    QTRY_COMPARE_WITH_TIMEOUT(controller.playbackState(), QStringLiteral("Paused"), 3000);
    QCOMPARE(call(QString::fromLatin1(playerInterface), QStringLiteral("Play")).type(),
             QDBusMessage::ReplyMessage);
    QTRY_COMPARE_WITH_TIMEOUT(controller.playbackState(), QStringLiteral("Playing"), 3000);

    QCOMPARE(setMprisProperty(QString::fromLatin1(playerInterface),
                              QStringLiteral("LoopStatus"),
                              QStringLiteral("Track")).type(),
             QDBusMessage::ReplyMessage);
    QCOMPARE(controller.repeatMode(), QStringLiteral("track"));
    QCOMPARE(setMprisProperty(QString::fromLatin1(playerInterface),
                              QStringLiteral("Shuffle"), true).type(),
             QDBusMessage::ReplyMessage);
    QVERIFY(controller.shuffle());
    QVERIFY(!mprisProperty(QString::fromLatin1(playerInterface),
                           QStringLiteral("CanGoNext")).toBool());
    QCOMPARE(setMprisProperty(QString::fromLatin1(playerInterface),
                              QStringLiteral("Volume"), 0.35).type(),
             QDBusMessage::ReplyMessage);
    QVERIFY(qAbs(controller.volume() - 0.35) < 0.01);

    QTRY_VERIFY_WITH_TIMEOUT(controller.seekable(), 5000);
    QSignalSpy seeked(&controller, &MusicController::seeked);
    QCOMPARE(call(QString::fromLatin1(playerInterface), QStringLiteral("Seek"),
                  {QVariant::fromValue<qlonglong>(400000)}).type(),
             QDBusMessage::ReplyMessage);
    QTRY_VERIFY_WITH_TIMEOUT(!seeked.isEmpty(), 3000);

    QSignalSpy raised(&controller, &MusicController::raiseRequested);
    QCOMPARE(call(QString::fromLatin1(rootInterface), QStringLiteral("Raise")).type(),
             QDBusMessage::ReplyMessage);
    QTRY_COMPARE_WITH_TIMEOUT(raised.size(), 1, 2000);
    QCOMPARE(call(QString::fromLatin1(playerInterface), QStringLiteral("Stop")).type(),
             QDBusMessage::ReplyMessage);
    QTRY_COMPARE_WITH_TIMEOUT(controller.playbackState(), QStringLiteral("Stopped"), 2000);
}

void MusicMprisTest::playbackModesPersist()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    qputenv("KOS_MUSIC_FAKE_AUDIO", "1");
    qputenv("KOS_MUSIC_DATA_DIR", directory.filePath(QStringLiteral("data")).toUtf8());
    qputenv("KOS_MUSIC_CACHE_DIR", directory.filePath(QStringLiteral("cache")).toUtf8());

    {
        MusicController controller;
        QTRY_VERIFY_WITH_TIMEOUT(controller.ready(), 3000);
        controller.setPlaybackMode(QStringLiteral("sequential"));
        QCOMPARE(controller.playbackMode(), QStringLiteral("sequential"));
        QCOMPARE(controller.repeatMode(), QStringLiteral("none"));
        QVERIFY(!controller.shuffle());

        controller.setPlaybackMode(QStringLiteral("playlist"));
        QCOMPARE(controller.repeatMode(), QStringLiteral("playlist"));
        QVERIFY(!controller.shuffle());

        controller.setPlaybackMode(QStringLiteral("shuffle"));
        QCOMPARE(controller.playbackMode(), QStringLiteral("shuffle"));
        QCOMPARE(controller.repeatMode(), QStringLiteral("none"));
        QVERIFY(controller.shuffle());

        controller.setPlaybackMode(QStringLiteral("track"));
        QCOMPARE(controller.playbackMode(), QStringLiteral("track"));
        QCOMPARE(controller.repeatMode(), QStringLiteral("track"));
        QVERIFY(!controller.shuffle());
    }
    QCoreApplication::processEvents();
    {
        MusicController controller;
        QTRY_VERIFY_WITH_TIMEOUT(controller.ready(), 3000);
        QCOMPARE(controller.playbackMode(), QStringLiteral("track"));
        QCOMPARE(controller.repeatMode(), QStringLiteral("track"));
        QVERIFY(!controller.shuffle());
    }
}

void MusicMprisTest::onlineQueueAttemptsResolveAfterRestart()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    qputenv("KOS_MUSIC_FAKE_AUDIO", "1");
    const QString dataPath = directory.filePath(QStringLiteral("data"));
    qputenv("KOS_MUSIC_DATA_DIR", dataPath.toUtf8());
    qputenv("KOS_MUSIC_CACHE_DIR", directory.filePath(QStringLiteral("cache")).toUtf8());

    {
        MusicDatabase database;
        QString error;
        QVERIFY2(database.open(QDir(dataPath).filePath(QStringLiteral("library.sqlite")),
                               &error), qPrintable(error));
        TrackRecord online;
        online.path = QStringLiteral("lx://wy/186016");
        online.title = QStringLiteral("晴天");
        online.artist = QStringLiteral("周杰伦");
        online.source = QStringLiteral("wy");
        online.providerId = QStringLiteral("186016");
        online.sourceData = QStringLiteral("{}");
        const qint64 id = database.addExternalTrack(online, &error);
        QVERIFY2(id > 0, qPrintable(error));
        QVERIFY2(database.setQueueTrackIds({id}, &error), qPrintable(error));
        QVERIFY2(database.setSetting(QStringLiteral("queueIndex"), QStringLiteral("0"),
                                     &error), qPrintable(error));
    }

    MusicController controller;
    QTRY_VERIFY_WITH_TIMEOUT(controller.ready(), 3000);
    QCOMPARE(controller.currentTitle(), QStringLiteral("晴天"));
    QSignalSpy stateChanges(&controller, &MusicController::playbackStateChanged);
    controller.play();
    QVERIFY(stateChanges.size() >= 2); // Loading, then a classified source failure.
    QVERIFY(controller.errorMessage().contains(
        QStringLiteral("没有可用的兼容音源")));
}

void MusicMprisTest::onlineQualityPersistsAndRejectsInvalid()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    qputenv("KOS_MUSIC_FAKE_AUDIO", "1");
    qputenv("KOS_MUSIC_DATA_DIR", directory.filePath(QStringLiteral("data")).toUtf8());
    qputenv("KOS_MUSIC_CACHE_DIR", directory.filePath(QStringLiteral("cache")).toUtf8());

    {
        MusicController controller;
        QTRY_VERIFY_WITH_TIMEOUT(controller.ready(), 3000);
        controller.setOnlineQuality(QStringLiteral("320k"));
        QCOMPARE(controller.onlineQuality(), QStringLiteral("320k"));
        controller.setOnlineQuality(QStringLiteral("unsupported"));
        QCOMPARE(controller.onlineQuality(), QStringLiteral("320k"));
    }
    QCoreApplication::processEvents();
    {
        MusicController controller;
        QTRY_VERIFY_WITH_TIMEOUT(controller.ready(), 3000);
        QCOMPARE(controller.onlineQuality(), QStringLiteral("320k"));
    }
}

void MusicMprisTest::onlineCacheResumesWithoutResolvingAgain()
{
    QTemporaryDir directory;
    const QString dataPath = directory.filePath(QStringLiteral("data"));
    qputenv("KOS_MUSIC_DATA_DIR", dataPath.toUtf8());
    qputenv("KOS_MUSIC_CACHE_DIR", directory.filePath(QStringLiteral("cache")).toUtf8());
    const QString wavePath = directory.filePath(QStringLiteral("online.wav"));
    QVERIFY(writeTestWave(wavePath, 12));
    QFile wave(wavePath);
    QVERIFY(wave.open(QIODevice::ReadOnly));
    const QByteArray audio = wave.readAll();
    QTcpServer server;
    QVERIFY(server.listen(QHostAddress::LocalHost));
    int requests = 0;
    connect(&server, &QTcpServer::newConnection, this, [&] {
        while (QTcpSocket *socket = server.nextPendingConnection()) {
            connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
            connect(socket, &QTcpSocket::readyRead, socket, [&, socket] {
                socket->readAll();
                if (socket->property("answered").toBool())
                    return;
                socket->setProperty("answered", true);
                ++requests;
                // Leave time to pause/stop before an online load completes.
                QTimer::singleShot(200, socket, [socket, audio] {
                    socket->write("HTTP/1.1 200 OK\r\nContent-Type: audio/wav\r\nContent-Length: "
                        + QByteArray::number(audio.size()) + "\r\nConnection: close\r\n\r\n" + audio);
                    socket->disconnectFromHost();
                });
            });
        }
    });
    QFile source(directory.filePath(QStringLiteral("fixture.js")));
    QVERIFY(source.open(QIODevice::WriteOnly));
    source.write(QStringLiteral(R"JS(/*
 * @name Cache test
 * @version 1.0.0
 */
lx.on(lx.EVENT_NAMES.request, () => Promise.resolve("http://127.0.0.1:%1/track.wav"));
lx.send(lx.EVENT_NAMES.inited, { sources: { wy: {
    name: "fixture", type: "music", actions: ["musicUrl"], qualitys: ["128k"]
} } });
)JS").arg(server.serverPort()).toUtf8());
    source.close();
    qint64 trackId;
    {
        MusicDatabase database;
        QVERIFY(database.open(QDir(dataPath).filePath(QStringLiteral("library.sqlite"))));
        TrackRecord track;
        track.path = QStringLiteral("lx://wy/cache-test");
        track.source = QStringLiteral("wy");
        track.providerId = QStringLiteral("cache-test");
        track.sourceData = QStringLiteral("{}");
        track.title = QStringLiteral("Cached online track");
        track.durationMs = 12000;
        trackId = database.addExternalTrack(track);
        QVERIFY(trackId > 0);
        QVERIFY(database.setQueueTrackIds({trackId}));
        QVERIFY(database.setSetting(QStringLiteral("queueIndex"), QStringLiteral("0")));
    }
    qint64 savedPosition;
    {
        MusicController controller;
        QTRY_VERIFY(controller.ready());
        controller.importMusicSource(source.fileName());
        QTRY_COMPARE_WITH_TIMEOUT(controller.musicSourceState(), QStringLiteral("ready"), 5000);
        controller.play();
        QTRY_COMPARE(requests, 1);
        controller.stop();
        QTest::qWait(250);
        QCOMPARE(controller.playbackState(), QStringLiteral("Stopped"));
        QCOMPARE(controller.positionMs(), 0);
        controller.play();
        QTRY_COMPARE(requests, 2);
        controller.pause();
        QTRY_COMPARE(controller.playbackState(), QStringLiteral("Paused"));
        QTRY_VERIFY(controller.seekable());
        QCOMPARE(controller.playbackState(), QStringLiteral("Paused"));
        controller.play();
        QTRY_COMPARE(controller.playbackState(), QStringLiteral("Playing"));
        controller.seek(2400);
        controller.pause();
        QTRY_COMPARE(controller.playbackState(), QStringLiteral("Paused"));
        savedPosition = controller.positionMs();
        QVERIFY(savedPosition >= 2350);
        QTest::qWait(350);
        QCOMPARE(controller.positionMs(), savedPosition);
        QCOMPARE(call(QString::fromLatin1(playerInterface), QStringLiteral("PlayPause")).type(),
                 QDBusMessage::ReplyMessage);
        QTRY_COMPARE(controller.playbackState(), QStringLiteral("Playing"));
        QVERIFY(controller.positionMs() >= savedPosition);
        QCOMPARE(requests, 2);
        // A completed cache must remain usable without either the source or HTTP server.
        controller.removeMusicSource(controller.activeMusicSourceId());
        server.close();
        controller.pause();
        QTRY_COMPARE(controller.playbackState(), QStringLiteral("Paused"));
        savedPosition = controller.positionMs();
    }
    QCoreApplication::processEvents();
    {
        MusicController controller;
        QTRY_VERIFY(controller.ready());
        QCOMPARE(controller.currentTrackId(), trackId);
        QCOMPARE(controller.positionMs(), savedPosition);
        QCOMPARE(controller.playbackState(), QStringLiteral("Paused"));
        controller.play();
        QTRY_COMPARE_WITH_TIMEOUT(controller.playbackState(), QStringLiteral("Playing"), 5000);
        QVERIFY(controller.positionMs() >= savedPosition - 50);
        QVERIFY(controller.errorMessage().isEmpty());
        QCOMPARE(requests, 2);
        controller.stop();
        QCOMPARE(controller.positionMs(), 0);
    }
    QCoreApplication::processEvents();
    MusicController stopped;
    QTRY_VERIFY(stopped.ready());
    QCOMPARE(stopped.positionMs(), 0);
    stopped.clearQueue();
}

void MusicMprisTest::localPositionSurvivesRestart()
{
    QTemporaryDir directory;
    qputenv("KOS_MUSIC_DATA_DIR", directory.filePath(QStringLiteral("data")).toUtf8());
    qputenv("KOS_MUSIC_CACHE_DIR", directory.filePath(QStringLiteral("cache")).toUtf8());
    const QString path = directory.filePath(QStringLiteral("local.wav"));
    QVERIFY(writeTestWave(path, 12));
    qint64 savedPosition;
    {
        MusicController controller;
        QTRY_VERIFY(controller.ready());
        controller.openUri(QUrl::fromLocalFile(path).toString());
        QTRY_COMPARE(controller.playbackState(), QStringLiteral("Playing"));
        QTRY_VERIFY(controller.seekable());
        controller.seek(3400);
        controller.pause();
        QTRY_COMPARE(controller.playbackState(), QStringLiteral("Paused"));
        savedPosition = controller.positionMs();
        QVERIFY(savedPosition >= 3350);
    }
    QCoreApplication::processEvents();
    MusicController controller;
    QTRY_VERIFY(controller.ready());
    QCOMPARE(controller.positionMs(), savedPosition);
    controller.play();
    QTRY_COMPARE(controller.playbackState(), QStringLiteral("Playing"));
    QVERIFY(controller.positionMs() >= savedPosition - 50);
}

void MusicMprisTest::lyricsSwitchPersistsAndHidesMetadata()
{
    QTemporaryDir directory;
    qputenv("KOS_MUSIC_DATA_DIR", directory.filePath(QStringLiteral("data")).toUtf8());
    qputenv("KOS_MUSIC_CACHE_DIR", directory.filePath(QStringLiteral("cache")).toUtf8());
    const QString path = directory.filePath(QStringLiteral("lyrics.wav"));
    QVERIFY(writeTestWave(path, 12));
    QFile lyrics(directory.filePath(QStringLiteral("lyrics.lrc")));
    QVERIFY(lyrics.open(QIODevice::WriteOnly));
    lyrics.write("[00:00.00]First line\n[00:01.00]Second line\n");
    lyrics.close();
    {
        MusicController controller;
        QTRY_VERIFY(controller.ready());
        controller.openUri(QUrl::fromLocalFile(path).toString());
        QTRY_COMPARE(controller.currentLyric(), QStringLiteral("First line"));
        controller.setLyricsEnabled(false);
        QVERIFY(controller.lyrics().isEmpty());
        QVERIFY(controller.currentLyric().isEmpty());
        QVERIFY(controller.mprisMetadata().value(QStringLiteral("kos:currentLyric")).toString().isEmpty());
        controller.setLyricsEnabled(true);
        QTRY_COMPARE(controller.currentLyric(), QStringLiteral("First line"));
        controller.setLyricsEnabled(false);
    }
    QCoreApplication::processEvents();
    MusicController controller;
    QTRY_VERIFY(controller.ready());
    QVERIFY(!controller.lyricsEnabled());
}

void MusicMprisTest::sourceFallback_data()
{
    QTest::addColumn<QString>("fault");
    for (const char *fault : {"reject", "hang", "bad-audio", "http-403", "unsupported", "busy-host", "late-reply", "http-stall", "deadline-skip", "corrupt-cache", "host-crash"})
        QTest::newRow(fault) << QString::fromLatin1(fault);
}

void MusicMprisTest::sourceFallback()
{
    QFETCH(QString, fault);
    QTemporaryDir directory;
    const QString dataPath = directory.filePath(QStringLiteral("data"));
    qputenv("KOS_MUSIC_DATA_DIR", dataPath.toUtf8());
    qputenv("KOS_MUSIC_CACHE_DIR", directory.filePath(QStringLiteral("cache")).toUtf8());
    const QString wavePath = directory.filePath(QStringLiteral("healthy.wav"));
    QVERIFY(writeTestWave(wavePath, 12));
    QFile wave(wavePath);
    QVERIFY(wave.open(QIODevice::ReadOnly));
    const QByteArray audio = wave.readAll();
    QTcpServer server;
    QVERIFY(server.listen(QHostAddress::LocalHost));
    connect(&server, &QTcpServer::newConnection, this, [&] {
        auto *socket = server.nextPendingConnection();
        connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
        connect(socket, &QTcpSocket::readyRead, socket, [&, socket] {
            const QByteArray request = socket->readAll();
            if (socket->property("answered").toBool()) return;
            socket->setProperty("answered", true);
            const bool bad = request.contains("/bad");
            if (bad && fault == QLatin1String("http-stall")) return;
            const QByteArray body = bad ? QByteArray("invalid media bytes") : audio;
            if (bad && fault == QLatin1String("http-403"))
                socket->write("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
            else
                socket->write("HTTP/1.1 200 OK\r\nContent-Length: " + QByteArray::number(body.size())
                    + "\r\nConnection: close\r\n\r\n" + body);
            socket->disconnectFromHost();
        });
    });
    qint64 trackId;
    qint64 healthyTrackId = -1;
    {
        MusicDatabase database;
        QVERIFY(database.open(QDir(dataPath).filePath(QStringLiteral("library.sqlite"))));
        TrackRecord track;
        track.path = QStringLiteral("lx://wy/fallback");
        track.source = QStringLiteral("wy");
        track.sourceData = QStringLiteral("{}");
        track.title = QStringLiteral("Fallback fixture");
        trackId = database.addExternalTrack(track);
        QVERIFY(trackId > 0);
        TrackRecord healthy;
        healthy.path = wavePath;
        healthy.url = QUrl::fromLocalFile(wavePath).toString();
        healthy.title = QStringLiteral("Healthy next song");
        healthyTrackId = database.addExternalTrack(healthy);
        QVERIFY(database.setQueueTrackIds({trackId, healthyTrackId}));
        QVERIFY(database.setSetting(QStringLiteral("queueIndex"), QStringLiteral("0")));
    }
    if (fault == QLatin1String("corrupt-cache")) {
        AudioCache cache(directory.filePath(QStringLiteral("cache/audio")));
        QFile bad(directory.filePath(QStringLiteral("cache/audio/stream-invalid")));
        QVERIFY(bad.open(QIODevice::WriteOnly));
        bad.write("This is not audio");
        bad.close();
        const QString key = QStringLiteral("wy") + QChar(0x1f)
            + QStringLiteral("lx://wy/fallback") + QChar(0x1f) + QStringLiteral("128k");
        QVERIFY(cache.storeCompleted(key, bad.fileName()));
    }
    MusicController controller;
    QTRY_VERIFY(controller.ready());
    const auto importScript = [&](const QString &name, const QString &expression, const QString &platform) {
        QFile script(directory.filePath(name + QStringLiteral(".js")));
        if (!script.open(QIODevice::WriteOnly)) return false;
        script.write(QStringLiteral("/*\n * @name %1\n */\n"
            "lx.on(lx.EVENT_NAMES.request, () => %2);\n"
            "lx.send(lx.EVENT_NAMES.inited, {sources:{%3:{name:'fixture',type:'music',actions:['musicUrl'],qualitys:['128k']}}});\n")
            .arg(name, expression, platform).toUtf8());
        script.close();
        controller.importMusicSource(script.fileName());
        return true;
    };
    QVERIFY(importScript(QStringLiteral("Healthy"), QStringLiteral("Promise.resolve('http://127.0.0.1:%1/good')").arg(server.serverPort()), QStringLiteral("wy")));
    QTRY_COMPARE(controller.musicSourceState(), QStringLiteral("ready"));
    QString expression = QStringLiteral("Promise.reject(new Error('fixture rejected'))");
    if (fault == QLatin1String("hang") || fault == QLatin1String("deadline-skip") || fault == QLatin1String("host-crash")) expression = QStringLiteral("new Promise(() => {})");
    if (fault == QLatin1String("late-reply")) expression = QStringLiteral("new Promise(resolve => setTimeout(() => resolve('http://127.0.0.1:%1/bad'), 1500))").arg(server.serverPort());
    if (fault == QLatin1String("busy-host")) expression = QStringLiteral("(() => { while (true) {} })()");
    if (fault == QLatin1String("bad-audio") || fault == QLatin1String("http-403") || fault == QLatin1String("http-stall"))
        expression = QStringLiteral("Promise.resolve('http://127.0.0.1:%1/bad')").arg(server.serverPort());
    QVERIFY(importScript(QStringLiteral("Broken"), expression, fault == QLatin1String("unsupported") ? QStringLiteral("kg") : QStringLiteral("wy")));
    QTRY_COMPARE(controller.musicSourceState(), QStringLiteral("ready"));
    const QString preferred = controller.activeMusicSourceId();
    auto *attempt = controller.findChild<QTimer *>(QStringLiteral("sourceAttemptTimeout"));
    QVERIFY(attempt);
    attempt->setInterval(700);
    if (fault == QLatin1String("deadline-skip")) {
        controller.findChild<QTimer *>(QStringLiteral("trackPreparationTimeout"))->setInterval(200);
        controller.findChild<QTimer *>(QStringLiteral("failedTrackSkipDelay"))->setInterval(80);
    }
    controller.play();
    if (fault == QLatin1String("host-crash")) {
        auto *host = controller.findChild<QProcess *>();
        QVERIFY(host);
        host->kill();
    }
    QTRY_COMPARE_WITH_TIMEOUT(controller.playbackState(), QStringLiteral("Playing"), 6000);
    QCOMPARE(controller.currentTrackId(), fault == QLatin1String("deadline-skip") ? healthyTrackId : trackId);
    QCOMPARE(controller.activeMusicSourceId(), preferred); // Automatic fallback preserves preference.
    QVERIFY(!controller.playbackAttempts().isEmpty());
    QVERIFY(controller.errorMessage().isEmpty());
    QTest::qWait(200);
    QCOMPARE(controller.playbackState(), QStringLiteral("Playing"));
    controller.pause();
    QTest::qWait(50); // The audio sink acknowledges pause asynchronously.
    const qint64 position = controller.positionMs();
    QTest::qWait(200);
    QCOMPARE(controller.playbackState(), QStringLiteral("Paused"));
    QCOMPARE(controller.positionMs(), position);
    controller.play();
    QTRY_COMPARE(controller.playbackState(), QStringLiteral("Playing"));
}

void MusicMprisTest::failedQueueRecovery_data()
{
    QTest::addColumn<QString>("mode");
    QTest::addColumn<QString>("action");
    for (const char *mode : {"sequential", "playlist", "track", "shuffle"}) {
        QTest::newRow(qPrintable(QString::fromLatin1(mode) + "-skip")) << QString::fromLatin1(mode) << QStringLiteral("skip");
        QTest::newRow(qPrintable(QString::fromLatin1(mode) + "-all-bad")) << QString::fromLatin1(mode) << QStringLiteral("all-bad");
    }
    for (const char *action : {"pause", "stop", "clear", "remove", "next"})
        QTest::newRow(action) << QStringLiteral("sequential") << QString::fromLatin1(action);
}

void MusicMprisTest::failedQueueRecovery()
{
    QFETCH(QString, mode);
    QFETCH(QString, action);
    QTemporaryDir directory;
    const QString dataPath = directory.filePath(QStringLiteral("data"));
    qputenv("KOS_MUSIC_DATA_DIR", dataPath.toUtf8());
    qputenv("KOS_MUSIC_CACHE_DIR", directory.filePath(QStringLiteral("cache")).toUtf8());
    const QString wavePath = directory.filePath(QStringLiteral("healthy.wav"));
    QVERIFY(writeTestWave(wavePath, 12));
    QList<qint64> ids;
    {
        MusicDatabase database;
        QVERIFY(database.open(QDir(dataPath).filePath(QStringLiteral("library.sqlite"))));
        for (int i = 0; i < 3; ++i) {
            TrackRecord track;
            track.path = (i == 2 && action != QLatin1String("all-bad")) ? wavePath
                : directory.filePath(QStringLiteral("missing-%1.wav").arg(i));
            track.url = QUrl::fromLocalFile(track.path).toString();
            track.title = QStringLiteral("Queue fixture %1").arg(i);
            ids.append(database.addExternalTrack(track));
            QVERIFY(ids.last() > 0);
        }
        QVERIFY(database.setQueueTrackIds(ids));
        QVERIFY(database.setSetting(QStringLiteral("queueIndex"), QStringLiteral("0")));
    }
    MusicController controller;
    QTRY_VERIFY(controller.ready());
    auto *skip = controller.findChild<QTimer *>(QStringLiteral("failedTrackSkipDelay"));
    QVERIFY(skip);
    skip->setInterval(150);
    controller.setPlaybackMode(mode);
    controller.play();
    QTRY_VERIFY(controller.playbackState() == QLatin1String("Error"));
    if (action == QLatin1String("pause")) controller.pause();
    if (action == QLatin1String("stop")) controller.stop();
    if (action == QLatin1String("clear")) controller.clearQueue();
    if (action == QLatin1String("remove")) controller.removeQueueRow(0);
    if (action == QLatin1String("next")) controller.playQueueRow(2);
    if (action == QLatin1String("skip") || action == QLatin1String("next")) {
        QTRY_COMPARE_WITH_TIMEOUT(controller.playbackState(), QStringLiteral("Playing"), 3000);
        QCOMPARE(controller.currentTrackId(), ids.last());
    } else if (action == QLatin1String("all-bad")) {
        QTRY_VERIFY_WITH_TIMEOUT(controller.playbackStatusText().contains(QStringLiteral("没有更多")), 3000);
        const int index = controller.queueIndex();
        QTest::qWait(500);
        QCOMPARE(controller.queueIndex(), index);
        QVERIFY(!skip->isActive());
    } else {
        const qint64 id = controller.currentTrackId();
        QTest::qWait(500);
        QCOMPARE(controller.currentTrackId(), id);
        QVERIFY(controller.playbackState() != QLatin1String("Playing"));
        QVERIFY(!skip->isActive());
    }
}

void MusicMprisTest::deleteMusic_data()
{
    QTest::addColumn<QString>("scenario");
    for (const char *scenario : {"playing", "paused", "other-track", "only-track", "missing-file", "stale-menu", "invalid-directory", "trash-unavailable", "scan-in-flight"})
        QTest::newRow(scenario) << QString::fromLatin1(scenario);
}

void MusicMprisTest::deleteMusic()
{
    QFETCH(QString, scenario);
    QTemporaryDir directory;
    const QByteArray oldDataHome = qgetenv("XDG_DATA_HOME");
    const auto restoreEnvironment = qScopeGuard([oldDataHome] {
        if (oldDataHome.isNull()) qunsetenv("XDG_DATA_HOME");
        else qputenv("XDG_DATA_HOME", oldDataHome);
    });
    qputenv("XDG_DATA_HOME", directory.filePath(QStringLiteral("trash-data")).toUtf8());
    if (scenario == QLatin1String("trash-unavailable")) {
        // A file at the data-home path cannot contain Trash, even when a Qt
        // version tries to create missing parent directories automatically.
        QFile blockedDataHome(QString::fromUtf8(qgetenv("XDG_DATA_HOME")));
        QVERIFY(blockedDataHome.open(QIODevice::WriteOnly));
    } else {
        QVERIFY(QDir().mkpath(QString::fromUtf8(qgetenv("XDG_DATA_HOME"))));
    }
    const QString dataPath = directory.filePath(QStringLiteral("data"));
    qputenv("KOS_MUSIC_DATA_DIR", dataPath.toUtf8());
    qputenv("KOS_MUSIC_CACHE_DIR", directory.filePath(QStringLiteral("cache")).toUtf8());
    const QString audioDir = directory.filePath(QStringLiteral("audio"));
    QVERIFY(QDir().mkpath(audioDir));
    const QString first = QDir(audioDir).filePath(QStringLiteral("first.wav"));
    const QString second = QDir(audioDir).filePath(QStringLiteral("second.wav"));
    QVERIFY(writeTestWave(first, 12));
    QVERIFY(writeTestWave(second, 12));
    QList<qint64> ids;
    qint64 playlist;
    {
        MusicDatabase database;
        QVERIFY(database.open(QDir(dataPath).filePath(QStringLiteral("library.sqlite"))));
        for (const QString &path : {first, second}) {
            TrackRecord track;
            track.path = path;
            track.url = QUrl::fromLocalFile(path).toString();
            track.title = QFileInfo(path).baseName();
            ids.append(database.addExternalTrack(track));
        }
        QVERIFY(database.setQueueTrackIds(scenario == QLatin1String("only-track")
            ? QList<qint64>{ids.first()} : QList<qint64>{ids.first(), ids.last(), ids.first()}));
        QVERIFY(database.setSetting(QStringLiteral("queueIndex"), scenario == QLatin1String("other-track") ? QStringLiteral("1") : QStringLiteral("0")));
        playlist = database.createPlaylist(QStringLiteral("Deletion fixture"));
        for (qint64 id : ids) QVERIFY(database.addTrackToPlaylist(playlist, id));
    }
    MusicController controller;
    QTRY_VERIFY(controller.ready());
    controller.selectPlaylist(playlist);
    if (scenario == QLatin1String("playing") || scenario == QLatin1String("paused")
        || scenario == QLatin1String("other-track") || scenario == QLatin1String("only-track")) {
        controller.play();
        QTRY_COMPARE(controller.playbackState(), QStringLiteral("Playing"));
        if (scenario == QLatin1String("paused")) controller.pause();
    }
    if (scenario == QLatin1String("missing-file")) QVERIFY(QFile::remove(first));
    if (scenario == QLatin1String("invalid-directory")) {
        QVERIFY(QFile::remove(first));
        QVERIFY(QDir().mkpath(first));
    }
    if (scenario == QLatin1String("scan-in-flight")) controller.addLibraryFolder(audioDir);
    const auto info = controller.trackDeletionInfo(ids.first());
    QCOMPARE(info.value(QStringLiteral("path")).toString(), first);
    QSignalSpy deleted(&controller, &MusicController::trackDeleted);
    const bool succeeds = scenario != QLatin1String("stale-menu") && scenario != QLatin1String("invalid-directory")
        && scenario != QLatin1String("trash-unavailable");
    const bool deletedSuccessfully = controller.deleteTrack(ids.first(), scenario == QLatin1String("stale-menu")
        ? second : first);
    if (succeeds) QVERIFY2(deletedSuccessfully, qPrintable(controller.errorMessage()));
    else QVERIFY(!deletedSuccessfully);
    if (!succeeds) {
        QCOMPARE(deleted.size(), 0);
        QVERIFY(QFileInfo::exists(first));
        QCOMPARE(controller.queueModel()->rowCount(), 3);
        QCOMPARE(controller.playlistTracksModel()->rowCount(), 2);
        return;
    }
    QCOMPARE(deleted.size(), 1);
    QVERIFY(!QFileInfo::exists(first));
    QCOMPARE(controller.queueModel()->rowCount(), scenario == QLatin1String("only-track") ? 0 : 1);
    QCOMPARE(controller.playlistTracksModel()->rowCount(), 1);
    QCOMPARE(controller.currentTrackId(), scenario == QLatin1String("only-track") ? -1 : ids.last());
    if (scenario == QLatin1String("playing") || scenario == QLatin1String("other-track"))
        QTRY_COMPARE(controller.playbackState(), QStringLiteral("Playing"));
    if (scenario == QLatin1String("paused") || scenario == QLatin1String("only-track"))
        QVERIFY(controller.playbackState() != QLatin1String("Playing"));
    if (scenario == QLatin1String("scan-in-flight")) {
        QTRY_VERIFY(!controller.scanning());
        QVERIFY(controller.trackDeletionInfo(ids.first()).isEmpty());
    }
    {
        MusicDatabase database;
        QVERIFY(database.open(QDir(dataPath).filePath(QStringLiteral("library.sqlite"))));
        QVERIFY(!database.trackForPath(first).has_value());
        QCOMPARE(database.queueTrackIds(), scenario == QLatin1String("only-track") ? QList<qint64>{} : QList<qint64>{ids.last()});
        QCOMPARE(database.playlistTrackIds(playlist), QList<qint64>{ids.last()});
    }
    const QString trashPath = deleted.first().at(1).toString();
    if (scenario != QLatin1String("missing-file")) {
        QVERIFY(!trashPath.isEmpty());
        QFile trashed(trashPath), original(second);
        QVERIFY(trashed.open(QIODevice::ReadOnly));
        QVERIFY(original.open(QIODevice::ReadOnly));
        QCOMPARE(trashed.readAll(), original.readAll());
        trashed.close();
        // Clean up only this test's trash entry; no user's files are selected.
        QVERIFY(QFile::remove(trashPath));
        const QFileInfo trashFile(trashPath);
        const QString infoPath = QDir(trashFile.absolutePath()).filePath(
            QStringLiteral("../info/") + trashFile.fileName() + QStringLiteral(".trashinfo"));
        if (QFile::exists(infoPath)) QVERIFY(QFile::remove(infoPath));
    }
}

void MusicMprisTest::queueNextMovesWithoutDuplicating()
{
    QTemporaryDir directory;
    const QString dataPath = directory.filePath(QStringLiteral("data"));
    qputenv("KOS_MUSIC_DATA_DIR", dataPath.toUtf8());
    qputenv("KOS_MUSIC_CACHE_DIR", directory.filePath(QStringLiteral("cache")).toUtf8());
    QList<qint64> ids;
    {
        MusicDatabase database;
        QVERIFY(database.open(QDir(dataPath).filePath(QStringLiteral("library.sqlite"))));
        for (int i = 0; i < 4; ++i) {
            TrackRecord track;
            track.path = directory.filePath(QStringLiteral("track-%1.wav").arg(i));
            QVERIFY(writeTestWave(track.path, 12));
            track.url = QUrl::fromLocalFile(track.path).toString();
            track.title = QString::number(i);
            ids.append(database.addExternalTrack(track));
        }
        QVERIFY(database.setQueueTrackIds(ids));
        QVERIFY(database.setSetting(QStringLiteral("queueIndex"), QStringLiteral("1")));
    }
    MusicController controller;
    QTRY_VERIFY(controller.ready());
    controller.play();
    QTRY_COMPARE(controller.playbackState(), QStringLiteral("Playing"));
    controller.seek(2500);
    controller.pause();
    QTest::qWait(50);
    const auto position = controller.positionMs();
    controller.moveQueueRowNext(0);
    QCOMPARE(controller.queueIndex(), 0);
    QCOMPARE(controller.currentTrackId(), ids.at(1));
    QCOMPARE(controller.queueModel()->rowCount(), 4);
    QCOMPARE(controller.positionMs(), position);
    controller.playTrackNext(ids.last());
    QCOMPARE(controller.queueModel()->rowCount(), 4);
    MusicDatabase database;
    QVERIFY(database.open(QDir(dataPath).filePath(QStringLiteral("library.sqlite"))));
    QCOMPARE(database.queueTrackIds(), QList<qint64>({ids.at(1), ids.last(), ids.first(), ids.at(2)}));
    TrackRecord online;
    online.path = QStringLiteral("lx://wy/next-fixture");
    online.source = QStringLiteral("wy");
    online.sourceData = QStringLiteral("{}");
    online.title = QStringLiteral("Online next fixture");
    controller.onlineModel()->setTracks({online});
    controller.playOnlineNext(0);
    const auto onlineId = database.trackForPath(online.path)->id;
    QCOMPARE(database.queueTrackIds(), QList<qint64>({ids.at(1), onlineId, ids.last(), ids.first(), ids.at(2)}));
    QCOMPARE(controller.positionMs(), position);
    QCOMPARE(controller.playbackState(), QStringLiteral("Paused"));
}

QTEST_GUILESS_MAIN(MusicMprisTest)

#include "MusicMprisTest.moc"
