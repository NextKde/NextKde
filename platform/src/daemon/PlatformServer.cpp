#include "PlatformServer.h"
#include "../kwin/KWinBridge.h"

#include <QClipboard>
#include <QCoreApplication>
#include <QDBusInterface>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QMimeData>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QUrl>

#include <algorithm>
#include <functional>

namespace KosPlatform {
namespace {

constexpr int kProtocolVersion = 1;
constexpr auto kClipboardCutMime = "application/x-kde-cutselection";
constexpr auto kGnomeFilesMime = "x-special/gnome-copied-files";

QString runtimeSocketPath()
{
    const QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (!runtime.isEmpty())
        return runtime + QStringLiteral("/kos-platform.sock");
    return QDir::tempPath() + QStringLiteral("/kos-platform-")
        + QString::number(QCoreApplication::applicationPid()) + QStringLiteral(".sock");
}

QJsonObject errorObject(const QString &code, const QString &message, bool retryable)
{
    return QJsonObject{{QStringLiteral("code"), code},
                       {QStringLiteral("message"), message},
                       {QStringLiteral("retryable"), retryable}};
}

QString cleanPath(const QString &path)
{
    if (path.isEmpty())
        return {};
    const QFileInfo info(path);
    return info.isAbsolute() ? info.absoluteFilePath() : QString{};
}

QString resolveDesktopFile(const QString &id)
{
    if (id.isEmpty() || id.contains(QChar('/')))
        return {};
    if (QFileInfo(id).isAbsolute() && QFileInfo(id).isFile())
        return QFileInfo(id).absoluteFilePath();
    const QStringList roots = QStandardPaths::standardLocations(QStandardPaths::ApplicationsLocation);
    for (const QString &root : roots) {
        const QString candidate = QDir(root).filePath(id);
        if (QFileInfo(candidate).isFile())
            return QFileInfo(candidate).absoluteFilePath();
    }
    return {};
}

QStringList cleanPaths(const QJsonValue &value)
{
    QStringList paths;
    QSet<QString> seen;
    for (const QJsonValue &item : value.toArray()) {
        const QString path = cleanPath(item.toString());
        if (!path.isEmpty() && !seen.contains(path)) {
            seen.insert(path);
            paths.append(path);
        }
    }
    return paths;
}

QJsonArray jsonPaths(const QStringList &paths)
{
    QJsonArray values;
    for (const QString &path : paths)
        values.append(path);
    return values;
}

QJsonObject parseOutput(const QByteArray &output, int exitCode)
{
    return QJsonObject{{QStringLiteral("exitCode"), exitCode},
                       {QStringLiteral("stdout"), QString::fromUtf8(output)}};
}

QStringList splitNmcli(const QString &line)
{
    QStringList fields;
    QString value;
    bool escaped = false;
    for (const QChar c : line) {
        if (escaped) {
            value += c;
            escaped = false;
        } else if (c == QChar('\\')) {
            escaped = true;
        } else if (c == QChar(':')) {
            fields.append(value);
            value.clear();
        } else {
            value += c;
        }
    }
    fields.append(value);
    return fields;
}

QJsonObject parseNetworkRefresh(const QByteArray &output, int exitCode)
{
    if (exitCode != 0)
        return QJsonObject{{QStringLiteral("available"), false}};
    const QStringList sections = QString::fromUtf8(output).split(QChar(0x1e));
    const QStringList general = splitNmcli(sections.value(0).trimmed());
    QJsonObject result{{QStringLiteral("available"), general.value(0) == QStringLiteral("running")},
                       {QStringLiteral("networkingEnabled"), general.value(0) == QStringLiteral("running")},
                       {QStringLiteral("connectivity"), general.value(2, QStringLiteral("unknown"))},
                       {QStringLiteral("wifiEnabled"), general.value(3).toLower() != QStringLiteral("disabled")}};
    QJsonObject selected;
    for (const QString &row : sections.value(1).trimmed().split(QChar('\n'), Qt::SkipEmptyParts)) {
        const QStringList fields = splitNmcli(row);
        if (fields.size() < 3 || (fields.value(1) != QStringLiteral("wifi")
            && fields.value(1) != QStringLiteral("ethernet")))
            continue;
        QJsonObject candidate{{QStringLiteral("device"), fields.value(0)},
                              {QStringLiteral("type"), fields.value(1)},
                              {QStringLiteral("state"), fields.value(2)},
                              {QStringLiteral("connection"), fields.value(3) == QStringLiteral("--") ? QString() : fields.mid(3).join(QStringLiteral(":"))}};
        if (selected.isEmpty() || fields.value(2) == QStringLiteral("connected"))
            selected = candidate;
        if (fields.value(2) == QStringLiteral("connected"))
            break;
    }
    const QString type = selected.value(QStringLiteral("type")).toString();
    const QString state = selected.value(QStringLiteral("state")).toString().toLower();
    result.insert(QStringLiteral("connectionType"), type.isEmpty() ? QStringLiteral("none") : type);
    result.insert(QStringLiteral("deviceName"), selected.value(QStringLiteral("device")));
    result.insert(QStringLiteral("connectionName"), selected.value(QStringLiteral("connection")));
    result.insert(QStringLiteral("deviceState"), state == QStringLiteral("connected") ? QStringLiteral("connected")
                  : state.contains(QStringLiteral("connect")) ? QStringLiteral("connecting")
                  : state == QStringLiteral("disconnected") ? QStringLiteral("disconnected")
                  : QStringLiteral("unknown"));
    result.insert(QStringLiteral("ssid"), type == QStringLiteral("wifi") && state == QStringLiteral("connected")
                  ? selected.value(QStringLiteral("connection")) : QString());
    result.insert(QStringLiteral("signalStrength"), -1);
    result.insert(QStringLiteral("ipv4"), QString());
    return result;
}

QJsonObject parseAudio(const QByteArray &output, int exitCode)
{
    const QString text = QString::fromUtf8(output);
    const QRegularExpression match(QStringLiteral("Volume:\\s*([0-9.]+)"));
    const auto m = match.match(text);
    if (exitCode != 0 || !m.hasMatch())
        return QJsonObject{{QStringLiteral("available"), false}};
    const double value = qBound(0.0, m.captured(1).toDouble(), 1.5);
    return QJsonObject{{QStringLiteral("available"), true},
                       {QStringLiteral("percent"), qRound(value * 100.0)},
                       {QStringLiteral("muted"), text.contains(QStringLiteral("[MUTED]"))}};
}

QJsonObject parseNetworkScan(const QByteArray &output, int exitCode)
{
    QJsonArray networks;
    if (exitCode == 0) {
        QHash<QString, QJsonObject> bySsid;
        for (const QString &line : QString::fromUtf8(output).split(QChar('\n'), Qt::SkipEmptyParts)) {
            const QStringList fields = splitNmcli(line);
            if (fields.size() < 4)
                continue;
            const QString ssid = fields.value(1).trimmed();
            if (ssid.isEmpty())
                continue;
            const int signal = qBound(0, fields.value(2).toInt(), 100);
            QJsonObject item{{QStringLiteral("ssid"), ssid},
                             {QStringLiteral("signalStrength"), signal},
                             {QStringLiteral("security"), fields.mid(3).join(QStringLiteral(":"))},
                             {QStringLiteral("secured"), !fields.mid(3).join(QStringLiteral(":")).trimmed().isEmpty()},
                             {QStringLiteral("enterprise"), fields.mid(3).join(QStringLiteral(":")).contains(QStringLiteral("802.1x"), Qt::CaseInsensitive)},
                             {QStringLiteral("active"), fields.value(0).trimmed() == QStringLiteral("*")}};
            if (!bySsid.contains(ssid) || item.value(QStringLiteral("signalStrength")).toInt()
                    > bySsid.value(ssid).value(QStringLiteral("signalStrength")).toInt())
                bySsid.insert(ssid, item);
        }
        QList<QJsonObject> sorted;
        sorted.reserve(bySsid.size());
        for (const auto &item : bySsid)
            sorted.append(item);
        std::sort(sorted.begin(), sorted.end(), [](const QJsonObject &left,
                                                   const QJsonObject &right) {
            const bool leftActive = left.value(QStringLiteral("active")).toBool();
            const bool rightActive = right.value(QStringLiteral("active")).toBool();
            if (leftActive != rightActive)
                return leftActive;
            const int leftSignal = left.value(QStringLiteral("signalStrength")).toInt();
            const int rightSignal = right.value(QStringLiteral("signalStrength")).toInt();
            if (leftSignal != rightSignal)
                return leftSignal > rightSignal;
            return left.value(QStringLiteral("ssid")).toString()
                < right.value(QStringLiteral("ssid")).toString();
        });
        for (const auto &item : sorted)
            networks.append(item);
    }
    return QJsonObject{{QStringLiteral("available"), exitCode == 0},
                       {QStringLiteral("networks"), networks}};
}

QHash<QString, QString> parseSavedWifiProfiles(const QByteArray &output, int exitCode)
{
    QHash<QString, QString> profiles;
    if (exitCode != 0)
        return profiles;
    for (const QString &line : QString::fromUtf8(output).split(QChar('\n'), Qt::SkipEmptyParts)) {
        const QStringList fields = splitNmcli(line);
        if (fields.size() < 3 || fields.value(1) != QStringLiteral("802-11-wireless"))
            continue;
        const QString uuid = fields.value(0).trimmed();
        const QString ssid = fields.mid(2).join(QStringLiteral(":"));
        if (!uuid.isEmpty() && !ssid.isEmpty() && !profiles.contains(ssid))
            profiles.insert(ssid, uuid);
    }
    return profiles;
}

QJsonObject parseNetworkDetails(const QByteArray &output, int exitCode)
{
    if (exitCode != 0)
        return QJsonObject{{QStringLiteral("available"), false}};
    const QStringList rows = QString::fromUtf8(output).trimmed()
                                 .split(QChar('\n'), Qt::KeepEmptyParts);
    QString connection = rows.value(0).trimmed();
    if (connection == QStringLiteral("--"))
        connection.clear();
    QString ipv4 = rows.value(1).trimmed();
    const qsizetype slash = ipv4.indexOf(QChar('/'));
    if (slash >= 0)
        ipv4.truncate(slash);
    return QJsonObject{{QStringLiteral("available"), true},
                       {QStringLiteral("connectionName"), connection},
                       {QStringLiteral("ssid"), connection},
                       {QStringLiteral("ipv4"), ipv4}};
}

QJsonObject parseBluetooth(const QByteArray &output, int exitCode)
{
    const QString text = QString::fromUtf8(output);
    const QRegularExpression powered(QStringLiteral("Powered:\\s*(yes|no)"),
                                     QRegularExpression::CaseInsensitiveOption);
    const auto powerMatch = powered.match(text);
    QJsonArray devices;
    for (const QString &line : text.split(QChar('\n'), Qt::SkipEmptyParts)) {
        const auto match = QRegularExpression(QStringLiteral("^Device\\s+(\\S+)\\s+(.+)$")).match(line.trimmed());
        if (match.hasMatch())
            devices.append(QJsonObject{{QStringLiteral("address"), match.captured(1)},
                                       {QStringLiteral("name"), match.captured(2)},
                                       {QStringLiteral("paired"), true},
                                       {QStringLiteral("connected"), false}});
    }
    return QJsonObject{{QStringLiteral("available"), exitCode == 0 && powerMatch.hasMatch()},
                       {QStringLiteral("powered"), powerMatch.hasMatch() && powerMatch.captured(1).toLower() == QStringLiteral("yes")},
                       {QStringLiteral("devices"), devices}};
}

QJsonObject parseBrightness(const QByteArray &output, int exitCode)
{
    if (exitCode != 0)
        return QJsonObject{{QStringLiteral("available"), false}};
    const QString text = QString::fromUtf8(output).trimmed();
    // brightnessctl -m: device,class,current,max,percentage
    const QStringList fields = text.split(QChar(','));
    if (fields.size() >= 5) {
        const auto match = QRegularExpression(QStringLiteral("(\\d+)%")).match(fields.at(4));
        if (match.hasMatch())
            return QJsonObject{{QStringLiteral("available"), true},
                               {QStringLiteral("percent"), match.captured(1).toInt()},
                               {QStringLiteral("device"), fields.at(0)}};
    }
    return QJsonObject{{QStringLiteral("available"), false}};
}

QString uniquePath(const QString &destination, const QString &baseName)
{
    QString candidate = QDir(destination).filePath(baseName);
    if (!QFileInfo::exists(candidate))
        return candidate;
    const QFileInfo sourceInfo(baseName);
    const QString suffix = sourceInfo.suffix();
    const QString stem = suffix.isEmpty() ? baseName
                                          : baseName.left(baseName.size() - suffix.size() - 1);
    for (int index = 1; index < 10000; ++index) {
        const QString copyName = suffix.isEmpty()
            ? QStringLiteral("%1 (copy %2)").arg(stem).arg(index)
            : QStringLiteral("%1 (copy %2).%3").arg(stem).arg(index).arg(suffix);
        candidate = QDir(destination).filePath(copyName);
        if (!QFileInfo::exists(candidate))
            return candidate;
    }
    return {};
}

bool copyRecursively(const QString &source, const QString &target)
{
    const QFileInfo info(source);
    if (info.isDir()) {
        if (!QDir().mkpath(target))
            return false;
        QDirIterator iterator(source, QDir::NoDotAndDotDot | QDir::AllEntries);
        while (iterator.hasNext()) {
            iterator.next();
            const QString childTarget = QDir(target).filePath(iterator.fileName());
            if (!copyRecursively(iterator.filePath(), childTarget))
                return false;
        }
        return true;
    }
    return QFile::copy(source, target);
}

bool moveOrCopy(const QString &source, const QString &destination, bool move)
{
    const QFileInfo sourceInfo(source);
    if (!sourceInfo.exists())
        return false;
    if (sourceInfo.isDir() && destination.startsWith(sourceInfo.absoluteFilePath() + QDir::separator()))
        return false;
    if (move && QFile::rename(source, destination))
        return true;
    if (!copyRecursively(source, destination))
        return false;
    if (!move)
        return true;
    return sourceInfo.isDir() ? QDir(source).removeRecursively() : QFile::remove(source);
}

QString mimeOperation(const QMimeData *mime)
{
    if (mime->hasFormat(QString::fromLatin1(kClipboardCutMime))
        && mime->data(QString::fromLatin1(kClipboardCutMime)).trimmed() == "1")
        return QStringLiteral("cut");
    if (mime->hasFormat(QString::fromLatin1(kGnomeFilesMime))) {
        const QByteArray first = mime->data(QString::fromLatin1(kGnomeFilesMime))
                                     .split('\n').value(0).trimmed();
        if (first == "cut")
            return QStringLiteral("cut");
    }
    return QStringLiteral("copy");
}

QStringList localClipboardPaths(const QMimeData *mime)
{
    QStringList result;
    QSet<QString> seen;
    const auto append = [&result, &seen](const QUrl &url) {
        if (!url.isLocalFile())
            return;
        const QString path = cleanPath(url.toLocalFile());
        if (!path.isEmpty() && !seen.contains(path)) {
            seen.insert(path);
            result.append(path);
        }
    };
    for (const QUrl &url : mime->urls())
        append(url);
    if (result.isEmpty() && mime->hasFormat(QStringLiteral("text/uri-list"))) {
        for (QByteArray line : mime->data(QStringLiteral("text/uri-list")).split('\n')) {
            line = line.trimmed();
            if (!line.isEmpty() && !line.startsWith('#'))
                append(QUrl::fromEncoded(line));
        }
    }
    if (result.isEmpty() && mime->hasFormat(QString::fromLatin1(kGnomeFilesMime))) {
        const QList<QByteArray> lines = mime->data(QString::fromLatin1(kGnomeFilesMime))
                                            .split('\n');
        for (qsizetype i = 1; i < lines.size(); ++i)
            append(QUrl::fromEncoded(lines.at(i).trimmed()));
    }
    return result;
}

} // namespace

PlatformServer::PlatformServer(QObject *parent)
    : QObject(parent), m_socketPath(runtimeSocketPath())
{
    connect(&m_server, &QLocalServer::newConnection,
            this, &PlatformServer::acceptConnections);
}

bool PlatformServer::listen()
{
    QLocalServer::removeServer(m_socketPath);
    if (!m_server.listen(m_socketPath)) {
        qWarning() << "Unable to listen on" << m_socketPath << m_server.errorString();
        return false;
    }
    // QLocalServer follows the platform's default umask, which is commonly
    // 0666.  The platform socket carries clipboard paths and power controls,
    // so it must never be readable by another local user.
    QFile::setPermissions(m_socketPath, QFileDevice::ReadOwner
        | QFileDevice::WriteOwner);
    return true;
}

void PlatformServer::acceptConnections()
{
    while (m_server.hasPendingConnections()) {
        auto *socket = m_server.nextPendingConnection();
        m_buffers.insert(socket, {});
        connect(socket, &QLocalSocket::readyRead, this, &PlatformServer::readClient);
        connect(socket, &QLocalSocket::disconnected, this, &PlatformServer::clientDisconnected);
    }
}

void PlatformServer::readClient()
{
    auto *socket = qobject_cast<QLocalSocket *>(sender());
    if (!socket)
        return;
    QByteArray &buffer = m_buffers[socket];
    buffer.append(socket->readAll());
    while (true) {
        const qsizetype newline = buffer.indexOf('\n');
        if (newline < 0)
            break;
        const QByteArray line = buffer.left(newline).trimmed();
        buffer.remove(0, newline + 1);
        if (line.isEmpty())
            continue;
        QJsonParseError error;
        const QJsonDocument document = QJsonDocument::fromJson(line, &error);
        if (error.error != QJsonParseError::NoError || !document.isObject()) {
            QJsonObject response{{QStringLiteral("version"), kProtocolVersion},
                                  {QStringLiteral("ok"), false},
                                  {QStringLiteral("error"), errorObject(
                                       QStringLiteral("invalid-json"),
                                       QStringLiteral("请求不是有效 JSON"), false)}};
            socket->write(QJsonDocument(response).toJson(QJsonDocument::Compact) + '\n');
            socket->flush();
            continue;
        }
        handleRequest(socket, document.object());
    }
}

void PlatformServer::clientDisconnected()
{
    auto *socket = qobject_cast<QLocalSocket *>(sender());
    if (!socket)
        return;
    m_windowSubscribers.remove(socket);
    m_buffers.remove(socket);
    socket->deleteLater();
}

QString PlatformServer::requestId(const QJsonObject &request) const
{
    return request.value(QStringLiteral("requestId")).toString();
}

QString PlatformServer::operation(const QJsonObject &request) const
{
    return request.value(QStringLiteral("operation")).toString();
}

void PlatformServer::respond(QLocalSocket *socket, const QJsonObject &request,
                              bool ok, const QJsonObject &result,
                              const QString &code, const QString &message,
                              bool retryable)
{
    if (!socket || socket->state() != QLocalSocket::ConnectedState)
        return;
    QJsonObject response{{QStringLiteral("version"), kProtocolVersion},
                         {QStringLiteral("requestId"), requestId(request)},
                         {QStringLiteral("ok"), ok}};
    if (ok)
        response.insert(QStringLiteral("result"), result);
    else
        response.insert(QStringLiteral("error"), errorObject(code, message, retryable));
    socket->write(QJsonDocument(response).toJson(QJsonDocument::Compact) + '\n');
    socket->flush();
}

void PlatformServer::sendEvent(QLocalSocket *socket, const QJsonObject &event)
{
    if (!socket || socket->state() != QLocalSocket::ConnectedState)
        return;
    QString eventName = event.value(QStringLiteral("type")).toString();
    if (eventName == QStringLiteral("snapshot"))
        eventName = QStringLiteral("window.snapshot");
    else if (eventName == QStringLiteral("action"))
        eventName = QStringLiteral("window.action");
    QJsonObject message{{QStringLiteral("version"), kProtocolVersion},
                        {QStringLiteral("event"), eventName},
                        {QStringLiteral("payload"), event}};
    socket->write(QJsonDocument(message).toJson(QJsonDocument::Compact) + '\n');
    socket->flush();
}

void PlatformServer::broadcastKWinEvent(const QJsonObject &event)
{
    for (auto *socket : std::as_const(m_windowSubscribers))
        sendEvent(socket, event);
}

void PlatformServer::runCommand(QLocalSocket *socket, const QJsonObject &request,
                                const QString &program, const QStringList &arguments,
                                std::function<QJsonObject(const QByteArray &, int)> parser)
{
    auto *process = new QProcess(this);
    process->setProgram(program);
    process->setArguments(arguments);
    connect(process, &QProcess::finished, this,
            [this, socket, request, process, parser](int exitCode,
                                                      QProcess::ExitStatus) {
        const QByteArray output = process->readAllStandardOutput();
        const QByteArray error = process->readAllStandardError();
        if (exitCode == 0) {
            respond(socket, request, true,
                    parser ? parser(output, exitCode) : parseOutput(output, exitCode));
        } else {
            Q_UNUSED(error);
            respond(socket, request, false, {}, QStringLiteral("command-failed"),
                    QStringLiteral("平台命令执行失败"), true);
        }
        process->deleteLater();
    });
    process->start();
}

bool PlatformServer::handleClipboard(QLocalSocket *socket, const QJsonObject &request)
{
    const QString op = operation(request);
    QClipboard *clipboard = QGuiApplication::clipboard();
    if (!clipboard) {
        respond(socket, request, false, {}, QStringLiteral("clipboard-unavailable"),
                QStringLiteral("剪贴板不可用"), true);
        return true;
    }
    if (op == QStringLiteral("clipboard.set")) {
        const QString mode = request.value(QStringLiteral("payload")).toObject()
                                 .value(QStringLiteral("mode")).toString();
        const QStringList paths = cleanPaths(request.value(QStringLiteral("payload"))
                                                  .toObject().value(QStringLiteral("paths")));
        if ((mode != QStringLiteral("copy") && mode != QStringLiteral("cut"))
            || paths.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-clipboard-request"),
                    QStringLiteral("剪贴板请求无效"), false);
            return true;
        }
        auto *mime = new QMimeData;
        QList<QUrl> urls;
        for (const QString &path : paths)
            urls.append(QUrl::fromLocalFile(path));
        mime->setUrls(urls);
        mime->setData(QString::fromLatin1(kClipboardCutMime), mode == QStringLiteral("cut") ? "1" : "0");
        QByteArray gnome = mode.toUtf8();
        for (const QUrl &url : urls) {
            gnome.append('\n');
            gnome.append(url.toEncoded());
        }
        mime->setData(QString::fromLatin1(kGnomeFilesMime), gnome);
        clipboard->setMimeData(mime, QClipboard::Clipboard);
        if (!clipboard->ownsClipboard()) {
            respond(socket, request, false, {}, QStringLiteral("clipboard-not-owned"),
                    QStringLiteral("无法取得剪贴板所有权"), true);
            return true;
        }
        respond(socket, request, true,
                QJsonObject{{QStringLiteral("mode"), mode},
                            {QStringLiteral("paths"), jsonPaths(paths)}});
        return true;
    }
    if (op == QStringLiteral("clipboard.read")) {
        const QMimeData *mime = clipboard->mimeData(QClipboard::Clipboard);
        if (!mime) {
            respond(socket, request, false, {}, QStringLiteral("clipboard-unavailable"),
                    QStringLiteral("剪贴板不可用"), true);
            return true;
        }
        respond(socket, request, true,
                QJsonObject{{QStringLiteral("mode"), mimeOperation(mime)},
                            {QStringLiteral("paths"), jsonPaths(localClipboardPaths(mime))}});
        return true;
    }
    return false;
}

