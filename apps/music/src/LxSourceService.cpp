#include "LxSourceService.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QSaveFile>
#include <QTimer>
#include <QUrl>
#include <QUuid>

#include <utility>

namespace {

constexpr qsizetype maximumScriptBytes = 2 * 1024 * 1024;
constexpr int commandTimeoutMs = 35000;

QString metadataValue(const QString &script, const QString &field)
{
    const QRegularExpression expression(
        QStringLiteral(R"(^\s*\*?\s*@%1\s+(.+?)\s*$)").arg(QRegularExpression::escape(field)),
        QRegularExpression::MultilineOption);
    const QRegularExpressionMatch match = expression.match(script);
    return match.hasMatch() ? match.captured(1).trimmed() : QString{};
}

} // namespace

LxSourceService::LxSourceService(QString dataPath, QObject *parent)
    : QObject(parent)
    , m_dataPath(std::move(dataPath))
    , m_sourcesPath(QDir(m_dataPath).filePath(QStringLiteral("sources")))
    , m_host(this)
    , m_network(this)
{
    QDir().mkpath(m_sourcesPath);
    connect(&m_host, &QProcess::readyReadStandardOutput,
            this, &LxSourceService::readHostOutput);
    connect(&m_host, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (m_stoppingHost
            || (error != QProcess::Crashed && error != QProcess::FailedToStart)) {
            return;
        }
        failHost(tr("Music source host failed: %1").arg(m_host.errorString()));
    });
    connect(&m_host, &QProcess::finished, this,
            [this](int exitCode, QProcess::ExitStatus) {
        if (m_stoppingHost || m_state == QLatin1String("inactive")
            || m_state == QLatin1String("error")) {
            return;
        }
        QString detail = QString::fromUtf8(m_host.readAllStandardError()).trimmed();
        if (detail.size() > 512)
            detail = detail.right(512);
        QString message = tr("Music source host exited unexpectedly (code %1)")
                              .arg(exitCode);
        if (!detail.isEmpty())
            message += QStringLiteral(": ") + detail;
        failHost(message);
    });
    loadIndex();
    m_runtimeSourceId = m_activeSourceId;
    if (!m_activeSourceId.isEmpty())
        startHost();
}

LxSourceService::~LxSourceService()
{
    stopHost(false);
}

QVariantList LxSourceService::sources() const { return m_sources; }
QString LxSourceService::activeSourceId() const { return m_activeSourceId; }
QString LxSourceService::state() const { return m_state; }
QString LxSourceService::errorMessage() const { return m_errorMessage; }
QStringList LxSourceService::availableQualities(const QString &platform) const { return m_supportedQualities.value(platform); }

void LxSourceService::importSource(const QString &pathOrUrl)
{
    QUrl url(pathOrUrl);
    if (!url.isValid() || url.scheme().isEmpty())
        url = QUrl::fromLocalFile(QFileInfo(pathOrUrl).absoluteFilePath());
    if (url.isLocalFile()) {
        QFile file(url.toLocalFile());
        if (!file.open(QIODevice::ReadOnly)) {
            setError(tr("Unable to read source: %1").arg(file.errorString()));
            return;
        }
        const QByteArray script = file.read(maximumScriptBytes + 1);
        installScript(script, file.fileName());
        return;
    }
    if (url.scheme() != QLatin1String("https")
        && !(url.scheme() == QLatin1String("http")
             && (url.host() == QLatin1String("localhost")
                 || url.host() == QLatin1String("127.0.0.1")))) {
        setError(tr("Only HTTPS source URLs are allowed"));
        return;
    }
    if (m_importReply) {
        m_importReply->abort();
        m_importReply->deleteLater();
    }
    QNetworkRequest request(url);
    request.setTransferTimeout(20000);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::NoLessSafeRedirectPolicy);
    request.setRawHeader("User-Agent", "KOS-Music/1.0");
    QNetworkReply *reply = m_network.get(request);
    m_importReply = reply;
    connect(reply, &QNetworkReply::finished, this, [this, url, reply] {
        if (m_importReply != reply) {
            reply->deleteLater();
            return;
        }
        m_importReply = nullptr;
        if (reply->error() != QNetworkReply::NoError) {
            setError(tr("Unable to download source: %1").arg(reply->errorString()));
        } else {
            installScript(reply->read(maximumScriptBytes + 1), url.toString());
        }
        reply->deleteLater();
    });
}

void LxSourceService::activateSource(const QString &sourceId)
{
    if (sourceForId(sourceId).isEmpty()) {
        setError(tr("Music source was not found"));
        return;
    }
    m_activeSourceId = sourceId;
    m_runtimeSourceId = sourceId;
    for (QVariant &value : m_sources) {
        QVariantMap source = value.toMap();
        source.insert(QStringLiteral("active"),
                      source.value(QStringLiteral("id")).toString() == sourceId);
        value = source;
    }
    saveIndex();
    emit sourcesChanged();
    startHost();
}

