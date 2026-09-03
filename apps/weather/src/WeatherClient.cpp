#include "WeatherClient.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QProcess>
#include <QStandardPaths>
#include <QStringList>

#include <utility>

namespace {

QString stateRoot()
{
    const QString configured = qEnvironmentVariable("XDG_STATE_HOME");
    if (!configured.isEmpty())
        return configured;
    return QDir::home().filePath(QStringLiteral(".local/state"));
}

QString runtimeRoot()
{
    const QString configured = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (!configured.isEmpty())
        return configured;
    return QDir::tempPath();
}

QVariantList arrayToList(const QJsonValue &value)
{
    return value.isArray() ? value.toArray().toVariantList() : QVariantList{};
}

QString serviceExecutable()
{
    QStringList candidates;
    const QString configured = qEnvironmentVariable("KOS_DATA_SERVICE");
    if (!configured.isEmpty())
        candidates.append(configured);
    candidates.append(QDir(QCoreApplication::applicationDirPath())
                          .filePath(QStringLiteral("kos-data-service")));
    candidates.append(QDir(QCoreApplication::applicationDirPath())
                          .filePath(QStringLiteral("../libexec/kos-data-service")));
#ifdef KOS_DATA_SERVICE_BUILD_PATH
    candidates.append(QStringLiteral(KOS_DATA_SERVICE_BUILD_PATH));
#endif
    candidates.append(QStandardPaths::findExecutable(
        QStringLiteral("kos-data-service")));

    for (const QString &candidate : std::as_const(candidates)) {
        if (!candidate.isEmpty() && QFileInfo(candidate).isExecutable())
            return QFileInfo(candidate).absoluteFilePath();
    }
    return {};
}

} // namespace

WeatherClient::WeatherClient(QObject *parent)
    : QObject(parent)
    , m_snapshotDirectory(QDir(stateRoot()).filePath(
          QStringLiteral("quickshell/shell-data-service")))
    , m_snapshotPath(QDir(m_snapshotDirectory).filePath(QStringLiteral("snapshot.json")))
    , m_socketPath(qEnvironmentVariable(
          "KOS_DATA_SOCKET",
          QDir(runtimeRoot()).filePath(QStringLiteral("kos-data.sock"))))
{
    m_reconnectTimer.setInterval(1000);
    m_reconnectTimer.setSingleShot(true);
    connect(&m_reconnectTimer, &QTimer::timeout, this, &WeatherClient::connectSocket);

    m_snapshotFallbackTimer.setInterval(10000);
    connect(&m_snapshotFallbackTimer, &QTimer::timeout, this, [this] {
        ensureSnapshotWatch();
        reloadSnapshot();
    });
    m_snapshotFallbackTimer.start();

    connect(&m_socket, &QLocalSocket::connected, this, &WeatherClient::onSocketConnected);
    connect(&m_socket, &QLocalSocket::disconnected, this, &WeatherClient::onSocketDisconnected);
    connect(&m_socket, &QLocalSocket::readyRead, this, &WeatherClient::readSocketLines);
    connect(&m_socket, &QLocalSocket::errorOccurred, this, &WeatherClient::onSocketError);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] {
        reloadSnapshot();
    });

    ensureSnapshotWatch();
    reloadSnapshot();
    connectSocket();
}

bool WeatherClient::ready() const
{
    return m_ready;
}

bool WeatherClient::connected() const
{
    return m_socket.state() == QLocalSocket::ConnectedState;
}

bool WeatherClient::loading() const
{
    return m_loading;
}

bool WeatherClient::stale() const
{
    return m_ready && m_staleAt > 0 && QDateTime::currentMSecsSinceEpoch() >= m_staleAt;
}

bool WeatherClient::searching() const
{
    return m_searching;
}

QString WeatherClient::status() const
{
    return m_status;
}

QString WeatherClient::units() const
{
    return m_units;
}

QString WeatherClient::errorMessage() const
{
    return m_errorMessage;
}

QVariantMap WeatherClient::location() const
{
    return m_location;
}

QVariantList WeatherClient::locations() const
{
    return m_locations;
}

QVariantMap WeatherClient::current() const
{
    return m_current;
}

QVariantList WeatherClient::hourly() const
{
    return m_hourly;
}

