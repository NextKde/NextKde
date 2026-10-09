#include "sourcehost/source_protocol.h"
#include "sourcehost/plugin_runtime.h"

#include <QCoreApplication>
#include <QMetaObject>
#include <QThread>

#include <array>
#include <functional>
#include <iostream>
#include <utility>

#ifdef Q_OS_WIN
#include <fcntl.h>
#include <io.h>
#endif

namespace {

constexpr qsizetype MaxProtocolFrameBytes = 1024 * 1024 + 4;

void writeResponse(listenfree::sourcehost::SourceMessage response) {
    QByteArray encoded = listenfree::sourcehost::SourceProtocol::encode(response);
    if (encoded.size() > MaxProtocolFrameBytes) {
        response.type = listenfree::sourcehost::MessageType::Error;
        response.payload = {
            {QStringLiteral("code"), QStringLiteral("plugin.response-too-large")},
            {QStringLiteral("message"),
             QStringLiteral("Plugin response exceeds the 1 MiB protocol limit.")},
        };
        encoded = listenfree::sourcehost::SourceProtocol::encode(response);
    }
    if (encoded.size() > MaxProtocolFrameBytes) return;
    std::cout.write(encoded.constData(), static_cast<std::streamsize>(encoded.size()));
    std::cout.flush();
}

class StdinReader final : public QThread {
public:
    using Handler = std::function<void(QByteArray)>;

    explicit StdinReader(Handler handler) : handler_(std::move(handler)) {}

protected:
    void run() override {
        bool shutdownReceived = false;
        while (!isInterruptionRequested()) {
            std::array<char, 4> header{};
            std::cin.read(header.data(), static_cast<std::streamsize>(header.size()));
            if (std::cin.gcount() != static_cast<std::streamsize>(header.size())) break;
            QByteArray frame(header.data(), static_cast<qsizetype>(header.size()));
            const auto* bytes = reinterpret_cast<const unsigned char*>(header.data());
            const quint32 bodySize = (static_cast<quint32>(bytes[0]) << 24U) |
                                     (static_cast<quint32>(bytes[1]) << 16U) |
                                     (static_cast<quint32>(bytes[2]) << 8U) |
                                     static_cast<quint32>(bytes[3]);
            if (bodySize == 0 || bodySize > 1024U * 1024U) break;
            QByteArray body(static_cast<qsizetype>(bodySize), Qt::Uninitialized);
            std::cin.read(body.data(), static_cast<std::streamsize>(body.size()));
            if (std::cin.gcount() != static_cast<std::streamsize>(body.size())) break;
            frame.append(body);
            const auto handler = handler_;
            QMetaObject::invokeMethod(QCoreApplication::instance(), [handler, frame] { handler(frame); },
                                      Qt::BlockingQueuedConnection);

            listenfree::sourcehost::SourceMessage message;
            if (listenfree::sourcehost::SourceProtocol::decode(frame, message) &&
                message.type == listenfree::sourcehost::MessageType::Shutdown) {
                shutdownReceived = true;
                break;
            }
        }
        if (!shutdownReceived && !isInterruptionRequested()) {
            QMetaObject::invokeMethod(QCoreApplication::instance(), [] { QCoreApplication::exit(3); },
                                      Qt::QueuedConnection);
        }
    }

private:
    Handler handler_;
};

} // namespace

int main(int argc, char* argv[]) {
#ifdef Q_OS_WIN
    // The four-byte frame length is binary. Text mode treats 0x1A as EOF
    // and translates CR/LF, corrupting otherwise valid requests/responses.
    if (_setmode(_fileno(stdin), _O_BINARY) == -1 ||
        _setmode(_fileno(stdout), _O_BINARY) == -1)
        return 4;
#endif
    QCoreApplication app(argc, argv);
    listenfree::sourcehost::PluginRuntime pluginRuntime;
    QObject::connect(&pluginRuntime, &listenfree::sourcehost::PluginRuntime::responseReady, &app,
                     [](const listenfree::sourcehost::SourceMessage& response) {
                         writeResponse(response);
                     });

    StdinReader reader([&app, &pluginRuntime](QByteArray frame) {
        listenfree::sourcehost::SourceMessage request;
        QString error;
        if (!listenfree::sourcehost::SourceProtocol::decode(frame, request, &error)) return;
        if (request.type == listenfree::sourcehost::MessageType::Shutdown) {
            app.quit();
            return;
        }
        if (request.type == listenfree::sourcehost::MessageType::LoadPlugin ||
            request.type == listenfree::sourcehost::MessageType::UnloadPlugin ||
            request.type == listenfree::sourcehost::MessageType::Initialize ||
            request.type == listenfree::sourcehost::MessageType::ResolveMusicUrl ||
            request.type == listenfree::sourcehost::MessageType::ResolveLyric ||
            request.type == listenfree::sourcehost::MessageType::ResolvePic ||
            request.type == listenfree::sourcehost::MessageType::Cancel) {
            pluginRuntime.handle(request);
            return;
        }
        listenfree::sourcehost::SourceMessage response;
        response.type = request.type == listenfree::sourcehost::MessageType::Hello
                            ? listenfree::sourcehost::MessageType::HelloAck
                            : listenfree::sourcehost::MessageType::Result;
        response.requestId = request.requestId;
        response.payload.insert(QStringLiteral("ok"), true);
        response.payload.insert(QStringLiteral("messageType"),
                                listenfree::sourcehost::SourceProtocol::typeName(request.type));
        writeResponse(std::move(response));
    });
    reader.start();
    const int exitCode = app.exec();
    reader.requestInterruption();
    reader.wait();
    return exitCode;
}