void LxSourceService::useSourceForPlayback(const QString &sourceId)
{
    if (sourceForId(sourceId).isEmpty())
        return;
    if (m_runtimeSourceId == sourceId && (m_state == QLatin1String("ready")
        || m_state == QLatin1String("starting")))
        return;
    cancelResolves();
    m_runtimeSourceId = sourceId;
    startHost();
}

void LxSourceService::removeSource(const QString &sourceId)
{
    for (qsizetype index = 0; index < m_sources.size(); ++index) {
        const QVariantMap source = m_sources.at(index).toMap();
        if (source.value(QStringLiteral("id")).toString() != sourceId)
            continue;
        QFile::remove(source.value(QStringLiteral("path")).toString());
        m_sources.removeAt(index);
        if (m_activeSourceId == sourceId)
            m_activeSourceId.clear();
        if (m_runtimeSourceId == sourceId) {
            m_runtimeSourceId.clear();
            stopHost();
            setState(QStringLiteral("inactive"));
        }
        saveIndex();
        emit sourcesChanged();
        return;
    }
}

void LxSourceService::cancelResolves()
{
    for (auto it = m_pending.begin(); it != m_pending.end();) {
        if (it->operation != QLatin1String("resolve")) {
            ++it;
            continue;
        }
        it->timer->stop();
        it->timer->deleteLater();
        it = m_pending.erase(it);
    }
}

void LxSourceService::resolve(qint64 trackId, const QString &platform,
                              const QString &sourceData, const QString &quality)
{
    if (m_state != QLatin1String("ready")) {
        emit resolveFailed(trackId, tr("Choose a ready custom music source first"));
        return;
    }
    if (!m_supportedQualities.contains(platform)) {
        emit resolveFailed(trackId, tr("The active source does not support %1").arg(platform));
        return;
    }
    if (platform != QLatin1String("local")
        && !m_supportedQualities.value(platform).contains(quality)) {
        emit resolveFailed(trackId, tr("The active source does not support %1 quality").arg(quality));
        return;
    }
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(sourceData.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        emit resolveFailed(trackId, tr("The online track metadata is invalid"));
        return;
    }
    const QJsonObject request{
        {QStringLiteral("source"), platform},
        {QStringLiteral("action"), QStringLiteral("musicUrl")},
        {QStringLiteral("info"), QJsonObject{
             {QStringLiteral("type"), quality},
             {QStringLiteral("musicInfo"), document.object()},
        }},
    };
    sendCommand(QJsonObject{{QStringLiteral("op"), QStringLiteral("resolve")},
                            {QStringLiteral("request"), request}},
                QStringLiteral("resolve"), trackId);
}

void LxSourceService::loadIndex()
{
    QFile file(QDir(m_sourcesPath).filePath(QStringLiteral("index.json")));
    if (!file.open(QIODevice::ReadOnly))
        return;
    const QJsonObject index = QJsonDocument::fromJson(file.readAll()).object();
    m_activeSourceId = index.value(QStringLiteral("activeSourceId")).toString();
    for (const QJsonValue &value : index.value(QStringLiteral("sources")).toArray()) {
        QVariantMap source = value.toObject().toVariantMap();
        const QString fileName = source.value(QStringLiteral("fileName")).toString();
        const QString path = QDir(m_sourcesPath).filePath(fileName);
        if (QFileInfo::exists(path)) {
            source.insert(QStringLiteral("path"), path);
            source.insert(QStringLiteral("active"),
                          source.value(QStringLiteral("id")).toString() == m_activeSourceId);
            m_sources.append(source);
        }
    }
    if (sourceForId(m_activeSourceId).isEmpty())
        m_activeSourceId.clear();
}

bool LxSourceService::saveIndex()
{
    QJsonArray sources;
    for (const QVariant &value : std::as_const(m_sources)) {
        QVariantMap source = value.toMap();
        source.remove(QStringLiteral("path"));
        source.remove(QStringLiteral("active"));
        sources.append(QJsonObject::fromVariantMap(source));
    }
    QSaveFile file(QDir(m_sourcesPath).filePath(QStringLiteral("index.json")));
    if (!file.open(QIODevice::WriteOnly)) {
        setError(file.errorString());
        return false;
    }
    file.write(QJsonDocument(QJsonObject{
        {QStringLiteral("activeSourceId"), m_activeSourceId},
        {QStringLiteral("sources"), sources},
    }).toJson(QJsonDocument::Indented));
    if (!file.commit()) {
        setError(file.errorString());
        return false;
    }
    return true;
}

