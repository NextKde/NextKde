#include "application/ports.h"
#include "application/playback_service.h"
#include "media/qt_audio_player.h"

#include <QDataStream>
#include <QAudioBuffer>
#include <QAudioBufferOutput>
#include <QAudioSink>
#include <QFile>
#include <QFileInfo>
#include <QHostAddress>
#include <QMediaDevices>
#include <QMediaMetaData>
#include <QMediaPlayer>
#include <QSignalSpy>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QtTest>

#include <cmath>
#include <algorithm>
#include <cstdint>
#include <optional>
#include <set>
#include <memory>

#ifdef Q_OS_WIN
#include <windows.h>
#endif

namespace {

QByteArray makePcmWav(int durationMs) {
    constexpr quint32 sampleRate = 8'000;
    constexpr quint16 channels = 1;
    constexpr quint16 bitsPerSample = 16;
    const quint32 sampleCount = static_cast<quint32>((static_cast<quint64>(sampleRate) *
                                                       static_cast<quint64>(durationMs)) /
                                                      1'000U);
    const quint32 dataSize = sampleCount * channels * (bitsPerSample / 8U);

    QByteArray wav;
    QDataStream stream(&wav, QIODevice::WriteOnly);
    stream.setByteOrder(QDataStream::LittleEndian);
    stream.writeRawData("RIFF", 4);
    stream << quint32(36U + dataSize);
    stream.writeRawData("WAVEfmt ", 8);
    stream << quint32(16U) << quint16(1U) << channels << sampleRate
           << quint32(sampleRate * channels * (bitsPerSample / 8U))
           << quint16(channels * (bitsPerSample / 8U)) << bitsPerSample;
    stream.writeRawData("data", 4);
    stream << dataSize;
    for (quint32 index = 0; index < sampleCount; ++index) {
        const double phase = 2.0 * 3.14159265358979323846 * 440.0 *
                             static_cast<double>(index) / static_cast<double>(sampleRate);
        stream << static_cast<qint16>(std::sin(phase) * 4'000.0);
    }
    return wav;
}

QString writeWav(QTemporaryDir& directory, QStringView name, int durationMs) {
    const QString path = directory.filePath(name.toString());
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly) || file.write(makePcmWav(durationMs)) <= 44) return {};
    file.close();
    return path;
}

listenfree::domain::PlaybackItem localItem(const QString& path) {
    listenfree::domain::PlaybackItem item;
    item.track.id = listenfree::domain::TrackId("generated-wav");
    item.track.title = "Generated WAV";
    item.track.localPath = path.toStdString();
    return item;
}

quint32 processHandleCount() {
#ifdef Q_OS_WIN
    DWORD count = 0;
    return GetProcessHandleCount(GetCurrentProcess(), &count) ? count : 0;
#else
    return 0;
#endif
}

class LoopbackWavServer final : public QObject {
public:
    explicit LoopbackWavServer(QByteArray wav, QObject* parent = nullptr)
        : QObject(parent), wav_(std::move(wav)) {
        connect(&server_, &QTcpServer::newConnection, this, [this] {
            while (auto* socket = server_.nextPendingConnection()) {
                const auto request = std::make_shared<QByteArray>();
                const auto responded = std::make_shared<bool>(false);
                connect(socket, &QTcpSocket::readyRead, socket, [this, socket, request, responded] {
                    if (*responded) return;
                    request->append(socket->readAll());
                    if (request->size() > 16 * 1024) {
                        socket->abort();
                        return;
                    }
                    if (!request->contains("\r\n\r\n")) return;
                    *responded = true;
                    ++requestCount_;

                    const QByteArray lower = request->toLower();
                    qsizetype start = 0;
                    const qsizetype range = lower.indexOf("range: bytes=");
                    if (range >= 0) {
                        const qsizetype valueStart = range + qsizetype(sizeof("range: bytes=") - 1);
                        const qsizetype dash = lower.indexOf('-', valueStart);
                        bool ok = false;
                        const qint64 requestedStart = lower.mid(valueStart, dash - valueStart).toLongLong(&ok);
                        if (ok) start = std::clamp<qsizetype>(requestedStart, 0, wav_.size());
                    }
                    const QByteArray body = wav_.mid(start);
                    const bool partial = start > 0;
                    const bool head = lower.startsWith("head ");
                    const QByteArray header = (partial ? QByteArrayLiteral("HTTP/1.1 206 Partial Content\r\n")
                                                       : QByteArrayLiteral("HTTP/1.1 200 OK\r\n")) +
                                              QByteArrayLiteral("Content-Type: audio/wav\r\n") +
                                              QByteArrayLiteral("Accept-Ranges: bytes\r\n") +
                                              (partial ? QByteArrayLiteral("Content-Range: bytes ") +
                                                             QByteArray::number(start) + '-' +
                                                             QByteArray::number(wav_.size() - 1) + '/' +
                                                             QByteArray::number(wav_.size()) + "\r\n"
                                                       : QByteArray{}) +
                                              QByteArrayLiteral("Connection: close\r\n") +
                                              QByteArrayLiteral("Content-Length: ") +
                                              QByteArray::number(body.size()) +
                                              QByteArrayLiteral("\r\n\r\n");
                    socket->write(header);
                    if (!head) socket->write(body);
                    socket->disconnectFromHost();
                });
                connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
            }
        });
    }

