#include "MetadataScanner.h"
#include "MusicDatabase.h"
#include "TrackListModel.h"

#include <QDataStream>
#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include <QUrl>
#include <QtTest>

#include <utility>

namespace {

bool writeTestWave(const QString &path)
{
    constexpr quint32 sampleRate = 8000;
    constexpr quint16 channels = 1;
    constexpr quint16 bitsPerSample = 16;
    QByteArray samples(static_cast<qsizetype>(sampleRate / 5 * channels
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

TrackRecord track(QString path, QString title, QString artist = {})
{
    TrackRecord result;
    result.path = std::move(path);
    result.url = QUrl::fromLocalFile(result.path).toString();
    result.title = std::move(title);
    result.artist = std::move(artist);
    result.album = QStringLiteral("Test Album");
    result.albumArtist = result.artist;
    result.fileSize = 100;
    result.modifiedMs = 200;
    result.durationMs = 3000;
    result.format = QStringLiteral("WAV");
    return result;
}

} // namespace

class MusicCoreTest : public QObject {
    Q_OBJECT

private slots:
    void databasePersistsLibraryQueueAndPlaylists();
    void scannerSkipsUnchangedFilesAndRemovesMissingFiles();
    void trackModelFiltersAndSorts();
};

void MusicCoreTest::databasePersistsLibraryQueueAndPlaylists()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString root = directory.filePath(QStringLiteral("library"));
    QVERIFY(QDir().mkpath(root));
    const QString databasePath = directory.filePath(QStringLiteral("music.sqlite"));

    MusicDatabase database;
    QString error;
    QVERIFY2(database.open(databasePath, &error), qPrintable(error));
    QVERIFY2(database.addLibraryRoot(root, &error), qPrintable(error));
    ScanResult scan;
    scan.rootPath = root;
    scan.changedTracks = {
        track(QDir(root).filePath(QStringLiteral("one.wav")), QStringLiteral("One"),
              QStringLiteral("Alice")),
        track(QDir(root).filePath(QStringLiteral("two.wav")), QStringLiteral("Two"),
              QStringLiteral("Bob")),
    };
    for (const TrackRecord &item : std::as_const(scan.changedTracks))
        scan.visitedPaths.append(item.path);
    QVERIFY2(database.applyScan(scan, &error), qPrintable(error));
    const QList<TrackRecord> tracks = database.allTracks(&error);
    QCOMPARE(tracks.size(), 2);

    const qint64 playlistId = database.createPlaylist(QStringLiteral("Focus"), &error);
    QVERIFY2(playlistId > 0, qPrintable(error));
    QVERIFY(database.addTrackToPlaylist(playlistId, tracks.at(0).id, &error));
    QVERIFY(database.addTrackToPlaylist(playlistId, tracks.at(1).id, &error));
    QCOMPARE(database.playlistTrackIds(playlistId, &error).size(), 2);
    QVERIFY(database.setQueueTrackIds({tracks.at(1).id, tracks.at(0).id}, &error));
    QCOMPARE(database.queueTrackIds(&error), QList<qint64>({tracks.at(1).id,
                                                            tracks.at(0).id}));
    QVERIFY(database.setSetting(QStringLiteral("repeat"), QStringLiteral("playlist"), &error));
    QCOMPARE(database.setting(QStringLiteral("repeat"), {}, &error),
             QStringLiteral("playlist"));
}

void MusicCoreTest::scannerSkipsUnchangedFilesAndRemovesMissingFiles()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString root = directory.filePath(QStringLiteral("library"));
    QVERIFY(QDir().mkpath(root));
    const QString wavePath = QDir(root).filePath(QStringLiteral("tone.wav"));
    QVERIFY(writeTestWave(wavePath));

    MusicDatabase database;
    QString error;
    QVERIFY(database.open(directory.filePath(QStringLiteral("music.sqlite")), &error));
    QVERIFY(database.addLibraryRoot(root, &error));
    const QString artwork = directory.filePath(QStringLiteral("artwork"));
    const ScanResult first = MetadataScanner::scan(root, {}, artwork);
    QCOMPARE(first.visitedPaths.size(), 1);
    QCOMPARE(first.changedTracks.size(), 1);
    QCOMPARE(first.changedTracks.first().title, QStringLiteral("tone"));
    QVERIFY2(database.applyScan(first, &error), qPrintable(error));

    const ScanResult second = MetadataScanner::scan(
        root, database.fingerprints(root, &error), artwork);
    QCOMPARE(second.visitedPaths.size(), 1);
    QCOMPARE(second.changedTracks.size(), 0);
    QVERIFY(database.applyScan(second, &error));
    QCOMPARE(database.allTracks(&error).size(), 1);

    QVERIFY(QFile::remove(wavePath));
    const ScanResult third = MetadataScanner::scan(
        root, database.fingerprints(root, &error), artwork);
    QCOMPARE(third.visitedPaths.size(), 0);
    QVERIFY(database.applyScan(third, &error));
    QCOMPARE(database.allTracks(&error).size(), 0);
}

void MusicCoreTest::trackModelFiltersAndSorts()
{
    TrackRecord zebra = track(QStringLiteral("/tmp/z.wav"), QStringLiteral("Zebra"),
                              QStringLiteral("Alice"));
    zebra.id = 2;
    zebra.addedAt = 10;
    TrackRecord alpha = track(QStringLiteral("/tmp/a.wav"), QStringLiteral("Alpha"),
                              QStringLiteral("Bob"));
    alpha.id = 1;
    alpha.addedAt = 20;

    TrackListModel model;
    model.setTracks({zebra, alpha});
    QCOMPARE(model.trackIdAt(0), 1);
    model.setSearch(QStringLiteral("alice"));
    QCOMPARE(model.count(), 1);
    QCOMPARE(model.trackIdAt(0), 2);
    model.setSearch({});
    model.setMode(QStringLiteral("recent"));
    QCOMPARE(model.trackIdAt(0), 1);
}

QTEST_GUILESS_MAIN(MusicCoreTest)

#include "MusicCoreTest.moc"
