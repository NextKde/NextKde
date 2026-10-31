#include "PimStore.h"
#include <QRegularExpression>
#include <QMimeDatabase>
#include <QImageReader>
#include <QBuffer>

#include <KCalendarCore/Alarm>
#include <KCalendarCore/Duration>
#include <KCalendarCore/Event>
#include <KCalendarCore/ICalFormat>
#include <KCalendarCore/MemoryCalendar>
#include <KCalendarCore/OccurrenceIterator>
#include <KCalendarCore/Recurrence>
#include <KCalendarCore/Todo>

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>
#include <QDateTime>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QLocale>
#include <QProcess>
#include <QProcessEnvironment>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDir>
#include <QDebug>
#include <QFile>
#include <QFileInfo>
#include <QHash>
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
constexpr auto keyFlagged = "FLAGGED";
constexpr auto keySection = "SECTION";
constexpr auto keyImages = "IMAGE-FILES";
constexpr auto keyOrder = "ORDER";
constexpr auto keyRecurrence = "RECURRENCE-PRESET";
constexpr auto keyLinkedTodoId = "LINKED-TODO-ID";
constexpr auto keyLinkedEventId = "LINKED-EVENT-ID";

QJsonArray holidaySources()
{
    QJsonArray sources;
    const QList<QStringList> regions{
        {"CN", "China", "cn_zh"}, {"US", "United States", "us_en"},
        {"GB", "United Kingdom", "gb_en"}, {"JP", "Japan", "jp_ja"},
        {"DE", "Germany", "de_de"}, {"FR", "France", "fr_fr"},
        {"AU", "Australia", "au_en"}, {"CA", "Canada", "ca_en"},
    };
    for (const auto &region : regions)
        sources.append(QJsonObject{{"id", region[0]}, {"name", region[1]},
            {"url", "https://calendars.icloud.com/holidays/" + region[2] + ".ics"},
            {"provider", "Apple"}});
    return sources;
}

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

// User-defined organization is additive: old lists/tasks remain valid.
bool applyListOrganization(QJsonObject &list, const QJsonObject &input, QString *message)
{
    if (input.contains("color") && !QRegularExpression("^#[0-9a-fA-F]{6}$").match(input.value("color").toString()).hasMatch()) {
        *message = "Invalid list color"; return false;
    }
    if (input.contains("viewMode")) {
        if (input.value("viewMode") != "list" && input.value("viewMode") != "columns") { *message = "Invalid list view"; return false; }
        list.insert("viewMode", input.value("viewMode"));
    }
    if (input.contains("icon")) {
        const QStringList icons{"reminder", "calendar", "home", "folder", "music", "album", "artist", "keyboard", "settings", "wallpaper", "heart", "flag", "sparkle", "queue", "download", "radio", "grid", "circle"};
        if (!icons.contains(input.value("icon").toString())) { *message = "Invalid list icon"; return false; }
        list.insert("icon", input.value("icon"));
    }
    if (input.contains("group")) {
        if (!input.value("group").isString() || input.value("group").toString().size() > 128) {
            *message = "Group name is too long"; return false;
        }
        list.insert("group", input.value("group").toString().trimmed());
    }
    if (input.contains("kind")) {
        const QString kind = input.value("kind").toString();
        if (kind != "list" && kind != "smart") { *message = "Invalid list type"; return false; }
        list.insert("kind", kind);
    }
    if (input.contains("rules")) {
        if (!input.value("rules").isObject()) { *message = "Invalid smart list rules"; return false; }
        const auto rules = input.value("rules").toObject();
        const QHash<QString, QStringList> choices{
            {"date", {"any", "today", "scheduled", "undated", "overdue"}},
            {"flag", {"any", "yes", "no"}},
            {"priority", {"any", "high", "medium", "low", "none"}}};
        for (auto it = rules.begin(); it != rules.end(); ++it) {
            if (choices.contains(it.key())) {
                if (!choices.value(it.key()).contains(it.value().toString())) { *message = "Invalid rule value"; return false; }
            } else if (it.key() == "tag" || it.key() == "listId") {
                if (!it.value().isString() || it.value().toString().size() > 128) { *message = "Invalid rule text"; return false; }
            } else { *message = "Unknown smart list rule"; return false; }
        }
        list.insert("rules", rules);
    }
    return true;
}

bool applyTodoOrganization(const KCalendarCore::Todo::Ptr &todo, const QJsonObject &input, QString *message)
{
    if (input.contains("section")) {
        if (!input.value("section").isString() || input.value("section").toString().size() > 128) {
            *message = "Section name is too long"; return false;
        }
        const auto section = input.value("section").toString().trimmed();
        if (section.isEmpty()) todo->removeCustomProperty(customApp, keySection);
        else todo->setCustomProperty(customApp, keySection, section);
    }
    if (input.contains("tags")) {
        if (!input.value("tags").isArray() || input.value("tags").toArray().size() > 32) {
            *message = "At most 32 tags are allowed"; return false;
        }
        QStringList tags;
        for (const auto &value : input.value("tags").toArray()) {
            QString tag = value.toString().trimmed();
            while (tag.startsWith('#')) tag.remove(0, 1);
            if (!value.isString() || tag.isEmpty() || tag.size() > 64 || tag.contains(QRegularExpression("\\s"))) {
                *message = "Tags must be 1–64 characters without spaces"; return false;
            }
            if (!tags.contains(tag, Qt::CaseInsensitive)) tags.append(tag);
        }
        todo->setCategories(tags);
    }
    return true;
}

