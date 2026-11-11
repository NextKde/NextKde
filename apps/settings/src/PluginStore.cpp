#include "PluginStore.h"

#include <QDateTime>
#include <QDir>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonParseError>

namespace {
constexpr qsizetype MaxReplyBytes = 8 * 1024 * 1024;
}

PluginStore::PluginStore(QObject *parent) : QObject(parent)
{
    m_poll.setInterval(10000);
    m_deadline.setSingleShot(true);
    m_planExpiry.setSingleShot(true);
    m_socket.setReadBufferSize(MaxReplyBytes + 1);
    connect(&m_poll, &QTimer::timeout, this, [this] {
        if (!busy()) refresh();
    });
    connect(&m_socket, &QLocalSocket::connected, this, [this] {
        emit changed();
        sendRequest();
    });
    connect(&m_socket, &QLocalSocket::readyRead, this, &PluginStore::receive);
    connect(&m_socket, &QLocalSocket::disconnected, this, [this] {
        if (busy()) fail(QStringLiteral("Plugin service disconnected. Refresh to check the current state."));
        discardPlan();
        emit changed();
    });
    connect(&m_socket, &QLocalSocket::errorOccurred, this, [this](QLocalSocket::LocalSocketError) {
        if (busy()) fail(QStringLiteral("Plugin service unavailable. Refresh to reconnect."), true);
    });
    connect(&m_deadline, &QTimer::timeout, this, [this] {
        fail(QStringLiteral("Plugin request timed out. Refresh to check the current state."), true);
    });
    connect(&m_planExpiry, &QTimer::timeout, this, [this] {
        discardPlan();
        m_error = QStringLiteral("Installation plan expired. Review a new plan before installing.");
        emit changed();
    });
}

void PluginStore::setObserving(bool observing)
{
    if (m_observing == observing) return;
    m_observing = observing;
    if (observing) {
        m_poll.start();
        refresh();
    } else {
        m_poll.stop();
        discardPlan();
    }
    emit changed();
}

void PluginStore::refresh(bool catalog)
{
    if (!busy()) request(catalog ? QStringLiteral("plugin.refresh-catalog") : QStringLiteral("plugin.snapshot"));
}

void PluginStore::prepareInstall(const QString &sourceId, const QString &pluginId)
{
    if (busy()) return;
    discardPlan();
    m_acceptPlan = true;
    request(QStringLiteral("plugin.prepare-install"), {{"sourceId", sourceId}, {"pluginId", pluginId}});
}

void PluginStore::importFile(const QUrl &file)
{
    if (busy()) return;
    if (!file.isLocalFile() || file.toLocalFile().isEmpty()) {
        m_error = QStringLiteral("Select a local plugin JSON file.");
        emit changed();
        return;
    }
    discardPlan();
    m_acceptPlan = true;
    request(QStringLiteral("plugin.prepare-install"), {{"path", file.toLocalFile()}});
}

void PluginStore::confirmInstall(const QStringList &permissions, bool trustLocal)
{
    if (busy() || m_plan.isEmpty()) return;
    const QString id = m_plan.value(QStringLiteral("id")).toString();
    discardPlan();
    request(QStringLiteral("plugin.confirm-install"), {
        {"planId", id}, {"permissions", QJsonArray::fromStringList(permissions)}, {"trustLocal", trustLocal}
    });
}

void PluginStore::discardPlan()
{
    m_acceptPlan = false;
    m_planExpiry.stop();
    if (m_plan.isEmpty()) return;
    m_plan.clear();
    emit planChanged();
}

void PluginStore::setEnabled(const QString &pluginId, bool enabled)
{
    request(QStringLiteral("plugin.set-enabled"), {{"pluginId", pluginId}, {"enabled", enabled}});
}

void PluginStore::uninstall(const QString &pluginId, bool removeData)
{
    request(QStringLiteral("plugin.uninstall"), {{"pluginId", pluginId}, {"removeData", removeData}});
}

void PluginStore::setPermissions(const QString &pluginId, const QStringList &permissions)
{
    request(QStringLiteral("plugin.set-permissions"), {
        {"pluginId", pluginId}, {"permissions", QJsonArray::fromStringList(permissions)}
    });
}

void PluginStore::addInstance(const QString &pluginId, const QString &widgetId, const QString &size)
{
    request(QStringLiteral("plugin.instance-add"), {{"pluginId", pluginId}, {"widgetId", widgetId}, {"size", size}});
}

void PluginStore::request(const QString &operation, const QJsonObject &payload)
{
    if (busy()) return; // One in-flight action, never replay a mutation after disconnect.
    if (operation != QLatin1String("plugin.prepare-install") && operation != QLatin1String("plugin.snapshot"))
        discardPlan();
    m_operation = operation;
    m_requestId = QStringLiteral("settings-plugins-%1-%2").arg(QDateTime::currentMSecsSinceEpoch()).arg(++m_serial);
    m_payload = payload;
    m_sent = false;
    if (operation != QLatin1String("plugin.snapshot")) {
        m_error.clear();
        m_lastMessage.clear();
    }
    emit changed();
    m_deadline.start(operation == QLatin1String("plugin.prepare-install")
        || operation == QLatin1String("plugin.refresh-catalog") ? 180000 : 30000);
    if (connected()) {
        sendRequest();
        return;
    }
    QString path = qEnvironmentVariable("KOS_PLATFORM_SOCKET");
    if (path.isEmpty()) {
        const QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
        if (!runtime.isEmpty()) path = QDir(runtime).filePath(QStringLiteral("kos-platform.sock"));
    }
    if (path.isEmpty()) {
        fail(QStringLiteral("Plugin service unavailable. Refresh to reconnect."));
        return;
    }
    m_socket.connectToServer(path);
}