QVariantList WeatherClient::daily() const
{
    return m_daily;
}

QVariantList WeatherClient::searchResults() const
{
    return m_searchResults;
}

qint64 WeatherClient::fetchedAt() const
{
    return m_fetchedAt;
}

qint64 WeatherClient::staleAt() const
{
    return m_staleAt;
}

void WeatherClient::refresh()
{
    sendRequest(QStringLiteral("weather.refresh"));
}

void WeatherClient::searchLocations(const QString &query)
{
    const QString normalized = query.trimmed();
    if (normalized.size() < 2) {
        clearSearch();
        return;
    }
    if (!m_searching) {
        m_searching = true;
        emit searchingChanged();
    }
    const QString language = QLocale().name().section(QLatin1Char('_'), 0, 0);
    sendRequest(QStringLiteral("weather.search"), {
        {QStringLiteral("query"), normalized},
        {QStringLiteral("language"), language},
        {QStringLiteral("limit"), 8},
    });
}

void WeatherClient::selectLocation(const QVariantMap &location)
{
    if (location.isEmpty())
        return;
    sendRequest(QStringLiteral("weather.set-location"), {
        {QStringLiteral("location"), location},
    });
    clearSearch();
}

void WeatherClient::setUnits(const QString &units)
{
    if (units != QLatin1String("metric") && units != QLatin1String("imperial"))
        return;
    sendRequest(QStringLiteral("weather.set-units"), {
        {QStringLiteral("units"), units},
    });
}

void WeatherClient::clearSearch()
{
    const bool hadResults = !m_searchResults.isEmpty();
    m_searchResults.clear();
    if (hadResults)
        emit searchResultsChanged();
    if (m_searching) {
        m_searching = false;
        emit searchingChanged();
    }
}

void WeatherClient::ensureServiceStarted()
{
    if (m_serviceStartAttempted
        || qEnvironmentVariableIsSet("KOS_WEATHER_DISABLE_SERVICE_AUTOSTART")) {
        return;
    }
    m_serviceStartAttempted = true;
    const QString executable = serviceExecutable();
    if (executable.isEmpty()) {
        setTransportError(tr("Weather data service is not installed"));
        return;
    }

    QProcess process;
    process.setProgram(executable);
    process.setStandardInputFile(QProcess::nullDevice());
    process.setStandardOutputFile(QProcess::nullDevice());
    process.setStandardErrorFile(QProcess::nullDevice());
    if (!process.startDetached())
        setTransportError(tr("Unable to start the weather data service"));
    QTimer::singleShot(5000, this, [this] {
        m_serviceStartAttempted = false;
    });
}

void WeatherClient::connectSocket()
{
    if (m_socket.state() != QLocalSocket::UnconnectedState)
        return;
    m_socket.connectToServer(m_socketPath, QIODevice::ReadWrite);
}

void WeatherClient::onSocketConnected()
{
    m_serviceStartAttempted = false;
    emit connectedChanged();
    sendRequest(QStringLiteral("weather.snapshot"));
    flushRequests();
}

void WeatherClient::onSocketDisconnected()
{
    emit connectedChanged();
    if (!m_reconnectTimer.isActive())
        m_reconnectTimer.start();
}

void WeatherClient::onSocketError(QLocalSocket::LocalSocketError error)
{
    if (error != QLocalSocket::PeerClosedError && !m_ready)
        setTransportError(tr("Weather data service is unavailable"));
    if (error != QLocalSocket::PeerClosedError)
        ensureServiceStarted();
    if (m_socket.state() != QLocalSocket::UnconnectedState)
        m_socket.abort();
    if (!m_reconnectTimer.isActive())
        m_reconnectTimer.start();
}

void WeatherClient::readSocketLines()
{
    m_readBuffer += m_socket.readAll();
    qsizetype newline = -1;
    while ((newline = m_readBuffer.indexOf('\n')) >= 0) {
        const QByteArray line = m_readBuffer.left(newline).trimmed();
        m_readBuffer.remove(0, newline + 1);
        if (!line.isEmpty())
            processSocketLine(line);
    }
}