bool applyTodoMedia(const KCalendarCore::Todo::Ptr &todo, const QJsonObject &input, const QString &storageDirectory, QString *message)
{
    if (input.contains("url")) {
        const QString text = input.value("url").toString().trimmed();
        const QUrl url(text);
        if (!input.value("url").isString() || text.size() > 4096 || (!text.isEmpty()
            && (!url.isValid() || url.host().isEmpty() || (url.scheme() != "https" && url.scheme() != "http")))) {
            *message = "Enter an HTTP or HTTPS link"; return false;
        }
        todo->setUrl(url);
    }
    if (!input.contains("images")) return true;
    if (!input.value("images").isArray() || input.value("images").toArray().size() > 8) {
        *message = "At most 8 images are allowed"; return false;
    }
    QJsonArray images;
    const QDir folder(QDir(storageDirectory).filePath("images"));
    if (!folder.mkpath(".")) { *message = "Unable to create image storage"; return false; }
    for (const auto &entry : input.value("images").toArray()) {
        const QUrl url(entry.toString());
        if (!entry.isString() || !url.isLocalFile()) { *message = "Choose a local image file"; return false; }
        QFile file(url.toLocalFile());
        if (!file.open(QIODevice::ReadOnly) || file.size() > 10 * 1024 * 1024 || file.size() < 1) {
            *message = "Image is unavailable or exceeds 10 MB"; return false;
        }
        const QByteArray bytes = file.readAll();
        const auto mime = QMimeDatabase().mimeTypeForData(bytes).name();
        const QHash<QString, QString> suffixes{{"image/png", "png"}, {"image/jpeg", "jpg"}, {"image/webp", "webp"}, {"image/gif", "gif"}, {"image/bmp", "bmp"}};
        if (!suffixes.contains(mime)) { *message = "Choose a PNG, JPEG, WebP, GIF or BMP image"; return false; }
        QBuffer buffer;
        buffer.setData(bytes);
        buffer.open(QIODevice::ReadOnly);
        QImageReader reader(&buffer);
        const QSize dimensions = reader.size();
        if (!reader.canRead() || dimensions.isEmpty()
            || qint64(dimensions.width()) * dimensions.height() > 25000000 || reader.read().isNull()) {
            *message = "Image is damaged or exceeds 25 megapixels"; return false;
        }
        const QString destination = folder.filePath(QString::fromLatin1(QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex()) + "." + suffixes.value(mime));
        if (!QFile::exists(destination)) {
            QSaveFile copy(destination);
            if (!copy.open(QIODevice::WriteOnly) || copy.write(bytes) != bytes.size() || !copy.commit()) {
                *message = "Unable to save image"; return false;
            }
        }
        const QString stored = QUrl::fromLocalFile(destination).toString();
        if (!images.contains(stored)) images.append(stored);
    }
    todo->setCustomProperty(customApp, keyImages, QString::fromUtf8(QJsonDocument(images).toJson(QJsonDocument::Compact)));
    return true;
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

// event uid -> todo uid for every todo that back-references an event. The
// reverse direction is not stored on the event when the link was created
// from the todo side, so bulk serializers build this once instead of
// scanning rawTodos() per event (which made snapshot() O(events x todos)).
QHash<QString, QString> todoIdsByLinkedEvent(
    const KCalendarCore::MemoryCalendar *calendar)
{
    QHash<QString, QString> result;
    if (!calendar)
        return result;
    for (const KCalendarCore::Todo::Ptr &todo : calendar->rawTodos()) {
        const QString eventId = linkedEventId(todo);
        if (!eventId.isEmpty() && !result.contains(eventId))
            result.insert(eventId, todo->uid());
    }
    return result;
}

QString linkedTodoId(const KCalendarCore::Event::Ptr &event,
                     const KCalendarCore::MemoryCalendar *calendar,
                     const QHash<QString, QString> *todoByEvent = nullptr)
{
    const QString customId = event->customProperty(customApp, keyLinkedTodoId);
    if (!customId.isEmpty() && (!calendar || calendar->todo(customId)))
        return customId;
    if (!calendar)
        return customId;
    if (todoByEvent)
        return todoByEvent->value(event->uid());
    const QHash<QString, QString> resolved = todoIdsByLinkedEvent(calendar);
    return resolved.value(event->uid());
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
    todo->setCustomProperty(customApp, keyCalendarId, event->customProperty(customApp, keyCalendarId));
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

    if (!todo->customProperty(customApp, keyCalendarId).isEmpty())
        event->setCustomProperty(customApp, keyCalendarId, todo->customProperty(customApp, keyCalendarId));
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
                        const KCalendarCore::MemoryCalendar *calendar = nullptr,
                        const QHash<QString, QString> *todoByEvent = nullptr)
{
    const QDateTime start = occurrenceStart.isValid() ? occurrenceStart : event->dtStart();
    const QDateTime end = occurrenceEnd.isValid() ? occurrenceEnd : event->dtEnd();
    const QString todoId = linkedTodoId(event, calendar, todoByEvent);
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
        {QStringLiteral("calendarId"), todo->customProperty(customApp, keyCalendarId).isEmpty()
                ? QStringLiteral("personal") : todo->customProperty(customApp, keyCalendarId)},
        {QStringLiteral("parentId"), todo->customProperty(customApp, keyParentId)},
        {QStringLiteral("flagged"), todo->customProperty(customApp, keyFlagged) == "1"},
        {QStringLiteral("section"), todo->customProperty(customApp, keySection)},
        {QStringLiteral("tags"), QJsonArray::fromStringList(todo->categories())},
        {QStringLiteral("url"), todo->url().toString()},
        {QStringLiteral("images"), QJsonDocument::fromJson(todo->customProperty(customApp, keyImages).toUtf8()).array()},
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

    int calendarIndex(const QString &id) const
    {
        for (qsizetype i = 0; i < calendars.size(); ++i)
            if (calendars[i].toObject().value("id").toString() == id) return int(i);
        return -1;
    }

    bool hasList(const QString &id) const
    {
        return std::any_of(lists.begin(), lists.end(), [&id](const QJsonValue &entry) {
            return entry.toObject().value(QStringLiteral("id")).toString() == id
                && entry.toObject().value("kind").toString() != "smart";
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

    int holidayIndex(const QString &id) const
    {
        for (qsizetype i = 0; i < holidayCalendars.size(); ++i)
            if (holidayCalendars[i].toObject().value("id").toString() == id) return int(i);
        return -1;
    }

    // Mutations coalesce their writes through a short debounce: serializing
    // the whole calendar to iCalendar plus two QSaveFile commits per edit
    // made a burst of N edits cost N full write cycles. A flush still goes
    // through writeAtomic(), and PimStore's destructor flushes pending edits.
    static constexpr int saveDebounceMs = 150;

    void ensureOrganization()
    {
        for (qsizetype i = 0; i < lists.size(); ++i) {
            auto list = lists[i].toObject();
            const auto group = list.value("group").toString();
            bool found = group.isEmpty();
            for (const auto &value : groups) if (value.toObject().value("name").toString() == group) found = true;
            if (!found) groups.append(QJsonObject{{"id", QUuid::createUuid().toString(QUuid::WithoutBraces)}, {"name", group}});
            auto sections = list.value("sections").toArray();
            for (const auto &todo : calendar->rawTodos()) {
                if (todo->customProperty(customApp, keyListId) != list.value("id").toString()) continue;
                const auto name = todo->customProperty(customApp, keySection);
                bool exists = name.isEmpty();
                for (const auto &value : sections) if (value.toObject().value("name").toString() == name) exists = true;
                if (!exists) sections.append(QJsonObject{{"id", QUuid::createUuid().toString(QUuid::WithoutBraces)}, {"name", name}});
            }
            list.insert("sections", sections);
            lists.replace(i, list);
        }
    }

    void scheduleSave()
    {
        ensureOrganization();
        dirty = true;
        if (saveTimer) {
            saveTimer->start(saveDebounceMs);
        } else if (flushSave()) {
            // Match the timer path and flush(): a synchronous save is also
            // followed by a widget snapshot refresh.
            q->writeWidgetSnapshot();
        }
    }

    bool flushSave()
    {
        if (!dirty)
            return true;
        QString message;
        const bool written = writeState(&message);
        if (!written)
            qWarning() << "Unable to persist PIM state:" << message;
        // Keep unsaved edits marked for a later retry and the final flush.
        // Transient storage failure must not silently discard this obligation.
        if (written)
            dirty = false;
        return written;
    }

    bool writeState(QString *message)
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
            {QStringLiteral("groups"), groups},
            {QStringLiteral("calendars"), calendars},
            {QStringLiteral("holidayCalendars"), holidayCalendars},
        };
        return writeAtomic(metadataPath,
                           QJsonDocument(metadata).toJson(QJsonDocument::Indented), message);
    }

    void load()
    {
        lists = defaultLists();
        calendars = QJsonArray{
            QJsonObject{{"id", "default"}, {"name", "Default"}, {"color", "#BF57DA"}, {"builtinName", true}},
            QJsonObject{{"id", "work"}, {"name", "Work"}, {"color", "#FB8208"}, {"builtinName", true}},
            QJsonObject{{"id", "personal"}, {"name", "Personal"}, {"color", "#1D9BF6"}, {"builtinName", true}},
            QJsonObject{{"id", "family"}, {"name", "Family"}, {"color", "#56D72B"}, {"builtinName", true}}
        };
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
                        holidayCalendars = metadata.value("holidayCalendars").toArray();
                        groups = metadata.value("groups").toArray();
                        if (metadata.value("calendars").isArray()) {
                            const auto defaults = calendars;
                            calendars = metadata.value("calendars").toArray();
                            if (calendarIndex("default") < 0) calendars.prepend(defaults.first());
                        }
                        if (!loadedLists.isEmpty())
                            lists = loadedLists;
                    }
                }
            }
        }
        // Upgrade untouched bundled categories only; user-edited names/colors stay intact.
        const QHash<QString, QString> legacyColors{{"default", "#9B80C9"}, {"work", "#DA8A3A"},
            {"personal", "#508BD6"}, {"family", "#57A878"}};
        const QHash<QString, QString> presetColors{{"default", "#BF57DA"}, {"work", "#FB8208"},
            {"personal", "#1D9BF6"}, {"family", "#56D72B"}};
        for (qsizetype i = 0; i < calendars.size(); ++i) {
            auto category = calendars[i].toObject();
            const auto id = category.value("id").toString();
            if (category.value("builtinName").toBool() && !category.value("customColor").toBool()
                && legacyColors.contains(id)
                && category.value("color").toString().compare(legacyColors.value(id), Qt::CaseInsensitive) == 0) {
                category.insert("color", presetColors.value(id));
                calendars.replace(i, category);
            }
        }
        if (!hasList(QStringLiteral("inbox")))
            lists.prepend(defaultLists().first());

        if (!QFileInfo::exists(calendarPath)) {
            ensureOrganization();
            return;
        }
        KCalendarCore::ICalFormat format;
        if (!format.load(calendar, calendarPath)) {
            storageError = QStringLiteral("Unable to load the existing iCalendar file");
            writable = false;
        }
        ensureOrganization();
    }

    QString storageDirectory;
    QString calendarPath;
    QString metadataPath;
    KCalendarCore::MemoryCalendar::Ptr calendar;
    QJsonArray lists;
    QJsonArray groups;
    QJsonArray calendars;
    QJsonArray holidayCalendars;
    QNetworkAccessManager *holidayNetwork = nullptr;
    QHash<QString, QNetworkReply *> holidayRequests;
    quint64 revision = 0;
    bool writable = true;
    QString storageError;
    QTimer *reminderTimer = nullptr;
    QTimer *saveTimer = nullptr;
    PimStore *q = nullptr;
    bool dirty = false;
    QHash<QString, QDateTime> deliveredReminders;
    struct NotificationTarget { QString uid; bool todo; QString token; };
    QHash<uint, NotificationTarget> notifications;
};

