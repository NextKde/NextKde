#include "PimStore.h"

#include <KCalendarCore/Alarm>
#include <KCalendarCore/Duration>
#include <KCalendarCore/Event>
#include <KCalendarCore/ICalFormat>
#include <KCalendarCore/MemoryCalendar>
#include <KCalendarCore/OccurrenceIterator>
#include <KCalendarCore/Recurrence>
#include <KCalendarCore/Todo>

#include <QDateTime>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDir>
#include <QDebug>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <QTimeZone>
#include <QTimer>
#include <QUuid>

#include <algorithm>
#include <limits>
#include <utility>

namespace {

constexpr int pimSchemaVersion = 1;
constexpr qsizetype maximumPayloadBytes = 1024 * 1024;
constexpr qint64 maximumImportBytes = 20 * 1024 * 1024;
constexpr auto customApp = "KOS";
constexpr auto keyCalendarId = "CALENDAR-ID";
constexpr auto keyListId = "LIST-ID";
constexpr auto keyParentId = "PARENT-ID";
constexpr auto keyOrder = "ORDER";
constexpr auto keyRecurrence = "RECURRENCE-PRESET";
constexpr auto keyLinkedTodoId = "LINKED-TODO-ID";
constexpr auto keyLinkedEventId = "LINKED-EVENT-ID";

QString defaultStorageDirectory()
{
    const QString configured = qEnvironmentVariable("KOS_PIM_STORAGE_DIR");
    if (!configured.isEmpty())
        return configured;
    return QDir(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation))
        .filePath(QStringLiteral("kos/pim"));
}

QString compactJson(const QJsonObject &object)
{
    return QString::fromUtf8(QJsonDocument(object).toJson(QJsonDocument::Compact));
}

QString errorResponse(const QString &code, const QString &message)
{
    return compactJson({
        {QStringLiteral("ok"), false},
        {QStringLiteral("error"), QJsonObject{
             {QStringLiteral("code"), code},
             {QStringLiteral("message"), message},
         }},
    });
}

QString successResponse(quint64 revision, const QJsonObject &item = {})
{
    QJsonObject response{
        {QStringLiteral("ok"), true},
        {QStringLiteral("revision"), static_cast<double>(revision)},
    };
    if (!item.isEmpty())
        response.insert(QStringLiteral("item"), item);
    return compactJson(response);
}

bool parsePayload(const QString &payload, QJsonObject *result, QString *message)
{
    const QByteArray bytes = payload.toUtf8();
    if (bytes.size() > maximumPayloadBytes) {
        *message = QStringLiteral("PIM payload exceeds 1 MiB");
        return false;
    }
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(bytes, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        *message = QStringLiteral("PIM payload must be one JSON object");
        return false;
    }
    *result = document.object();
    return true;
}

QString boundedString(const QJsonObject &payload, const QString &key, qsizetype maximum,
                      bool *valid)
{
    const QString value = payload.value(key).toString().trimmed();
    if (value.size() > maximum)
        *valid = false;
    return value;
}

QDateTime parseDateTime(const QJsonValue &value, bool allDay, const QTimeZone &timeZone)
{
    const QString encoded = value.toString().trimmed();
    if (encoded.isEmpty())
        return {};
    if (allDay) {
        const QDate date = QDate::fromString(encoded.left(10), Qt::ISODate);
        return date.isValid() ? QDateTime(date, QTime(0, 0), timeZone) : QDateTime{};
    }
    QDateTime result = QDateTime::fromString(encoded, Qt::ISODateWithMs);
    if (!result.isValid())
        result = QDateTime::fromString(encoded, Qt::ISODate);
    if (result.isValid() && timeZone.isValid())
        result = result.toTimeZone(timeZone);
    return result;
}

QString encodeDateTime(const QDateTime &value)
{
    return value.isValid() ? value.toString(Qt::ISODateWithMs) : QString{};
}

QJsonArray defaultLists()
{
    return {
        QJsonObject{
            {QStringLiteral("id"), QStringLiteral("inbox")},
            {QStringLiteral("name"), QStringLiteral("Inbox")},
            {QStringLiteral("color"), QStringLiteral("#4f8cff")},
            {QStringLiteral("position"), 0},
        },
        QJsonObject{
            {QStringLiteral("id"), QStringLiteral("personal")},
            {QStringLiteral("name"), QStringLiteral("Personal")},
            {QStringLiteral("color"), QStringLiteral("#39c487")},
            {QStringLiteral("position"), 1},
        },
    };
}

QString recurrencePreset(const KCalendarCore::Incidence::Ptr &incidence)
{
    const QString stored = incidence->customProperty(customApp, keyRecurrence);
    if (!stored.isEmpty())
        return stored;
    return incidence->recurs() ? QStringLiteral("custom") : QStringLiteral("none");
}

int reminderMinutes(const KCalendarCore::Incidence::Ptr &incidence)
{
    for (const KCalendarCore::Alarm::Ptr &alarm : incidence->alarms()) {
        if (!alarm->enabled())
            continue;
        if (alarm->hasStartOffset()) {
            const int seconds = alarm->startOffset().asSeconds();
            if (seconds <= 0)
                return -seconds / 60;
        }
        if (alarm->hasEndOffset()) {
            const int endSeconds = alarm->endOffset().asSeconds();
            if (endSeconds <= 0)
                return -endSeconds / 60;
        }
    }
    return -1;
}

void applyReminder(const KCalendarCore::Incidence::Ptr &incidence, int minutes)
{
    incidence->clearAlarms();
    if (minutes < 0)
        return;
    auto alarm = incidence->newAlarm();
    alarm->setDisplayAlarm(incidence->summary());
    const auto todo = qSharedPointerDynamicCast<KCalendarCore::Todo>(incidence);
    if (todo && !todo->hasStartDate() && todo->hasDueDate())
        alarm->setEndOffset(KCalendarCore::Duration(-minutes * 60));
    else
        alarm->setStartOffset(KCalendarCore::Duration(-minutes * 60));
    alarm->setEnabled(true);
}

bool applyRecurrence(const KCalendarCore::Incidence::Ptr &incidence,
                     const QJsonObject &payload, QString *message)
{
    if (!payload.contains(QStringLiteral("recurrence")))
        return true;
    const QString recurrence = payload.value(QStringLiteral("recurrence")).toString(
        QStringLiteral("none"));
    KCalendarCore::Recurrence *rule = incidence->recurrence();
    rule->clear();
    if (recurrence == QLatin1String("none")) {
        incidence->removeCustomProperty(customApp, keyRecurrence);
        return true;
    }
    const auto todo = qSharedPointerDynamicCast<KCalendarCore::Todo>(incidence);
    if (!incidence->dtStart().isValid() && (!todo || !todo->hasDueDate())) {
        *message = QStringLiteral("A recurring item requires a start or due date");
        return false;
    }
    if (recurrence == QLatin1String("daily"))
        rule->setDaily(1);
    else if (recurrence == QLatin1String("weekly"))
        rule->setWeekly(1);
    else if (recurrence == QLatin1String("monthly"))
        rule->setMonthly(1);
    else if (recurrence == QLatin1String("yearly"))
        rule->setYearly(1);
    else {
        *message = QStringLiteral("Unsupported recurrence preset");
        return false;
    }
    const int count = payload.value(QStringLiteral("recurrenceCount")).toInt();
    if (count > 0)
        rule->setDuration(std::min(count, 10000));
    const QDate until = QDate::fromString(
        payload.value(QStringLiteral("recurrenceUntil")).toString(), Qt::ISODate);
    if (until.isValid())
        rule->setEndDate(until);
    incidence->setCustomProperty(customApp, keyRecurrence, recurrence);
    return true;
}