    ~LoopbackWavServer() override {
        server_.close();
        for (auto* socket : server_.findChildren<QTcpSocket*>()) socket->abort();
    }

    bool listen() { return server_.listen(QHostAddress::LocalHost, 0); }
    QUrl url() const {
        return QUrl(QStringLiteral("http://127.0.0.1:%1/generated.wav").arg(server_.serverPort()));
    }
    int requestCount() const noexcept { return requestCount_; }

private:
    QTcpServer server_;
    QByteArray wav_;
    int requestCount_{0};
};

} // namespace

class PlaybackTests final : public QObject {
    Q_OBJECT

private slots:
    void noSourceAndClearRemainIdle();
    void callbacksMayReplaceSubscriptionsAndReenter();
    void destructionDoesNotPublishSignals();
    void physicalAudioOutputCanOpen();
    void generatedWavDecodesWithoutAudioOutput();
    void generatedWavLoadsPlaysPausesSeeksAndStops();
    void endOfMediaIsObservable();
    void realEndOfMediaAdvancesApplicationQueue();
    void missingFileReportsStructuredError();
    void corruptWavReportsStructuredError();
    void unsupportedUrlSchemeReportsStructuredError();
    void clearAndDestructionReleaseTheSourceFile();
    void repeatedOpenPlayStopHasBoundedLifetime();
    void repeatedConstructionAndPlaybackHasBoundedHandles();
    void loopbackHttpWavLoadsAndPlays();
    void devicesAndCapabilitiesReflectRuntimeInventory();
};

void PlaybackTests::noSourceAndClearRemainIdle() {
    listenfree::media::QtAudioPlayer adapter;
    listenfree::application::IAudioPlayer& player = adapter;
    player.open({});
    QCOMPARE(player.state(), listenfree::domain::PlaybackState::Idle);
    player.play();
    QCOMPARE(player.state(), listenfree::domain::PlaybackState::Idle);
    player.pause();
    player.seek(std::chrono::milliseconds(100));
    player.stop();
    QCOMPARE(player.state(), listenfree::domain::PlaybackState::Idle);
    player.clear();
    QCOMPARE(player.state(), listenfree::domain::PlaybackState::Idle);
    QVERIFY(!player.lastError().has_value());
}