PimStore::PimStore(const QString &storageDirectory, QObject *parent)
    : QObject(parent)
    , d(std::make_unique<Private>(storageDirectory))
{
    d->q = this;
    d->load();
    // Recover the single holiday category created by older versions only when
    // it actually contains imported events. Fresh profiles start with no sources.
    if (d->holidayIndex(QStringLiteral("holidays")) < 0) {
        for (const auto &event : d->calendar->rawEvents()) {
            if (event->customProperty(customApp, keyCalendarId) == QStringLiteral("holidays")) {
                d->holidayCalendars.append(QJsonObject{{"id", "holidays"},
                    {"name", "Imported holidays"}, {"type", "file"},
                    {"enabled", true}, {"color", "#D95658"}});
                break;
            }
        }
    }
    d->holidayNetwork = new QNetworkAccessManager(this);
    auto *holidayTimer = new QTimer(this);
    holidayTimer->setInterval(60 * 60 * 1000);
    connect(holidayTimer, &QTimer::timeout, this, &PimStore::refreshHolidaySubscriptions);
    holidayTimer->start();
    QTimer::singleShot(1500, this, &PimStore::refreshHolidaySubscriptions);
    d->saveTimer = new QTimer(this);
    d->saveTimer->setSingleShot(true);
    d->saveTimer->setInterval(Private::saveDebounceMs);
    connect(d->saveTimer, &QTimer::timeout, this, [this] {
        // A failed save must not advance the widget file ahead of the state
        // actually committed to disk.
        if (d->flushSave())
            writeWidgetSnapshot();
        else
            d->saveTimer->start(5000);
    });
    d->reminderTimer = new QTimer(this);
    d->reminderTimer->setSingleShot(true);
    connect(d->reminderTimer, &QTimer::timeout,
            this, &PimStore::deliverDueReminders);
    connect(this, &PimStore::changed,
            this, &PimStore::scheduleNextReminder);
    QTimer::singleShot(0, this, &PimStore::scheduleNextReminder);
    QTimer::singleShot(0, this, &PimStore::writeWidgetSnapshot);

    auto bus = QDBusConnection::sessionBus();
    const QString service = QStringLiteral("org.freedesktop.Notifications");
    const QString path = QStringLiteral("/org/freedesktop/Notifications");
    bus.connect(service, path, service, QStringLiteral("ActionInvoked"),
                this, SLOT(notificationAction(uint,QString)));
    bus.connect(service, path, service, QStringLiteral("NotificationClosed"),
                this, SLOT(notificationClosed(uint,uint)));
    bus.connect(service, path, service, QStringLiteral("ActivationToken"),
                this, SLOT(notificationToken(uint,QString)));
    auto *watcher = new QDBusServiceWatcher(service, bus,
        QDBusServiceWatcher::WatchForOwnerChange, this);
    connect(watcher, &QDBusServiceWatcher::serviceOwnerChanged, this,
            [this] { d->notifications.clear(); });

    auto *widgetRefreshTimer = new QTimer(this);
    widgetRefreshTimer->setInterval(5 * 60 * 1000);
    connect(widgetRefreshTimer, &QTimer::timeout,
            this, &PimStore::writeWidgetSnapshot);
    widgetRefreshTimer->start();
}

PimStore::~PimStore()
{
    // Persist whatever the debounce window still holds: a store destroyed
    // before the timer fires must not drop its last mutations.
    flush();
}

void PimStore::flush()
{
    d->saveTimer->stop();
    // Match the debounce-timer and synchronous scheduleSave() paths: only a
    // successful state commit refreshes the widget file, so a failed save
    // cannot leave the widget snapshot ahead of what is on disk.
    if (d->flushSave())
        writeWidgetSnapshot();
}

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
    // Retain deduplication keys beyond the catch-up window, then expire them.
    for (auto it = d->deliveredReminders.begin(); it != d->deliveredReminders.end();) {
        if (it.value() < now.addSecs(-600)) it = d->deliveredReminders.erase(it);
        else ++it;
    }
    const auto alarms = d->calendar->alarms(now.addSecs(-300), now);
    for (const KCalendarCore::Alarm::Ptr &alarm : alarms) {
        QDateTime trigger = alarm->time();
        if (!trigger.isValid())
            trigger = alarm->nextTime(now.addSecs(-301));
        if (!trigger.isValid() || trigger < now.addSecs(-300) || trigger > now)
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

        d->deliveredReminders.insert(key, trigger);

        const bool isTodo = incidence->type() == KCalendarCore::IncidenceBase::TypeTodo;
        const bool chinese = QLocale().language() == QLocale::Chinese;
        const QString title = incidence->summary().isEmpty()
            ? (isTodo ? QStringLiteral("Task reminder")
                      : QStringLiteral("Event reminder"))
            : incidence->summary();
        QString body = chinese ? QStringLiteral("日历提醒") : QStringLiteral("Calendar reminder");
        if (!incidence->location().isEmpty())
            body += QStringLiteral(" Location: %1").arg(incidence->location().toHtmlEscaped());

        QDBusMessage notification = QDBusMessage::createMethodCall(
            QStringLiteral("org.freedesktop.Notifications"),
            QStringLiteral("/org/freedesktop/Notifications"),
            QStringLiteral("org.freedesktop.Notifications"),
            QStringLiteral("Notify"));
        QVariantMap hints{
            {QStringLiteral("desktop-entry"),
             QStringLiteral("kos-calendar")},
            {QStringLiteral("urgency"), static_cast<uchar>(1)},
        };
        QStringList actions{QStringLiteral("default"), chinese ? QStringLiteral("查看详情") : QStringLiteral("View details")};
        if (isTodo)
            actions << QStringLiteral("complete") << (chinese ? QStringLiteral("标记完成") : QStringLiteral("Mark completed"));
        notification.setArguments({
            QStringLiteral("KOS Calendar"),
            0U,
            isTodo ? QStringLiteral("view-task") : QStringLiteral("view-calendar"),
            title,
            body,
            actions,
            hints,
            -1,
        });
        auto *pending = new QDBusPendingCallWatcher(
            QDBusConnection::sessionBus().asyncCall(notification, 5000), this);
        const QString uid = incidence->uid();
        connect(pending, &QDBusPendingCallWatcher::finished, this,
                [this, pending, uid, isTodo, key] {
            const QDBusPendingReply<uint> reply = *pending;
            if (!reply.isError() && reply.value() > 0) {
                d->notifications.insert(reply.value(), {uid, isTodo, {}});
            } else {
                d->deliveredReminders.remove(key);
                // Retry delivery while this alarm is still in the catch-up window.
                d->reminderTimer->start(5000);
            }
            pending->deleteLater();
        });
    }
    scheduleNextReminder();
}

