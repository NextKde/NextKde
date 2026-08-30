#include "PimClient.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusError>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusReply>
#include <QDBusServiceWatcher>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

#include <algorithm>

namespace {

constexpr auto serviceName = "org.nextkde.Kos.Pim1";
constexpr auto objectPath = "/Pim";
constexpr auto interfaceName = "org.nextkde.Kos.Pim1";

QString payload(const QVariantMap &value)
{
    return QString::fromUtf8(QJsonDocument(QJsonObject::fromVariantMap(value))
                                 .toJson(QJsonDocument::Compact));
}

QString responseError(const QJsonObject &object, const QString &fallback)
{
    const QJsonValue error = object.value(QStringLiteral("error"));
    if (error.isObject())
        return error.toObject().value(QStringLiteral("message")).toString(fallback);
    if (error.isString())
        return error.toString(fallback);
    return fallback;
}

} // namespace

PimClient::PimClient(QObject *parent)
    : QObject(parent)
    , m_serviceWatcher(new QDBusServiceWatcher(
          QString::fromLatin1(serviceName), QDBusConnection::sessionBus(),
          QDBusServiceWatcher::WatchForOwnerChange, this))
{
    connect(m_serviceWatcher, &QDBusServiceWatcher::serviceOwnerChanged,
            this, &PimClient::onServiceChanged);
    QDBusConnection::sessionBus().connect(
        QString::fromLatin1(serviceName), QString::fromLatin1(objectPath),
        QString::fromLatin1(interfaceName), QStringLiteral("changed"),
        this, SLOT(onRemoteChanged(qulonglong)));

    if (QDBusConnectionInterface *interface = QDBusConnection::sessionBus().interface()) {
        const QDBusReply<bool> registered = interface->isServiceRegistered(
            QString::fromLatin1(serviceName));
        setConnected(registered.isValid() && registered.value());
    }
    refresh();
}

bool PimClient::ready() const
{
    return m_ready;
}

bool PimClient::connected() const
{
    return m_connected;
}

bool PimClient::busy() const
{
    return m_pendingCalls > 0;
}

bool PimClient::writable() const
{
    return m_writable;
}

QString PimClient::errorMessage() const
{
    return m_errorMessage;
}

qulonglong PimClient::revision() const
{
    return m_revision;
}

QVariantList PimClient::lists() const
{
    return m_lists;
}

QVariantList PimClient::events() const
{
    return m_events;
}

QVariantList PimClient::occurrences() const
{
    return m_occurrences;
}

QVariantList PimClient::todos() const
{
    return m_todos;
}

void PimClient::refresh()
{
    invoke(QStringLiteral("snapshot"), {}, ReplyKind::Snapshot);
}

void PimClient::setEventRange(const QString &startDate, const QString &endDate)
{
    if (m_rangeStart == startDate && m_rangeEnd == endDate && !m_occurrences.isEmpty())
        return;
    m_rangeStart = startDate;
    m_rangeEnd = endDate;
    requestRange();
}

void PimClient::createEvent(const QVariantMap &event)
{
    invoke(QStringLiteral("createEvent"), {payload(event)}, ReplyKind::Mutation,
           QStringLiteral("createEvent"));
}

void PimClient::updateEvent(const QString &uid, const QVariantMap &event)
{
    invoke(QStringLiteral("updateEvent"), {uid, payload(event)}, ReplyKind::Mutation,
           QStringLiteral("updateEvent"), uid);
}

void PimClient::removeEvent(const QString &uid)
{
    invoke(QStringLiteral("removeEvent"), {uid}, ReplyKind::Mutation,
           QStringLiteral("removeEvent"), uid);
}

void PimClient::createTodo(const QVariantMap &todo)
{
    invoke(QStringLiteral("createTodo"), {payload(todo)}, ReplyKind::Mutation,
           QStringLiteral("createTodo"));
}

void PimClient::updateTodo(const QString &uid, const QVariantMap &todo)
{
    invoke(QStringLiteral("updateTodo"), {uid, payload(todo)}, ReplyKind::Mutation,
           QStringLiteral("updateTodo"), uid);
}

void PimClient::removeTodo(const QString &uid)
{
    invoke(QStringLiteral("removeTodo"), {uid}, ReplyKind::Mutation,
           QStringLiteral("removeTodo"), uid);
}

void PimClient::createList(const QVariantMap &list)
{
    invoke(QStringLiteral("createList"), {payload(list)}, ReplyKind::Mutation,
           QStringLiteral("createList"));
}

void PimClient::updateList(const QString &id, const QVariantMap &list)
{
    invoke(QStringLiteral("updateList"), {id, payload(list)}, ReplyKind::Mutation,
           QStringLiteral("updateList"), id);
}