void LxSourceService::installScript(const QByteArray &script, const QString &origin)
{
    if (script.isEmpty() || script.size() > maximumScriptBytes) {
        setError(tr("The source script is empty or larger than 2 MiB"));
        return;
    }
    const QString text = QString::fromUtf8(script);
    QString name = metadataValue(text, QStringLiteral("name"));
    if (name.isEmpty())
        name = QFileInfo(QUrl(origin).path()).completeBaseName();
    if (name.isEmpty())
        name = tr("Custom source");
    const QString version = metadataValue(text, QStringLiteral("version"));
    const bool hasMetadataHeader = QRegularExpression(
        QStringLiteral(R"(^\s*/\*)")).match(text).hasMatch();
    if (!hasMetadataHeader) {
        setError(tr("The source is missing its leading LuoXue metadata comment"));
        return;
    }
    const QString id = QString::fromLatin1(
        QCryptographicHash::hash(script, QCryptographicHash::Sha256).toHex().left(16));
    const QString fileName = id + QStringLiteral(".js");
    const QString path = QDir(m_sourcesPath).filePath(fileName);
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly) || file.write(script) != script.size() || !file.commit()) {
        setError(tr("Unable to store source: %1").arg(file.errorString()));
        return;
    }
    QVariantMap metadata{
        {QStringLiteral("id"), id},
        {QStringLiteral("name"), name},
        {QStringLiteral("version"), version},
        {QStringLiteral("description"), metadataValue(text, QStringLiteral("description"))},
        {QStringLiteral("author"), metadataValue(text, QStringLiteral("author"))},
        {QStringLiteral("homepage"), metadataValue(text, QStringLiteral("homepage"))},
        {QStringLiteral("origin"), origin},
        {QStringLiteral("fileName"), fileName},
        {QStringLiteral("path"), path},
        {QStringLiteral("active"), true},
    };
    bool replaced = false;
    for (QVariant &value : m_sources) {
        QVariantMap existing = value.toMap();
        existing.insert(QStringLiteral("active"), false);
        if (existing.value(QStringLiteral("id")).toString() == id) {
            value = metadata;
            replaced = true;
        } else {
            value = existing;
        }
    }
    if (!replaced)
        m_sources.append(metadata);
    m_activeSourceId = id;
    m_runtimeSourceId = id;
    setError({});
    saveIndex();
    emit sourcesChanged();
    emit sourceImported(name);
    startHost();
}

void LxSourceService::startHost()
{
    stopHost();
    if (m_runtimeSourceId.isEmpty()) {
        setState(QStringLiteral("inactive"));
        return;
    }
    setError({});
    setState(QStringLiteral("starting"));
    m_host.setProgram(hostProgram());
    m_host.setArguments({});
    m_host.setProcessChannelMode(QProcess::SeparateChannels);
    connect(&m_host, &QProcess::started, this, &LxSourceService::sendLoad,
            Qt::SingleShotConnection);
    m_host.start();
}

void LxSourceService::stopHost(bool notifyPending)
{
    if (!m_supportedQualities.isEmpty()) {
        m_supportedQualities.clear();
        emit capabilitiesChanged();
    }
    const QString cancellation = tr("Music source operation was cancelled");
    for (const PendingCommand &pending : std::as_const(m_pending)) {
        if (pending.timer) {
            pending.timer->stop();
            pending.timer->deleteLater();
        }
        if (notifyPending && pending.trackId >= 0)
            emit resolveFailed(pending.trackId, cancellation);
    }
    m_pending.clear();
    m_hostBuffer.clear();
    if (m_host.state() != QProcess::NotRunning) {
        m_stoppingHost = true;
        m_host.terminate();
        if (!m_host.waitForFinished(1000)) {
            m_host.kill();
            m_host.waitForFinished(1000);
        }
        m_stoppingHost = false;
    }
}

void LxSourceService::failHost(const QString &message)
{
    if (!m_supportedQualities.isEmpty()) {
        m_supportedQualities.clear();
        emit capabilitiesChanged();
    }
    setError(message);
    setState(QStringLiteral("error"));
    for (const PendingCommand &pending : std::as_const(m_pending)) {
        if (pending.timer) {
            pending.timer->stop();
            pending.timer->deleteLater();
        }
        if (pending.trackId >= 0)
            emit resolveFailed(pending.trackId, message);
    }
    m_pending.clear();
    m_hostBuffer.clear();
}

