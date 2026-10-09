#include "media/mpv_audio_player.h"

#include <QFile>
#include <QHostAddress>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QtTest>

#include <cmath>

#ifdef Q_OS_WIN
#include <windows.h>
#include <tlhelp32.h>
#endif

namespace {

void writeLe16(QByteArray& bytes, quint16 value) {
    bytes.append(char(value & 0xff));
    bytes.append(char((value >> 8) & 0xff));
}

void writeLe32(QByteArray& bytes, quint32 value) {
    for (int i = 0; i < 4; ++i) bytes.append(char((value >> (8 * i)) & 0xff));
}

QString writeWav(const QString& directory, quint32 frames = 1'600) {
    constexpr quint32 sampleRate = 8'000;
    constexpr quint16 channels = 1;
    constexpr quint16 bits = 16;
    QByteArray pcm;
    pcm.reserve(static_cast<int>(frames * 2));
    for (quint32 i = 0; i < frames; ++i) {
        constexpr double pi = 3.14159265358979323846;
        const auto sample = static_cast<qint16>(std::sin(2.0 * pi * 440.0 * i / sampleRate) * 8'000.0);
        writeLe16(pcm, static_cast<quint16>(sample));
    }
    QByteArray wav("RIFF", 4);
    writeLe32(wav, 36U + static_cast<quint32>(pcm.size()));
    wav.append("WAVEfmt ", 8);
    writeLe32(wav, 16);
    writeLe16(wav, 1);
    writeLe16(wav, channels);
    writeLe32(wav, sampleRate);
    writeLe32(wav, sampleRate * channels * bits / 8);
    writeLe16(wav, channels * bits / 8);
    writeLe16(wav, bits);
    wav.append("data", 4);
    writeLe32(wav, static_cast<quint32>(pcm.size()));
    wav.append(pcm);
    const auto path = QDir(directory).filePath(QStringLiteral("mpv.wav"));
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly)) return {};
    if (file.write(wav) != wav.size()) return {};
    return path;
}

QByteArray readFile(const QString& path) {
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray{};
}

class LoopbackWavServer final : public QObject {
public:
    explicit LoopbackWavServer(QByteArray body) : body_(std::move(body)) {
        connect(&server_, &QTcpServer::newConnection, this, [this] {
            while (auto* socket = server_.nextPendingConnection()) {
                connect(socket, &QTcpSocket::readyRead, socket, [this, socket] {
                    socket->readAll();
                    ++requestCount_;
                    const auto header = QByteArrayLiteral("HTTP/1.1 200 OK\r\n") +
                                        QByteArrayLiteral("Content-Type: audio/wav\r\n") +
                                        QByteArrayLiteral("Accept-Ranges: bytes\r\n") +
                                        QByteArrayLiteral("Connection: close\r\n") +
                                        QByteArrayLiteral("Content-Length: ") +
                                        QByteArray::number(body_.size()) + QByteArrayLiteral("\r\n\r\n");
                    socket->write(header);
                    socket->write(body_);
                    socket->disconnectFromHost();
                });
                connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
            }
        });
    }

    bool listen() { return server_.listen(QHostAddress::LocalHost, 0); }
    QUrl url() const {
        return QUrl(QStringLiteral("http://127.0.0.1:%1/test.wav").arg(server_.serverPort()));
    }
    int requestCount() const noexcept { return requestCount_; }

private:
    QTcpServer server_;
    QByteArray body_;
    int requestCount_{0};
};

quint32 processHandleCount() {
#ifdef Q_OS_WIN
    DWORD count = 0;
    return GetProcessHandleCount(GetCurrentProcess(), &count) ? count : 0;
#else
    return 0;
#endif
}

quint32 processThreadCount() {
#ifdef Q_OS_WIN
    const DWORD processId = GetCurrentProcessId();
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return 0;
    quint32 count = 0;
    THREADENTRY32 entry{};
    entry.dwSize = sizeof(entry);
    if (Thread32First(snapshot, &entry)) {
        do {
            if (entry.th32OwnerProcessID == processId) ++count;
        } while (Thread32Next(snapshot, &entry));
    }
    CloseHandle(snapshot);
    return count;
#else
    return 0;
#endif
}

} // namespace

