#include "MusicController.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>
#include <QDataStream>
#include <QDir>
#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QUrl>
#include <QVariantMap>
#include <QtTest>

namespace {

constexpr auto serviceName = "org.mpris.MediaPlayer2.kosmusic";
constexpr auto objectPath = "/org/mpris/MediaPlayer2";
constexpr auto rootInterface = "org.mpris.MediaPlayer2";
constexpr auto playerInterface = "org.mpris.MediaPlayer2.Player";
constexpr auto propertiesInterface = "org.freedesktop.DBus.Properties";

bool writeTestWave(const QString &path)
{
    constexpr quint32 sampleRate = 16000;
    constexpr quint16 channels = 1;
    constexpr quint16 bitsPerSample = 16;
    QByteArray samples(static_cast<qsizetype>(sampleRate * 3 * channels
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

QVariant property(const QString &interface, const QString &name)
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

QDBusMessage setProperty(const QString &interface, const QString &name,
                         const QVariant &value)
{
    return call(QString::fromLatin1(propertiesInterface), QStringLiteral("Set"),
                {interface, name, QVariant::fromValue(QDBusVariant(value))});
}

} // namespace

class MusicMprisTest : public QObject {
    Q_OBJECT

private slots:
    void exposesPropertiesAndControlsPlayback();
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

    MusicController controller;
    QVERIFY(controller.ready());
    QVERIFY2(controller.mprisRegistered(), "MPRIS service did not register");
    QCOMPARE(property(QString::fromLatin1(rootInterface), QStringLiteral("Identity"))
                 .toString(),
             QStringLiteral("KOS Music"));

    const QDBusMessage opened = call(QString::fromLatin1(playerInterface),
                                     QStringLiteral("OpenUri"),
                                     {QUrl::fromLocalFile(inputPath).toString()});
    QCOMPARE(opened.type(), QDBusMessage::ReplyMessage);
    QTRY_VERIFY_WITH_TIMEOUT(controller.currentTrackId() > 0, 3000);
    QTRY_COMPARE_WITH_TIMEOUT(controller.playbackState(), QStringLiteral("Playing"), 5000);

    const QVariantMap metadata = property(QString::fromLatin1(playerInterface),
                                          QStringLiteral("Metadata")).toMap();
    QCOMPARE(metadata.value(QStringLiteral("xesam:title")).toString(),
             QStringLiteral("mpris-tone"));
    QCOMPARE(property(QString::fromLatin1(playerInterface),
                      QStringLiteral("PlaybackStatus")).toString(),
             QStringLiteral("Playing"));

    QCOMPARE(call(QString::fromLatin1(playerInterface), QStringLiteral("Pause")).type(),
             QDBusMessage::ReplyMessage);
    QTRY_COMPARE_WITH_TIMEOUT(controller.playbackState(), QStringLiteral("Paused"), 3000);
    QCOMPARE(call(QString::fromLatin1(playerInterface), QStringLiteral("Play")).type(),
             QDBusMessage::ReplyMessage);
    QTRY_COMPARE_WITH_TIMEOUT(controller.playbackState(), QStringLiteral("Playing"), 3000);

    QCOMPARE(setProperty(QString::fromLatin1(playerInterface),
                         QStringLiteral("LoopStatus"),
                         QStringLiteral("Track")).type(),
             QDBusMessage::ReplyMessage);
    QCOMPARE(controller.repeatMode(), QStringLiteral("track"));
    QCOMPARE(setProperty(QString::fromLatin1(playerInterface),
                         QStringLiteral("Shuffle"), true).type(),
             QDBusMessage::ReplyMessage);
    QVERIFY(controller.shuffle());
    QCOMPARE(setProperty(QString::fromLatin1(playerInterface),
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

QTEST_GUILESS_MAIN(MusicMprisTest)

#include "MusicMprisTest.moc"