bool PlatformServer::handleFileOperation(QLocalSocket *socket, const QJsonObject &request)
{
    const QString op = operation(request);
    const QJsonObject payload = request.value(QStringLiteral("payload")).toObject();
    if (op == QStringLiteral("file.open")) {
        const QString path = cleanPath(payload.value(QStringLiteral("path")).toString());
        if (path.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-path"), QStringLiteral("文件路径无效"), false);
            return true;
        }
        runCommand(socket, request, QStringLiteral("xdg-open"), {path});
        return true;
    }
    if (op == QStringLiteral("file.launch")) {
        const QString desktop = resolveDesktopFile(payload.value(QStringLiteral("desktopFile")).toString());
        const QString target = cleanPath(payload.value(QStringLiteral("path")).toString());
        if (desktop.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-desktop-file"),
                    QStringLiteral("启动器不存在"), false);
            return true;
        }
        if (target.isEmpty() && payload.contains(QStringLiteral("path"))) {
            respond(socket, request, false, {}, QStringLiteral("invalid-path"), QStringLiteral("文件路径无效"), false);
            return true;
        }
        QStringList args{QStringLiteral("launch"), desktop};
        if (!target.isEmpty())
            args.append(target);
        runCommand(socket, request, QStringLiteral("gio"), args);
        return true;
    }
    if (op == QStringLiteral("file.trash")) {
        const QStringList paths = cleanPaths(payload.value(QStringLiteral("paths")));
        if (paths.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-path"), QStringLiteral("文件路径无效"), false);
            return true;
        }
        runCommand(socket, request, QStringLiteral("gio"), QStringList{QStringLiteral("trash")} + paths);
        return true;
    }
    if (op == QStringLiteral("file.rename")) {
        const QString source = cleanPath(payload.value(QStringLiteral("source")).toString());
        const QString target = cleanPath(payload.value(QStringLiteral("target")).toString());
        if (source.isEmpty() || target.isEmpty() || QFileInfo::exists(target)) {
            respond(socket, request, false, {}, QStringLiteral("target-exists"), QStringLiteral("目标文件已存在或路径无效"), false);
            return true;
        }
        if (QFile::rename(source, target))
            respond(socket, request, true, QJsonObject{{QStringLiteral("path"), target}});
        else
            respond(socket, request, false, {}, QStringLiteral("rename-failed"), QStringLiteral("重命名失败"), true);
        return true;
    }
    if (op == QStringLiteral("file.create-folder") || op == QStringLiteral("file.create-file")) {
        const QString directory = cleanPath(payload.value(QStringLiteral("directory")).toString());
        if (directory.isEmpty() || !QFileInfo(directory).isDir()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-path"), QStringLiteral("文件路径无效"), false);
            return true;
        }
        const QString baseName = op.endsWith(QStringLiteral("folder"))
            ? QStringLiteral("untitled folder") : QStringLiteral("untitled file.txt");
        QString path = uniquePath(directory, baseName);
        const bool ok = path.isEmpty() ? false
            : (op.endsWith(QStringLiteral("folder")) ? QDir().mkpath(path)
               : [&path] { QFile file(path); return file.open(QIODevice::WriteOnly); }());
        if (ok)
            respond(socket, request, true, QJsonObject{{QStringLiteral("path"), path}});
        else
            respond(socket, request, false, {}, QStringLiteral("create-failed"), QStringLiteral("创建失败"), true);
        return true;
    }
    if (op == QStringLiteral("file.transfer")) {
        const QString destination = cleanPath(payload.value(QStringLiteral("destination")).toString());
        const QString mode = payload.value(QStringLiteral("mode")).toString();
        const bool move = mode == QStringLiteral("move");
        const QStringList paths = cleanPaths(payload.value(QStringLiteral("paths")));
        if (destination.isEmpty() || paths.isEmpty()
            || (mode != QStringLiteral("copy") && !move)) {
            respond(socket, request, false, {}, QStringLiteral("invalid-transfer"),
                    QStringLiteral("文件传输请求无效"), false);
            return true;
        }
        if (!QFileInfo(destination).isDir() && !QDir().mkpath(destination)) {
            respond(socket, request, false, {}, QStringLiteral("invalid-destination"),
                    QStringLiteral("目标文件夹无效"), false);
            return true;
        }
        QStringList transferred;
        for (const QString &source : paths) {
            const QString target = uniquePath(destination, QFileInfo(source).fileName());
            if (target.isEmpty() || target == source || !moveOrCopy(source, target, move)) {
                respond(socket, request, false, {}, QStringLiteral("transfer-failed"),
                        QStringLiteral("文件传输未完成"), true);
                return true;
            }
            transferred.append(target);
        }
        respond(socket, request, true,
                QJsonObject{{QStringLiteral("paths"), jsonPaths(transferred)},
                            {QStringLiteral("mode"), mode}});
        return true;
    }
    if (op == QStringLiteral("file.open-with")) {
        const QString path = cleanPath(payload.value(QStringLiteral("path")).toString());
        if (path.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-path"), QStringLiteral("文件路径无效"), false);
            return true;
        }
        const QString requestedMime = payload.value(QStringLiteral("mime")).toString().trimmed();
        auto finish = [this, socket, request, path](const QString &mime) {
            if (mime.isEmpty()) {
                respond(socket, request, false, {}, QStringLiteral("mime-unavailable"),
                        QStringLiteral("无法确定文件类型"), false);
                return;
            }
            auto *process = new QProcess(this);
            process->setProgram(QStringLiteral("gio"));
            process->setArguments({QStringLiteral("mime"), mime});
            connect(process, &QProcess::finished, this,
                    [this, socket, request, process, mime, path](int exitCode, QProcess::ExitStatus) {
                const QString output = QString::fromUtf8(process->readAllStandardOutput());
                if (exitCode != 0) {
                    respond(socket, request, false, {}, QStringLiteral("open-with-failed"),
                            QStringLiteral("无法读取打开方式"), true);
                    process->deleteLater();
                    return;
                }
                QString defaultId;
                QStringList handlers;
                const QStringList lines = output.split(QRegularExpression(QStringLiteral("\\r?\\n")));
                for (const QString &line : lines) {
                    const QString trimmed = line.trimmed();
                    const QRegularExpressionMatch defaultMatch =
                        QRegularExpression(QStringLiteral("^Default application.*:\\s*(\\S+)$"))
                            .match(trimmed);
                    if (defaultMatch.hasMatch())
                        defaultId = defaultMatch.captured(1);
                    const QRegularExpressionMatch idMatch =
                        QRegularExpression(QStringLiteral("^(\\S+\\.desktop)$")).match(trimmed);
                    if (idMatch.hasMatch() && !handlers.contains(idMatch.captured(1)))
                        handlers.append(idMatch.captured(1));
                }
                if (!defaultId.isEmpty() && !handlers.contains(defaultId))
                    handlers.prepend(defaultId);
                respond(socket, request, true,
                        QJsonObject{{QStringLiteral("path"), path},
                                    {QStringLiteral("mime"), mime},
                                    {QStringLiteral("defaultId"), defaultId},
                                    {QStringLiteral("handlers"), QJsonArray::fromStringList(handlers)}});
                process->deleteLater();
            });
            process->start();
        };
        if (!requestedMime.isEmpty()) {
            finish(requestedMime);
            return true;
        }
        auto *info = new QProcess(this);
        info->setProgram(QStringLiteral("gio"));
        info->setArguments({QStringLiteral("info"), QStringLiteral("-a"),
                            QStringLiteral("standard::content-type"), path});
        connect(info, &QProcess::finished, this,
                [info, finish](int exitCode, QProcess::ExitStatus) {
            const QString output = QString::fromUtf8(info->readAllStandardOutput());
            QString mime;
            if (exitCode == 0) {
                const QRegularExpressionMatch match =
                    QRegularExpression(QStringLiteral("standard::content-type:\\s*(\\S+)"))
                        .match(output);
                if (match.hasMatch())
                    mime = match.captured(1);
            }
            finish(mime);
            info->deleteLater();
        });
        info->start();
        return true;
    }
    if (op == QStringLiteral("file.set-default")) {
        const QString mime = payload.value(QStringLiteral("mime")).toString().trimmed();
        const QString desktopId = payload.value(QStringLiteral("desktopId")).toString().trimmed();
        if (mime.isEmpty() || desktopId.isEmpty() || desktopId.contains(QChar('/'))
            || !desktopId.endsWith(QStringLiteral(".desktop"))) {
            respond(socket, request, false, {}, QStringLiteral("invalid-handler"),
                    QStringLiteral("默认应用无效"), false);
            return true;
        }
        runCommand(socket, request, QStringLiteral("gio"),
                   {QStringLiteral("mime"), mime, desktopId});
        return true;
    }
    if (op == QStringLiteral("file.open-kde")) {
        const QString path = cleanPath(payload.value(QStringLiteral("path")).toString());
        if (path.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-path"),
                    QStringLiteral("文件路径无效"), false);
            return true;
        }
        const QString helper = QStandardPaths::findExecutable(QStringLiteral("quickshell-kde-open-with"));
        if (helper.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("open-with-unavailable"),
                    QStringLiteral("KDE 打开方式面板不可用"), false);
            return true;
        }
        runCommand(socket, request, helper, {path});
        return true;
    }
    return false;
}