QString linkedEventId(const KCalendarCore::Todo::Ptr &todo)
{
    const QString customId = todo->customProperty(customApp, keyLinkedEventId);
    return customId.isEmpty() ? todo->relatedTo() : customId;
}

QString linkedTodoId(const KCalendarCore::Event::Ptr &event,
                     const KCalendarCore::MemoryCalendar *calendar)
{
    const QString customId = event->customProperty(customApp, keyLinkedTodoId);
    if (!customId.isEmpty() && (!calendar || calendar->todo(customId)))
        return customId;
    if (!calendar)
        return customId;
    for (const KCalendarCore::Todo::Ptr &todo : calendar->rawTodos()) {
        if (linkedEventId(todo) == event->uid())
            return todo->uid();
    }
    return {};
}

void linkEventAndTodo(const KCalendarCore::Event::Ptr &event,
                      const KCalendarCore::Todo::Ptr &todo)
{
    event->setCustomProperty(customApp, keyLinkedTodoId, todo->uid());
    todo->setCustomProperty(customApp, keyLinkedEventId, event->uid());
    // RELATED-TO keeps the relationship meaningful to other iCalendar tools.
    // The reverse lookup remains an X-property because one VEVENT can only
    // carry one standard relation of each type in KCalendarCore.
    todo->setRelatedTo(event->uid());
}

void unlinkEventAndTodo(const KCalendarCore::Event::Ptr &event,
                        const KCalendarCore::Todo::Ptr &todo)
{
    if (event && todo && reminderMinutes(todo) < 0)
        applyReminder(todo, reminderMinutes(event));
    if (event)
        event->removeCustomProperty(customApp, keyLinkedTodoId);
    if (todo) {
        todo->removeCustomProperty(customApp, keyLinkedEventId);
        todo->setRelatedTo(QString{});
    }
}

bool copyEditableRecurrence(const KCalendarCore::Incidence::Ptr &source,
                            const KCalendarCore::Incidence::Ptr &destination,
                            QString *message)
{
    const QString preset = recurrencePreset(source);
    if (preset == QLatin1String("custom"))
        return true;
    return applyRecurrence(destination, {
        {QStringLiteral("recurrence"), preset},
    }, message);
}

bool synchronizeTodoFromEvent(const KCalendarCore::Event::Ptr &event,
                              const KCalendarCore::Todo::Ptr &todo,
                              const QString &listId, int priority,
                              QString *message)
{
    todo->setSummary(event->summary());
    todo->setDescription(event->description());
    todo->setAllDay(event->allDay());
    todo->setDtStart(event->dtStart());
    todo->setDtDue(event->dtStart(), true);
    todo->setPriority(std::clamp(priority, 0, 9));
    todo->setCustomProperty(customApp, keyListId, listId);
    if (todo->customProperty(customApp, keyOrder).isEmpty()) {
        todo->setCustomProperty(customApp, keyOrder,
                                QString::number(QDateTime::currentMSecsSinceEpoch()));
    }
    if (!copyEditableRecurrence(event, todo, message))
        return false;
    // The event owns the alarm so a linked pair never emits duplicate desktop
    // notifications for the same appointment.
    applyReminder(todo, -1);
    linkEventAndTodo(event, todo);
    return true;
}

bool synchronizeEventFromTodo(const KCalendarCore::Todo::Ptr &todo,
                              const KCalendarCore::Event::Ptr &event,
                              QString *message)
{
    if (!todo->hasDueDate()) {
        *message = QStringLiteral("A task linked to a calendar event requires a due date");
        return false;
    }
    todo->setDtStart(todo->dtDue(true));
    const QDateTime oldStart = event->dtStart();
    const QDateTime oldEnd = event->dtEnd();
    const qint64 durationSeconds = std::max<qint64>(60, oldStart.secsTo(oldEnd));
    const qint64 durationDays = std::max<qint64>(
        1, oldStart.date().daysTo(oldEnd.date()));
    const QDateTime start = todo->dtDue(true);

    event->setSummary(todo->summary());
    event->setDescription(todo->description());
    event->setAllDay(todo->allDay());
    event->setDtStart(start);
    event->setDtEnd(todo->allDay() ? start.addDays(durationDays)
                                  : start.addSecs(durationSeconds));
    if (!copyEditableRecurrence(todo, event, message))
        return false;
    linkEventAndTodo(event, todo);
    return true;
}

QJsonObject eventObject(const KCalendarCore::Event::Ptr &event,
                        const QDateTime &occurrenceStart = {},
                        const QDateTime &occurrenceEnd = {},
                        const QDateTime &recurrenceId = {},
                        const KCalendarCore::MemoryCalendar *calendar = nullptr)
{
    const QDateTime start = occurrenceStart.isValid() ? occurrenceStart : event->dtStart();
    const QDateTime end = occurrenceEnd.isValid() ? occurrenceEnd : event->dtEnd();
    const QString todoId = linkedTodoId(event, calendar);
    const KCalendarCore::Todo::Ptr linkedTodo = calendar && !todoId.isEmpty()
        ? calendar->todo(todoId) : KCalendarCore::Todo::Ptr{};
    return {
        {QStringLiteral("id"), event->uid()},
        {QStringLiteral("seriesId"), event->uid()},
        {QStringLiteral("title"), event->summary()},
        {QStringLiteral("description"), event->description()},
        {QStringLiteral("location"), event->location()},
        {QStringLiteral("start"), encodeDateTime(start)},
        {QStringLiteral("end"), encodeDateTime(end)},
        {QStringLiteral("allDay"), event->allDay()},
        {QStringLiteral("timeZone"), QString::fromUtf8(start.timeZone().id())},
        {QStringLiteral("calendarId"), event->customProperty(customApp, keyCalendarId)
                 .isEmpty()
             ? QStringLiteral("personal")
             : event->customProperty(customApp, keyCalendarId)},
        {QStringLiteral("recurrence"), recurrencePreset(event)},
        {QStringLiteral("recurrenceId"), encodeDateTime(recurrenceId)},
        {QStringLiteral("reminderMinutes"), reminderMinutes(event)},
        {QStringLiteral("linkedTodoId"), todoId},
        {QStringLiteral("linkedTodoCompleted"), linkedTodo && linkedTodo->isCompleted()},
        {QStringLiteral("linkedTodoListId"), linkedTodo
                 ? linkedTodo->customProperty(customApp, keyListId) : QString{}},
        {QStringLiteral("linkedTodoPriority"), linkedTodo ? linkedTodo->priority() : 0},
        {QStringLiteral("modifiedAt"), encodeDateTime(event->lastModified())},
    };
}

