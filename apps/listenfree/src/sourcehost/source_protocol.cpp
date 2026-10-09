#include "sourcehost/source_protocol.h"

#include <QDataStream>
#include <QIODevice>
#include <QJsonDocument>
#include <QJsonValue>

namespace listenfree::sourcehost {

QString SourceProtocol::typeName(MessageType type) {
    switch (type) {
    case MessageType::Hello: return QStringLiteral("hello");
    case MessageType::HelloAck: return QStringLiteral("helloAck");
    case MessageType::LoadPlugin: return QStringLiteral("loadPlugin");
    case MessageType::UnloadPlugin: return QStringLiteral("unloadPlugin");
    case MessageType::Initialize: return QStringLiteral("initialize");
    case MessageType::ResolveMusicUrl: return QStringLiteral("resolveMusicUrl");
    case MessageType::ResolveLyric: return QStringLiteral("resolveLyric");
    case MessageType::ResolvePic: return QStringLiteral("resolvePic");
    case MessageType::Search: return QStringLiteral("search");
    case MessageType::GetPlaylist: return QStringLiteral("getPlaylist");
    case MessageType::GetChart: return QStringLiteral("getChart");
    case MessageType::Cancel: return QStringLiteral("cancel");
    case MessageType::Result: return QStringLiteral("result");
    case MessageType::Error: return QStringLiteral("error");
    case MessageType::Log: return QStringLiteral("log");
    case MessageType::UpdateAlert: return QStringLiteral("updateAlert");
    case MessageType::Shutdown: return QStringLiteral("shutdown");
    }
    return QStringLiteral("error");
}

bool SourceProtocol::typeFromName(const QString& name, MessageType& type) {
    const QList<MessageType> types{
        MessageType::Hello, MessageType::HelloAck, MessageType::LoadPlugin, MessageType::UnloadPlugin,
        MessageType::Initialize, MessageType::ResolveMusicUrl, MessageType::ResolveLyric, MessageType::ResolvePic,
        MessageType::Search, MessageType::GetPlaylist,
        MessageType::GetChart, MessageType::Cancel, MessageType::Result, MessageType::Error, MessageType::Log,
        MessageType::UpdateAlert, MessageType::Shutdown};
    for (const auto candidate : types) {
        if (typeName(candidate) == name) {
            type = candidate;
            return true;
        }
    }
    return false;
}

QByteArray SourceProtocol::encode(const SourceMessage& message) {
    QJsonObject object;
    object.insert(QStringLiteral("protocolVersion"), message.protocolVersion);
    object.insert(QStringLiteral("messageType"), typeName(message.type));
    object.insert(QStringLiteral("requestId"), message.requestId);
    object.insert(QStringLiteral("payload"), message.payload);
    const QByteArray body = QJsonDocument(object).toJson(QJsonDocument::Compact);
    QByteArray frame;
    QDataStream stream(&frame, QIODevice::WriteOnly);
    stream.setByteOrder(QDataStream::BigEndian);
    stream << static_cast<quint32>(body.size());
    frame.append(body);
    return frame;
}

bool SourceProtocol::decode(const QByteArray& frame, SourceMessage& message, QString* error) {
    auto fail = [error](const QString& reason) {
        if (error) *error = reason;
        return false;
    };
    if (frame.size() < 4) return fail(QStringLiteral("frame-too-short"));
    QDataStream stream(frame.left(4));
    stream.setByteOrder(QDataStream::BigEndian);
    quint32 size = 0;
    stream >> size;
    if (size == 0 || size > 1024U * 1024U) return fail(QStringLiteral("invalid-frame-size"));
    if (frame.size() != static_cast<qsizetype>(size) + 4) return fail(QStringLiteral("incomplete-frame"));
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(frame.mid(4), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) return fail(QStringLiteral("invalid-json"));
    const QJsonObject object = document.object();
    if (!object.value(QStringLiteral("protocolVersion")).isDouble() ||
        !object.value(QStringLiteral("messageType")).isString() ||
        !object.value(QStringLiteral("requestId")).isString() ||
        !object.value(QStringLiteral("payload")).isObject()) {
        return fail(QStringLiteral("invalid-envelope"));
    }
    const double protocolVersion = object.value(QStringLiteral("protocolVersion")).toDouble();
    if (protocolVersion != 1.0) return fail(QStringLiteral("unsupported-protocol-version"));
    const QString requestId = object.value(QStringLiteral("requestId")).toString();
    if (requestId.toUtf8().size() > SourceProtocol::MaxRequestIdBytes) {
        return fail(QStringLiteral("request-id-too-large"));
    }
    MessageType type;
    if (!typeFromName(object.value(QStringLiteral("messageType")).toString(), type)) return fail(QStringLiteral("unknown-message-type"));
    message.protocolVersion = 1;
    message.type = type;
    message.requestId = requestId;
    message.payload = object.value(QStringLiteral("payload")).toObject();
    return true;
}

} // namespace listenfree::sourcehost
