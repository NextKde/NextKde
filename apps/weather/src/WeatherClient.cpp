#include "WeatherClient.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>

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

} // namespace

WeatherClient::WeatherClient(QObject *parent)
    : QObject(parent)
    , m_snapshotDirectory(QDir(stateRoot()).filePath(
          QStringLiteral("quickshell/shell-data-service")))
    , m_snapshotPath(QDir(m_snapshotDirectory).filePath(QStringLiteral("snapshot.json")))
    , m_socketPath(QDir(runtimeRoot()).filePath(QStringLiteral("shell-data-service.sock")))
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
    sendRequest({{QStringLiteral("type"), QStringLiteral("weather_refresh")}});
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
    sendRequest({
        {QStringLiteral("type"), QStringLiteral("weather_search")},
        {QStringLiteral("query"), normalized},
        {QStringLiteral("language"), language},
        {QStringLiteral("limit"), 8},
    });
}

void WeatherClient::selectLocation(const QVariantMap &location)
{
    if (location.isEmpty())
        return;
    sendRequest({
        {QStringLiteral("type"), QStringLiteral("weather_set_location")},
        {QStringLiteral("location"), location},
    });
    clearSearch();
}

void WeatherClient::setUnits(const QString &units)
{
    if (units != QLatin1String("metric") && units != QLatin1String("imperial"))
        return;
    sendRequest({
        {QStringLiteral("type"), QStringLiteral("weather_set_units")},
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

void WeatherClient::connectSocket()
{
    if (m_socket.state() != QLocalSocket::UnconnectedState)
        return;
    m_socket.connectToServer(m_socketPath, QIODevice::ReadWrite);
}

void WeatherClient::onSocketConnected()
{
    emit connectedChanged();
    const QByteArray subscription = QJsonDocument(QJsonObject{
        {QStringLiteral("type"), QStringLiteral("subscribe_weather")},
    }).toJson(QJsonDocument::Compact) + '\n';
    m_socket.write(subscription);
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
    if (m_socket.state() == QLocalSocket::UnconnectedState && !m_reconnectTimer.isActive())
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
    if (line == QByteArrayLiteral("weather_changed")) {
        reloadSnapshot();
        return;
    }
    if (!line.startsWith('{'))
        return;

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(line, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject())
        return;
    const QJsonObject response = document.object();
    const QString type = response.value(QStringLiteral("type")).toString();
    const bool ok = response.value(QStringLiteral("ok")).toBool();
    if (type == QLatin1String("weather_search")) {
        m_searching = false;
        emit searchingChanged();
        m_searchResults = ok
            ? response.value(QStringLiteral("locations")).toArray().toVariantList()
            : QVariantList{};
        emit searchResultsChanged();
    }
    if (!ok) {
        setTransportError(response.value(QStringLiteral("error")).toString(
            tr("Weather request failed")));
    }
}

void WeatherClient::sendRequest(const QVariantMap &request)
{
    const QByteArray payload = QJsonDocument(QJsonObject::fromVariantMap(request))
                                   .toJson(QJsonDocument::Compact) + '\n';
    if (connected()) {
        m_socket.write(payload);
        return;
    }
    if (m_pendingRequests.size() >= 16)
        m_pendingRequests.dequeue();
    m_pendingRequests.enqueue(payload);
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
    const QJsonObject weather = document.object().value(QStringLiteral("weather")).toObject();
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
    ensureSnapshotWatch();
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