QJsonObject todoObject(const KCalendarCore::Todo::Ptr &todo)
{
    const QString listId = todo->customProperty(customApp, keyListId);
    return {
        {QStringLiteral("id"), todo->uid()},
        {QStringLiteral("title"), todo->summary()},
        {QStringLiteral("description"), todo->description()},
        {QStringLiteral("listId"), listId.isEmpty() ? QStringLiteral("inbox") : listId},
        {QStringLiteral("parentId"), todo->customProperty(customApp, keyParentId)},
        {QStringLiteral("order"), todo->customProperty(customApp, keyOrder).toDouble()},
        {QStringLiteral("start"), todo->hasStartDate()
                 ? encodeDateTime(todo->dtStart(true)) : QString{}},
        {QStringLiteral("due"), todo->hasDueDate()
                 ? encodeDateTime(todo->dtDue(true)) : QString{}},
        {QStringLiteral("allDay"), todo->allDay()},
        {QStringLiteral("priority"), todo->priority()},
        {QStringLiteral("completed"), todo->isCompleted()},
        {QStringLiteral("completedAt"), todo->hasCompletedDate()
                 ? encodeDateTime(todo->completed()) : QString{}},
        {QStringLiteral("recurrence"), recurrencePreset(todo)},
        {QStringLiteral("reminderMinutes"), reminderMinutes(todo)},
        {QStringLiteral("linkedEventId"), linkedEventId(todo)},
        {QStringLiteral("modifiedAt"), encodeDateTime(todo->lastModified())},
    };
}

QJsonObject todoOccurrenceObject(const KCalendarCore::Todo::Ptr &todo,
                                 const QDateTime &occurrenceStart,
                                 const QDateTime &occurrenceEnd,
                                 const QDateTime &recurrenceId)
{
    QJsonObject object = todoObject(todo);
    object.insert(QStringLiteral("seriesId"), todo->uid());
    object.insert(QStringLiteral("recurrenceId"), encodeDateTime(recurrenceId));
    if (todo->hasStartDate() && occurrenceStart.isValid())
        object.insert(QStringLiteral("start"), encodeDateTime(occurrenceStart));
    if (todo->hasDueDate()) {
        object.insert(QStringLiteral("due"), encodeDateTime(
            occurrenceEnd.isValid() ? occurrenceEnd : occurrenceStart));
    }
    return object;
}

bool writeAtomic(const QString &path, const QByteArray &contents, QString *message)
{
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        *message = file.errorString();
        return false;
    }
    if (file.write(contents) != contents.size()) {
        *message = file.errorString();
        file.cancelWriting();
        return false;
    }
    if (!file.commit()) {
        *message = file.errorString();
        return false;
    }
    return true;
}

} // namespace

class PimStore::Private {
public:
    explicit Private(const QString &directory)
        : storageDirectory(directory.isEmpty() ? defaultStorageDirectory() : directory)
        , calendarPath(QDir(storageDirectory).filePath(QStringLiteral("calendar.ics")))
        , metadataPath(QDir(storageDirectory).filePath(QStringLiteral("metadata.json")))
        , calendar(new KCalendarCore::MemoryCalendar(QTimeZone::systemTimeZone()))
    {
    }

    bool hasList(const QString &id) const
    {
        return std::any_of(lists.begin(), lists.end(), [&id](const QJsonValue &entry) {
            return entry.toObject().value(QStringLiteral("id")).toString() == id;
        });
    }

    int listIndex(const QString &id) const
    {
        for (qsizetype index = 0; index < lists.size(); ++index) {
            if (lists.at(index).toObject().value(QStringLiteral("id")).toString() == id)
                return static_cast<int>(index);
        }
        return -1;
    }

    bool save(QString *message)
    {
        if (!QDir().mkpath(storageDirectory)) {
            *message = QStringLiteral("Unable to create PIM storage directory");
            return false;
        }
        KCalendarCore::ICalFormat format;
        const QByteArray calendarBytes = format.toString(calendar).toUtf8();
        if (!writeAtomic(calendarPath, calendarBytes, message))
            return false;
        const QJsonObject metadata{
            {QStringLiteral("schemaVersion"), pimSchemaVersion},
            {QStringLiteral("revision"), static_cast<double>(revision)},
            {QStringLiteral("lists"), lists},
        };
        return writeAtomic(metadataPath,
                           QJsonDocument(metadata).toJson(QJsonDocument::Indented), message);
    }

    void load()
    {
        lists = defaultLists();
        if (QFileInfo::exists(metadataPath)) {
            QFile metadataFile(metadataPath);
            if (metadataFile.open(QIODevice::ReadOnly)) {
                QJsonParseError error;
                const QJsonDocument document = QJsonDocument::fromJson(
                    metadataFile.readAll(), &error);
                if (error.error == QJsonParseError::NoError && document.isObject()) {
                    const QJsonObject metadata = document.object();
                    if (metadata.value(QStringLiteral("schemaVersion")).toInt()
                        == pimSchemaVersion) {
                        revision = static_cast<quint64>(
                            metadata.value(QStringLiteral("revision")).toDouble());
                        const QJsonArray loadedLists = metadata.value(
                            QStringLiteral("lists")).toArray();
                        if (!loadedLists.isEmpty())
                            lists = loadedLists;
                    }
                }
            }
        }
        if (!hasList(QStringLiteral("inbox")))
            lists.prepend(defaultLists().first());

        if (!QFileInfo::exists(calendarPath))
            return;
        KCalendarCore::ICalFormat format;
        if (!format.load(calendar, calendarPath)) {
            storageError = QStringLiteral("Unable to load the existing iCalendar file");
            writable = false;
        }
    }

    QString storageDirectory;
    QString calendarPath;
    QString metadataPath;
    KCalendarCore::MemoryCalendar::Ptr calendar;
    QJsonArray lists;
    quint64 revision = 0;
    bool writable = true;
    QString storageError;
    QTimer *reminderTimer = nullptr;
    QSet<QString> deliveredReminders;
};

PimStore::PimStore(const QString &storageDirectory, QObject *parent)
    : QObject(parent)
    , d(std::make_unique<Private>(storageDirectory))
{
    d->load();
    d->reminderTimer = new QTimer(this);
    d->reminderTimer->setSingleShot(true);
    connect(d->reminderTimer, &QTimer::timeout,
            this, &PimStore::deliverDueReminders);
    connect(this, &PimStore::changed,
            this, &PimStore::scheduleNextReminder);
    connect(this, &PimStore::changed,
            this, &PimStore::writeWidgetSnapshot);
    QTimer::singleShot(0, this, &PimStore::scheduleNextReminder);
    QTimer::singleShot(0, this, &PimStore::writeWidgetSnapshot);

    auto *widgetRefreshTimer = new QTimer(this);
    widgetRefreshTimer->setInterval(5 * 60 * 1000);
    connect(widgetRefreshTimer, &QTimer::timeout,
            this, &PimStore::writeWidgetSnapshot);
    widgetRefreshTimer->start();
}

PimStore::~PimStore() = default;