void PimStore::notificationToken(uint id, const QString &token)
{
    auto it = d->notifications.find(id);
    if (it != d->notifications.end()) it->token = token;
}

void PimStore::notificationClosed(uint id, uint)
{
    d->notifications.remove(id);
}

void PimStore::notificationAction(uint id, const QString &action)
{
    const auto it = d->notifications.constFind(id);
    if (it == d->notifications.cend()) return;
    const auto target = *it;
    if (action == QStringLiteral("complete") && target.todo) {
        updateTodo(target.uid, QStringLiteral("{\"completed\":true}"));
        return;
    }
    if (action != QStringLiteral("default")) return;
    const QStringList args{QStringLiteral("--item"),
        (target.todo ? QStringLiteral("todo:") : QStringLiteral("event:")) + target.uid};
    QDBusMessage message = QDBusMessage::createMethodCall(
        QStringLiteral("org.nextkde.Kos.Calendar"),
        QStringLiteral("/org/nextkde/Kos/Application"),
        QStringLiteral("org.nextkde.Kos.Application1"), QStringLiteral("Activate"));
    message.setArguments({args, target.token, QString{}});
    auto *pending = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(message), this);
    connect(pending, &QDBusPendingCallWatcher::finished, this, [pending, args, target] {
        const QDBusPendingReply<> reply = *pending;
        if (reply.isError()) {
            const QDir directory(QCoreApplication::applicationDirPath());
            QString executable = directory.filePath(QStringLiteral("kos-calendar"));
            if (!QFileInfo::exists(executable))
                executable = directory.filePath(QStringLiteral("../../apps/calendar/kos-calendar"));
            if (!QFileInfo::exists(executable)) executable = QStandardPaths::findExecutable(QStringLiteral("kos-calendar"));
            if (!executable.isEmpty()) {
                QProcess process;
                auto environment = QProcessEnvironment::systemEnvironment();
                if (!target.token.isEmpty()) {
                    environment.insert(QStringLiteral("XDG_ACTIVATION_TOKEN"), target.token);
                    environment.insert(QStringLiteral("DESKTOP_STARTUP_ID"), target.token);
                }
                process.setProcessEnvironment(environment);
                process.setProgram(executable);
                process.setArguments(args);
                if (!process.startDetached()) qWarning() << "Unable to open calendar reminder";
            }
        }
        pending->deleteLater();
    });
}