void PluginStore::sendRequest()
{
    if (!busy() || m_sent || !connected()) return;
    m_sent = true;
    const QJsonObject envelope{{"version", 1}, {"requestId", m_requestId},
        {"operation", m_operation}, {"payload", m_payload}};
    const QByteArray bytes = QJsonDocument(envelope).toJson(QJsonDocument::Compact) + '\n';
    if (m_socket.write(bytes) != bytes.size())
        fail(QStringLiteral("Plugin service disconnected. Refresh to check the current state."), true);
}

void PluginStore::receive()
{
    m_buffer += m_socket.readAll();
    if (m_buffer.size() > MaxReplyBytes) {
        fail(QStringLiteral("Invalid plugin service response."), true);
        return;
    }
    qsizetype end;
    while ((end = m_buffer.indexOf('\n')) >= 0) {
        const QByteArray line = m_buffer.left(end);
        m_buffer.remove(0, end + 1);
        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(line, &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
            fail(QStringLiteral("Invalid plugin service response."), true);
            return;
        }
        const QJsonObject reply = document.object();
        if (reply.value(QStringLiteral("requestId")).toString() != m_requestId || !busy()) continue;
        if (reply.value(QStringLiteral("version")).toInt() != 1) {
            fail(QStringLiteral("Invalid plugin service response."), true);
            return;
        }
        applyReply(reply);
    }
}

void PluginStore::applyReply(const QJsonObject &reply)
{
    const QString operation = m_operation;
    m_deadline.stop();
    m_requestId.clear();
    m_operation.clear();
    m_payload = {};
    if (!reply.value(QStringLiteral("ok")).toBool()) {
        const auto error = reply.value(QStringLiteral("error")).toObject();
        m_error = error.value(QStringLiteral("message")).toString();
        if (m_error.isEmpty()) m_error = error.value(QStringLiteral("code")).toString();
        if (m_error.isEmpty()) m_error = QStringLiteral("Plugin operation failed.");
        discardPlan();
        emit changed();
        emit operationFinished(operation, false);
        return;
    }
    const QJsonObject result = reply.value(QStringLiteral("result")).toObject();
    if (!result.value(QStringLiteral("plugins")).isArray()
        || !result.value(QStringLiteral("catalog")).isArray()
        || !result.value(QStringLiteral("instances")).isArray()) {
        fail(QStringLiteral("Invalid plugin service response."), true);
        emit operationFinished(operation, false);
        return;
    }
    if (!m_plan.isEmpty() && m_snapshot.value(QStringLiteral("revision")) != result.value(QStringLiteral("revision")).toVariant()) {
        discardPlan();
        m_error = QStringLiteral("Plugin state changed. Review a new installation plan.");
    } else if (operation != QLatin1String("plugin.snapshot")
        || m_error.startsWith(QLatin1String("Plugin service"))
        || m_error.startsWith(QLatin1String("Plugin request timed out"))) {
        m_error.clear();
    }
    m_snapshot = result.toVariantMap();
    m_snapshot.remove(QStringLiteral("plan"));
    if (operation == QLatin1String("plugin.prepare-install") && m_acceptPlan) {
        m_plan = result.value(QStringLiteral("plan")).toObject().toVariantMap();
        m_acceptPlan = false;
        if (m_plan.isEmpty()) {
            m_error = QStringLiteral("Invalid plugin service response.");
        } else {
            // Backend remains authoritative about expiresAt and revision. Stop
            // displaying a review after five minutes even without further clicks.
            m_planExpiry.start(300000);
            emit planChanged();
        }
    } else if (operation == QLatin1String("plugin.confirm-install")) {
        m_lastMessage = QStringLiteral("Plugin installed. Add a widget to place it on the desktop.");
    } else if (operation == QLatin1String("plugin.instance-add")) {
        m_lastMessage = QStringLiteral("Widget added to the desktop.");
    } else if (operation == QLatin1String("plugin.uninstall")) {
        m_lastMessage = QStringLiteral("Plugin uninstalled.");
    } else if (operation != QLatin1String("plugin.snapshot")) {
        m_lastMessage = QStringLiteral("Plugin state updated.");
    }
    emit changed();
    if (!m_plan.isEmpty() && operation == QLatin1String("plugin.prepare-install")) emit planReady();
    emit operationFinished(operation, true);
}

void PluginStore::fail(const QString &message, bool disconnect)
{
    const QString operation = m_operation;
    m_deadline.stop();
    m_requestId.clear();
    m_operation.clear();
    m_payload = {};
    m_buffer.clear();
    m_error = message;
    discardPlan();
    if (disconnect) m_socket.abort();
    emit changed();
    if (!operation.isEmpty()) emit operationFinished(operation, false);
}