void PimStore::scheduleNextReminder()
{
    const QDateTime now = QDateTime::currentDateTime();
    const auto alarms = d->calendar->alarms(now.addSecs(1), now.addDays(30));
    qint64 delay = 24LL * 60 * 60 * 1000;
    for (const KCalendarCore::Alarm::Ptr &alarm : alarms) {
        QDateTime trigger = alarm->time();
        if (!trigger.isValid() || trigger <= now)
            trigger = alarm->nextTime(now);
        if (!trigger.isValid() || trigger <= now)
            continue;
        delay = std::min(delay, now.msecsTo(trigger));
    }
    delay = std::clamp<qint64>(delay, 50, std::numeric_limits<int>::max());
    d->reminderTimer->start(static_cast<int>(delay));
}

void PimStore::deliverDueReminders()
{
    const QDateTime now = QDateTime::currentDateTime();
    const auto alarms = d->calendar->alarms(now.addSecs(-300), now.addSecs(30));
    for (const KCalendarCore::Alarm::Ptr &alarm : alarms) {
        QDateTime trigger = alarm->time();
        if (!trigger.isValid())
            trigger = alarm->nextTime(now.addSecs(-301));
        if (!trigger.isValid() || trigger < now.addSecs(-300) || trigger > now.addSecs(30))
            continue;
        const QString key = alarm->parentUid() + QLatin1Char('@')
            + QString::number(trigger.toMSecsSinceEpoch());
        if (d->deliveredReminders.contains(key))
            continue;
        const KCalendarCore::Incidence::Ptr incidence = d->calendar->incidence(
            alarm->parentUid());
        if (!incidence)
            continue;
        const auto todo = qSharedPointerDynamicCast<KCalendarCore::Todo>(incidence);
        if (todo && todo->isCompleted())
            continue;

        d->deliveredReminders.insert(key);
        if (d->deliveredReminders.size() > 512)
            d->deliveredReminders.clear();

        const bool isTodo = incidence->type() == KCalendarCore::IncidenceBase::TypeTodo;
        const QString title = incidence->summary().isEmpty()
            ? (isTodo ? QStringLiteral("Task reminder")
                      : QStringLiteral("Event reminder"))
            : incidence->summary();
        QString body = isTodo ? QStringLiteral("This task is due.")
                              : QStringLiteral("This event is starting.");
        if (!incidence->location().isEmpty())
            body += QStringLiteral(" Location: %1").arg(incidence->location());

        QDBusMessage notification = QDBusMessage::createMethodCall(
            QStringLiteral("org.freedesktop.Notifications"),
            QStringLiteral("/org/freedesktop/Notifications"),
            QStringLiteral("org.freedesktop.Notifications"),
            QStringLiteral("Notify"));
        QVariantMap hints{
            {QStringLiteral("desktop-entry"),
             isTodo ? QStringLiteral("kos-todo") : QStringLiteral("kos-calendar")},
            {QStringLiteral("urgency"), static_cast<uchar>(1)},
        };
        notification.setArguments({
            QStringLiteral("KOS PIM"),
            0U,
            isTodo ? QStringLiteral("view-task") : QStringLiteral("view-calendar"),
            title,
            body,
            QStringList{},
            hints,
            10000,
        });
        QDBusConnection::sessionBus().asyncCall(notification, 5000);
    }
    scheduleNextReminder();
}

void PimStore::writeWidgetSnapshot()
{
    const QDate today = QDate::currentDate();
    QJsonParseError parseError;
    const QJsonObject full = QJsonDocument::fromJson(
        snapshot().toUtf8(), &parseError).object();
    if (parseError.error != QJsonParseError::NoError)
        return;
    const QJsonObject range = QJsonDocument::fromJson(
        eventsForRange(today.toString(Qt::ISODate),
                       today.addDays(7).toString(Qt::ISODate)).toUtf8(),
        &parseError).object();
    if (parseError.error != QJsonParseError::NoError)
        return;

    QJsonArray events;
    const QJsonArray occurrences = range.value(QStringLiteral("occurrences")).toArray();
    for (qsizetype index = 0; index < occurrences.size() && index < 16; ++index)
        events.append(occurrences.at(index));

    QJsonArray todos;
    const QJsonArray allTodos = full.value(QStringLiteral("todos")).toArray();
    for (const QJsonValue &value : allTodos) {
        const QJsonObject todo = value.toObject();
        if (todo.value(QStringLiteral("completed")).toBool())
            continue;
        todos.append(todo);
        if (todos.size() >= 16)
            break;
    }

    const QJsonObject widgetSnapshot{
        {QStringLiteral("schemaVersion"), 1},
        {QStringLiteral("revision"), static_cast<double>(d->revision)},
        {QStringLiteral("generatedAt"), static_cast<double>(
             QDateTime::currentMSecsSinceEpoch())},
        {QStringLiteral("today"), today.toString(Qt::ISODate)},
        {QStringLiteral("events"), events},
        {QStringLiteral("todos"), todos},
    };
    if (!QDir().mkpath(d->storageDirectory))
        return;
    QString message;
    const QString path = QDir(d->storageDirectory).filePath(
        QStringLiteral("widget-snapshot.json"));
    if (!writeAtomic(path,
                     QJsonDocument(widgetSnapshot).toJson(QJsonDocument::Compact),
                     &message)) {
        qWarning() << "Unable to update PIM widget snapshot:" << message;
    }
}

QString PimStore::snapshot() const
{
    QJsonArray events;
    QList<QJsonObject> sortedEvents;
    for (const KCalendarCore::Event::Ptr &event : d->calendar->rawEvents())
        sortedEvents.append(eventObject(event, {}, {}, {}, d->calendar.data()));
    std::sort(sortedEvents.begin(), sortedEvents.end(), [](const QJsonObject &left,
                                                            const QJsonObject &right) {
        return left.value(QStringLiteral("start")).toString()
            < right.value(QStringLiteral("start")).toString();
    });
    for (const QJsonObject &event : std::as_const(sortedEvents))
        events.append(event);

    QJsonArray todos;
    QList<QJsonObject> sortedTodos;
    for (const KCalendarCore::Todo::Ptr &todo : d->calendar->rawTodos())
        sortedTodos.append(todoObject(todo));
    std::sort(sortedTodos.begin(), sortedTodos.end(), [](const QJsonObject &left,
                                                          const QJsonObject &right) {
        if (left.value(QStringLiteral("completed")).toBool()
            != right.value(QStringLiteral("completed")).toBool()) {
            return !left.value(QStringLiteral("completed")).toBool();
        }
        const double leftOrder = left.value(QStringLiteral("order")).toDouble();
        const double rightOrder = right.value(QStringLiteral("order")).toDouble();
        if (leftOrder != rightOrder)
            return leftOrder < rightOrder;
        return left.value(QStringLiteral("title")).toString()
            < right.value(QStringLiteral("title")).toString();
    });
    for (const QJsonObject &todo : std::as_const(sortedTodos))
        todos.append(todo);

    return compactJson({
        {QStringLiteral("schemaVersion"), pimSchemaVersion},
        {QStringLiteral("revision"), static_cast<double>(d->revision)},
        {QStringLiteral("generatedAt"), static_cast<double>(
             QDateTime::currentMSecsSinceEpoch())},
        {QStringLiteral("writable"), d->writable},
        {QStringLiteral("error"), d->storageError},
        {QStringLiteral("lists"), d->lists},
        {QStringLiteral("events"), events},
        {QStringLiteral("todos"), todos},
    });
}