bool PlatformServer::handleKWin(QLocalSocket *socket, const QJsonObject &request)
{
    const QString op = operation(request);
    if (op == QStringLiteral("kwin.subscribe")) {
        m_windowSubscribers.insert(socket);
        respond(socket, request, true, QJsonObject{{QStringLiteral("subscribed"), true}});
        return true;
    }
    if (op == QStringLiteral("kwin.command")) {
        if (!enqueueKWinCommand(request.value(QStringLiteral("payload")).toObject())) {
            respond(socket, request, false, {}, QStringLiteral("kwin-unavailable"),
                    QStringLiteral("KWin 平台桥不可用"), true);
            return true;
        }
        respond(socket, request, true);
        return true;
    }
    if (op == QStringLiteral("kwin.animation.update-targets")
        || op == QStringLiteral("kwin.animation.prepare-launch")) {
        const QString payload = request.value(QStringLiteral("payload")).toObject()
                                     .value(QStringLiteral("payload")).toString();
        if (payload.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-payload"),
                    QStringLiteral("动画参数无效"), false);
            return true;
        }
        QDBusInterface effect(QStringLiteral("org.kde.KWin"),
                              QStringLiteral("/KOSDockWindowAnimation"),
                              QStringLiteral("org.kos.KWin.DockWindowAnimation"));
        if (!effect.isValid()) {
            respond(socket, request, false, {}, QStringLiteral("kwin-effect-unavailable"),
                    QStringLiteral("Dock 窗口动画特效不可用"), true);
            return true;
        }
        const QString method = op.endsWith(QStringLiteral("update-targets"))
            ? QStringLiteral("updateTargets") : QStringLiteral("prepareLaunch");
        const QDBusMessage reply = effect.call(method, payload);
        if (reply.type() == QDBusMessage::ErrorMessage) {
            respond(socket, request, false, {}, QStringLiteral("kwin-effect-failed"),
                    QStringLiteral("Dock 窗口动画特效调用失败"), true);
            return true;
        }
        respond(socket, request, true, QJsonObject{{QStringLiteral("accepted"), true}});
        return true;
    }
    return false;
}