void PimClient::removeList(const QString &id)
{
    invoke(QStringLiteral("removeList"), {id}, ReplyKind::Mutation,
           QStringLiteral("removeList"), id);
}

void PimClient::importIcalendar(const QString &path, bool replaceExisting)
{
    invoke(QStringLiteral("importIcalendar"), {path, replaceExisting}, ReplyKind::Mutation,
           QStringLiteral("importIcalendar"));
}

void PimClient::exportIcalendar(const QString &path)
{
    invoke(QStringLiteral("exportIcalendar"), {path}, ReplyKind::Mutation,
           QStringLiteral("exportIcalendar"));
}

void PimClient::onServiceChanged(const QString &, const QString &, const QString &newOwner)
{
    setConnected(!newOwner.isEmpty());
    if (m_connected)
        refresh();
}

void PimClient::onRemoteChanged(qulonglong revision)
{
    if (revision >= m_revision)
        refresh();
}

void PimClient::invoke(const QString &method, const QVariantList &arguments,
                       ReplyKind kind, const QString &operation, const QString &itemId)
{
    QDBusMessage message = QDBusMessage::createMethodCall(
        QString::fromLatin1(serviceName), QString::fromLatin1(objectPath),
        QString::fromLatin1(interfaceName), method);
    message.setArguments(arguments);
    auto *watcher = new QDBusPendingCallWatcher(
        QDBusConnection::sessionBus().asyncCall(message, 30000), this);
    changePending(1);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, kind, operation, itemId](QDBusPendingCallWatcher *finished) {
                handleReply(finished, kind, operation, itemId);
            });
}

void PimClient::handleReply(QDBusPendingCallWatcher *watcher, ReplyKind kind,
                            const QString &operation, const QString &itemId)
{
    changePending(-1);
    const QDBusPendingReply<QString> reply = *watcher;
    watcher->deleteLater();
    if (reply.isError()) {
        setConnected(false);
        const QString message = tr("PIM service is unavailable: %1")
                                    .arg(reply.error().message());
        setErrorMessage(message);
        if (kind == ReplyKind::Mutation)
            emit operationFailed(operation, message);
        return;
    }
    setConnected(true);

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(
        reply.value().toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        const QString message = tr("PIM service returned invalid data");
        setErrorMessage(message);
        if (kind == ReplyKind::Mutation)
            emit operationFailed(operation, message);
        return;
    }
    const QJsonObject object = document.object();
    if (kind == ReplyKind::Snapshot) {
        if (object.value(QStringLiteral("schemaVersion")).toInt() != 1) {
            setErrorMessage(tr("Unsupported PIM data version"));
            return;
        }
        m_revision = static_cast<qulonglong>(
            object.value(QStringLiteral("revision")).toDouble());
        m_writable = object.value(QStringLiteral("writable")).toBool();
        m_lists = object.value(QStringLiteral("lists")).toArray().toVariantList();
        m_events = object.value(QStringLiteral("events")).toArray().toVariantList();
        m_todos = object.value(QStringLiteral("todos")).toArray().toVariantList();
        m_ready = true;
        setErrorMessage(object.value(QStringLiteral("error")).toString());
        emit snapshotChanged();
        requestRange();
        return;
    }
    if (!object.value(QStringLiteral("ok")).toBool()) {
        const QString message = responseError(object, tr("PIM operation failed"));
        setErrorMessage(message);
        if (kind == ReplyKind::Mutation)
            emit operationFailed(operation, message);
        return;
    }
    if (kind == ReplyKind::Range) {
        m_occurrences = object.value(QStringLiteral("occurrences")).toArray().toVariantList();
        emit occurrencesChanged();
        return;
    }
    setErrorMessage({});
    QString resolvedId = itemId;
    if (resolvedId.isEmpty()) {
        resolvedId = object.value(QStringLiteral("item")).toObject()
                         .value(QStringLiteral("id")).toString();
    }
    emit operationSucceeded(operation, resolvedId);
    refresh();
}

void PimClient::requestRange()
{
    if (m_rangeStart.isEmpty() || m_rangeEnd.isEmpty())
        return;
    invoke(QStringLiteral("eventsForRange"), {m_rangeStart, m_rangeEnd},
           ReplyKind::Range);
}

void PimClient::setConnected(bool connected)
{
    if (m_connected == connected)
        return;
    m_connected = connected;
    emit connectedChanged();
}

void PimClient::setErrorMessage(const QString &message)
{
    if (m_errorMessage == message)
        return;
    m_errorMessage = message;
    emit errorMessageChanged();
}

void PimClient::changePending(int delta)
{
    const bool wasBusy = busy();
    m_pendingCalls = std::max(0, m_pendingCalls + delta);
    if (wasBusy != busy())
        emit busyChanged();
}