void LxSourceService::sendLoad()
{
    const QVariantMap source = sourceForId(m_runtimeSourceId);
    QFile file(source.value(QStringLiteral("path")).toString());
    if (!file.open(QIODevice::ReadOnly)) {
        setState(QStringLiteral("error"));
        setError(file.errorString());
        return;
    }
    const QJsonObject info{
        {QStringLiteral("name"), source.value(QStringLiteral("name")).toString()},
        {QStringLiteral("description"), source.value(QStringLiteral("description")).toString()},
        {QStringLiteral("version"), source.value(QStringLiteral("version")).toString()},
        {QStringLiteral("author"), source.value(QStringLiteral("author")).toString()},
        {QStringLiteral("homepage"), source.value(QStringLiteral("homepage")).toString()},
        {QStringLiteral("fileName"), source.value(QStringLiteral("fileName")).toString()},
    };
    sendCommand(QJsonObject{{QStringLiteral("op"), QStringLiteral("load")},
                            {QStringLiteral("script"), QString::fromUtf8(file.readAll())},
                            {QStringLiteral("info"), info}},
                QStringLiteral("load"));
}

QString LxSourceService::sendCommand(const QJsonObject &command, const QString &operation,
                                     qint64 trackId)
{
    if (m_host.state() != QProcess::Running) {
        if (trackId >= 0)
            emit resolveFailed(trackId, tr("Music source host is not running"));
        return {};
    }
    const QString id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    QJsonObject message = command;
    message.insert(QStringLiteral("id"), id);
    auto *timer = new QTimer(this);
    timer->setSingleShot(true);
    connect(timer, &QTimer::timeout, this, [this, id] {
        const PendingCommand pending = m_pending.take(id);
        const QString message = tr("Music source timed out");
        if (pending.trackId >= 0)
            emit resolveFailed(pending.trackId, message);
        setError(message);
        stopHost();
        setState(QStringLiteral("error"));
    });
    timer->start(commandTimeoutMs);
    m_pending.insert(id, PendingCommand{operation, trackId, timer});
    m_host.write(QJsonDocument(message).toJson(QJsonDocument::Compact));
    m_host.write("\n");
    return id;
}

void LxSourceService::readHostOutput()
{
    m_hostBuffer += m_host.readAllStandardOutput();
    while (true) {
        const qsizetype newline = m_hostBuffer.indexOf('\n');
        if (newline < 0)
            return;
        const QByteArray line = m_hostBuffer.left(newline).trimmed();
        m_hostBuffer.remove(0, newline + 1);
        const QJsonDocument document = QJsonDocument::fromJson(line);
        if (document.isObject())
            handleHostReply(document.object());
    }
}

void LxSourceService::handleHostReply(const QJsonObject &reply)
{
    const QString id = reply.value(QStringLiteral("id")).toString();
    if (!m_pending.contains(id))
        return;
    const PendingCommand pending = m_pending.take(id);
    if (pending.timer)
        pending.timer->deleteLater();
    const bool ok = reply.value(QStringLiteral("ok")).toBool();
    if (pending.operation == QLatin1String("load")) {
        m_supportedQualities.clear();
        if (ok) {
            const QJsonObject sources = reply.value(QStringLiteral("result")).toObject().value(QStringLiteral("sources")).toObject();
            for (auto iterator = sources.constBegin(); iterator != sources.constEnd(); ++iterator) {
                QStringList qualities;
                for (const QJsonValue &quality : iterator.value().toObject().value(QStringLiteral("qualitys")).toArray())
                    qualities.append(quality.toString());
                m_supportedQualities.insert(iterator.key(), qualities);
            }
            emit capabilitiesChanged();
            setError({});
            setState(QStringLiteral("ready"));
        } else {
            setError(tr("Source failed to load: %1").arg(
                reply.value(QStringLiteral("error")).toString()));
            emit capabilitiesChanged();
            setState(QStringLiteral("error"));
        }
        return;
    }
    if (ok) {
        emit resolved(pending.trackId, QUrl(reply.value(QStringLiteral("result"))
                                                .toObject().value(QStringLiteral("url")).toString()));
    } else {
        const QString message = reply.value(QStringLiteral("error")).toString();
        setError(message);
        emit resolveFailed(pending.trackId, message);
    }
}

QVariantMap LxSourceService::sourceForId(const QString &sourceId) const
{
    for (const QVariant &value : m_sources) {
        const QVariantMap source = value.toMap();
        if (source.value(QStringLiteral("id")).toString() == sourceId)
            return source;
    }
    return {};
}

QString LxSourceService::hostProgram() const
{
    const QString overridden = qEnvironmentVariable("KOS_MUSIC_SOURCE_HOST");
    return overridden.isEmpty()
        ? QDir(QCoreApplication::applicationDirPath()).filePath(
              QStringLiteral("kos-music-lx-source-host"))
        : overridden;
}

void LxSourceService::setState(const QString &state)
{
    if (m_state == state)
        return;
    m_state = state;
    emit stateChanged();
}

void LxSourceService::setError(const QString &message)
{
    if (m_errorMessage == message)
        return;
    m_errorMessage = message;
    emit errorMessageChanged();
}