bool PlatformServer::handleSystemOperation(QLocalSocket *socket, const QJsonObject &request)
{
    const QString op = operation(request);
    const QJsonObject payload = request.value(QStringLiteral("payload")).toObject();
    if (op == QStringLiteral("audio.get")) {
        runCommand(socket, request, QStringLiteral("wpctl"),
                   {QStringLiteral("get-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@")}, parseAudio);
        return true;
    }
    if (op == QStringLiteral("audio.set-volume")) {
        const int value = qBound(0, payload.value(QStringLiteral("percent")).toInt(), 150);
        runCommand(socket, request, QStringLiteral("wpctl"),
                   {QStringLiteral("set-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@"),
                    QString::number(value / 100.0, 'f', 3)});
        return true;
    }
    if (op == QStringLiteral("audio.set-mute")) {
        runCommand(socket, request, QStringLiteral("wpctl"),
                   {QStringLiteral("set-mute"), QStringLiteral("@DEFAULT_AUDIO_SINK@"),
                    payload.value(QStringLiteral("muted")).toBool() ? QStringLiteral("1") : QStringLiteral("0")});
        return true;
    }
    if (op == QStringLiteral("network.refresh")) {
        runCommand(socket, request, QStringLiteral("nmcli"),
                   {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("RUNNING,STATE,CONNECTIVITY,WIFI"), QStringLiteral("general"),
                    QStringLiteral("--wait"), QStringLiteral("2")}, parseNetworkRefresh);
        return true;
    }
    if (op == QStringLiteral("network.details")) {
        const QString device = payload.value(QStringLiteral("device")).toString();
        if (device.isEmpty() || device.contains(QChar('/')) || device.contains(QChar(':'))) {
            respond(socket, request, false, {}, QStringLiteral("invalid-device"),
                    QStringLiteral("网络设备无效"), false);
            return true;
        }
        runCommand(socket, request, QStringLiteral("nmcli"),
                   {QStringLiteral("-t"), QStringLiteral("-f"),
                    QStringLiteral("GENERAL.CONNECTION,IP4.ADDRESS"),
                    QStringLiteral("device"), QStringLiteral("show"), device},
                   parseNetworkDetails);
        return true;
    }
    if (op == QStringLiteral("network.scan")) {
        const QString device = payload.value(QStringLiteral("device")).toString();
        if (device.isEmpty() || device.contains(QChar('/')) || device.contains(QChar(':'))) {
            respond(socket, request, false, {}, QStringLiteral("invalid-device"),
                    QStringLiteral("网络设备无效"), false);
            return true;
        }
        // Resolve saved profiles in the same adapter call as the RF scan. The
        // profile UUID is immutable even when a user renames the connection,
        // so the UI can safely reconnect or forget the selected network.
        auto *profiles = new QProcess(this);
        profiles->setProgram(QStringLiteral("nmcli"));
        profiles->setArguments({QStringLiteral("-t"), QStringLiteral("-f"),
                                QStringLiteral("UUID,TYPE,802-11-wireless.ssid"),
                                QStringLiteral("connection"), QStringLiteral("show")});
        connect(profiles, &QProcess::finished, this,
                [this, socket, request, device, profiles](int profileExit,
                                                          QProcess::ExitStatus) {
            const QHash<QString, QString> savedProfiles = parseSavedWifiProfiles(
                profiles->readAllStandardOutput(), profileExit);
            profiles->deleteLater();
            if (profileExit != 0) {
                respond(socket, request, false, {}, QStringLiteral("network-unavailable"),
                        QStringLiteral("无法读取已保存的网络配置"), true);
                return;
            }
            auto *scan = new QProcess(this);
            scan->setProgram(QStringLiteral("nmcli"));
            scan->setArguments({QStringLiteral("-t"), QStringLiteral("-f"),
                                QStringLiteral("IN-USE,SSID,SIGNAL,SECURITY"),
                                QStringLiteral("device"), QStringLiteral("wifi"),
                                QStringLiteral("list"), QStringLiteral("ifname"), device,
                                QStringLiteral("--rescan"), QStringLiteral("auto")});
            connect(scan, &QProcess::finished, this,
                    [this, socket, request, savedProfiles, scan](int scanExit,
                                                                  QProcess::ExitStatus) {
                const QJsonObject result = parseNetworkScan(
                    scan->readAllStandardOutput(), scanExit);
                scan->deleteLater();
                if (scanExit != 0) {
                    respond(socket, request, false, {}, QStringLiteral("network-scan-failed"),
                            QStringLiteral("Wi‑Fi 扫描失败"), true);
                    return;
                }
                QJsonArray networks = result.value(QStringLiteral("networks")).toArray();
                for (int index = 0; index < networks.size(); ++index) {
                    QJsonObject network = networks.at(index).toObject();
                    network.insert(QStringLiteral("savedProfileUuid"),
                                   savedProfiles.value(network.value(QStringLiteral("ssid"))
                                                           .toString()));
                    networks[index] = network;
                }
                QJsonObject normalized{{QStringLiteral("available"), true},
                                       {QStringLiteral("networks"), networks}};
                respond(socket, request, true, normalized);
            });
            scan->start();
        });
        profiles->start();
        return true;
    }
    if (op == QStringLiteral("network.wifi-power")) {
        runCommand(socket, request, QStringLiteral("nmcli"),
                   {QStringLiteral("radio"), QStringLiteral("wifi"), payload.value(QStringLiteral("enabled")).toBool() ? QStringLiteral("on") : QStringLiteral("off")});
        return true;
    }
    if (op == QStringLiteral("network.connect")) {
        const QString ssid = payload.value(QStringLiteral("ssid")).toString();
        const QString device = payload.value(QStringLiteral("device")).toString();
        const QString password = payload.value(QStringLiteral("password")).toString();
        const QString uuid = payload.value(QStringLiteral("savedProfileUuid")).toString();
        if (ssid.isEmpty() || device.isEmpty() || device.contains(QChar('/'))) {
            respond(socket, request, false, {}, QStringLiteral("invalid-network"),
                    QStringLiteral("网络参数无效"), false);
            return true;
        }
        if (!password.isEmpty()) {
            runCommand(socket, request, QStringLiteral("nmcli"),
                       {QStringLiteral("--wait"), QStringLiteral("20"), QStringLiteral("device"), QStringLiteral("wifi"), QStringLiteral("connect"), ssid, QStringLiteral("password"), password, QStringLiteral("ifname"), device});
        } else if (!uuid.isEmpty()) {
            runCommand(socket, request, QStringLiteral("nmcli"),
                       {QStringLiteral("--wait"), QStringLiteral("20"), QStringLiteral("connection"), QStringLiteral("up"), QStringLiteral("uuid"), uuid, QStringLiteral("ifname"), device});
        } else {
            runCommand(socket, request, QStringLiteral("nmcli"),
                       {QStringLiteral("--wait"), QStringLiteral("20"), QStringLiteral("device"), QStringLiteral("wifi"), QStringLiteral("connect"), ssid, QStringLiteral("ifname"), device});
        }
        return true;
    }
    if (op == QStringLiteral("network.connect-enterprise")) {
        const QString ssid = payload.value(QStringLiteral("ssid")).toString();
        const QString device = payload.value(QStringLiteral("device")).toString();
        const QString identity = payload.value(QStringLiteral("identity")).toString();
        const QString password = payload.value(QStringLiteral("password")).toString();
        const QString method = payload.value(QStringLiteral("eapMethod")).toString().toLower();
        const QString phase2 = method == QStringLiteral("peap") ? QStringLiteral("mschapv2")
            : method == QStringLiteral("ttls") ? QStringLiteral("pap") : QString();
        const QString anonymous = payload.value(QStringLiteral("anonymousIdentity")).toString();
        if (ssid.isEmpty() || device.isEmpty() || identity.isEmpty() || password.isEmpty()
            || phase2.isEmpty() || device.contains(QChar('/'))) {
            respond(socket, request, false, {}, QStringLiteral("invalid-network"),
                    QStringLiteral("802.1X 参数无效"), false);
            return true;
        }
        const QString profile = QStringLiteral("quickshell-8021x-") + ssid;
        QStringList args{QStringLiteral("connection"), QStringLiteral("delete"), profile};
        // Deleting a missing profile is harmless; use a separate process for
        // each explicit command so no shell interpolation is required.
        auto *deleteProcess = new QProcess(this);
        deleteProcess->setProgram(QStringLiteral("nmcli"));
        deleteProcess->setArguments(args);
        connect(deleteProcess, &QProcess::finished, this, [this, socket, request, payload, profile, ssid, device, identity, password, method, phase2, anonymous, deleteProcess](int, QProcess::ExitStatus) {
            deleteProcess->deleteLater();
            QStringList add{QStringLiteral("connection"), QStringLiteral("add"), QStringLiteral("type"), QStringLiteral("wifi"), QStringLiteral("ifname"), device, QStringLiteral("con-name"), profile, QStringLiteral("ssid"), ssid};
            auto *addProcess = new QProcess(this);
            addProcess->setProgram(QStringLiteral("nmcli"));
            addProcess->setArguments(add);
            connect(addProcess, &QProcess::finished, this, [this, socket, request, profile, device, identity, password, method, phase2, anonymous, addProcess](int exitCode, QProcess::ExitStatus) {
                addProcess->deleteLater();
                if (exitCode != 0) {
                    respond(socket, request, false, {}, QStringLiteral("network-failed"), QStringLiteral("无法创建网络配置"), true);
                    return;
                }
                QStringList modify{QStringLiteral("connection"), QStringLiteral("modify"), profile,
                    QStringLiteral("wifi-sec.key-mgmt"), QStringLiteral("wpa-eap"),
                    QStringLiteral("802-1x.eap"), method, QStringLiteral("802-1x.identity"), identity,
                    QStringLiteral("802-1x.password"), password, QStringLiteral("802-1x.phase2-auth"), phase2,
                    QStringLiteral("connection.autoconnect"), QStringLiteral("yes")};
                if (!anonymous.isEmpty())
                    modify << QStringLiteral("802-1x.anonymous-identity") << anonymous;
                auto *modifyProcess = new QProcess(this);
                modifyProcess->setProgram(QStringLiteral("nmcli"));
                modifyProcess->setArguments(modify);
                connect(modifyProcess, &QProcess::finished, this, [this, socket, request, profile, device, modifyProcess](int modifyExit, QProcess::ExitStatus) {
                    modifyProcess->deleteLater();
                    if (modifyExit != 0) {
                        respond(socket, request, false, {}, QStringLiteral("network-failed"), QStringLiteral("无法保存网络配置"), true);
                        return;
                    }
                    runCommand(socket, request, QStringLiteral("nmcli"), {QStringLiteral("--wait"), QStringLiteral("25"), QStringLiteral("connection"), QStringLiteral("up"), profile, QStringLiteral("ifname"), device});
                });
                modifyProcess->start();
            });
            addProcess->start();
        });
        deleteProcess->start();
        return true;
    }
    if (op == QStringLiteral("network.disconnect")) {
        const QString device = payload.value(QStringLiteral("device")).toString();
        if (device.isEmpty() || device.contains(QChar('/'))) {
            respond(socket, request, false, {}, QStringLiteral("invalid-device"), QStringLiteral("网络设备无效"), false);
            return true;
        }
        runCommand(socket, request, QStringLiteral("nmcli"), {QStringLiteral("device"), QStringLiteral("disconnect"), device});
        return true;
    }
    if (op == QStringLiteral("network.forget")) {
        const QString uuid = payload.value(QStringLiteral("uuid")).toString();
        static const QRegularExpression uuidPattern(QStringLiteral("^[0-9A-Fa-f-]{8,}$"));
        if (!uuidPattern.match(uuid).hasMatch()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-profile"), QStringLiteral("网络配置无效"), false);
            return true;
        }
        runCommand(socket, request, QStringLiteral("nmcli"), {QStringLiteral("connection"), QStringLiteral("delete"), QStringLiteral("uuid"), uuid});
        return true;
    }
    if (op == QStringLiteral("bluetooth.power")) {
        runCommand(socket, request, QStringLiteral("bluetoothctl"),
                   {QStringLiteral("power"), payload.value(QStringLiteral("enabled")).toBool() ? QStringLiteral("on") : QStringLiteral("off")});
        return true;
    }
    if (op == QStringLiteral("bluetooth.list")) {
        runCommand(socket, request, QStringLiteral("bluetoothctl"), {QStringLiteral("devices")}, parseBluetooth);
        return true;
    }
    if (op == QStringLiteral("bluetooth.connect") || op == QStringLiteral("bluetooth.disconnect")) {
        const QString address = payload.value(QStringLiteral("address")).toString().trimmed();
        static const QRegularExpression addressPattern(QStringLiteral("^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$"));
        if (!addressPattern.match(address).hasMatch()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-address"),
                    QStringLiteral("蓝牙地址无效"), false);
            return true;
        }
        runCommand(socket, request, QStringLiteral("bluetoothctl"),
                   {op == QStringLiteral("bluetooth.connect") ? QStringLiteral("connect") : QStringLiteral("disconnect"), address});
        return true;
    }
    if (op == QStringLiteral("session.lock")) {
        runCommand(socket, request, QStringLiteral("loginctl"), {QStringLiteral("lock-session")});
        return true;
    }
    if (op == QStringLiteral("session.suspend") || op == QStringLiteral("session.hibernate")
        || op == QStringLiteral("session.reboot") || op == QStringLiteral("session.poweroff")) {
        const QString action = op.mid(QStringLiteral("session.").size());
        runCommand(socket, request, QStringLiteral("systemctl"), {action});
        return true;
    }
    if (op == QStringLiteral("session.logout")) {
        runCommand(socket, request, QStringLiteral("loginctl"), {QStringLiteral("terminate-session"),
                   qEnvironmentVariable("XDG_SESSION_ID")});
        return true;
    }
    if (op == QStringLiteral("session.switch-user")) {
        runCommand(socket, request, QStringLiteral("dm-tool"), {QStringLiteral("switch-to-greeter")});
        return true;
    }
    if (op == QStringLiteral("display.brightness.get")) {
        const QString brightnessctl = QStandardPaths::findExecutable(QStringLiteral("brightnessctl"));
        if (brightnessctl.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("brightness-unavailable"),
                    QStringLiteral("亮度控制不可用"), false);
            return true;
        }
        runCommand(socket, request, brightnessctl, {QStringLiteral("-m")}, parseBrightness);
        return true;
    }
    if (op == QStringLiteral("display.brightness.set")) {
        const int value = qBound(0, payload.value(QStringLiteral("percent")).toInt(), 100);
        const QString brightnessctl = QStandardPaths::findExecutable(QStringLiteral("brightnessctl"));
        if (brightnessctl.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("brightness-unavailable"),
                    QStringLiteral("亮度控制不可用"), false);
            return true;
        }
        runCommand(socket, request, brightnessctl,
                   {QStringLiteral("set"), QStringLiteral("%1%").arg(value)});
        return true;
    }
    if (op == QStringLiteral("theme.reconfigure")) {
        QDBusInterface kwin(QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"),
                            QStringLiteral("org.kde.KWin"));
        if (kwin.isValid())
            kwin.call(QStringLiteral("reconfigure"));
        respond(socket, request, true, QJsonObject{{QStringLiteral("reconfigured"), true}});
        return true;
    }
    if (op == QStringLiteral("theme.sync-glass")) {
        const int contentBlur = qBound(1,
            payload.value(QStringLiteral("contentBlurLevel")).toInt(), 15);
        const int dockBlur = qBound(1,
            payload.value(QStringLiteral("dockBlurLevel")).toInt(), 15);
        const int refraction = qBound(0,
            payload.value(QStringLiteral("refractionLevel")).toInt(), 20);
        const QString kwriteconfig = QStandardPaths::findExecutable(
            QStringLiteral("kwriteconfig6"));
        if (kwriteconfig.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("theme-unavailable"),
                    QStringLiteral("KDE 主题配置工具不可用"), false);
            return true;
        }
        const QList<QStringList> writes{
            {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"),
             QStringLiteral("Effect-blurplus"), QStringLiteral("--key"),
             QStringLiteral("BlurStrength"), QString::number(contentBlur)},
            {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"),
             QStringLiteral("Effect-blurplus"), QStringLiteral("--key"),
             QStringLiteral("DockBlurStrength"), QString::number(dockBlur)},
            {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"),
             QStringLiteral("Effect-blurplus"), QStringLiteral("--key"),
             QStringLiteral("RefractionStrength"), QString::number(refraction)},
            {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"),
             QStringLiteral("Effect-blur"), QStringLiteral("--key"),
             QStringLiteral("BlurStrength"), QString::number(contentBlur)}};
        for (const QStringList &arguments : writes) {
            if (QProcess::execute(kwriteconfig, arguments) != 0) {
                respond(socket, request, false, {}, QStringLiteral("theme-write-failed"),
                        QStringLiteral("无法保存玻璃特效配置"), true);
                return true;
            }
        }
        QDBusInterface effects(QStringLiteral("org.kde.KWin"), QStringLiteral("/Effects"),
                               QStringLiteral("org.kde.kwin.Effects"));
        if (effects.isValid()) {
            effects.call(QStringLiteral("reconfigureEffect"), QStringLiteral("glass"));
            effects.call(QStringLiteral("reconfigureEffect"), QStringLiteral("blur"));
        }
        respond(socket, request, true,
                QJsonObject{{QStringLiteral("configured"), true},
                            {QStringLiteral("kwinAvailable"), effects.isValid()}});
        return true;
    }
    if (op == QStringLiteral("theme.sync-dock-animation")) {
        const QString style = payload.value(QStringLiteral("style")).toString();
        if (style != QStringLiteral("scale") && style != QStringLiteral("genie")) {
            respond(socket, request, false, {}, QStringLiteral("invalid-style"),
                    QStringLiteral("窗口动画样式无效"), false);
            return true;
        }
        const QString kwriteconfig = QStandardPaths::findExecutable(
            QStringLiteral("kwriteconfig6"));
        if (kwriteconfig.isEmpty()
            || QProcess::execute(kwriteconfig,
                {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"),
                 QStringLiteral("Effect-kos_dock_window_animation"), QStringLiteral("--key"),
                 QStringLiteral("AnimationStyle"), style}) != 0) {
            respond(socket, request, false, {}, QStringLiteral("theme-write-failed"),
                    QStringLiteral("无法保存窗口动画配置"), true);
            return true;
        }
        QDBusInterface effects(QStringLiteral("org.kde.KWin"), QStringLiteral("/Effects"),
                               QStringLiteral("org.kde.kwin.Effects"));
        if (effects.isValid())
            effects.call(QStringLiteral("reconfigureEffect"),
                         QStringLiteral("kos_dock_window_animation"));
        respond(socket, request, true,
                QJsonObject{{QStringLiteral("configured"), true},
                            {QStringLiteral("kwinAvailable"), effects.isValid()}});
        return true;
    }
    if (op == QStringLiteral("theme.toggle")) {
        auto *reader = new QProcess(this);
        reader->setProgram(QStringLiteral("kreadconfig6"));
        reader->setArguments({QStringLiteral("--file"), QStringLiteral("kdeglobals"),
                              QStringLiteral("--group"), QStringLiteral("General"),
                              QStringLiteral("--key"), QStringLiteral("ColorScheme")});
        connect(reader, &QProcess::finished, this, [this, socket, request, reader](int, QProcess::ExitStatus) {
            const QString scheme = QString::fromUtf8(reader->readAllStandardOutput()).trimmed();
            reader->deleteLater();
            const bool dark = scheme.contains(QStringLiteral("dark"), Qt::CaseInsensitive);
            const QString package = dark ? QStringLiteral("org.kde.breeze.desktop")
                                         : QStringLiteral("org.kde.breezedark.desktop");
            runCommand(socket, request, QStringLiteral("plasma-apply-lookandfeel"),
                       {QStringLiteral("--apply"), package});
        });
        reader->start();
        return true;
    }
    if (op == QStringLiteral("screenshot.capture")) {
        const QStringList candidates{QStringLiteral("mark-shot"), QStringLiteral("markshot"),
                                     QStringLiteral("flameshot"), QStringLiteral("ksnip"),
                                     QStringLiteral("spectacle"), QStringLiteral("grimblast")};
        for (const QString &candidate : candidates) {
            const QString executable = QStandardPaths::findExecutable(candidate);
            if (executable.isEmpty())
                continue;
            QStringList args;
            if (candidate == QStringLiteral("mark-shot") || candidate == QStringLiteral("markshot")) args = {QStringLiteral("--capture")};
            else if (candidate == QStringLiteral("flameshot")) args = {QStringLiteral("gui")};
            else if (candidate == QStringLiteral("ksnip")) args = {QStringLiteral("-r")};
            else if (candidate == QStringLiteral("spectacle")) args = {QStringLiteral("-r")};
            else args = {QStringLiteral("copy"), QStringLiteral("area")};
            runCommand(socket, request, executable, args);
            return true;
        }
        respond(socket, request, false, {}, QStringLiteral("screenshot-unavailable"),
                QStringLiteral("没有可用的截图工具"), false);
        return true;
    }
    return false;
}

void PlatformServer::handleRequest(QLocalSocket *socket, const QJsonObject &request)
{
    if (request.value(QStringLiteral("version")).toInt(kProtocolVersion) != kProtocolVersion) {
        respond(socket, request, false, {}, QStringLiteral("unsupported-version"),
                QStringLiteral("不支持的协议版本"), false);
        return;
    }
    const QString op = operation(request);
    if (op.isEmpty()) {
        respond(socket, request, false, {}, QStringLiteral("missing-operation"),
                QStringLiteral("缺少 operation"), false);
        return;
    }
    if (op == QStringLiteral("platform.ping")) {
        respond(socket, request, true, QJsonObject{{QStringLiteral("ready"), true}});
        return;
    }
    if (handleClipboard(socket, request) || handleFileOperation(socket, request)
        || handleKWin(socket, request) || handleSystemOperation(socket, request))
        return;
    respond(socket, request, false, {}, QStringLiteral("unknown-operation"),
            QStringLiteral("未知的平台操作"), false);
}

} // namespace KosPlatform
