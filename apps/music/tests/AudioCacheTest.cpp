#include "AudioCache.h"

#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include <QtTest>

class AudioCacheTest : public QObject {
    Q_OBJECT
private slots:
    void cachesCompletedFilesAndEvicts();
    void doesNotPublishInvalidFiles();
};

static QString completeFile(const QString &directory, const QString &name, const QByteArray &data)
{
    const QString path = QDir(directory).filePath(name);
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly) || file.write(data) != data.size())
        return {};
    return path;
}

void AudioCacheTest::cachesCompletedFilesAndEvicts()
{
    QTemporaryDir directory;
    AudioCache cache(directory.path(), 9);
    const QString path = completeFile(directory.path(), QStringLiteral("stream-first"), "audio");
    QVERIFY(cache.lookup(QStringLiteral("track-128k")).isEmpty());
    QVERIFY(cache.storeCompleted(QStringLiteral("track-128k"), path));
    const QUrl first = cache.lookup(QStringLiteral("track-128k"));
    QVERIFY(first.isLocalFile());
    QVERIFY(!QFile::exists(path));
    QFile file(first.toLocalFile());
    QVERIFY(file.open(QIODevice::ReadOnly));
    QCOMPARE(file.readAll(), QByteArray("audio"));
    file.close();
    QVERIFY(cache.lookup(QStringLiteral("track-320k")).isEmpty());
    QTest::qWait(20);
    QVERIFY(cache.storeCompleted(QStringLiteral("second-128k"),
        completeFile(directory.path(), QStringLiteral("stream-second"), "audio")));
    QVERIFY(cache.lookup(QStringLiteral("track-128k")).isEmpty());
    AudioCache reopened(directory.path(), 9);
    QVERIFY(reopened.lookup(QStringLiteral("second-128k")).isLocalFile());
    reopened.remove(QStringLiteral("second-128k"));
    QVERIFY(reopened.lookup(QStringLiteral("second-128k")).isEmpty());
}

void AudioCacheTest::doesNotPublishInvalidFiles()
{
    QTemporaryDir directory, external;
    AudioCache cache(directory.path(), 9);
    QVERIFY(!cache.storeCompleted(QStringLiteral("empty"),
        completeFile(directory.path(), QStringLiteral("stream-empty"), {})));
    QVERIFY(!cache.storeCompleted(QStringLiteral("large"),
        completeFile(directory.path(), QStringLiteral("stream-large"), "ten bytes!")));
    QVERIFY(!cache.storeCompleted(QStringLiteral("outside"),
        completeFile(external.path(), QStringLiteral("stream-outside"), "audio")));
    QVERIFY(cache.lookup(QStringLiteral("empty")).isEmpty());
    QVERIFY(cache.lookup(QStringLiteral("large")).isEmpty());
    QVERIFY(cache.lookup(QStringLiteral("outside")).isEmpty());
}

QTEST_GUILESS_MAIN(AudioCacheTest)
#include "AudioCacheTest.moc"