class MpvBackendTests final : public QObject {
    Q_OBJECT
private slots:
    void exposesMatureCoreCapabilities();
    void emptySourceRemainsIdle();
    void rejectsUnsupportedSchemesBeforeCoreDispatch();
    void invalidReplacementStopsPreviousPlayback();
    void rapidReplacementIgnoresSupersededTerminalEvents();
    void playsLocalFileAndPublishesEndExactlyOnce();
    void playsLoopbackHttpStream();
    void endOfMediaCanReplay();
    void userStopCanReplay();
    void clearRemainsIdleAfterLateCoreEvents();
    void repeatedConstructionHasBoundedProcessResources();
};

void MpvBackendTests::exposesMatureCoreCapabilities() {
    listenfree::media::MpvAudioPlayer player;
    QVERIFY2(player.available(), "libmpv should initialize with the configured WASAPI backend");
    using listenfree::application::PlaybackCapability;
    const auto caps = player.capabilities();
    QVERIFY(caps & listenfree::application::capabilityMask(PlaybackCapability::LocalFile));
    QVERIFY(caps & listenfree::application::capabilityMask(PlaybackCapability::HttpStream));
    QVERIFY(caps & listenfree::application::capabilityMask(PlaybackCapability::Equalizer));
    QVERIFY(caps & listenfree::application::capabilityMask(PlaybackCapability::DeviceSelection));
    const auto devices = player.devices();
    QVERIFY(!devices.empty());
    for (const auto& device : devices) {
        QVERIFY(device.id == "auto" || device.id.starts_with("wasapi/"));
    }
    QVERIFY(player.setEqualizerBand(4, 3.0F));
    QVERIFY(player.setReverbAmount(0.25F));
    QVERIFY(!player.setEqualizerBand(-1, 3.0F));
}

void MpvBackendTests::emptySourceRemainsIdle() {
    listenfree::media::MpvAudioPlayer player;
    player.open(listenfree::domain::PlaybackItem{});
    QCOMPARE(player.state(), listenfree::domain::PlaybackState::Idle);
    QVERIFY(!player.lastError().has_value());
}

void MpvBackendTests::rejectsUnsupportedSchemesBeforeCoreDispatch() {
    listenfree::media::MpvAudioPlayer player;
    listenfree::domain::PlaybackItem item;
    item.resolvedUrl = "ftp://127.0.0.1/not-supported.mp3";
    player.open(item);
    QCOMPARE(player.state(), listenfree::domain::PlaybackState::Error);
    QVERIFY(player.lastError().has_value());
    QCOMPARE(player.lastError()->code, listenfree::domain::PlaybackErrorCode::Unsupported);
}