void WeatherClient::processSocketLine(const QByteArray &line)
{
    if (!line.startsWith('{'))
        return;

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(line, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject())
        return;
    const QJsonObject response = document.object();
    if (response.value(QStringLiteral("event")).toString()
        == QLatin1String("weather.changed")) {
        sendRequest(QStringLiteral("weather.snapshot"));
        return;
    }

    const QString requestId = response.value(QStringLiteral("requestId")).toString();
    const QString operation = m_requestOperations.take(requestId);
    const bool ok = response.value(QStringLiteral("ok")).toBool();
    const QJsonObject result = response.value(QStringLiteral("result")).toObject();
    if (operation == QLatin1String("weather.search")) {
        m_searching = false;
        emit searchingChanged();
        m_searchResults = ok
            ? result.value(QStringLiteral("locations")).toArray().toVariantList()
            : QVariantList{};
        emit searchResultsChanged();
    }
    if (ok && operation == QLatin1String("weather.snapshot"))
        applyWeather(result.value(QStringLiteral("weather")).toObject());
    if (!ok) {
        const QString message = response.value(QStringLiteral("error")).toObject()
                                    .value(QStringLiteral("message")).toString();
        setTransportError(message.isEmpty() ? tr("Weather request failed") : message);
    }
}

void WeatherClient::sendRequest(const QString &operation, const QVariantMap &payload)
{
    const QString requestId = QStringLiteral("weather-%1").arg(++m_requestSerial);
    const QJsonObject request{
        {QStringLiteral("version"), 1},
        {QStringLiteral("requestId"), requestId},
        {QStringLiteral("operation"), operation},
        {QStringLiteral("payload"), QJsonObject::fromVariantMap(payload)},
    };
    const QByteArray encoded = QJsonDocument(request).toJson(QJsonDocument::Compact) + '\n';
    m_requestOperations.insert(requestId, operation);
    if (connected()) {
        m_socket.write(encoded);
        return;
    }
    if (m_pendingRequests.size() >= 16) {
        const QJsonObject dropped = QJsonDocument::fromJson(m_pendingRequests.dequeue()).object();
        m_requestOperations.remove(dropped.value(QStringLiteral("requestId")).toString());
    }
    m_pendingRequests.enqueue(encoded);
    connectSocket();
}

void WeatherClient::flushRequests()
{
    while (connected() && !m_pendingRequests.isEmpty())
        m_socket.write(m_pendingRequests.dequeue());
}

void WeatherClient::reloadSnapshot()
{
    QFile file(m_snapshotPath);
    if (!file.open(QIODevice::ReadOnly)) {
        ensureSnapshotWatch();
        return;
    }
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject())
        return;
    applyWeather(document.object().value(QStringLiteral("weather")).toObject());
    ensureSnapshotWatch();
}

void WeatherClient::applyWeather(const QJsonObject &weather)
{
    if (weather.value(QStringLiteral("schemaVersion")).toInt() != 1)
        return;

    m_status = weather.value(QStringLiteral("status")).toString(QStringLiteral("idle"));
    m_units = weather.value(QStringLiteral("units")).toString(QStringLiteral("metric"));
    m_errorMessage = weather.value(QStringLiteral("error")).toString();
    m_location = weather.value(QStringLiteral("location")).toObject().toVariantMap();
    m_locations = arrayToList(weather.value(QStringLiteral("locations")));
    m_current = weather.value(QStringLiteral("current")).toObject().toVariantMap();
    m_hourly = arrayToList(weather.value(QStringLiteral("hourly")));
    m_daily = arrayToList(weather.value(QStringLiteral("daily")));
    m_fetchedAt = weather.value(QStringLiteral("fetchedAt")).toInteger();
    m_staleAt = weather.value(QStringLiteral("staleAt")).toInteger();
    m_loading = m_status == QLatin1String("loading");
    m_ready = !m_current.isEmpty();
    emit snapshotChanged();
}

void WeatherClient::ensureSnapshotWatch()
{
    if (!QFileInfo::exists(m_snapshotDirectory))
        return;
    if (!m_watcher.directories().contains(m_snapshotDirectory))
        m_watcher.addPath(m_snapshotDirectory);
}

void WeatherClient::setTransportError(const QString &message)
{
    if (message.isEmpty() || m_errorMessage == message)
        return;
    m_errorMessage = message;
    emit snapshotChanged();
}