QString PimStore::eventsForRange(const QString &startDate, const QString &endDate) const
{
    const QDate start = QDate::fromString(startDate, Qt::ISODate);
    const QDate end = QDate::fromString(endDate, Qt::ISODate);
    if (!start.isValid() || !end.isValid() || end < start || start.daysTo(end) > 730)
        return errorResponse(QStringLiteral("invalid_range"),
                             QStringLiteral("Event range must cover 0 to 730 days"));
    const QTimeZone zone = d->calendar->timeZone();
    KCalendarCore::OccurrenceIterator iterator(
        *d->calendar, QDateTime(start, QTime(0, 0), zone),
        QDateTime(end.addDays(1), QTime(0, 0), zone).addMSecs(-1));
    QJsonArray occurrences;
    QJsonArray todoOccurrences;
    while (iterator.hasNext()
           && occurrences.size() + todoOccurrences.size() < 5000) {
        iterator.next();
        const auto event = qSharedPointerDynamicCast<KCalendarCore::Event>(
            iterator.incidence());
        if (event) {
            occurrences.append(eventObject(event, iterator.occurrenceStartDate(),
                                           iterator.occurrenceEndDate(),
                                           iterator.recurrenceId(), d->calendar.data()));
            continue;
        }
        const auto todo = qSharedPointerDynamicCast<KCalendarCore::Todo>(
            iterator.incidence());
        if (todo && todo->hasDueDate()) {
            todoOccurrences.append(todoOccurrenceObject(
                todo, iterator.occurrenceStartDate(), iterator.occurrenceEndDate(),
                iterator.recurrenceId()));
        }
    }
    return compactJson({
        {QStringLiteral("ok"), true},
        {QStringLiteral("revision"), static_cast<double>(d->revision)},
        {QStringLiteral("occurrences"), occurrences},
        {QStringLiteral("todoOccurrences"), todoOccurrences},
    });
}

QString PimStore::createEvent(const QString &payload)
{
    if (!d->writable)
        return errorResponse(QStringLiteral("storage_read_only"), d->storageError);
    QJsonObject input;
    QString message;
    if (!parsePayload(payload, &input, &message))
        return errorResponse(QStringLiteral("invalid_payload"), message);
    bool valid = true;
    const QString title = boundedString(input, QStringLiteral("title"), 512, &valid);
    const QString description = boundedString(input, QStringLiteral("description"), 32768,
                                              &valid);
    const QString location = boundedString(input, QStringLiteral("location"), 1024, &valid);
    if (!valid || title.isEmpty())
        return errorResponse(QStringLiteral("invalid_event"),
                             QStringLiteral("Event title or text length is invalid"));
    const bool allDay = input.value(QStringLiteral("allDay")).toBool();
    QTimeZone zone(input.value(QStringLiteral("timeZone")).toString().toUtf8());
    if (!zone.isValid())
        zone = d->calendar->timeZone();
    const QDateTime start = parseDateTime(input.value(QStringLiteral("start")), allDay, zone);
    QDateTime end = parseDateTime(input.value(QStringLiteral("end")), allDay, zone);
    if (!start.isValid())
        return errorResponse(QStringLiteral("invalid_event"),
                             QStringLiteral("Event start date is required"));
    if (!end.isValid())
        end = allDay ? start.addDays(1) : start.addSecs(3600);
    if (end <= start)
        return errorResponse(QStringLiteral("invalid_event"),
                             QStringLiteral("Event end must be after its start"));

    auto event = KCalendarCore::Event::Ptr(new KCalendarCore::Event);
    event->setUid(QUuid::createUuid().toString(QUuid::WithoutBraces));
    event->setSummary(title);
    event->setDescription(description);
    event->setLocation(location);
    event->setAllDay(allDay);
    event->setDtStart(start);
    event->setDtEnd(end);
    event->setCustomProperty(customApp, keyCalendarId,
                             input.value(QStringLiteral("calendarId")).toString(
                                 QStringLiteral("personal")));
    if (!applyRecurrence(event, input, &message))
        return errorResponse(QStringLiteral("invalid_recurrence"), message);
    applyReminder(event, input.value(QStringLiteral("reminderMinutes")).toInt(-1));

    KCalendarCore::Todo::Ptr linkedTodo;
    if (input.value(QStringLiteral("linkedTodo")).toBool()) {
        QString listId = input.value(QStringLiteral("todoListId"))
                             .toString(QStringLiteral("personal"));
        if (!d->hasList(listId))
            listId = QStringLiteral("inbox");
        linkedTodo = KCalendarCore::Todo::Ptr(new KCalendarCore::Todo);
        linkedTodo->setUid(QUuid::createUuid().toString(QUuid::WithoutBraces));
        if (!synchronizeTodoFromEvent(
                event, linkedTodo, listId,
                input.value(QStringLiteral("todoPriority")).toInt(), &message)) {
            return errorResponse(QStringLiteral("invalid_linked_todo"), message);
        }
    }
    if (!d->calendar->addEvent(event))
        return errorResponse(QStringLiteral("calendar_error"),
                             QStringLiteral("Unable to add event"));
    if (linkedTodo && !d->calendar->addTodo(linkedTodo)) {
        d->calendar->deleteEvent(event);
        return errorResponse(QStringLiteral("calendar_error"),
                             QStringLiteral("Unable to add the linked todo"));
    }
    ++d->revision;
    if (!d->save(&message))
        return errorResponse(QStringLiteral("storage_error"), message);
    emit changed(d->revision);
    return successResponse(d->revision,
                           eventObject(event, {}, {}, {}, d->calendar.data()));
}

