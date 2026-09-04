#include "MetadataScanner.h"
#include "PlaybackEngine.h"
#include "Transcoder.h"

#include <QDataStream>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QUrl>
#include <QVariantMap>
#include <QtTest>

namespace {

bool writeTestWave(const QString &path, int durationMs)
{
    constexpr quint32 sampleRate = 16000;
    constexpr quint16 channels = 1;
    constexpr quint16 bitsPerSample = 16;
    const qsizetype byteCount = static_cast<qsizetype>(
        sampleRate * durationMs / 1000 * channels * bitsPerSample / 8);
    QByteArray samples(byteCount, '\0');
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

QString formatExtension(const QVariantList &formats, const QString &formatId)
{
    for (const QVariant &entry : formats) {
        const QVariantMap format = entry.toMap();
        if (format.value(QStringLiteral("id")).toString() == formatId)
            return format.value(QStringLiteral("extension")).toString();
    }
    return {};
}

} // namespace

class MusicEngineTest : public QObject {
    Q_OBJECT

private slots:
    void initTestCase();
    void decodesPlaysPausesAndSeeks();
    void transcodesToAnInstalledFormat();
};

void MusicEngineTest::initTestCase()
{
    qputenv("KOS_MUSIC_FAKE_AUDIO", "1");
}

void MusicEngineTest::decodesPlaysPausesAndSeeks()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString inputPath = directory.filePath(QStringLiteral("playback.wav"));
    QVERIFY(writeTestWave(inputPath, 2500));

    PlaybackEngine engine;
    QVERIFY2(engine.available(), qPrintable(engine.errorMessage()));
    QSignalSpy seeked(&engine, &PlaybackEngine::seeked);
    QVERIFY(engine.load(QUrl::fromLocalFile(inputPath), true));
    QTRY_COMPARE_WITH_TIMEOUT(engine.state(), QStringLiteral("Playing"), 5000);
    QTRY_VERIFY_WITH_TIMEOUT(engine.durationMs() >= 2400, 5000);
    QTRY_VERIFY_WITH_TIMEOUT(engine.seekable(), 5000);

    engine.seek(900);
    QTRY_COMPARE_WITH_TIMEOUT(seeked.size(), 1, 2000);
    QVERIFY(engine.positionMs() >= 850);
    engine.pause();
    QTRY_COMPARE_WITH_TIMEOUT(engine.state(), QStringLiteral("Paused"), 3000);
    engine.play();
    QTRY_COMPARE_WITH_TIMEOUT(engine.state(), QStringLiteral("Playing"), 3000);
    engine.stop();
    QCOMPARE(engine.state(), QStringLiteral("Stopped"));
}

void MusicEngineTest::transcodesToAnInstalledFormat()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString inputPath = directory.filePath(QStringLiteral("source.wav"));
    QVERIFY(writeTestWave(inputPath, 500));

    Transcoder transcoder;
    const QVariantList formats = transcoder.availableFormats();
    QVERIFY2(!formats.isEmpty(), "No GStreamer audio encoder is installed");
    QString formatId = QStringLiteral("flac");
    QString extension = formatExtension(formats, formatId);
    if (extension.isEmpty()) {
        const QVariantMap first = formats.constFirst().toMap();
        formatId = first.value(QStringLiteral("id")).toString();
        extension = first.value(QStringLiteral("extension")).toString();
    }
    QVERIFY(!formatId.isEmpty());
    QVERIFY(!extension.isEmpty());

    const QString outputPath = directory.filePath(
        QStringLiteral("converted.%1").arg(extension));
    QSignalSpy completed(&transcoder, &Transcoder::finished);
    QVERIFY2(transcoder.start(QUrl::fromLocalFile(inputPath),
                              QUrl::fromLocalFile(outputPath), formatId, false),
             qPrintable(transcoder.errorMessage()));
    QTRY_COMPARE_WITH_TIMEOUT(completed.size(), 1, 15000);
    QCOMPARE(transcoder.status(), QStringLiteral("Completed"));
    QVERIFY(QFileInfo(outputPath).size() > 0);

    completed.clear();
    QVERIFY2(transcoder.start(QUrl::fromLocalFile(inputPath),
                              QUrl::fromLocalFile(outputPath), formatId, true),
             qPrintable(transcoder.errorMessage()));
    QTRY_COMPARE_WITH_TIMEOUT(completed.size(), 1, 15000);
    QCOMPARE(transcoder.status(), QStringLiteral("Completed"));

    QString warning;
    const auto scanned = MetadataScanner::scanFile(
        outputPath, directory.filePath(QStringLiteral("artwork")), &warning);
    QVERIFY2(scanned.has_value(), qPrintable(warning));
    QVERIFY(scanned->durationMs >= 400);
}

QTEST_GUILESS_MAIN(MusicEngineTest)

#include "MusicEngineTest.moc"