void PimStore::writeWidgetSnapshot()
{
    // Periodic refreshes must obey the same committed-state boundary as the
    // save callback; a failed write or unreadable store cannot publish ahead.
    if (d->dirty || !d->writable)
        return;
    const QDate today = QDate::currentDate();

    // Build the widget payload straight from the in-memory model. Routing
    // this through snapshot()+eventsForRange() serialized the whole store to
    // JSON twice and parsed it back just to keep a 16-item subset.
    const QHash<QString, QString> todoByEvent =
        todoIdsByLinkedEvent(d->calendar.data());

    QJsonArray events;
    const QTimeZone zone = d->calendar->timeZone();
    KCalendarCore::OccurrenceIterator iterator(
        *d->calendar, QDateTime(today, QTime(0, 0), zone),
        QDateTime(today.addDays(8), QTime(0, 0), zone).addMSecs(-1));
    while (iterator.hasNext() && events.size() < 16) {
        iterator.next();
        const auto event = qSharedPointerDynamicCast<KCalendarCore::Event>(
            iterator.incidence());
        if (event) {
            events.append(eventObject(event, iterator.occurrenceStartDate(),
                                      iterator.occurrenceEndDate(),
                                      iterator.recurrenceId(), d->calendar.data(),
                                      &todoByEvent));
        }
    }

    QList<KCalendarCore::Todo::Ptr> openTodos;
    for (const KCalendarCore::Todo::Ptr &todo : d->calendar->rawTodos()) {
        if (!todo->isCompleted())
            openTodos.append(todo);
    }
    // Same ordering the full snapshot applies to its todo section once the
    // completed items are filtered out.
    std::sort(openTodos.begin(), openTodos.end(),
              [](const KCalendarCore::Todo::Ptr &left,
                 const KCalendarCore::Todo::Ptr &right) {
        const double leftOrder = left->customProperty(customApp, keyOrder)
                                     .toDouble();
        const double rightOrder = right->customProperty(customApp, keyOrder)
                                      .toDouble();
        if (leftOrder != rightOrder)
            return leftOrder < rightOrder;
        return left->summary() < right->summary();
    });
    QJsonArray todos;
    for (const KCalendarCore::Todo::Ptr &todo : std::as_const(openTodos)) {
        todos.append(todoObject(todo));
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
    const QHash<QString, QString> todoByEvent =
        todoIdsByLinkedEvent(d->calendar.data());
    QJsonArray events;
    QList<QJsonObject> sortedEvents;
    for (const KCalendarCore::Event::Ptr &event : d->calendar->rawEvents())
        sortedEvents.append(eventObject(event, {}, {}, {}, d->calendar.data(),
                                        &todoByEvent));
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
        {QStringLiteral("groups"), d->groups},
        {QStringLiteral("calendars"), d->calendars},
        {QStringLiteral("holidayCalendars"), d->holidayCalendars},
        {QStringLiteral("holidaySources"), holidaySources()},
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
    const QHash<QString, QString> todoByEvent =
        todoIdsByLinkedEvent(d->calendar.data());
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
                                           iterator.recurrenceId(), d->calendar.data(),
                                           &todoByEvent));
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
    // The write is debounced; a storage failure is reported by flushSave().
    d->scheduleSave();
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
    if (d->holidayIndex(event->customProperty(customApp, keyCalendarId)) >= 0)
        return errorResponse(QStringLiteral("read_only_calendar"),
                             QStringLiteral("Manage this event through its holiday calendar"));
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
    // The write is debounced; a storage failure is reported by flushSave().
    d->scheduleSave();
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
    if (d->holidayIndex(event->customProperty(customApp, keyCalendarId)) >= 0)
        return errorResponse(QStringLiteral("read_only_calendar"),
                             QStringLiteral("Manage this event through its holiday calendar"));
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
    // The write is debounced; a storage failure is reported by flushSave().
    d->scheduleSave();
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
    const QString parentId = input.value("parentId").toString();
    if (!parentId.isEmpty()) {
        const auto parent = d->calendar->todo(parentId);
        if (!parent)
            return errorResponse("invalid_parent", "Parent reminder not found");
        listId = parent->customProperty(customApp, keyListId);
    }
    if (input.contains("flagged") && !input.value("flagged").isBool())
        return errorResponse("invalid_todo", "Flagged must be a boolean");
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
    todo->setCustomProperty(customApp, keyCalendarId,
                            input.value(QStringLiteral("calendarId")).toString(QStringLiteral("personal")));
    todo->setCustomProperty(customApp, keyListId, listId);
    todo->setCustomProperty(customApp, keyFlagged, input.value("flagged").toBool() ? "1" : "0");
    todo->setCustomProperty(customApp, keyParentId,
                            input.value(QStringLiteral("parentId")).toString());
    todo->setCustomProperty(customApp, keyOrder,
                            QString::number(input.value(QStringLiteral("order")).toDouble(
                                QDateTime::currentMSecsSinceEpoch()), 'g', 17));
    if (!applyTodoOrganization(todo, input, &message))
        return errorResponse("invalid_todo", message);
    if (!applyRecurrence(todo, input, &message))
        return errorResponse(QStringLiteral("invalid_recurrence"), message);
    if (!applyTodoMedia(todo, input, d->storageDirectory, &message))
        return errorResponse("invalid_todo", message);
    applyReminder(todo, input.value(QStringLiteral("reminderMinutes")).toInt(-1));
    if (input.value(QStringLiteral("completed")).toBool())
        todo->setCompleted(QDateTime::currentDateTimeUtc());
    if (!d->calendar->addTodo(todo))
        return errorResponse(QStringLiteral("calendar_error"),
                             QStringLiteral("Unable to add todo"));
    ++d->revision;
    // The write is debounced; a storage failure is reported by flushSave().
    d->scheduleSave();
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
    if (input.contains(QStringLiteral("calendarId")))
        updated->setCustomProperty(customApp, keyCalendarId,
                                   input.value(QStringLiteral("calendarId")).toString());
    if (input.contains(QStringLiteral("listId"))) {
        const QString listId = input.value(QStringLiteral("listId")).toString();
        if (!d->hasList(listId))
            return errorResponse(QStringLiteral("invalid_list"), QStringLiteral("List not found"));
        updated->setCustomProperty(customApp, keyListId, listId);
    }
    if (input.contains("flagged")) {
        if (!input.value("flagged").isBool())
            return errorResponse("invalid_todo", "Flagged must be a boolean");
        updated->setCustomProperty(customApp, keyFlagged, input.value("flagged").toBool() ? "1" : "0");
    }
    if (input.contains("parentId")) {
        const QString parentId = input.value("parentId").toString();
        QSet<QString> visited{uid};
        QString ancestor = parentId;
        while (!ancestor.isEmpty()) {
            const auto parent = d->calendar->todo(ancestor);
            if (!parent || visited.contains(ancestor))
                return errorResponse("invalid_parent", "Parent reminder is missing or would create a cycle");
            visited.insert(ancestor);
            ancestor = parent->customProperty(customApp, keyParentId);
        }
        if (!parentId.isEmpty())
            updated->setCustomProperty(customApp, keyListId,
                d->calendar->todo(parentId)->customProperty(customApp, keyListId));
        if (parentId.isEmpty()) updated->removeCustomProperty(customApp, keyParentId);
        else updated->setCustomProperty(customApp, keyParentId, parentId);
    } else if (input.contains("listId")
               && updated->customProperty(customApp, keyListId) != todo->customProperty(customApp, keyListId)) {
        // Moving a child explicitly to a different list makes it a top-level task.
        updated->removeCustomProperty(customApp, keyParentId);
    }
    // A moved parent carries its descendants; completion remains independent.
    QSet<QString> descendants{uid};
    bool added = true;
    while (added) {
        added = false;
        for (const auto &candidate : d->calendar->rawTodos()) {
            if (!descendants.contains(candidate->uid())
                && descendants.contains(candidate->customProperty(customApp, keyParentId))) {
                descendants.insert(candidate->uid());
                added = true;
            }
        }
    }
    if (input.contains(QStringLiteral("order")))
        updated->setCustomProperty(customApp, keyOrder,
                                   QString::number(input.value(QStringLiteral("order")).toDouble(), 'g', 17));
    if (input.contains(QStringLiteral("completed"))) {
        if (input.value(QStringLiteral("completed")).toBool())
            updated->setCompleted(QDateTime::currentDateTimeUtc());
        else
            updated->setCompleted(false);
    }
    if (!applyTodoOrganization(updated, input, &message))
        return errorResponse("invalid_todo", message);
    if (!applyRecurrence(updated, input, &message))
        return errorResponse(QStringLiteral("invalid_recurrence"), message);
    if (input.contains(QStringLiteral("reminderMinutes")))
        applyReminder(updated, input.value(QStringLiteral("reminderMinutes")).toInt(-1));

    if (!applyTodoMedia(updated, input, d->storageDirectory, &message))
        return errorResponse("invalid_todo", message);

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
    if (updated->customProperty(customApp, keyListId) != todo->customProperty(customApp, keyListId)
        || updated->customProperty(customApp, keySection) != todo->customProperty(customApp, keySection)) {
        for (const auto &candidate : d->calendar->rawTodos()) {
            if (descendants.contains(candidate->uid()) && candidate->uid() != uid) {
                candidate->setCustomProperty(customApp, keyListId, updated->customProperty(customApp, keyListId));
                if (updated->customProperty(customApp, keySection).isEmpty()) candidate->removeCustomProperty(customApp, keySection);
                else candidate->setCustomProperty(customApp, keySection, updated->customProperty(customApp, keySection));
            }
        }
    }
    ++d->revision;
    // The write is debounced; a storage failure is reported by flushSave().
    d->scheduleSave();
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
    // The write is debounced; a storage failure is reported by flushSave().
    d->scheduleSave();
    emit changed(d->revision);
    return successResponse(d->revision);
}

QString PimStore::createCalendar(const QString &payload)
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
        return errorResponse(QStringLiteral("invalid_calendar"), QStringLiteral("Calendar name is invalid"));
    static const QRegularExpression colorPattern(QStringLiteral("^#[0-9a-fA-F]{6}$"));
    if (input.contains("color") && !colorPattern.match(input.value("color").toString()).hasMatch())
        return errorResponse("invalid_calendar", "Calendar color is invalid");
    const QString id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    const QJsonObject list{
        {QStringLiteral("id"), id},
        {QStringLiteral("name"), name},
        {QStringLiteral("color"), input.value(QStringLiteral("color")).toString(
             QStringLiteral("#4f8cff"))},
        {QStringLiteral("position"), d->calendars.size()},
    };
    d->calendars.append(list);
    ++d->revision;
    // The write is debounced; a storage failure is reported by flushSave().
    d->scheduleSave();
    emit changed(d->revision);
    return successResponse(d->revision, list);
}