QString PimStore::updateEvent(const QString &uid, const QString &payload)
{
    if (!d->writable)
        return errorResponse(QStringLiteral("storage_read_only"), d->storageError);
    const auto event = d->calendar->event(uid);
    if (!event)
        return errorResponse(QStringLiteral("not_found"), QStringLiteral("Event not found"));
    const QString existingTodoId = linkedTodoId(event, d->calendar.data());
    const KCalendarCore::Todo::Ptr existingTodo = existingTodoId.isEmpty()
        ? KCalendarCore::Todo::Ptr{} : d->calendar->todo(existingTodoId);
    const KCalendarCore::Event::Ptr updated(event->clone());
    QJsonObject input;
    QString message;
    if (!parsePayload(payload, &input, &message))
        return errorResponse(QStringLiteral("invalid_payload"), message);
    bool valid = true;
    if (input.contains(QStringLiteral("title"))) {
        const QString title = boundedString(input, QStringLiteral("title"), 512, &valid);
        if (title.isEmpty())
            valid = false;
        else
            updated->setSummary(title);
    }
    if (input.contains(QStringLiteral("description")))
        updated->setDescription(boundedString(input, QStringLiteral("description"), 32768,
                                              &valid));
    if (input.contains(QStringLiteral("location")))
        updated->setLocation(boundedString(input, QStringLiteral("location"), 1024, &valid));
    if (!valid)
        return errorResponse(QStringLiteral("invalid_event"),
                             QStringLiteral("Event title or text length is invalid"));
    const bool allDay = input.contains(QStringLiteral("allDay"))
        ? input.value(QStringLiteral("allDay")).toBool() : updated->allDay();
    QTimeZone zone(input.value(QStringLiteral("timeZone")).toString().toUtf8());
    if (!zone.isValid())
        zone = updated->dtStart().timeZone().isValid()
            ? updated->dtStart().timeZone() : d->calendar->timeZone();
    QDateTime start = updated->dtStart();
    QDateTime end = updated->dtEnd();
    if (input.contains(QStringLiteral("start")))
        start = parseDateTime(input.value(QStringLiteral("start")), allDay, zone);
    if (input.contains(QStringLiteral("end")))
        end = parseDateTime(input.value(QStringLiteral("end")), allDay, zone);
    if (!start.isValid() || !end.isValid() || end <= start)
        return errorResponse(QStringLiteral("invalid_event"),
                             QStringLiteral("Event dates are invalid"));
    updated->setAllDay(allDay);
    updated->setDtStart(start);
    updated->setDtEnd(end);
    if (input.contains(QStringLiteral("calendarId")))
        updated->setCustomProperty(customApp, keyCalendarId,
                                   input.value(QStringLiteral("calendarId")).toString());
    if (!applyRecurrence(updated, input, &message))
        return errorResponse(QStringLiteral("invalid_recurrence"), message);
    if (input.contains(QStringLiteral("reminderMinutes")))
        applyReminder(updated, input.value(QStringLiteral("reminderMinutes")).toInt(-1));

    const bool shouldLink = input.contains(QStringLiteral("linkedTodo"))
        ? input.value(QStringLiteral("linkedTodo")).toBool()
        : static_cast<bool>(existingTodo);
    KCalendarCore::Todo::Ptr updatedTodo;
    if (shouldLink) {
        updatedTodo = existingTodo
            ? KCalendarCore::Todo::Ptr(existingTodo->clone())
            : KCalendarCore::Todo::Ptr(new KCalendarCore::Todo);
        if (updatedTodo->uid().isEmpty())
            updatedTodo->setUid(QUuid::createUuid().toString(QUuid::WithoutBraces));
        QString listId = input.value(QStringLiteral("todoListId")).toString();
        if (listId.isEmpty() && existingTodo) {
            listId = existingTodo->customProperty(customApp, keyListId);
        }
        if (listId.isEmpty())
            listId = d->hasList(QStringLiteral("personal"))
                ? QStringLiteral("personal") : QStringLiteral("inbox");
        if (!d->hasList(listId))
            return errorResponse(QStringLiteral("invalid_list"),
                                 QStringLiteral("Linked todo list not found"));
        const int priority = input.contains(QStringLiteral("todoPriority"))
            ? input.value(QStringLiteral("todoPriority")).toInt()
            : (existingTodo ? existingTodo->priority() : 0);
        if (!synchronizeTodoFromEvent(updated, updatedTodo, listId, priority, &message))
            return errorResponse(QStringLiteral("invalid_linked_todo"), message);
    } else if (existingTodo) {
        updatedTodo = KCalendarCore::Todo::Ptr(existingTodo->clone());
        unlinkEventAndTodo(updated, updatedTodo);
    } else {
        updated->removeCustomProperty(customApp, keyLinkedTodoId);
    }

    if (!d->calendar->deleteEvent(event) || !d->calendar->addEvent(updated)) {
        if (!d->calendar->event(uid))
            d->calendar->addEvent(event);
        return errorResponse(QStringLiteral("calendar_error"),
                             QStringLiteral("Unable to replace event"));
    }
    bool todoUpdated = true;
    if (updatedTodo && existingTodo) {
        todoUpdated = d->calendar->deleteTodo(existingTodo)
            && d->calendar->addTodo(updatedTodo);
    } else if (updatedTodo) {
        todoUpdated = d->calendar->addTodo(updatedTodo);
    }
    if (!todoUpdated) {
        d->calendar->deleteEvent(updated);
        d->calendar->addEvent(event);
        if (existingTodo && !d->calendar->todo(existingTodo->uid()))
            d->calendar->addTodo(existingTodo);
        return errorResponse(QStringLiteral("calendar_error"),
                             QStringLiteral("Unable to update the linked todo"));
    }
    ++d->revision;
    if (!d->save(&message))
        return errorResponse(QStringLiteral("storage_error"), message);
    emit changed(d->revision);
    return successResponse(d->revision,
                           eventObject(updated, {}, {}, {}, d->calendar.data()));
}

QString PimStore::removeEvent(const QString &uid)
{
    if (!d->writable)
        return errorResponse(QStringLiteral("storage_read_only"), d->storageError);
    const auto event = d->calendar->event(uid);
    if (!event)
        return errorResponse(QStringLiteral("not_found"), QStringLiteral("Event not found"));
    const QString todoId = linkedTodoId(event, d->calendar.data());
    const KCalendarCore::Todo::Ptr linkedTodo = todoId.isEmpty()
        ? KCalendarCore::Todo::Ptr{} : d->calendar->todo(todoId);
    KCalendarCore::Todo::Ptr unlinkedTodo;
    if (linkedTodo) {
        unlinkedTodo = KCalendarCore::Todo::Ptr(linkedTodo->clone());
        if (reminderMinutes(unlinkedTodo) < 0)
            applyReminder(unlinkedTodo, reminderMinutes(event));
        unlinkEventAndTodo(KCalendarCore::Event::Ptr{}, unlinkedTodo);
    }
    if (!d->calendar->deleteEvent(event))
        return errorResponse(QStringLiteral("calendar_error"),
                             QStringLiteral("Unable to delete event"));
    if (linkedTodo
        && (!d->calendar->deleteTodo(linkedTodo) || !d->calendar->addTodo(unlinkedTodo))) {
        d->calendar->addEvent(event);
        if (!d->calendar->todo(linkedTodo->uid()))
            d->calendar->addTodo(linkedTodo);
        return errorResponse(QStringLiteral("calendar_error"),
                             QStringLiteral("Unable to unlink the related todo"));
    }
    ++d->revision;
    QString message;
    if (!d->save(&message))
        return errorResponse(QStringLiteral("storage_error"), message);
    emit changed(d->revision);
    return successResponse(d->revision);
}

