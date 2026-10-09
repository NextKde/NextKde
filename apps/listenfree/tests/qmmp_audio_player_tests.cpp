#include "media/qmmp_audio_player.h"

#include <QCoreApplication>
#include <QDataStream>
#include <QDir>
#include <QFile>
#include <QHostAddress>
#include <QSettings>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QTest>

#include <cmath>
#include <utility>

namespace {

QByteArray makeWave(int durationMs) {
    constexpr quint32 sampleRate = 8'000;
    constexpr quint16 channels = 1;
    constexpr quint16 bits = 16;
    const quint32 frames = sampleRate * static_cast<quint32>(durationMs) / 1'000;
    const quint32 dataSize = frames * channels * (bits / 8);
    QByteArray result;
    QDataStream out(&result, QIODevice::WriteOnly);
    out.setByteOrder(QDataStream::LittleEndian);
    out.writeRawData("RIFF", 4);
    out << quint32(36 + dataSize);
    out.writeRawData("WAVEfmt ", 8);
    out << quint32(16) << quint16(1) << channels << sampleRate;
    out << quint32(sampleRate * channels * (bits / 8));
    out << quint16(channels * (bits / 8)) << bits;
    out.writeRawData("data", 4);
    out << dataSize;
    for (quint32 frame = 0; frame < frames; ++frame) {
        const double phase = 2.0 * 3.141592653589793 * 440.0 * frame / sampleRate;
        out << static_cast<qint16>(std::sin(phase) * 4'000.0);
    }
    return result;
}

listenfree::domain::PlaybackItem localItem(const QString& path) {
    listenfree::domain::PlaybackItem item;
    item.track.id = listenfree::domain::TrackId("qmmp-generated-wave");
    item.track.title = "Qmmp generated wave";
    item.track.localPath = path.toStdString();
    return item;
}

class LoopbackAudioServer final : public QObject {
public:
    explicit LoopbackAudioServer(QByteArray body) : body_(std::move(body)) {
        connect(&server_, &QTcpServer::newConnection, this, [this] {
            while (auto* socket = server_.nextPendingConnection()) {
                connect(socket, &QTcpSocket::readyRead, socket, [this, socket] {
                    const QByteArray request = socket->readAll();
                    if (!request.contains("\r\n\r\n")) return;
                    QByteArray response = "HTTP/1.1 200 OK\r\nContent-Type: audio/wav\r\n";
                    response += "Connection: close\r\nContent-Length: " +
                                QByteArray::number(body_.size()) + "\r\n\r\n";
                    socket->write(response);
                    socket->write(body_);
                    socket->disconnectFromHost();
                });
                connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
            }
        });
    }

    bool listen() { return server_.listen(QHostAddress::LocalHost, 0); }
    std::string url() const {
        return QStringLiteral("http://127.0.0.1:%1/adapter.wav")
            .arg(server_.serverPort())
            .toStdString();
    }

private:
    QTcpServer server_;
    QByteArray body_;
};

} // namespace

class QmmpAudioPlayerTests final : public QObject {
    Q_OBJECT
private slots:
    void initTestCase();
    void reportsSelectedCapabilities();
    void missingAndUnsupportedSourcesAreStructured();
    void generatedWaveMapsLifecycleAndReleasesFile();
    void loopbackHttpUsesNetworkTransport();
};

void QmmpAudioPlayerTests::initTestCase() {
    QCoreApplication::setOrganizationName(QStringLiteral("ListenFreeTests"));
    QCoreApplication::setApplicationName(QStringLiteral("qmmp-audio-player-tests"));
    const QString settingsRoot = QDir::temp().filePath(QStringLiteral("listenfree-qmmp-tests"));
    QSettings::setDefaultFormat(QSettings::IniFormat);
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, settingsRoot);
    QSettings settings;
    settings.clear();
    settings.sync();
}

void QmmpAudioPlayerTests::reportsSelectedCapabilities() {
    listenfree::media::QmmpAudioPlayer player;
    QVERIFY(player.available());
    QCOMPARE(player.name(), std::string_view("qmmp-2.4"));
    const auto required =
        listenfree::application::capabilityMask(
            listenfree::application::PlaybackCapability::LocalFile) |
        listenfree::application::capabilityMask(
            listenfree::application::PlaybackCapability::HttpStream) |
        listenfree::application::capabilityMask(
            listenfree::application::PlaybackCapability::Equalizer) |
        listenfree::application::capabilityMask(
            listenfree::application::PlaybackCapability::Gapless) |
        listenfree::application::capabilityMask(
            listenfree::application::PlaybackCapability::Crossfade) |
        listenfree::application::capabilityMask(
            listenfree::application::PlaybackCapability::ReplayGain) |
        listenfree::application::capabilityMask(
            listenfree::application::PlaybackCapability::HighResolution);
    QCOMPARE(player.capabilities() & required, required);
    QVERIFY(player.supported());
}