QString PimStore::updateCalendar(const QString &id, const QString &payload)
{
    if (!d->writable)
        return errorResponse(QStringLiteral("storage_read_only"), d->storageError);
    const int index = d->calendarIndex(id);
    if (index < 0)
        return errorResponse(QStringLiteral("not_found"), QStringLiteral("Calendar not found"));
    QJsonObject input;
    QString message;
    if (!parsePayload(payload, &input, &message))
        return errorResponse(QStringLiteral("invalid_payload"), message);
    QJsonObject list = d->calendars.at(index).toObject();
    if (input.contains(QStringLiteral("name"))) {
        bool valid = true;
        const QString name = boundedString(input, QStringLiteral("name"), 128, &valid);
        if (!valid || name.isEmpty())
            return errorResponse(QStringLiteral("invalid_calendar"),
                                 QStringLiteral("Calendar name is invalid"));
        list.insert(QStringLiteral("name"), name);
        list.insert("builtinName", false);
    }
    if (input.contains(QStringLiteral("color"))) {
        static const QRegularExpression colorPattern(QStringLiteral("^#[0-9a-fA-F]{6}$"));
        if (!colorPattern.match(input.value("color").toString()).hasMatch())
            return errorResponse("invalid_calendar", "Calendar color is invalid");
        list.insert(QStringLiteral("color"), input.value(QStringLiteral("color")));
        list.insert("customColor", true);
    }
    if (input.contains(QStringLiteral("position")))
        list.insert(QStringLiteral("position"), input.value(QStringLiteral("position")).toInt());
    d->calendars.replace(index, list);
    ++d->revision;
    // The write is debounced; a storage failure is reported by flushSave().
    d->scheduleSave();
    emit changed(d->revision);
    return successResponse(d->revision, list);
}

QString PimStore::removeCalendar(const QString &id)
{
    if (id == QLatin1String("default"))
        return errorResponse(QStringLiteral("protected_calendar"),
                             QStringLiteral("The default calendar cannot be removed"));
    if (!d->writable)
        return errorResponse(QStringLiteral("storage_read_only"), d->storageError);
    const int index = d->calendarIndex(id);
    if (index < 0)
        return errorResponse(QStringLiteral("not_found"), QStringLiteral("Calendar not found"));
    d->calendars.removeAt(index);
    // Preserve records and recurrence rules; only their classification changes.
    for (const auto &incidence : d->calendar->rawIncidences()) {
        const auto category = incidence->customProperty(customApp, keyCalendarId);
        if (category == id || (category.isEmpty() && id == QLatin1String("personal")))
            incidence->setCustomProperty(customApp, keyCalendarId, QStringLiteral("default"));
    }
    ++d->revision;
    // The write is debounced; a storage failure is reported by flushSave().
    d->scheduleSave();
    emit changed(d->revision);
    return successResponse(d->revision);
}

QString PimStore::saveGroup(const QString &id, const QString &payload)
{
    if (!d->writable) return errorResponse("storage_read_only", d->storageError);
    QJsonObject input; QString message;
    if (!parsePayload(payload, &input, &message)) return errorResponse("invalid_payload", message);
    bool valid = true;
    const auto name = boundedString(input, "name", 128, &valid);
    if (!valid || name.isEmpty()) return errorResponse("invalid_group", "Enter a group name");
    int index = -1;
    for (qsizetype i = 0; i < d->groups.size(); ++i) {
        const auto group = d->groups[i].toObject();
        if (group.value("id").toString() == id) index = i;
        else if (group.value("name").toString().compare(name, Qt::CaseInsensitive) == 0)
            return errorResponse("duplicate_group", "A group with this name already exists");
    }
    if (!id.isEmpty() && index < 0) return errorResponse("not_found", "Group not found");
    const auto oldName = index < 0 ? QString() : d->groups[index].toObject().value("name").toString();
    const QJsonObject group{{"id", id.isEmpty() ? QUuid::createUuid().toString(QUuid::WithoutBraces) : id}, {"name", name}};
    if (index < 0) d->groups.append(group); else d->groups.replace(index, group);
    if (index >= 0) for (qsizetype i = 0; i < d->lists.size(); ++i) {
        auto list = d->lists[i].toObject();
        if (list.value("group").toString() == oldName) { list.insert("group", name); d->lists.replace(i, list); }
    }
    ++d->revision; d->scheduleSave(); emit changed(d->revision);
    return successResponse(d->revision, group);
}

QString PimStore::removeGroup(const QString &id)
{
    if (!d->writable) return errorResponse("storage_read_only", d->storageError);
    for (qsizetype i = 0; i < d->groups.size(); ++i) {
        const auto group = d->groups[i].toObject();
        if (group.value("id").toString() != id) continue;
        for (qsizetype j = 0; j < d->lists.size(); ++j) {
            auto list = d->lists[j].toObject();
            if (list.value("group").toString() == group.value("name").toString()) {
                list.remove("group"); d->lists.replace(j, list);
            }
        }
        d->groups.removeAt(i);
        ++d->revision; d->scheduleSave(); emit changed(d->revision);
        return successResponse(d->revision);
    }
    return errorResponse("not_found", "Group not found");
}

QString PimStore::saveSection(const QString &listId, const QString &id, const QString &payload)
{
    if (!d->writable) return errorResponse("storage_read_only", d->storageError);
    const int listIndex = d->listIndex(listId);
    if (listIndex < 0) return errorResponse("not_found", "List not found");
    auto list = d->lists[listIndex].toObject();
    if (list.value("kind").toString() == "smart") return errorResponse("invalid_list", "Smart lists cannot own sections");
    QJsonObject input; QString message;
    if (!parsePayload(payload, &input, &message)) return errorResponse("invalid_payload", message);
    auto sections = list.value("sections").toArray();
    int index = -1;
    for (qsizetype i = 0; i < sections.size(); ++i) if (sections[i].toObject().value("id").toString() == id) index = i;
    if (!id.isEmpty() && index < 0) return errorResponse("not_found", "Section not found");
    const auto oldName = index < 0 ? QString() : sections[index].toObject().value("name").toString();
    bool valid = true;
    const auto name = input.contains("name") ? boundedString(input, "name", 128, &valid) : oldName;
    if (!valid || name.isEmpty()) return errorResponse("invalid_section", "Enter a section name");
    for (qsizetype i = 0; i < sections.size(); ++i)
        if (i != index && sections[i].toObject().value("name").toString().compare(name, Qt::CaseInsensitive) == 0)
            return errorResponse("duplicate_section", "A section with this name already exists");
    if (input.contains("position") && (!input.value("position").isDouble() || input.value("position").toInt(-1) < 0
        || input.value("position").toInt() >= sections.size() + (index < 0 ? 1 : 0)))
        return errorResponse("invalid_section", "Invalid section position");
    const QJsonObject section{{"id", id.isEmpty() ? QUuid::createUuid().toString(QUuid::WithoutBraces) : id}, {"name", name}};
    const int position = input.contains("position") ? input.value("position").toInt() : index < 0 ? sections.size() : index;
    if (index >= 0) sections.removeAt(index);
    sections.insert(position, section);
    list.insert("sections", sections); d->lists.replace(listIndex, list);
    if (index >= 0 && oldName != name) for (const auto &todo : d->calendar->rawTodos())
        if (todo->customProperty(customApp, keyListId) == listId && todo->customProperty(customApp, keySection) == oldName)
            todo->setCustomProperty(customApp, keySection, name);
    ++d->revision; d->scheduleSave(); emit changed(d->revision);
    return successResponse(d->revision, section);
}