QString PimStore::createTodo(const QString &payload)
{
    if (!d->writable)
        return errorResponse(QStringLiteral("storage_read_only"), d->storageError);
    QJsonObject input;
    QString message;
    if (!parsePayload(payload, &input, &message))
        return errorResponse(QStringLiteral("invalid_payload"), message);
    bool valid = true;
    const QString title = boundedString(input, QStringLiteral("title"), 512, &valid);
    const QString description = boundedString(input, QStringLiteral("description"), 32768,
                                              &valid);
    QString listId = input.value(QStringLiteral("listId")).toString(QStringLiteral("inbox"));
    if (!d->hasList(listId))
        listId = QStringLiteral("inbox");
    if (!valid || title.isEmpty())
        return errorResponse(QStringLiteral("invalid_todo"),
                             QStringLiteral("Todo title or description is invalid"));
    const bool allDay = input.value(QStringLiteral("allDay")).toBool();
    QTimeZone zone(input.value(QStringLiteral("timeZone")).toString().toUtf8());
    if (!zone.isValid())
        zone = d->calendar->timeZone();

    auto todo = KCalendarCore::Todo::Ptr(new KCalendarCore::Todo);
    todo->setUid(QUuid::createUuid().toString(QUuid::WithoutBraces));
    todo->setSummary(title);
    todo->setDescription(description);
    todo->setAllDay(allDay);
    const QDateTime start = parseDateTime(input.value(QStringLiteral("start")), allDay, zone);
    const QDateTime due = parseDateTime(input.value(QStringLiteral("due")), allDay, zone);
    if (start.isValid())
        todo->setDtStart(start);
    if (due.isValid())
        todo->setDtDue(due, true);
    todo->setPriority(std::clamp(input.value(QStringLiteral("priority")).toInt(), 0, 9));
    todo->setCustomProperty(customApp, keyListId, listId);
    todo->setCustomProperty(customApp, keyParentId,
                            input.value(QStringLiteral("parentId")).toString());
    todo->setCustomProperty(customApp, keyOrder,
                            QString::number(input.value(QStringLiteral("order")).toDouble(
                                QDateTime::currentMSecsSinceEpoch())));
    if (!applyRecurrence(todo, input, &message))
        return errorResponse(QStringLiteral("invalid_recurrence"), message);
    applyReminder(todo, input.value(QStringLiteral("reminderMinutes")).toInt(-1));
    if (input.value(QStringLiteral("completed")).toBool())
        todo->setCompleted(QDateTime::currentDateTimeUtc());
    if (!d->calendar->addTodo(todo))
        return errorResponse(QStringLiteral("calendar_error"),
                             QStringLiteral("Unable to add todo"));
    ++d->revision;
    if (!d->save(&message))
        return errorResponse(QStringLiteral("storage_error"), message);
    emit changed(d->revision);
    return successResponse(d->revision, todoObject(todo));
}

QString PimStore::updateTodo(const QString &uid, const QString &payload)
{
    if (!d->writable)
        return errorResponse(QStringLiteral("storage_read_only"), d->storageError);
    const auto todo = d->calendar->todo(uid);
    if (!todo)
        return errorResponse(QStringLiteral("not_found"), QStringLiteral("Todo not found"));
    const QString existingEventId = linkedEventId(todo);
    const KCalendarCore::Event::Ptr existingEvent = existingEventId.isEmpty()
        ? KCalendarCore::Event::Ptr{} : d->calendar->event(existingEventId);
    const KCalendarCore::Todo::Ptr updated(todo->clone());
    QJsonObject input;
    QString message;
    if (!parsePayload(payload, &input, &message))
        return errorResponse(QStringLiteral("invalid_payload"), message);
    bool valid = true;
    if (input.contains(QStringLiteral("title"))) {
        const QString title = boundedString(input, QStringLiteral("title"), 512, &valid);
        if (title.isEmpty())
            valid = false;
        else
            updated->setSummary(title);
    }
    if (input.contains(QStringLiteral("description")))
        updated->setDescription(boundedString(input, QStringLiteral("description"), 32768,
                                              &valid));
    if (!valid)
        return errorResponse(QStringLiteral("invalid_todo"),
                             QStringLiteral("Todo title or description is invalid"));
    const bool allDay = input.contains(QStringLiteral("allDay"))
        ? input.value(QStringLiteral("allDay")).toBool() : updated->allDay();
    updated->setAllDay(allDay);
    const QTimeZone zone = d->calendar->timeZone();
    if (input.contains(QStringLiteral("start")))
        updated->setDtStart(parseDateTime(input.value(QStringLiteral("start")), allDay, zone));
    if (input.contains(QStringLiteral("due")))
        updated->setDtDue(parseDateTime(input.value(QStringLiteral("due")), allDay, zone), true);
    if (input.contains(QStringLiteral("priority")))
        updated->setPriority(std::clamp(input.value(QStringLiteral("priority")).toInt(), 0, 9));
    if (input.contains(QStringLiteral("listId"))) {
        const QString listId = input.value(QStringLiteral("listId")).toString();
        if (!d->hasList(listId))
            return errorResponse(QStringLiteral("invalid_list"), QStringLiteral("List not found"));
        updated->setCustomProperty(customApp, keyListId, listId);
    }
    if (input.contains(QStringLiteral("parentId"))) {
        const QString parentId = input.value(QStringLiteral("parentId")).toString();
        if (parentId == uid || (!parentId.isEmpty() && !d->calendar->todo(parentId)))
            return errorResponse(QStringLiteral("invalid_parent"),
                                 QStringLiteral("Todo parent is invalid"));
        updated->setCustomProperty(customApp, keyParentId, parentId);
    }
    if (input.contains(QStringLiteral("order")))
        updated->setCustomProperty(customApp, keyOrder,
                                   QString::number(input.value(QStringLiteral("order")).toDouble()));
    if (input.contains(QStringLiteral("completed"))) {
        if (input.value(QStringLiteral("completed")).toBool())
            updated->setCompleted(QDateTime::currentDateTimeUtc());
        else
            updated->setCompleted(false);
    }
    if (!applyRecurrence(updated, input, &message))
        return errorResponse(QStringLiteral("invalid_recurrence"), message);
    if (input.contains(QStringLiteral("reminderMinutes")))
        applyReminder(updated, input.value(QStringLiteral("reminderMinutes")).toInt(-1));

    KCalendarCore::Event::Ptr updatedEvent;
    if (existingEvent) {
        updatedEvent = KCalendarCore::Event::Ptr(existingEvent->clone());
        if (!synchronizeEventFromTodo(updated, updatedEvent, &message))
            return errorResponse(QStringLiteral("invalid_linked_event"), message);
        // The VEVENT is the single reminder owner for a linked pair.
        applyReminder(updated, -1);
    } else if (!existingEventId.isEmpty()) {
        updated->removeCustomProperty(customApp, keyLinkedEventId);
        updated->setRelatedTo(QString{});
    }
    if (!d->calendar->deleteTodo(todo) || !d->calendar->addTodo(updated)) {
        if (!d->calendar->todo(uid))
            d->calendar->addTodo(todo);
        return errorResponse(QStringLiteral("calendar_error"),
                             QStringLiteral("Unable to replace todo"));
    }
    if (updatedEvent
        && (!d->calendar->deleteEvent(existingEvent)
            || !d->calendar->addEvent(updatedEvent))) {
        d->calendar->deleteTodo(updated);
        d->calendar->addTodo(todo);
        if (!d->calendar->event(existingEvent->uid()))
            d->calendar->addEvent(existingEvent);
        return errorResponse(QStringLiteral("calendar_error"),
                             QStringLiteral("Unable to update the linked event"));
    }
    ++d->revision;
    if (!d->save(&message))
        return errorResponse(QStringLiteral("storage_error"), message);
    emit changed(d->revision);
    return successResponse(d->revision, todoObject(updated));
}