void PlaybackTests::callbacksMayReplaceSubscriptionsAndReenter() {
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    listenfree::media::QtAudioPlayer player;

    int muteEvents = 0;
    listenfree::application::PlaybackEvents muteSubscription;
    muteSubscription.onMutedChanged = [&](bool) {
        ++muteEvents;
        player.setEvents({});
    };
    player.setEvents(std::move(muteSubscription));
    player.setMuted(true);
    QCOMPARE(muteEvents, 1);

    listenfree::application::PlaybackEvents errorSubscription;
    errorSubscription.onStateChanged = [&](listenfree::domain::PlaybackState state) {
        if (state == listenfree::domain::PlaybackState::Error) player.clear();
    };
    player.setEvents(std::move(errorSubscription));
    player.open(localItem(directory.filePath(QStringLiteral("reentrant-missing.wav"))));
    QTRY_COMPARE_WITH_TIMEOUT(player.state(), listenfree::domain::PlaybackState::Idle, 5'000);
    QVERIFY(!player.lastError().has_value());

    const QString firstPath = writeWav(directory, u"reentrant-first.wav", 300);
    const QString secondPath = writeWav(directory, u"reentrant-second.wav", 900);
    bool switchedSource = false;
    listenfree::application::PlaybackEvents formatSubscription;
    formatSubscription.onAudioFormatChanged = [&](std::optional<listenfree::domain::AudioFormatInfo> format) {
        if (format && !switchedSource) {
            switchedSource = true;
            player.open(localItem(secondPath));
            player.play();
        }
    };
    player.setEvents(std::move(formatSubscription));
    player.open(localItem(firstPath));
    player.play();
    QTRY_VERIFY_WITH_TIMEOUT(switchedSource, 5'000);
    QTRY_VERIFY_WITH_TIMEOUT(player.duration() >= std::chrono::milliseconds(850), 5'000);
    QTRY_VERIFY_WITH_TIMEOUT(player.audioFormat().has_value(), 5'000);
}

void PlaybackTests::destructionDoesNotPublishSignals() {
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString path = writeWav(directory, u"destruction-signals.wav", 800);
    QVERIFY(!path.isEmpty());
    int teardownSignals = 0;
    auto player = std::make_unique<listenfree::media::QtAudioPlayer>();
    connect(player.get(), &listenfree::media::QtAudioPlayer::stateChanged, this,
            [&teardownSignals] { ++teardownSignals; });
    player->setMuted(true);
    player->open(localItem(path));
    player->play();
    QTRY_COMPARE_WITH_TIMEOUT(player->state(), listenfree::domain::PlaybackState::Playing, 5'000);
    teardownSignals = 0;
    player.reset();
    QCOMPARE(teardownSignals, 0);
    QVERIFY(QFile::remove(path));
}

void PlaybackTests::physicalAudioOutputCanOpen() {
    const auto outputs = QMediaDevices::audioOutputs();
    QVERIFY2(!outputs.empty(), "No Qt audio output is available for the physical output gate");
    const auto device = QMediaDevices::defaultAudioOutput().isNull()
                            ? outputs.front()
                            : QMediaDevices::defaultAudioOutput();
    const QAudioFormat format = device.preferredFormat();
    QVERIFY(format.isValid());
    QAudioSink sink(device, format);
    QVERIFY(!sink.isNull());
    QIODevice* stream = sink.start();
    QVERIFY2(stream != nullptr, "QAudioSink could not open the selected output device");
    QByteArray silence(std::max(1, format.bytesForDuration(200'000)), '\0');
    QVERIFY(stream->write(silence) > 0);
    QTRY_VERIFY_WITH_TIMEOUT(sink.state() == QtAudio::ActiveState ||
                                 sink.state() == QtAudio::IdleState,
                             2'000);
    QVERIFY(sink.error() != QtAudio::OpenError);
    QVERIFY(sink.error() != QtAudio::FatalError);
    qInfo() << "physical audio output:" << device.description() << format;
    sink.stop();
}

void PlaybackTests::generatedWavDecodesWithoutAudioOutput() {
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString path = writeWav(directory, u"decode-only.wav", 500);
    QVERIFY(!path.isEmpty());

    QMediaPlayer decoder;
    QAudioBufferOutput buffers;
    decoder.setAudioBufferOutput(&buffers);
    bool receivedBuffer = false;
    connect(&buffers, &QAudioBufferOutput::audioBufferReceived, &decoder,
            [&receivedBuffer](const QAudioBuffer& buffer) {
                if (buffer.isValid() && buffer.format().sampleRate() == 8'000) {
                    receivedBuffer = true;
                }
            });
    decoder.setSource(QUrl::fromLocalFile(path));
    decoder.play();
    QTRY_VERIFY_WITH_TIMEOUT(decoder.duration() >= 450, 5'000);
    QTRY_VERIFY_WITH_TIMEOUT(receivedBuffer, 5'000);
    decoder.stop();
    decoder.setSource({});
    decoder.setAudioBufferOutput(nullptr);
    QVERIFY(QFile::remove(path));
}

void PlaybackTests::generatedWavLoadsPlaysPausesSeeksAndStops() {
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString path = writeWav(directory, u"lifecycle.wav", 1'500);
    QVERIFY(!path.isEmpty());

    listenfree::media::QtAudioPlayer adapter;
    listenfree::application::IAudioPlayer& player = adapter;
    QVERIFY2(!adapter.devices().empty(), "No Qt audio output is available for the real playback gate");
    QVERIFY2(adapter.routesToAudioOutput(), "QMediaPlayer is not wired to the product audio output");
    player.setVolume(-1.0F);
    QCOMPARE(player.volume(), 0.0F);
    player.setVolume(2.0F);
    QCOMPARE(player.volume(), 1.0F);
    player.setMuted(true);
    QVERIFY(player.muted());
    player.open(localItem(path));
    QTRY_VERIFY_WITH_TIMEOUT(player.duration() >= std::chrono::milliseconds(1'400), 5'000);
    QVERIFY(player.duration() <= std::chrono::milliseconds(1'600));
    QTRY_VERIFY_WITH_TIMEOUT(player.seekable(), 5'000);

    player.play();
    QTRY_COMPARE_WITH_TIMEOUT(player.state(), listenfree::domain::PlaybackState::Playing, 5'000);
    QTRY_VERIFY_WITH_TIMEOUT(player.audioFormat().has_value(), 5'000);
    QCOMPARE(player.audioFormat()->sampleRate, 8'000);
    QCOMPARE(player.audioFormat()->channels, 1);
    QVERIFY(!player.audioFormat()->codec.empty());
    QVERIFY(player.audioFormat()->bitrate > 0);
    QTRY_VERIFY_WITH_TIMEOUT(player.position() > std::chrono::milliseconds(100), 5'000);

    player.pause();
    QTRY_COMPARE_WITH_TIMEOUT(player.state(), listenfree::domain::PlaybackState::Paused, 2'000);
    const auto pausedAt = player.position();
    QTest::qWait(150);
    QVERIFY(std::abs((player.position() - pausedAt).count()) < 80);
    player.seek(std::chrono::milliseconds(700));
    QTRY_VERIFY_WITH_TIMEOUT(std::abs((player.position() - std::chrono::milliseconds(700)).count()) < 150,
                             2'000);
    player.play();
    QTRY_COMPARE_WITH_TIMEOUT(player.state(), listenfree::domain::PlaybackState::Playing, 2'000);
    QTRY_VERIFY_WITH_TIMEOUT(player.position() > std::chrono::milliseconds(800), 2'000);
    player.stop();
    QTRY_COMPARE_WITH_TIMEOUT(player.state(), listenfree::domain::PlaybackState::Stopped, 2'000);
    QVERIFY(!player.lastError().has_value());
}

void PlaybackTests::endOfMediaIsObservable() {
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString path = writeWav(directory, u"end.wav", 300);
    QVERIFY(!path.isEmpty());

    int finished = 0;
    listenfree::media::QtAudioPlayer adapter;
    listenfree::application::IAudioPlayer& player = adapter;
    listenfree::application::PlaybackEvents events;
    events.onFinished = [&finished] { ++finished; };
    player.setEvents(std::move(events));
    player.open(localItem(path));
    QTRY_VERIFY_WITH_TIMEOUT(player.duration() >= std::chrono::milliseconds(250), 5'000);
    player.play();
    QTRY_COMPARE_WITH_TIMEOUT(finished, 1, 5'000);
    QCOMPARE(player.state(), listenfree::domain::PlaybackState::Stopped);
    QTest::qWait(150);
    QCOMPARE(finished, 1);
    player.play();
    QTRY_COMPARE_WITH_TIMEOUT(finished, 2, 5'000);
    QTest::qWait(150);
    QCOMPARE(finished, 2);
    QVERIFY(!player.lastError().has_value());
}

void PlaybackTests::realEndOfMediaAdvancesApplicationQueue() {
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString firstPath = writeWav(directory, u"queue-first.wav", 300);
    const QString secondPath = writeWav(directory, u"queue-second.wav", 300);
    QVERIFY(!firstPath.isEmpty());
    QVERIFY(!secondPath.isEmpty());
    auto first = localItem(firstPath);
    first.track.id = listenfree::domain::TrackId("queue-first");
    auto second = localItem(secondPath);
    second.track.id = listenfree::domain::TrackId("queue-second");

    listenfree::media::QtAudioPlayer player;
    player.setMuted(true);
    listenfree::application::PlaybackService service(player);
    service.setQueue({first, second});
    QVERIFY(service.playCurrent());
    QTRY_VERIFY_WITH_TIMEOUT(service.currentItem() != nullptr &&
                                 service.currentItem()->track.id.value() == "queue-second",
                             5'000);
    QTRY_COMPARE_WITH_TIMEOUT(player.state(), listenfree::domain::PlaybackState::Stopped, 5'000);
    QCOMPARE(service.queue().currentIndex(), std::size_t(1));
    QVERIFY(!player.lastError().has_value());
}

void PlaybackTests::missingFileReportsStructuredError() {
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    listenfree::media::QtAudioPlayer adapter;
    listenfree::application::IAudioPlayer& player = adapter;
    player.open(localItem(directory.filePath(QStringLiteral("missing.wav"))));
    QTRY_COMPARE_WITH_TIMEOUT(player.state(), listenfree::domain::PlaybackState::Error, 5'000);
    QVERIFY(player.lastError().has_value());
    QCOMPARE(player.lastError()->code, listenfree::domain::PlaybackErrorCode::OpenFailed);
    QVERIFY(!player.lastError()->message.empty());
    player.clear();
    QCOMPARE(player.state(), listenfree::domain::PlaybackState::Idle);
    QVERIFY(!player.lastError().has_value());
}

void PlaybackTests::corruptWavReportsStructuredError() {
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString path = directory.filePath(QStringLiteral("corrupt.wav"));
    QFile file(path);
    QVERIFY(file.open(QIODevice::WriteOnly));
    QVERIFY(file.write("not a wav") > 0);
    file.close();
    listenfree::media::QtAudioPlayer player;
    player.open(localItem(path));
    QTRY_COMPARE_WITH_TIMEOUT(player.state(), listenfree::domain::PlaybackState::Error, 5'000);
    QVERIFY(player.lastError().has_value());
    QVERIFY(!player.lastError()->message.empty());
}

void PlaybackTests::unsupportedUrlSchemeReportsStructuredError() {
    listenfree::media::QtAudioPlayer adapter;
    listenfree::domain::PlaybackItem item;
    item.resolvedUrl = "ftp://127.0.0.1/audio.wav";
    adapter.open(item);
    QCOMPARE(adapter.state(), listenfree::domain::PlaybackState::Error);
    QVERIFY(adapter.lastError().has_value());
    QCOMPARE(adapter.lastError()->code, listenfree::domain::PlaybackErrorCode::Unsupported);
    adapter.clear();
    QCOMPARE(adapter.state(), listenfree::domain::PlaybackState::Idle);
}

void PlaybackTests::clearAndDestructionReleaseTheSourceFile() {
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString clearedPath = writeWav(directory, u"clear.wav", 800);
    QVERIFY(!clearedPath.isEmpty());
    {
        listenfree::media::QtAudioPlayer player;
        player.open(localItem(clearedPath));
        QTRY_VERIFY_WITH_TIMEOUT(player.duration() > std::chrono::milliseconds(0), 5'000);
        player.clear();
        QCOMPARE(player.state(), listenfree::domain::PlaybackState::Idle);
        QVERIFY2(QFile::remove(clearedPath), "clear retained the generated WAV handle");
    }

    const QString destroyedPath = writeWav(directory, u"destroy.wav", 800);
    QVERIFY(!destroyedPath.isEmpty());
    {
        listenfree::media::QtAudioPlayer player;
        player.open(localItem(destroyedPath));
        QTRY_VERIFY_WITH_TIMEOUT(player.duration() > std::chrono::milliseconds(0), 5'000);
    }
    QVERIFY2(QFile::remove(destroyedPath), "destructor retained the generated WAV handle");
}

void PlaybackTests::repeatedOpenPlayStopHasBoundedLifetime() {
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString path = writeWav(directory, u"repeat.wav", 600);
    QVERIFY(!path.isEmpty());
    {
        listenfree::media::QtAudioPlayer player;
        player.setMuted(true);
        player.open(localItem(path));
        QTRY_VERIFY_WITH_TIMEOUT(player.duration() > std::chrono::milliseconds(0), 3'000);
        player.play();
        QTRY_COMPARE_WITH_TIMEOUT(player.state(), listenfree::domain::PlaybackState::Playing, 3'000);
        player.stop();
        player.clear();
        for (int iteration = 0; iteration < 20; ++iteration) {
            player.open(localItem(path));
            QTRY_VERIFY_WITH_TIMEOUT(player.duration() > std::chrono::milliseconds(0), 3'000);
            player.play();
            QTRY_COMPARE_WITH_TIMEOUT(player.state(), listenfree::domain::PlaybackState::Playing,
                                      3'000);
            player.stop();
            QCOMPARE(player.state(), listenfree::domain::PlaybackState::Stopped);
            player.clear();
            QCOMPARE(player.state(), listenfree::domain::PlaybackState::Idle);
        }
        // Qt Multimedia retires decoder/output workers asynchronously on Windows.
        // Compare only after the process has crossed that retirement window so
        // temporary worker handles are not mistaken for leaked handles.
        QTest::qWait(35'000);
        const quint32 handlesBefore = processHandleCount();
        for (int iteration = 0; iteration < 20; ++iteration) {
            player.open(localItem(path));
            QTRY_VERIFY_WITH_TIMEOUT(player.duration() > std::chrono::milliseconds(0), 3'000);
            player.play();
            QTRY_COMPARE_WITH_TIMEOUT(player.state(), listenfree::domain::PlaybackState::Playing,
                                      3'000);
            player.stop();
            QCOMPARE(player.state(), listenfree::domain::PlaybackState::Stopped);
            player.clear();
            QCOMPARE(player.state(), listenfree::domain::PlaybackState::Idle);
        }
        QTest::qWait(35'000);
        const quint32 handlesAfter = processHandleCount();
        qInfo().nospace() << "repeated playback handle count: " << handlesBefore << " -> "
                          << handlesAfter;
#ifdef Q_OS_WIN
        QVERIFY(handlesBefore != 0);
        QVERIFY2(handlesAfter <= handlesBefore + 3,
                 qPrintable(QStringLiteral("handle count grew from %1 to %2")
                                .arg(handlesBefore).arg(handlesAfter)));
#endif
    }
    QVERIFY2(QFile::remove(path), "repeated playback retained the generated WAV handle");
}

void PlaybackTests::repeatedConstructionAndPlaybackHasBoundedHandles() {
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    for (int iteration = 0; iteration < 20; ++iteration) {
            const QString constructionPath =
                writeWav(directory, QStringLiteral("construct-%1.wav").arg(iteration), 250);
            QVERIFY(!constructionPath.isEmpty());
            {
                listenfree::media::QtAudioPlayer constructedPlayer;
                constructedPlayer.setMuted(true);
                constructedPlayer.open(localItem(constructionPath));
                QTRY_VERIFY_WITH_TIMEOUT(constructedPlayer.duration() > std::chrono::milliseconds(0),
                                         3'000);
                constructedPlayer.play();
                QTRY_COMPARE_WITH_TIMEOUT(constructedPlayer.state(),
                                          listenfree::domain::PlaybackState::Playing, 3'000);
                constructedPlayer.stop();
                QCOMPARE(constructedPlayer.state(), listenfree::domain::PlaybackState::Stopped);
                constructedPlayer.clear();
            }
            QVERIFY(QFile::remove(constructionPath));
        }
    QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
    QTest::qWait(35'000);
    const quint32 handlesBefore = processHandleCount();
#ifdef Q_OS_WIN
    QVERIFY(handlesBefore != 0);
#endif
    for (int iteration = 0; iteration < 5; ++iteration) {
            const QString constructionPath =
                writeWav(directory, QStringLiteral("measured-construct-%1.wav").arg(iteration), 250);
            QVERIFY(!constructionPath.isEmpty());
            {
                listenfree::media::QtAudioPlayer constructedPlayer;
                constructedPlayer.setMuted(true);
                constructedPlayer.open(localItem(constructionPath));
                QTRY_VERIFY_WITH_TIMEOUT(constructedPlayer.duration() > std::chrono::milliseconds(0),
                                         3'000);
                constructedPlayer.play();
                QTRY_COMPARE_WITH_TIMEOUT(constructedPlayer.state(),
                                          listenfree::domain::PlaybackState::Playing, 3'000);
                constructedPlayer.stop();
                QCOMPARE(constructedPlayer.state(), listenfree::domain::PlaybackState::Stopped);
                constructedPlayer.clear();
            }
            QVERIFY(QFile::remove(constructionPath));
        }
    QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
    QTest::qWait(35'000);
    const quint32 handlesAfter = processHandleCount();
    qInfo().nospace() << "playback handle count: " << handlesBefore << " -> " << handlesAfter;
    if (handlesBefore != 0 && handlesAfter != 0) {
        QVERIFY2(handlesAfter <= handlesBefore + 3,
                 qPrintable(QStringLiteral("handle count grew from %1 to %2")
                                .arg(handlesBefore).arg(handlesAfter)));
    }
}

void PlaybackTests::loopbackHttpWavLoadsAndPlays() {
    LoopbackWavServer server(makePcmWav(1'200));
    QVERIFY(server.listen());

    listenfree::media::QtAudioPlayer adapter;
    listenfree::application::IAudioPlayer& player = adapter;
    QVERIFY(adapter.capabilities() & listenfree::application::capabilityMask(
                                       listenfree::application::PlaybackCapability::HttpStream));
    listenfree::domain::PlaybackItem item;
    item.track.id = listenfree::domain::TrackId("loopback-http");
    item.track.title = "Loopback HTTP";
    item.resolvedUrl = server.url().toString().toStdString();
    player.open(item);
    QTRY_VERIFY_WITH_TIMEOUT(player.duration() >= std::chrono::milliseconds(1'100), 5'000);
    player.play();
    QTRY_COMPARE_WITH_TIMEOUT(player.state(), listenfree::domain::PlaybackState::Playing, 5'000);
    QTRY_VERIFY_WITH_TIMEOUT(player.position() > std::chrono::milliseconds(100), 5'000);
    player.stop();
    QVERIFY(server.requestCount() > 0);
}

void PlaybackTests::devicesAndCapabilitiesReflectRuntimeInventory() {
    listenfree::media::QtAudioPlayer adapter;
    listenfree::application::IPlaybackBackend& backend = adapter;
    listenfree::application::IAudioDeviceService& deviceService = adapter;
    int deviceNotifications = 0;
    int capabilityNotifications = 0;
    listenfree::application::AudioDeviceEvents deviceEvents;
    deviceEvents.onDevicesChanged = [&] {
        ++deviceNotifications;
        deviceService.setDeviceEvents({});
    };
    deviceService.setDeviceEvents(std::move(deviceEvents));
    listenfree::application::PlaybackBackendEvents backendEvents;
    backendEvents.onCapabilitiesChanged = [&](std::uint32_t) {
        ++capabilityNotifications;
        backend.setBackendEvents({});
    };
    backend.setBackendEvents(std::move(backendEvents));
    deviceService.refresh();
    QCOMPARE(deviceNotifications, 1);
    QCOMPARE(capabilityNotifications, 1);
    const auto devices = deviceService.devices();
    qInfo() << "Qt audio output count:" << devices.size();
    for (const auto& device : devices) qInfo() << QString::fromStdString(device.name);

    std::set<std::string> ids;
    for (const auto& device : devices) {
        QVERIFY(!device.id.empty());
        QVERIFY(!device.name.empty());
        QVERIFY(ids.insert(device.id).second);
    }

    const auto advanced = listenfree::application::capabilityMask(
                              listenfree::application::PlaybackCapability::Equalizer) |
                          listenfree::application::capabilityMask(
                              listenfree::application::PlaybackCapability::Gapless) |
                          listenfree::application::capabilityMask(
                              listenfree::application::PlaybackCapability::Crossfade) |
                          listenfree::application::capabilityMask(
                              listenfree::application::PlaybackCapability::ReplayGain) |
                          listenfree::application::capabilityMask(
                              listenfree::application::PlaybackCapability::HighResolution);
    QCOMPARE(backend.name(), std::string_view("qt-multimedia"));
    QVERIFY(backend.available());
    const auto required = listenfree::application::capabilityMask(
                              listenfree::application::PlaybackCapability::LocalFile) |
                          listenfree::application::capabilityMask(
                              listenfree::application::PlaybackCapability::HttpStream) |
                          listenfree::application::capabilityMask(
                              listenfree::application::PlaybackCapability::Seek) |
                          listenfree::application::capabilityMask(
                              listenfree::application::PlaybackCapability::Volume) |
                          listenfree::application::capabilityMask(
                              listenfree::application::PlaybackCapability::Mute);
    QCOMPARE(backend.capabilities() & required, required);
    QCOMPARE(backend.capabilities() & advanced, 0U);
    QCOMPARE((backend.capabilities() & listenfree::application::capabilityMask(
                                          listenfree::application::PlaybackCapability::DeviceSelection)) != 0,
             !devices.empty());

    const std::string previous = deviceService.selectedDeviceId();
    QVERIFY(!deviceService.select("not-a-real-device"));
    QCOMPARE(deviceService.selectedDeviceId(), previous);
    if (!devices.empty()) {
        QVERIFY(deviceService.select(devices.front().id));
        QCOMPARE(deviceService.selectedDeviceId(), devices.front().id);
    }
}

QTEST_MAIN(PlaybackTests)
#include "playback_tests.moc"