void QmmpAudioPlayerTests::missingAndUnsupportedSourcesAreStructured() {
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    listenfree::media::QmmpAudioPlayer player;
    player.open(localItem(directory.filePath(QStringLiteral("missing.wav"))));
    QCOMPARE(player.state(), listenfree::domain::PlaybackState::Error);
    QVERIFY(player.lastError().has_value());
    QCOMPARE(player.lastError()->code, listenfree::domain::PlaybackErrorCode::OpenFailed);

    listenfree::domain::PlaybackItem unsupported;
    unsupported.resolvedUrl = "ftp://127.0.0.1/media.wav";
    player.open(unsupported);
    QCOMPARE(player.state(), listenfree::domain::PlaybackState::Error);
    QCOMPARE(player.lastError()->code, listenfree::domain::PlaybackErrorCode::Unsupported);
}

void QmmpAudioPlayerTests::generatedWaveMapsLifecycleAndReleasesFile() {
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString path = directory.filePath(QStringLiteral("lifecycle.wav"));
    QFile file(path);
    QVERIFY(file.open(QIODevice::WriteOnly));
    const QByteArray wave = makeWave(2'000);
    QCOMPARE(file.write(wave), wave.size());
    file.close();

    listenfree::media::QmmpAudioPlayer player;
    player.open(localItem(path));
    QCOMPARE(player.state(), listenfree::domain::PlaybackState::Stopped);
    QTRY_VERIFY_WITH_TIMEOUT(player.duration() >= std::chrono::milliseconds(1'900), 3'000);
    QVERIFY(player.seekable());
    QVERIFY(player.audioFormat().has_value());

    player.setVolume(-1.0F);
    QCOMPARE(player.volume(), 0.0F);
    player.setVolume(2.0F);
    QCOMPARE(player.volume(), 1.0F);
    player.setMuted(true);
    QVERIFY(player.muted());

    player.play();
    QTRY_COMPARE_WITH_TIMEOUT(player.state(), listenfree::domain::PlaybackState::Playing, 5'000);
    QTRY_VERIFY_WITH_TIMEOUT(player.position() > std::chrono::milliseconds(150), 5'000);
    player.pause();
    QTRY_COMPARE_WITH_TIMEOUT(player.state(), listenfree::domain::PlaybackState::Paused, 2'000);
    player.seek(std::chrono::milliseconds(1'000));
    QTRY_VERIFY_WITH_TIMEOUT(std::abs((player.position() - std::chrono::milliseconds(1'000)).count())
                                 < 200,
                             2'000);
    player.stop();
    QCOMPARE(player.state(), listenfree::domain::PlaybackState::Stopped);
    player.clear();
    QCOMPARE(player.state(), listenfree::domain::PlaybackState::Idle);
    QCOMPARE(player.duration(), std::chrono::milliseconds(0));
    QVERIFY(QFile::remove(path));
}

void QmmpAudioPlayerTests::loopbackHttpUsesNetworkTransport() {
    LoopbackAudioServer server(makeWave(40'000));
    QVERIFY(server.listen());

    listenfree::domain::PlaybackItem item;
    item.track.id = listenfree::domain::TrackId("qmmp-loopback-http");
    item.track.title = "Qmmp loopback HTTP";
    item.resolvedUrl = server.url();

    listenfree::media::QmmpAudioPlayer player;
    player.open(item);
    QCOMPARE(player.state(), listenfree::domain::PlaybackState::Stopped);
    QVERIFY(!player.seekable());
    player.play();
    QTRY_COMPARE_WITH_TIMEOUT(player.state(), listenfree::domain::PlaybackState::Playing, 5'000);
    QTRY_VERIFY_WITH_TIMEOUT(player.position() > std::chrono::milliseconds(150), 5'000);
    QVERIFY(!player.lastError().has_value());
    player.clear();
    QCOMPARE(player.state(), listenfree::domain::PlaybackState::Idle);
}

QTEST_GUILESS_MAIN(QmmpAudioPlayerTests)
#include "qmmp_audio_player_tests.moc"