void MpvBackendTests::invalidReplacementStopsPreviousPlayback() {
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const auto path = writeWav(directory.path(), 40'000);
    QVERIFY(!path.isEmpty());

    listenfree::media::MpvAudioPlayer player;
    player.setMuted(true);
    listenfree::domain::PlaybackItem local;
    local.track.localPath = path.toStdString();
    player.open(local);
    QTRY_VERIFY_WITH_TIMEOUT(player.duration() > std::chrono::milliseconds(0), 5'000);
    player.play();
    QTRY_COMPARE_WITH_TIMEOUT(player.state(), listenfree::domain::PlaybackState::Playing, 5'000);

    listenfree::domain::PlaybackItem invalid;
    invalid.resolvedUrl = "ftp://127.0.0.1/not-supported.mp3";
    player.open(invalid);
    QCOMPARE(player.state(), listenfree::domain::PlaybackState::Error);
    const auto stoppedPosition = player.position();
    QTest::qWait(300);
    QCOMPARE(player.state(), listenfree::domain::PlaybackState::Error);
    QCOMPARE(player.position(), stoppedPosition);
    QCOMPARE(player.duration(), std::chrono::milliseconds(0));
    QVERIFY(!player.seekable());
}

void MpvBackendTests::rapidReplacementIgnoresSupersededTerminalEvents() {
    QTemporaryDir firstDirectory;
    QTemporaryDir secondDirectory;
    QVERIFY(firstDirectory.isValid());
    QVERIFY(secondDirectory.isValid());
    const auto firstPath = writeWav(firstDirectory.path(), 40'000);
    const auto secondPath = writeWav(secondDirectory.path(), 8'000);
    QVERIFY(!firstPath.isEmpty());
    QVERIFY(!secondPath.isEmpty());

    listenfree::media::MpvAudioPlayer player;
    player.setMuted(true);
    int finished = 0;
    listenfree::application::PlaybackEvents events;
    events.onFinished = [&finished] { ++finished; };
    player.setEvents(std::move(events));

    listenfree::domain::PlaybackItem first;
    first.track.localPath = firstPath.toStdString();
    player.open(first);
    QTRY_VERIFY_WITH_TIMEOUT(player.duration() > std::chrono::milliseconds(0), 5'000);
    player.play();
    QTRY_COMPARE_WITH_TIMEOUT(player.state(), listenfree::domain::PlaybackState::Playing, 5'000);

    listenfree::domain::PlaybackItem second;
    second.track.localPath = secondPath.toStdString();
    player.open(second);
    player.play();
    QTRY_COMPARE_WITH_TIMEOUT(player.state(), listenfree::domain::PlaybackState::Playing, 5'000);
    QTRY_COMPARE_WITH_TIMEOUT(finished, 1, 5'000);
    QCOMPARE(player.state(), listenfree::domain::PlaybackState::Stopped);
}

void MpvBackendTests::playsLocalFileAndPublishesEndExactlyOnce() {
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const auto path = writeWav(directory.path());
    QVERIFY(!path.isEmpty());

    listenfree::media::MpvAudioPlayer player;
    player.setMuted(true);
    int finished = 0;
    listenfree::application::PlaybackEvents events;
    events.onFinished = [&finished] { ++finished; };
    player.setEvents(std::move(events));

    listenfree::domain::PlaybackItem item;
    item.track.localPath = path.toStdString();
    player.open(item);
    QTRY_VERIFY_WITH_TIMEOUT(player.duration() >= std::chrono::milliseconds(100), 5'000);
    QTRY_VERIFY_WITH_TIMEOUT(player.audioFormat().has_value(), 5'000);
    QCOMPARE(player.audioFormat()->sampleRate, 8'000);
    QCOMPARE(player.audioFormat()->channels, 1);
    QVERIFY(!player.audioFormat()->codec.empty());
    QTRY_COMPARE_WITH_TIMEOUT(player.state(), listenfree::domain::PlaybackState::Stopped, 5'000);
    player.play();
    QTRY_COMPARE_WITH_TIMEOUT(finished, 1, 5'000);
    QCOMPARE(player.state(), listenfree::domain::PlaybackState::Stopped);
    QTest::qWait(100);
    QCOMPARE(finished, 1);
    QVERIFY(!player.lastError().has_value());
}

void MpvBackendTests::playsLoopbackHttpStream() {
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const auto path = writeWav(directory.path(), 16'000);
    QVERIFY(!path.isEmpty());
    LoopbackWavServer server(readFile(path));
    QVERIFY(server.listen());

    listenfree::media::MpvAudioPlayer player;
    player.setMuted(true);
    listenfree::domain::PlaybackItem item;
    item.resolvedUrl = server.url().toString().toStdString();
    player.open(item);
    QTRY_VERIFY_WITH_TIMEOUT(player.duration() > std::chrono::milliseconds(0), 5'000);
    player.play();
    QTRY_COMPARE_WITH_TIMEOUT(player.state(), listenfree::domain::PlaybackState::Playing, 5'000);
    QVERIFY(server.requestCount() > 0);
    player.stop();
}

void MpvBackendTests::endOfMediaCanReplay() {
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const auto path = writeWav(directory.path());
    QVERIFY(!path.isEmpty());

    listenfree::media::MpvAudioPlayer player;
    player.setMuted(true);
    int finished = 0;
    listenfree::application::PlaybackEvents events;
    events.onFinished = [&finished] { ++finished; };
    player.setEvents(std::move(events));
    listenfree::domain::PlaybackItem item;
    item.track.localPath = path.toStdString();
    player.open(item);
    QTRY_VERIFY_WITH_TIMEOUT(player.duration() > std::chrono::milliseconds(0), 5'000);
    player.play();
    QTRY_COMPARE_WITH_TIMEOUT(finished, 1, 5'000);
    player.play();
    QTRY_COMPARE_WITH_TIMEOUT(finished, 2, 5'000);
    QCOMPARE(player.state(), listenfree::domain::PlaybackState::Stopped);
}

void MpvBackendTests::userStopCanReplay() {
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const auto path = writeWav(directory.path(), 16'000);
    QVERIFY(!path.isEmpty());

    listenfree::media::MpvAudioPlayer player;
    player.setMuted(true);
    listenfree::domain::PlaybackItem item;
    item.track.localPath = path.toStdString();
    player.open(item);
    QTRY_VERIFY_WITH_TIMEOUT(player.duration() > std::chrono::milliseconds(0), 5'000);
    player.play();
    QTRY_COMPARE_WITH_TIMEOUT(player.state(), listenfree::domain::PlaybackState::Playing, 5'000);
    player.stop();
    QCOMPARE(player.state(), listenfree::domain::PlaybackState::Stopped);
    player.play();
    QTRY_COMPARE_WITH_TIMEOUT(player.state(), listenfree::domain::PlaybackState::Playing, 5'000);
    QTRY_VERIFY_WITH_TIMEOUT(player.position() > std::chrono::milliseconds(0), 5'000);
}

void MpvBackendTests::clearRemainsIdleAfterLateCoreEvents() {
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const auto path = writeWav(directory.path());
    QVERIFY(!path.isEmpty());

    listenfree::media::MpvAudioPlayer player;
    listenfree::domain::PlaybackItem item;
    item.track.localPath = path.toStdString();
    player.open(item);
    QTRY_VERIFY_WITH_TIMEOUT(player.duration() > std::chrono::milliseconds(0), 5'000);
    player.clear();
    QCOMPARE(player.state(), listenfree::domain::PlaybackState::Idle);
    QTest::qWait(250);
    QCOMPARE(player.state(), listenfree::domain::PlaybackState::Idle);
    QCOMPARE(player.position(), std::chrono::milliseconds(0));
    QCOMPARE(player.duration(), std::chrono::milliseconds(0));
    QVERIFY(!player.lastError().has_value());
}

void MpvBackendTests::repeatedConstructionHasBoundedProcessResources() {
    for (int iteration = 0; iteration < 3; ++iteration) {
        listenfree::media::MpvAudioPlayer player;
        QVERIFY(player.available());
    }
    QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
    const quint32 handlesBefore = processHandleCount();
    const quint32 threadsBefore = processThreadCount();
    for (int iteration = 0; iteration < 10; ++iteration) {
        listenfree::media::MpvAudioPlayer player;
        QVERIFY(player.available());
        QVERIFY(player.setEqualizerBand(static_cast<int>(iteration % 10), 1.0F));
    }
    QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
    QTest::qWait(100);
    const quint32 handlesAfter = processHandleCount();
    const quint32 threadsAfter = processThreadCount();
    qInfo().nospace() << "libmpv resources handles " << handlesBefore << " -> " << handlesAfter
                      << ", threads " << threadsBefore << " -> " << threadsAfter;
#ifdef Q_OS_WIN
    QVERIFY(handlesBefore != 0);
    QVERIFY(threadsBefore != 0);
    QVERIFY2(handlesAfter <= handlesBefore + 3,
             qPrintable(QStringLiteral("handle count grew from %1 to %2")
                            .arg(handlesBefore).arg(handlesAfter)));
    QVERIFY2(threadsAfter <= threadsBefore + 1,
             qPrintable(QStringLiteral("thread count grew from %1 to %2")
                            .arg(threadsBefore).arg(threadsAfter)));
#endif
}

QTEST_MAIN(MpvBackendTests)
#include "mpv_backend_tests.moc"