QString PimStore::removeTodo(const QString &uid)
{
    if (!d->writable)
        return errorResponse(QStringLiteral("storage_read_only"), d->storageError);
    const auto todo = d->calendar->todo(uid);
    if (!todo)
        return errorResponse(QStringLiteral("not_found"), QStringLiteral("Todo not found"));
    const QString eventId = linkedEventId(todo);
    const KCalendarCore::Event::Ptr linkedEvent = eventId.isEmpty()
        ? KCalendarCore::Event::Ptr{} : d->calendar->event(eventId);
    KCalendarCore::Event::Ptr unlinkedEvent;
    if (linkedEvent) {
        unlinkedEvent = KCalendarCore::Event::Ptr(linkedEvent->clone());
        unlinkEventAndTodo(unlinkedEvent, KCalendarCore::Todo::Ptr{});
    }
    if (!d->calendar->deleteTodo(todo))
        return errorResponse(QStringLiteral("calendar_error"),
                             QStringLiteral("Unable to delete todo"));
    if (linkedEvent
        && (!d->calendar->deleteEvent(linkedEvent)
            || !d->calendar->addEvent(unlinkedEvent))) {
        d->calendar->addTodo(todo);
        if (!d->calendar->event(linkedEvent->uid()))
            d->calendar->addEvent(linkedEvent);
        return errorResponse(QStringLiteral("calendar_error"),
                             QStringLiteral("Unable to unlink the related event"));
    }
    for (const KCalendarCore::Todo::Ptr &candidate : d->calendar->rawTodos()) {
        if (candidate->customProperty(customApp, keyParentId) == uid)
            candidate->removeCustomProperty(customApp, keyParentId);
    }
    ++d->revision;
    QString message;
    if (!d->save(&message))
        return errorResponse(QStringLiteral("storage_error"), message);
    emit changed(d->revision);
    return successResponse(d->revision);
}

QString PimStore::createList(const QString &payload)
{
    if (!d->writable)
        return errorResponse(QStringLiteral("storage_read_only"), d->storageError);
    QJsonObject input;
    QString message;
    if (!parsePayload(payload, &input, &message))
        return errorResponse(QStringLiteral("invalid_payload"), message);
    bool valid = true;
    const QString name = boundedString(input, QStringLiteral("name"), 128, &valid);
    if (!valid || name.isEmpty())
        return errorResponse(QStringLiteral("invalid_list"), QStringLiteral("List name is invalid"));
    const QString id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    const QJsonObject list{
        {QStringLiteral("id"), id},
        {QStringLiteral("name"), name},
        {QStringLiteral("color"), input.value(QStringLiteral("color")).toString(
             QStringLiteral("#4f8cff"))},
        {QStringLiteral("position"), d->lists.size()},
    };
    d->lists.append(list);
    ++d->revision;
    if (!d->save(&message))
        return errorResponse(QStringLiteral("storage_error"), message);
    emit changed(d->revision);
    return successResponse(d->revision, list);
}

QString PimStore::updateList(const QString &id, const QString &payload)
{
    if (!d->writable)
        return errorResponse(QStringLiteral("storage_read_only"), d->storageError);
    const int index = d->listIndex(id);
    if (index < 0)
        return errorResponse(QStringLiteral("not_found"), QStringLiteral("List not found"));
    QJsonObject input;
    QString message;
    if (!parsePayload(payload, &input, &message))
        return errorResponse(QStringLiteral("invalid_payload"), message);
    QJsonObject list = d->lists.at(index).toObject();
    if (input.contains(QStringLiteral("name"))) {
        bool valid = true;
        const QString name = boundedString(input, QStringLiteral("name"), 128, &valid);
        if (!valid || name.isEmpty())
            return errorResponse(QStringLiteral("invalid_list"),
                                 QStringLiteral("List name is invalid"));
        list.insert(QStringLiteral("name"), name);
    }
    if (input.contains(QStringLiteral("color")))
        list.insert(QStringLiteral("color"), input.value(QStringLiteral("color")).toString());
    if (input.contains(QStringLiteral("position")))
        list.insert(QStringLiteral("position"), input.value(QStringLiteral("position")).toInt());
    d->lists.replace(index, list);
    ++d->revision;
    if (!d->save(&message))
        return errorResponse(QStringLiteral("storage_error"), message);
    emit changed(d->revision);
    return successResponse(d->revision, list);
}

QString PimStore::removeList(const QString &id)
{
    if (id == QLatin1String("inbox"))
        return errorResponse(QStringLiteral("protected_list"),
                             QStringLiteral("The Inbox list cannot be removed"));
    if (!d->writable)
        return errorResponse(QStringLiteral("storage_read_only"), d->storageError);
    const int index = d->listIndex(id);
    if (index < 0)
        return errorResponse(QStringLiteral("not_found"), QStringLiteral("List not found"));
    d->lists.removeAt(index);
    for (const KCalendarCore::Todo::Ptr &todo : d->calendar->rawTodos()) {
        if (todo->customProperty(customApp, keyListId) == id)
            todo->setCustomProperty(customApp, keyListId, QStringLiteral("inbox"));
    }
    ++d->revision;
    QString message;
    if (!d->save(&message))
        return errorResponse(QStringLiteral("storage_error"), message);
    emit changed(d->revision);
    return successResponse(d->revision);
}

QString PimStore::importIcalendar(const QString &path, bool replaceExisting)
{
    if (!d->writable)
        return errorResponse(QStringLiteral("storage_read_only"), d->storageError);
    const QFileInfo source(path);
    if (!source.isAbsolute() || !source.isFile() || source.size() > maximumImportBytes)
        return errorResponse(QStringLiteral("invalid_file"),
                             QStringLiteral("Import file is invalid or exceeds 20 MiB"));
    auto imported = KCalendarCore::MemoryCalendar::Ptr(
        new KCalendarCore::MemoryCalendar(d->calendar->timeZone()));
    KCalendarCore::ICalFormat format;
    if (!format.load(imported, source.absoluteFilePath()))
        return errorResponse(QStringLiteral("invalid_icalendar"),
                             QStringLiteral("Unable to parse iCalendar file"));
    int importedCount = 0;
    int skippedCount = 0;
    if (replaceExisting) {
        importedCount = imported->rawIncidences().size();
        d->calendar = imported;
    } else {
        for (const KCalendarCore::Incidence::Ptr &incidence : imported->rawIncidences()) {
            if (d->calendar->incidence(incidence->uid())) {
                ++skippedCount;
                continue;
            }
            KCalendarCore::Incidence::Ptr copy(incidence->clone());
            if (d->calendar->addIncidence(copy))
                ++importedCount;
            else
                ++skippedCount;
        }
    }
    ++d->revision;
    QString message;
    if (!d->save(&message))
        return errorResponse(QStringLiteral("storage_error"), message);
    emit changed(d->revision);
    return compactJson({
        {QStringLiteral("ok"), true},
        {QStringLiteral("revision"), static_cast<double>(d->revision)},
        {QStringLiteral("imported"), importedCount},
        {QStringLiteral("skipped"), skippedCount},
    });
}

QString PimStore::exportIcalendar(const QString &path) const
{
    const QFileInfo destination(path);
    if (!destination.isAbsolute())
        return errorResponse(QStringLiteral("invalid_file"),
                             QStringLiteral("Export path must be absolute"));
    if (!QDir().mkpath(destination.absolutePath()))
        return errorResponse(QStringLiteral("storage_error"),
                             QStringLiteral("Unable to create export directory"));
    KCalendarCore::ICalFormat format;
    QString message;
    if (!writeAtomic(destination.absoluteFilePath(), format.toString(d->calendar).toUtf8(),
                     &message)) {
        return errorResponse(QStringLiteral("storage_error"), message);
    }
    return successResponse(d->revision);
}
