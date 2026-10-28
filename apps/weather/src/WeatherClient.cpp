#include "WeatherClient.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDebug>
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

// Upper bound for m_readBuffer: newline-delimited responses are small, so a
// peer that never sends '\n' must not grow the buffer without limit.
constexpr qsizetype kMaxSocketBufferBytes = 1024 * 1024;

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
    m_searchTimer.setSingleShot(true);
    m_searchTimer.setInterval(15000);
    connect(&m_searchTimer, &QTimer::timeout, this, [this] {
        ++m_searchGeneration;
        setSearchState(QStringLiteral("error"), tr("Search timed out. Try again."));
    });
    m_removeTimer.setSingleShot(true);
    m_removeTimer.setInterval(15000);
    connect(&m_removeTimer, &QTimer::timeout, this, [this] {
        m_removingLocationId.clear();
        m_removeRequestId.clear();
        m_locationError = tr("Could not confirm removal. Please try again.");
        emit locationActionChanged();
    });
    m_locationTimer.setSingleShot(true);
    m_locationTimer.setInterval(30000);
    connect(&m_locationTimer, &QTimer::timeout, this, [this] {
        setTransportError(tr("Weather data service is unavailable"));
    });
    m_reconnectTimer.setInterval(1000);
    m_reconnectTimer.setSingleShot(true);
    connect(&m_reconnectTimer, &QTimer::timeout, this, &WeatherClient::connectSocket);

    m_snapshotFallbackTimer.setInterval(10000);
    connect(&m_snapshotFallbackTimer, &QTimer::timeout, this, [this] {
        ensureSnapshotWatch();
        reloadSnapshot();
    });
    // Polling the snapshot file is only a fallback for when the socket is
    // down; once connected, weather.changed events and the file watcher
    // already cover updates, so gate the timer on connectedChanged.
    connect(this, &WeatherClient::connectedChanged, this, [this] {
        if (connected())
            m_snapshotFallbackTimer.stop();
        else
            m_snapshotFallbackTimer.start();
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

WeatherClient::~WeatherClient()
{
    // The socket outlives the member timers. Do not let its destructor emit
    // disconnected into reconnect handlers after those timers were destroyed.
    m_socket.disconnect(this);
    m_socket.abort();
    m_reconnectTimer.stop();
    m_snapshotFallbackTimer.stop();
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

QVariantMap WeatherClient::airQuality() const
{
    return m_airQuality;
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
    if (!m_requestedLocation.isEmpty()) {
        selectLocation(m_requestedLocation);
        return;
    }
    sendRequest(QStringLiteral("weather.refresh"));
}

void WeatherClient::searchLocations(const QString &query)
{
    const QString normalized = query.trimmed();
    if (normalized.size() < 2) {
        clearSearch();
        return;
    }
    clearSearch(); // Also invalidates every earlier query, including late replies.
    setSearchState(QStringLiteral("loading"));
    m_searchTimer.start();
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
    QVariantMap requested = location;
    if (requested.value(QStringLiteral("id")).toString().isEmpty()) {
        requested.insert(QStringLiteral("id"), QStringLiteral("manual:%1,%2")
            .arg(requested.value(QStringLiteral("latitude")).toDouble(), 0, 'f', 5)
            .arg(requested.value(QStringLiteral("longitude")).toDouble(), 0, 'f', 5));
    }
    if (m_ready && m_requestedLocation.isEmpty()
        && requested.value(QStringLiteral("id")) == m_location.value(QStringLiteral("id"))) {
        clearSearch();
        return;
    }

    // Hide the previous forecast in the same event as the click. Snapshots
    // already in flight must not restore a city the user has since left.
    m_requestedLocation = requested;
    ++m_locationGeneration;
    m_location = requested;
    m_current.clear();
    m_hourly.clear();
    m_daily.clear();
    m_airQuality.clear();
    m_fetchedAt = m_staleAt = 0;
    m_ready = false;
    m_loading = true;
    m_status = QStringLiteral("loading");
    m_errorMessage.clear();
    m_locationTimer.start();
    emit snapshotChanged();
    sendRequest(QStringLiteral("weather.set-location"), {
        {QStringLiteral("location"), requested},
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

void WeatherClient::setSearchState(const QString &status, const QString &error)
{
    const bool searching = status == QLatin1String("loading");
    if (m_searching != searching) {
        m_searching = searching;
        emit searchingChanged();
    }
    m_searchStatus = status;
    m_searchError = error;
    emit searchStateChanged();
}

void WeatherClient::clearSearch()
{
    ++m_searchGeneration;
    m_searchTimer.stop();
    if (!m_searchResults.isEmpty()) {
        m_searchResults.clear();
        emit searchResultsChanged();
    }
    setSearchState(QStringLiteral("idle"));
}

void WeatherClient::removeLocation(const QString &id)
{
    if (id.isEmpty() || !m_removingLocationId.isEmpty()) return;
    m_locationError.clear();
    if (!connected()) {
        m_locationError = tr("Connect to the weather service to remove a city.");
        emit locationActionChanged();
        return;
    }
    // A deletion replaces any pending selection; old snapshots cannot resurrect it.
    ++m_locationGeneration;
    m_requestedLocation.clear();
    m_locationTimer.stop();
    m_removingLocationId = id;
    m_removeTimer.start();
    emit locationActionChanged();
    sendRequest(QStringLiteral("weather.remove-location"), {{QStringLiteral("id"), id}});
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
    if (m_searching) {
        ++m_searchGeneration;
        m_searchTimer.stop();
        setSearchState(QStringLiteral("error"), tr("Search is unavailable. Check your connection and retry."));
    }
    if (!m_removingLocationId.isEmpty()) {
        m_removeTimer.stop();
        m_removingLocationId.clear();
        m_removeRequestId.clear();
        m_locationError = tr("Could not confirm removal. Please try again.");
        emit locationActionChanged();
    }
    if (!m_requestedLocation.isEmpty())
        setTransportError(tr("Weather data service is unavailable"));
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
    if (m_readBuffer.size() > kMaxSocketBufferBytes) {
        qWarning() << "WeatherClient: socket read buffer exceeded"
                   << kMaxSocketBufferBytes
                   << "bytes without a newline; dropping the connection";
        m_readBuffer.clear();
        // abort() emits disconnected(), which restarts the fallback timer
        // and schedules reconnect via onSocketDisconnected().
        m_socket.abort();
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
    const quint64 generation = m_requestGenerations.take(requestId);
    if (operation.startsWith(QLatin1String("weather."))
        && operation != QLatin1String("weather.search")
        && operation != QLatin1String("weather.remove-location")
        && generation != m_locationGeneration)
        return;
    const bool ok = response.value(QStringLiteral("ok")).toBool();
    const QJsonObject result = response.value(QStringLiteral("result")).toObject();
    if (operation == QLatin1String("weather.search")) {
        if (generation != m_searchGeneration) return;
        m_searchTimer.stop();
        m_searchResults = ok ? result.value(QStringLiteral("locations")).toArray().toVariantList() : QVariantList{};
        emit searchResultsChanged();
        setSearchState(ok ? (m_searchResults.isEmpty() ? QStringLiteral("empty") : QStringLiteral("ready"))
                          : QStringLiteral("error"),
                       ok ? QString{} : tr("Search is unavailable. Check your connection and retry."));
        return; // Search failures must never replace the forecast error/status.
    }
    if (operation == QLatin1String("weather.remove-location")) {
        if (requestId != m_removeRequestId) return;
        m_removeRequestId.clear();
        m_removeTimer.stop();
        m_removingLocationId.clear();
        m_locationError = ok ? QString{} : tr("Could not remove the city. Please try again.");
        emit locationActionChanged();
        sendRequest(QStringLiteral("weather.snapshot"));
        return;
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
    if (operation == QLatin1String("weather.remove-location")) m_removeRequestId = requestId;
    const QJsonObject request{
        {QStringLiteral("version"), 1},
        {QStringLiteral("requestId"), requestId},
        {QStringLiteral("operation"), operation},
        {QStringLiteral("payload"), QJsonObject::fromVariantMap(payload)},
    };
    const QByteArray encoded = QJsonDocument(request).toJson(QJsonDocument::Compact) + '\n';
    m_requestOperations.insert(requestId, operation);
    m_requestGenerations.insert(requestId, operation == QLatin1String("weather.search") ? m_searchGeneration : m_locationGeneration);
    if (connected()) {
        m_socket.write(encoded);
        return;
    }
    if (m_pendingRequests.size() >= 16) {
        const QJsonObject dropped = QJsonDocument::fromJson(m_pendingRequests.dequeue()).object();
        m_requestOperations.remove(dropped.value(QStringLiteral("requestId")).toString());
        m_requestGenerations.remove(dropped.value(QStringLiteral("requestId")).toString());
    }
    m_pendingRequests.enqueue(encoded);
    connectSocket();
}

void WeatherClient::flushRequests()
{
    while (connected() && !m_pendingRequests.isEmpty()) {
        const auto encoded = m_pendingRequests.dequeue();
        const auto request = QJsonDocument::fromJson(encoded).object();
        const auto id = request.value(QStringLiteral("requestId")).toString();
        if (m_requestOperations.value(id) == QLatin1String("weather.search")
            && m_requestGenerations.value(id) != m_searchGeneration) {
            m_requestOperations.remove(id);
            m_requestGenerations.remove(id);
            continue;
        }
        m_socket.write(encoded);
    }
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

    const auto location = weather.value(QStringLiteral("location")).toObject().toVariantMap();
    if (!m_requestedLocation.isEmpty()
        && location.value(QStringLiteral("id")) != m_requestedLocation.value(QStringLiteral("id")))
        return;

    m_status = weather.value(QStringLiteral("status")).toString(QStringLiteral("idle"));
    m_units = weather.value(QStringLiteral("units")).toString(QStringLiteral("metric"));
    m_errorMessage = weather.value(QStringLiteral("error")).toString();
    m_location = weather.value(QStringLiteral("location")).toObject().toVariantMap();
    m_locations = arrayToList(weather.value(QStringLiteral("locations")));
    m_current = weather.value(QStringLiteral("current")).toObject().toVariantMap();
    m_hourly = arrayToList(weather.value(QStringLiteral("hourly")));
    m_daily = arrayToList(weather.value(QStringLiteral("daily")));
    m_airQuality = weather.value(QStringLiteral("airQuality")).toObject().toVariantMap();
    m_fetchedAt = weather.value(QStringLiteral("fetchedAt")).toInteger();
    m_staleAt = weather.value(QStringLiteral("staleAt")).toInteger();
    m_loading = m_status == QLatin1String("loading");
    m_ready = !m_current.isEmpty();
    if (m_ready || m_status == QLatin1String("error")) {
        m_locationTimer.stop();
        // Keep the requested city on failure so Refresh can retry it.
        if (m_ready)
            m_requestedLocation.clear();
    }
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
    if (!m_requestedLocation.isEmpty()) {
        m_loading = false;
        m_status = QStringLiteral("error");
        m_locationTimer.stop();
    }
    emit snapshotChanged();
}
