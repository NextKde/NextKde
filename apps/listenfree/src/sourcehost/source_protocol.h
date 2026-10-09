#pragma once

#include <QByteArray>
#include <QJsonObject>
#include <QString>
#include <QtGlobal>

namespace listenfree::sourcehost {

// LX permits one HTTP request to wait for 60 seconds. Both ends must use the
// same operation budget; the client includes a small IPC scheduling allowance.
inline constexpr int PluginOperationTimeoutMs = 60000;
inline constexpr int PluginClientTimeoutMs = PluginOperationTimeoutMs + 5000;

enum class MessageType {
    Hello,
    HelloAck,
    LoadPlugin,
    UnloadPlugin,
    Initialize,
    ResolveMusicUrl,
    ResolveLyric,
    ResolvePic,
    Search,
    GetPlaylist,
    GetChart,
    Cancel,
    Result,
    Error,
    Log,
    UpdateAlert,
    Shutdown
};

struct SourceMessage {
    int protocolVersion{1};
    MessageType type{MessageType::Error};
    QString requestId;
    QJsonObject payload;
};

class SourceProtocol final {
public:
    // Keep request identifiers bounded on both sides of the pipe so a
    // diagnostic response can always fit in the framed protocol envelope.
    static constexpr qsizetype MaxRequestIdBytes = 256 * 1024;
    static QByteArray encode(const SourceMessage& message);
    static bool decode(const QByteArray& frame, SourceMessage& message, QString* error = nullptr);
    static QString typeName(MessageType type);
    static bool typeFromName(const QString& name, MessageType& type);
};

} // namespace listenfree::sourcehost