QString PimStore::removeSection(const QString &listId, const QString &id)
{
    if (!d->writable) return errorResponse("storage_read_only", d->storageError);
    const int listIndex = d->listIndex(listId);
    if (listIndex < 0) return errorResponse("not_found", "List not found");
    auto list = d->lists[listIndex].toObject(); auto sections = list.value("sections").toArray();
    for (qsizetype i = 0; i < sections.size(); ++i) {
        const auto section = sections[i].toObject();
        if (section.value("id").toString() != id) continue;
        for (const auto &todo : d->calendar->rawTodos())
            if (todo->customProperty(customApp, keyListId) == listId && todo->customProperty(customApp, keySection) == section.value("name").toString())
                todo->removeCustomProperty(customApp, keySection);
        sections.removeAt(i); list.insert("sections", sections); d->lists.replace(listIndex, list);
        ++d->revision; d->scheduleSave(); emit changed(d->revision);
        return successResponse(d->revision);
    }
    return errorResponse("not_found", "Section not found");
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
    QJsonObject list{
        {QStringLiteral("id"), id},
        {QStringLiteral("name"), name},
        {QStringLiteral("color"), input.value(QStringLiteral("color")).toString(
             QStringLiteral("#4f8cff"))},
        {QStringLiteral("position"), d->lists.size()},
    };
    if (!applyListOrganization(list, input, &message))
        return errorResponse("invalid_list", message);
    d->lists.append(list);
    ++d->revision;
    // The write is debounced; a storage failure is reported by flushSave().
    d->scheduleSave();
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
    if (input.contains("kind") && input.value("kind").toString() != list.value("kind").toString("list"))
        return errorResponse("invalid_list", "An existing list cannot change its type");
    if (!applyListOrganization(list, input, &message))
        return errorResponse("invalid_list", message);
    d->lists.replace(index, list);
    ++d->revision;
    // The write is debounced; a storage failure is reported by flushSave().
    d->scheduleSave();
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
    // The write is debounced; a storage failure is reported by flushSave().
    d->scheduleSave();
    emit changed(d->revision);
    return successResponse(d->revision);
}

QString PimStore::importIcalendar(const QString &path, bool replaceExisting)
{
    return importCalendarFile(path, replaceExisting, false);
}

QString PimStore::importHolidays(const QString &path)
{
    return importCalendarFile(path, false, true);
}

QString PimStore::importCalendarFile(const QString &path, bool replaceExisting, bool holidaysOnly)
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
    if (holidaysOnly && imported->rawEvents().isEmpty())
        return errorResponse(QStringLiteral("empty_holiday_calendar"),
                             QStringLiteral("The holiday calendar contains no events"));
    int importedCount = 0;
    int skippedCount = 0;
    if (replaceExisting) {
        importedCount = imported->rawIncidences().size();
        d->calendar = imported;
    } else {
        for (const KCalendarCore::Incidence::Ptr &incidence : imported->rawIncidences()) {
            if (holidaysOnly && incidence->type() != KCalendarCore::IncidenceBase::TypeEvent) {
                ++skippedCount;
                continue;
            }
            if (d->calendar->incidence(incidence->uid())) {
                ++skippedCount;
                continue;
            }
            KCalendarCore::Incidence::Ptr copy(incidence->clone());
            if (holidaysOnly) {
                copy->setCustomProperty(customApp, keyCalendarId, QStringLiteral("holidays"));
                copy->setCustomProperty(customApp, keyLinkedTodoId, QString{});
                copy->clearAlarms();
            }
            if (d->calendar->addIncidence(copy))
                ++importedCount;
            else
                ++skippedCount;
        }
    }
    if (holidaysOnly && importedCount > 0 && d->holidayIndex("holidays") < 0)
        d->holidayCalendars.append(QJsonObject{{"id", "holidays"},
            {"name", "Imported holidays"}, {"type", "file"},
            {"enabled", true}, {"color", "#D95658"}});
    ++d->revision;
    // The write is debounced; a storage failure is reported by flushSave().
    d->scheduleSave();
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

QString PimStore::addHolidayCalendar(const QString &payload)
{
    if (!d->writable) return errorResponse("storage_read_only", d->storageError);
    QJsonObject input;
    QString error;
    if (!parsePayload(payload, &input, &error)) return errorResponse("invalid_payload", error);
    const QString type = input.value("type").toString();
    const QString name = input.value("name").toString().trimmed();
    if (name.isEmpty() || name.size() > 128)
        return errorResponse("invalid_name", QStringLiteral("Enter a calendar name"));
    QJsonObject descriptor{{"id", "holiday:" + QUuid::createUuid().toString(QUuid::WithoutBraces)},
        {"name", name}, {"type", type}, {"enabled", true}, {"color", "#D95658"}};
    QString sourceKey;
    if (type == "country") {
        const QString region = input.value("region").toString();
        for (const auto &entry : holidaySources()) {
            const auto source = entry.toObject();
            if (source.value("id").toString() == region) {
                descriptor.insert("region", region);
                descriptor.insert("url", source.value("url"));
                descriptor.insert("provider", source.value("provider"));
                sourceKey = "country:" + region;
                break;
            }
        }
        if (sourceKey.isEmpty()) return errorResponse("invalid_region", "Choose a country or region");
    } else if (type == "url") {
        QUrl url(input.value("url").toString().trimmed());
        if (url.scheme() == "webcal") url.setScheme("https");
        if (!url.isValid() || url.host().isEmpty() || !url.userInfo().isEmpty()
            || (url.scheme() != "https" && url.scheme() != "http") || url.toString().size() > 4096)
            return errorResponse("invalid_url", "Enter an HTTP or HTTPS calendar address");
        url.setFragment({});
        descriptor.insert("url", url.toString(QUrl::FullyEncoded));
        sourceKey = "url:" + url.toString(QUrl::FullyEncoded);
    } else if (type == "file") {
        const QUrl url(input.value("path").toString());
        const QFileInfo file(url.isLocalFile() ? url.toLocalFile() : input.value("path").toString());
        if (!file.isAbsolute() || !file.isFile()) return errorResponse("invalid_file", "Choose an iCalendar file");
        descriptor.insert("path", file.canonicalFilePath());
        sourceKey = "file:" + file.canonicalFilePath();
    } else return errorResponse("invalid_source", "Choose a calendar source");
    descriptor.insert("sourceKey", sourceKey);
    for (const auto &entry : d->holidayCalendars)
        if (entry.toObject().value("sourceKey").toString() == sourceKey)
            return errorResponse("duplicate_calendar", "This holiday calendar has already been added");
    for (auto *reply : std::as_const(d->holidayRequests))
        if (reply->property("sourceKey").toString() == sourceKey)
            return errorResponse("calendar_busy", "This holiday calendar is being added");
    return type == "file" ? loadHolidayFile(descriptor) : fetchHolidayCalendar(descriptor);
}

QString PimStore::loadHolidayFile(const QJsonObject &descriptor)
{
    const QFileInfo fileInfo(descriptor.value("path").toString());
    if (!fileInfo.isAbsolute() || !fileInfo.isFile() || fileInfo.size() > maximumImportBytes)
        return errorResponse("invalid_file", "Calendar file is missing or exceeds 20 MiB");
    QFile file(fileInfo.absoluteFilePath());
    if (!file.open(QIODevice::ReadOnly)) return errorResponse("invalid_file", file.errorString());
    const auto data = file.read(maximumImportBytes + 1);
    return applyHolidayCalendar(descriptor, data);
}

