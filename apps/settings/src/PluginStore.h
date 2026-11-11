#pragma once

#include <QJsonObject>
#include <QLocalSocket>
#include <QObject>
#include <QStringList>
#include <QTimer>
#include <QUrl>
#include <QVariantMap>

// Settings' persistent, asynchronous client for the authoritative platform plugin
// registry. Plans belong to this connection; no shell process or local registry.
class PluginStore final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap snapshot READ snapshot NOTIFY changed)
    Q_PROPERTY(QVariantMap plan READ plan NOTIFY planChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(bool connected READ connected NOTIFY changed)
    Q_PROPERTY(bool observing READ observing WRITE setObserving NOTIFY changed)
    Q_PROPERTY(QString operation READ operation NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(QString lastMessage READ lastMessage NOTIFY changed)
public:
    explicit PluginStore(QObject *parent = nullptr);
    QVariantMap snapshot() const { return m_snapshot; }
    QVariantMap plan() const { return m_plan; }
    bool busy() const { return !m_requestId.isEmpty(); }
    bool connected() const { return m_socket.state() == QLocalSocket::ConnectedState; }
    bool observing() const { return m_observing; }
    QString operation() const { return m_operation; }
    QString error() const { return m_error; }
    QString lastMessage() const { return m_lastMessage; }
    void setObserving(bool observing);

    Q_INVOKABLE void refresh(bool catalog = false);
    Q_INVOKABLE void prepareInstall(const QString &sourceId, const QString &pluginId);
    Q_INVOKABLE void importFile(const QUrl &file);
    Q_INVOKABLE void confirmInstall(const QStringList &permissions, bool trustLocal);
    Q_INVOKABLE void discardPlan();
    Q_INVOKABLE void setEnabled(const QString &pluginId, bool enabled);
    Q_INVOKABLE void uninstall(const QString &pluginId, bool removeData);
    Q_INVOKABLE void setPermissions(const QString &pluginId, const QStringList &permissions);
    Q_INVOKABLE void addInstance(const QString &pluginId, const QString &widgetId, const QString &size);

signals:
    void changed();
    void planChanged();
    void planReady();
    void operationFinished(const QString &operation, bool success);

private:
    void request(const QString &operation, const QJsonObject &payload = {});
    void sendRequest();
    void receive();
    void fail(const QString &message, bool disconnect = false);
    void applyReply(const QJsonObject &reply);
    QLocalSocket m_socket;
    QTimer m_poll, m_deadline, m_planExpiry;
    QByteArray m_buffer;
    QJsonObject m_payload;
    QVariantMap m_snapshot, m_plan;
    QString m_requestId, m_operation, m_error, m_lastMessage;
    quint64 m_serial = 0;
    bool m_observing = false;
    bool m_acceptPlan = false;
    bool m_sent = false;
};