QString PimStore::applyHolidayCalendar(const QJsonObject &descriptor, const QByteArray &data)
{
    if (!d->writable) return errorResponse("storage_read_only", d->storageError);
    if (data.size() > maximumImportBytes) return errorResponse("file_too_large", "Calendar exceeds 20 MiB");
    KCalendarCore::MemoryCalendar::Ptr imported(new KCalendarCore::MemoryCalendar(d->calendar->timeZone()));
    KCalendarCore::ICalFormat format;
    if (!format.fromString(imported, QString::fromUtf8(data)))
        return errorResponse("invalid_icalendar", "Unable to parse iCalendar file");
    const auto events = imported->rawEvents();
    if (events.isEmpty() || events.size() > 10000)
        return errorResponse("invalid_holidays", "Calendar must contain between 1 and 10000 events");
    const QString id = descriptor.value("id").toString();
    // Assemble the complete replacement before touching live data. Failed
    // refreshes leave the previous calendar, its UIDs and personal items intact.
    KCalendarCore::MemoryCalendar::Ptr staged(new KCalendarCore::MemoryCalendar(d->calendar->timeZone()));
    for (const auto &incidence : d->calendar->rawIncidences()) {
        if (incidence->customProperty(customApp, keyCalendarId) == id) continue;
        if (!staged->addIncidence(KCalendarCore::Incidence::Ptr(incidence->clone())))
            return errorResponse("calendar_error", "Unable to preserve existing calendar data");
    }
    for (const auto &event : events) {
        KCalendarCore::Event::Ptr copy(event->clone());
        copy->setUid(id + ':' + QString::fromLatin1(QCryptographicHash::hash(
            event->uid().toUtf8(), QCryptographicHash::Sha256).toHex()));
        copy->setCustomProperty(customApp, keyCalendarId, id);
        copy->setCustomProperty(customApp, keyLinkedTodoId, QString{});
        copy->clearAlarms();
        if (!staged->addEvent(copy)) return errorResponse("calendar_error", "Unable to load holiday events");
    }
    QJsonObject updated = descriptor;
    updated.insert("lastUpdated", double(QDateTime::currentMSecsSinceEpoch()));
    updated.insert("lastAttempt", updated.value("lastUpdated"));
    updated.insert("lastError", "");
    updated.insert("eventCount", events.size());
    const int index = d->holidayIndex(id);
    if (index < 0) d->holidayCalendars.append(updated);
    else {
        // Display preferences may have changed while a request was in flight.
        updated.insert("enabled", d->holidayCalendars[index].toObject().value("enabled"));
        d->holidayCalendars.replace(index, updated);
    }
    d->calendar = staged;
    ++d->revision;
    d->scheduleSave();
    emit changed(d->revision);
    return successResponse(d->revision, updated);
}

QString PimStore::refreshHolidayCalendar(const QString &id)
{
    if (!d->writable) return errorResponse("storage_read_only", d->storageError);
    const int index = d->holidayIndex(id);
    if (index < 0) return errorResponse("not_found", "Holiday calendar not found");
    const auto descriptor = d->holidayCalendars[index].toObject();
    return descriptor.value("type").toString() == "file"
        ? loadHolidayFile(descriptor) : fetchHolidayCalendar(descriptor);
}

QString PimStore::setHolidayCalendarEnabled(const QString &id, bool enabled)
{
    if (!d->writable) return errorResponse("storage_read_only", d->storageError);
    const int index = d->holidayIndex(id);
    if (index < 0) return errorResponse("not_found", "Holiday calendar not found");
    auto descriptor = d->holidayCalendars[index].toObject();
    descriptor.insert("enabled", enabled);
    d->holidayCalendars.replace(index, descriptor);
    ++d->revision;
    d->scheduleSave();
    emit changed(d->revision);
    return successResponse(d->revision, descriptor);
}

QString PimStore::removeHolidayCalendar(const QString &id)
{
    if (!d->writable) return errorResponse("storage_read_only", d->storageError);
    const int index = d->holidayIndex(id);
    if (index < 0) return errorResponse("not_found", "Holiday calendar not found");
    for (const auto &event : d->calendar->rawEvents())
        if (event->customProperty(customApp, keyCalendarId) == id) d->calendar->deleteEvent(event);
    d->holidayCalendars.removeAt(index);
    ++d->revision;
    d->scheduleSave();
    emit changed(d->revision);
    if (auto *reply = d->holidayRequests.value(id)) reply->abort();
    return successResponse(d->revision);
}

QString PimStore::fetchHolidayCalendar(const QJsonObject &descriptor)
{
    const QString id = descriptor.value("id").toString();
    if (d->holidayRequests.contains(id)) return errorResponse("calendar_busy", "Calendar is already refreshing");
    if (!calledFromDBus()) return errorResponse("async_required", "Online calendars require a D-Bus request");
    const auto bus = connection();
    auto reply = message().createReply();
    setDelayedReply(true);
    downloadHolidayCalendar(descriptor, d->holidayIndex(id) >= 0,
        [bus, reply](const QString &result) mutable { reply << result; bus.send(reply); });
    return {};
}

void PimStore::downloadHolidayCalendar(const QJsonObject &descriptor, bool existing,
                                      std::function<void(const QString &)> finished)
{
    const QString id = descriptor.value("id").toString();
    QNetworkRequest request{QUrl(descriptor.value("url").toString())};
    request.setTransferTimeout(15000);
    request.setMaximumRedirectsAllowed(4);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    request.setRawHeader("User-Agent", "NextKde-Calendar/1.0");
    request.setRawHeader("Accept", "text/calendar, text/plain;q=0.9, */*;q=0.1");
    auto *reply = d->holidayNetwork->get(request);
    reply->setProperty("sourceKey", descriptor.value("sourceKey").toString());
    d->holidayRequests.insert(id, reply);
    auto data = std::make_shared<QByteArray>();
    auto tooLarge = std::make_shared<bool>(false);
    // A wall-clock deadline also covers redirects and stalled DNS/TLS setup.
    QTimer::singleShot(20000, reply, [reply] { if (!reply->isFinished()) reply->abort(); });
    connect(reply, &QNetworkReply::readyRead, this, [reply, data, tooLarge] {
        data->append(reply->readAll());
        if (data->size() > maximumImportBytes) { *tooLarge = true; reply->abort(); }
    });
    connect(reply, &QNetworkReply::finished, this,
        [this, descriptor, id, existing, reply, data, tooLarge, finished = std::move(finished)] {
            data->append(reply->readAll());
            d->holidayRequests.remove(id);
            QString result;
            if (existing && d->holidayIndex(id) < 0)
                result = errorResponse("cancelled", "Holiday calendar was removed");
            else if (*tooLarge || data->size() > maximumImportBytes)
                result = errorResponse("file_too_large", "Calendar exceeds 20 MiB");
            else if (reply->error() != QNetworkReply::NoError
                     || reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() != 200)
                result = errorResponse("download_failed", "Unable to download the calendar: " + reply->errorString());
            else result = applyHolidayCalendar(descriptor, *data);
            const auto response = QJsonDocument::fromJson(result.toUtf8()).object();
            if (!response.value("ok").toBool()) {
                const int index = d->holidayIndex(id);
                if (index >= 0) {
                    auto current = d->holidayCalendars[index].toObject();
                    current.insert("lastError", response.value("error").toObject().value("message"));
                    current.insert("lastAttempt", double(QDateTime::currentMSecsSinceEpoch()));
                    d->holidayCalendars.replace(index, current);
                    ++d->revision;
                    d->scheduleSave();
                    emit changed(d->revision);
                }
            }
            reply->deleteLater();
            finished(result);
        });
}

void PimStore::refreshHolidaySubscriptions()
{
    if (!d->writable) return;
    const auto now = QDateTime::currentMSecsSinceEpoch();
    for (const auto &entry : d->holidayCalendars) {
        const auto descriptor = entry.toObject();
        const QString id = descriptor.value("id").toString();
        if (descriptor.value("type").toString() == "file" || d->holidayRequests.contains(id)) continue;
        if (now - qint64(descriptor.value("lastUpdated").toDouble()) < 24 * 60 * 60 * 1000LL) continue;
        if (now - qint64(descriptor.value("lastAttempt").toDouble()) < 60 * 60 * 1000LL) continue;
        downloadHolidayCalendar(descriptor, true, [](const QString &) {});
    }
}
