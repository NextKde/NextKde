#include "PimStore.h"

#include <QFileInfo>
#include <QFile>
#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTemporaryDir>
#include <QUrl>
#include <QtTest>

namespace {

QJsonObject parseObject(const QString &encoded)
{
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(encoded.toUtf8(), &error);
    if (error.error != QJsonParseError::NoError || !document.isObject())
        return {};
    return document.object();
}

QString encode(const QJsonObject &object)
{
    return QString::fromUtf8(QJsonDocument(object).toJson(QJsonDocument::Compact));
}

} // namespace

class PimStoreTest : public QObject {
    Q_OBJECT

private slots:
    void reminderGroupsAndSections();
    void reminderFlagsAndHierarchy();
    void reminderOrganizationMetadata();
    void reminderLinksImagesAndListIcons();
    void managedCalendarCategories();
    void calendarPaletteMigrationPreservesCustomColors();
    void eventPersistsAcrossRestart();
    void calendarCategoriesPreserveTodoLists();
    void recurringEventExpandsForRange();
    void todoListsAndCompletionPersist();
    void recurringTodoCanUseDueDate();
    void recurringTodoExpandsForCalendarRange();
    void linkedEventAndTodoStayInSync();
    void removingLinkedItemPreservesCounterpart();
    void invalidUpdatesDoNotMutateItems();
    void exportsAndImportsIcalendar();
    void holidayImportPreservesPersonalData();
    void managedHolidayCalendars();
    void widgetSnapshotRefreshesAfterMutation();
};

void PimStoreTest::reminderGroupsAndSections()
{
    QTemporaryDir directory;
    QString groupId, listId, sectionId, todoId;
    {
        PimStore store(directory.path());
        auto group = parseObject(store.saveGroup("", encode({{"name", "Projects"}})));
        QVERIFY(group.value("ok").toBool());
        groupId = group.value("item").toObject().value("id").toString();
        QVERIFY(!parseObject(store.saveGroup("", encode({{"name", "projects"}}))).value("ok").toBool());
        auto list = parseObject(store.createList(encode({{"name", "Launch"}, {"group", "Projects"}}))).value("item").toObject();
        listId = list.value("id").toString();
        auto section = parseObject(store.saveSection(listId, "", encode({{"name", "Before"}})));
        QVERIFY(section.value("ok").toBool());
        sectionId = section.value("item").toObject().value("id").toString();
        QVERIFY(!parseObject(store.saveSection(listId, "", encode({{"name", "before"}}))).value("ok").toBool());
        QVERIFY(!parseObject(store.saveSection(listId, sectionId, encode({{"position", -1}}))).value("ok").toBool());
        auto todo = parseObject(store.createTodo(encode({{"title", "Prepare"}, {"listId", listId}, {"section", "Before"}}))).value("item").toObject();
        todoId = todo.value("id").toString();
        QVERIFY(parseObject(store.saveSection(listId, "", encode({{"name", "After"}}))).value("ok").toBool());
        QVERIFY(parseObject(store.saveSection(listId, sectionId, encode({{"name", "Planning"}, {"position", 1}}))).value("ok").toBool());
        QCOMPARE(parseObject(store.snapshot()).value("todos").toArray()[0].toObject().value("section").toString(), QString("Planning"));
        QVERIFY(parseObject(store.saveGroup(groupId, encode({{"name", "Work"}}))).value("ok").toBool());
        QVERIFY(parseObject(store.updateList(listId, encode({{"viewMode", "columns"}}))).value("ok").toBool());
        store.flush();
    }
    {
        PimStore store(directory.path());
        auto snapshot = parseObject(store.snapshot());
        QCOMPARE(snapshot.value("groups").toArray()[0].toObject().value("name").toString(), QString("Work"));
        QJsonObject list;
        for (const auto &value : snapshot.value("lists").toArray()) if (value.toObject().value("id").toString() == listId) list = value.toObject();
        QCOMPARE(list.value("group").toString(), QString("Work"));
        QCOMPARE(list.value("viewMode").toString(), QString("columns"));
        QCOMPARE(list.value("sections").toArray().size(), 2);
        QCOMPARE(list.value("sections").toArray()[1].toObject().value("id").toString(), sectionId);
        QVERIFY(parseObject(store.removeSection(listId, sectionId)).value("ok").toBool());
        snapshot = parseObject(store.snapshot());
        QCOMPARE(snapshot.value("todos").toArray().size(), 1);
        QCOMPARE(snapshot.value("todos").toArray()[0].toObject().value("section").toString(), QString());
        QVERIFY(parseObject(store.removeGroup(groupId)).value("ok").toBool());
        snapshot = parseObject(store.snapshot());
        QCOMPARE(snapshot.value("groups").toArray().size(), 0);
        QCOMPARE(snapshot.value("todos").toArray().size(), 1);
        for (const auto &value : snapshot.value("lists").toArray()) if (value.toObject().value("id").toString() == listId) QVERIFY(value.toObject().value("group").toString().isEmpty());
        QVERIFY(parseObject(store.saveGroup("", encode({{"name", "Empty"}}))).value("ok").toBool());
        store.flush();
    }
    {
        PimStore store(directory.path());
        QCOMPARE(parseObject(store.snapshot()).value("groups").toArray().size(), 1);
        QCOMPARE(parseObject(store.snapshot()).value("todos").toArray()[0].toObject().value("id").toString(), todoId);
    }
}

void PimStoreTest::reminderLinksImagesAndListIcons()
{
    QTemporaryDir directory;
    QTemporaryDir originals;
    const auto imagePath = originals.filePath("image.png");
    QFile image(imagePath);
    QVERIFY(image.open(QIODevice::WriteOnly));
    image.write(QByteArray::fromBase64("iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAEp0lEQVR4nBXOsQqFhgEAwHxThw4ODg4ODg4ODg4OUiwIkWJBiAQDQqRYECrBgBApFoRKMBAaCAQC/bL23nD7ffGHP/3nf38kICQiJiElI6egpKKmoaWjZ2BkYmZhZWPn4OTi5uHliz/8WYCAkIiYhJSMnIKSipqGlo6egZGJmYWVjZ2Dk4ubh/fPn0AjQEBIRExCSkZOQUlFTUNLR8/AyMTMwsrGzsHJxc3D23wCXwoQEBIRk5CSkVNQUlHT0NLRMzAyMbOwsrFzcHJx8/B++Qn8RYCAkIiYhJSMnIKSipqGlo6egZGJmYWVjZ2Dk4ubh/cvn8BfBQgIiYhJSMnIKSipqGlo6egZGJmYWVjZ2Dk4ubh5eP/6CfQCBIRExCSkZOQUlFTUNLR09AyMTMwsrGzsHJxc3Dy8/SfwlQABIRExCSkZOQUlFTUNLR09AyMTMwsrGzsHJxc3D+9Xn8DXAgSERMQkpGTkFJRU1DS0dPQMjEzMLKxs7BycXNw8vF9/At8IEBASEZOQkpFTUFJR09DS0TMwMjGzsLKxc3BycfPwfvMJTAIEhETEJKRk5BSUVNQ0tHT0DIxMzCysbOwcnFzcPLzTJ/CtAAEhETEJKRk5BSUVNQ0tHT0DIxMzCysbOwcnFzcP77efwN8ECAiJiElIycgpKKmoaWjp6BkYmZhZWNnYOTi5uHl4//YJ/F2AgJCImISUjJyCkoqahpaOnoGRiZmFlY2dg5OLm4f375/AKkBASERMQkpGTkFJRU1DS0fPwMjEzMLKxs7BycXNw7t+Av8QICAkIiYhJSOnoKSipqGlo2dgZGJmYWVj5+Dk4ubh/ccn8J0AASERMQkpGTkFJRU1DS0dPQMjEzMLKxs7BycXNw/vd5/A9wIEhETEJKRk5BSUVNQ0tHT0DIxMzCysbOwcnFzcPLzffwKHAAEhETEJKRk5BSUVNQ0tHT0DIxMzCysbOwcnFzcP7/EJ/CBAQEhETEJKRk5BSUVNQ0tHz8DIxMzCysbOwcnFzcP7wyfwTwECQiJiElIycgpKKmoaWjp6BkYmZhZWNnYOTi5uHt5/fgL/EiAgJCImISUjp6CkoqahpaNnYGRiZmFlY+fg5OLm4f3XJ3ALEBASEZOQkpFTUFJR09DS0TMwMjGzsLKxc3BycfPw3p/AvwUICImISUjJyCkoqahpaOnoGRiZmFlY2dg5OLm4eXj//Qn8KEBASERMQkpGTkFJRU1DS0fPwMjEzMLKxs7BycXNw/vjJ/CTAAEhETEJKRk5BSUVNQ0tHT0DIxMzCysbOwcnFzcP70+fwM8CBIRExCSkZOQUlFTUNLR09AyMTMwsrGzsHJxc3Dy8P38CvwgQEBIRk5CSkVNQUlHT0NLRMzAyMbOwsrFzcHJx8/D+8gn8KkBASERMQkpGTkFJRU1DS0fPwMjEzMLKxs7BycXNw/vrJ/CbAAEhETEJKRk5BSUVNQ0tHT0DIxMzCysbOwcnFzcP72+fwO8CBIRExCSkZOQUlFTUNLR09AyMTMwsrGzsHJxc3Dy8v38C/xUgICQiJiElI6egpKKmoaWjZ2BkYmZhZWPn4OTi5uHl/wM61pdGhb6uAAAAAElFTkSuQmCC"));
    image.close();
    PimStore store(directory.path());
    const auto list = parseObject(store.createList(encode({{"name", "Home"}, {"icon", "home"}}))).value("item").toObject();
    QCOMPARE(list.value("icon").toString(), "home");
    QVERIFY(!parseObject(store.updateList(list.value("id").toString(), encode({{"icon", "missing-icon"}}))).value("ok").toBool());
    const auto result = parseObject(store.createTodo(encode({{"title", "Reference"}, {"url", "https://example.com/reference"}, {"images", QJsonArray{QUrl::fromLocalFile(imagePath).toString()}}})));
    QVERIFY(result.value("ok").toBool());
    const auto task = result.value("item").toObject();
    const auto id = task.value("id").toString();
    const auto storedUrl = task.value("images").toArray().first().toString();
    QVERIFY(QFile::exists(QUrl(storedUrl).toLocalFile()));
    QVERIFY(QUrl(storedUrl).toLocalFile() != imagePath);
    QVERIFY(QFile::remove(imagePath));
    QVERIFY(!parseObject(store.updateTodo(id, encode({{"url", "file:///etc/passwd"}}))).value("ok").toBool());
    QVERIFY(!parseObject(store.updateTodo(id, encode({{"images", QJsonArray{"https://example.com/image.png"}}}))).value("ok").toBool());
    store.flush();
    PimStore reloaded(directory.path());
    const auto snapshot = parseObject(reloaded.snapshot());
    const auto saved = snapshot.value("todos").toArray().first().toObject();
    QCOMPARE(saved.value("url").toString(), "https://example.com/reference");
    QCOMPARE(saved.value("images").toArray().first().toString(), storedUrl);
    QVERIFY(QFile::exists(QUrl(storedUrl).toLocalFile()));
    QVERIFY(parseObject(reloaded.updateTodo(id, encode({{"url", ""}, {"images", QJsonArray{}}}))).value("ok").toBool());
    const auto cleared = parseObject(reloaded.snapshot()).value("todos").toArray().first().toObject();
    QVERIFY(cleared.value("url").toString().isEmpty());
    QVERIFY(cleared.value("images").toArray().isEmpty());
}

void PimStoreTest::reminderOrganizationMetadata()
{
    QTemporaryDir directory;
    PimStore store(directory.path());
    const QJsonObject rules{{"tag", "release"}, {"date", "scheduled"}, {"flag", "yes"}, {"priority", "high"}};
    const auto list = parseObject(store.createList(encode({{"name", "Releases"}, {"group", "Work"}}))).value("item").toObject();
    const auto listId = list.value("id").toString();
    const auto smart = parseObject(store.createList(encode({{"name", "Important releases"}, {"group", "Work"}, {"kind", "smart"}, {"rules", rules}}))).value("item").toObject();
    QVERIFY(!smart.value("id").toString().isEmpty());
    QVERIFY(!parseObject(store.updateList(listId, encode({{"kind", "smart"}}))).value("ok").toBool());
    QVERIFY(!parseObject(store.createList(encode({{"name", "Invalid"}, {"rules", QJsonObject{{"date", "bad"}}}}))).value("ok").toBool());
    auto task = parseObject(store.createTodo(encode({{"title", "Ship"}, {"listId", listId}, {"section", "Ready"}, {"tags", QJsonArray{"#release", "Release", "docs"}}, {"order", 12.5}}))).value("item").toObject();
    QCOMPARE(task.value("tags").toArray(), QJsonArray({"release", "docs"}));
    const auto id = task.value("id").toString();
    QVERIFY(!parseObject(store.updateTodo(id, encode({{"tags", QJsonArray{"invalid tag"}}, {"title", "Must not save"}}))).value("ok").toBool());
    QVERIFY(parseObject(store.updateTodo(id, encode({{"order", 1793270012345.25}}))).value("ok").toBool());
    store.flush();
    PimStore reloaded(directory.path());
    const auto snapshot = parseObject(reloaded.snapshot());
    task = snapshot.value("todos").toArray().first().toObject();
    QCOMPARE(task.value("title").toString(), "Ship");
    QCOMPARE(task.value("section").toString(), "Ready");
    QCOMPARE(task.value("order").toDouble(), 1793270012345.25);
    QCOMPARE(task.value("tags").toArray(), QJsonArray({"release", "docs"}));
    bool found = false;
    for (const auto &entry : snapshot.value("lists").toArray()) {
        const auto item = entry.toObject();
        if (item.value("id") == smart.value("id")) {
            QCOMPARE(item.value("rules").toObject(), rules);
            QCOMPARE(item.value("group").toString(), "Work");
            found = true;
        }
    }
    QVERIFY(found);
    QVERIFY(parseObject(reloaded.removeList(smart.value("id").toString())).value("ok").toBool());
    QCOMPARE(parseObject(reloaded.snapshot()).value("todos").toArray().size(), 1);
}

void PimStoreTest::reminderFlagsAndHierarchy()
{
    QTemporaryDir directory;
    PimStore store(directory.path());
    const auto parent = parseObject(store.createTodo(encode({{"title", "Parent"}, {"flagged", true}}))).value("item").toObject();
    const auto parentId = parent.value("id").toString();
    QVERIFY(!parentId.isEmpty());
    QVERIFY(parent.value("flagged").toBool());
    QVERIFY(!parseObject(store.createTodo(encode({{"title", "Bad"}, {"parentId", "missing"}}))).value("ok").toBool());
    const auto child = parseObject(store.createTodo(encode({{"title", "Child"}, {"parentId", parentId}}))).value("item").toObject();
    const auto childId = child.value("id").toString();
    QVERIFY(!childId.isEmpty());
    QVERIFY(!parseObject(store.updateTodo(parentId, encode({{"parentId", childId}}))).value("ok").toBool());
    QVERIFY(!parseObject(store.updateTodo(parentId, encode({{"flagged", "yes"}}))).value("ok").toBool());
    const auto listId = parseObject(store.createList(encode({{"name", "Moved"}}))).value("item").toObject().value("id").toString();
    QVERIFY(parseObject(store.updateTodo(parentId, encode({{"listId", listId}}))).value("ok").toBool());
    const auto todos = parseObject(store.snapshot()).value("todos").toArray();
    QCOMPARE(todos.size(), 2);
    for (const auto &entry : todos) QCOMPARE(entry.toObject().value("listId").toString(), listId);
    store.flush();
    PimStore reloaded(directory.path());
    const auto saved = parseObject(reloaded.snapshot()).value("todos").toArray();
    for (const auto &entry : saved) {
        const auto item = entry.toObject();
        if (item.value("id").toString() == parentId) QVERIFY(item.value("flagged").toBool());
        else QCOMPARE(item.value("parentId").toString(), parentId);
    }
    QVERIFY(parseObject(reloaded.removeTodo(parentId)).value("ok").toBool());
    const auto remaining = parseObject(reloaded.snapshot()).value("todos").toArray();
    QCOMPARE(remaining.size(), 1);
    QVERIFY(remaining.first().toObject().value("parentId").toString().isEmpty());
}

void PimStoreTest::calendarPaletteMigrationPreservesCustomColors()
{
    QTemporaryDir directory;
    const auto path = directory.filePath("metadata.json");
    {
        PimStore store(directory.path());
        QVERIFY(parseObject(store.updateCalendar("family", encode({{"color", "#123456"}}))).value("ok").toBool());
        store.flush();
    }
    QFile file(path);
    QVERIFY(file.open(QIODevice::ReadOnly));
    auto metadata = QJsonDocument::fromJson(file.readAll()).object();
    file.close();
    auto calendars = metadata.value("calendars").toArray();
    auto untouched = calendars[0].toObject();
    untouched.insert("color", "#9B80C9");
    calendars[0] = untouched;
    auto customized = calendars[1].toObject();
    customized.insert("color", "#DA8A3A");
    customized.insert("customColor", true);
    calendars[1] = customized;
    metadata.insert("calendars", calendars);
    QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
    file.write(QJsonDocument(metadata).toJson());
    file.close();
    PimStore reloaded(directory.path());
    calendars = parseObject(reloaded.snapshot()).value("calendars").toArray();
    QCOMPARE(calendars[0].toObject().value("color").toString(), QString("#BF57DA"));
    QCOMPARE(calendars[1].toObject().value("color").toString(), QString("#DA8A3A"));
    QCOMPARE(calendars[3].toObject().value("color").toString(), QString("#123456"));
}

void PimStoreTest::managedCalendarCategories()
{
    QTemporaryDir directory;
    QString id, eventId, todoId;
    {
        PimStore store(directory.path());
        QCOMPARE(parseObject(store.snapshot()).value("calendars").toArray().size(), 4);
        const auto created = parseObject(store.createCalendar(encode({{"name", "Study"}, {"color", "#508BD6"}})));
        QVERIFY(created.value("ok").toBool());
        id = created.value("item").toObject().value("id").toString();
        QVERIFY(!parseObject(store.createCalendar(encode({{"name", " "}}))).value("ok").toBool());
        QVERIFY(!parseObject(store.updateCalendar(id, encode({{"name", "Changed"}, {"color", "bad"}}))).value("ok").toBool());
        auto calendars = parseObject(store.snapshot()).value("calendars").toArray();
        QCOMPARE(calendars.last().toObject().value("name").toString(), QString("Study"));
        QVERIFY(parseObject(store.updateCalendar(id, encode({{"name", "Learning"}, {"color", "#57A878"}}))).value("ok").toBool());
        eventId = parseObject(store.createEvent(encode({{"title", "Lesson"}, {"calendarId", id},
            {"start", "2026-10-28T12:00:00"}, {"end", "2026-10-28T13:00:00"}}))).value("item").toObject().value("id").toString();
        todoId = parseObject(store.createTodo(encode({{"title", "Homework"}, {"calendarId", id}, {"listId", "inbox"}}))).value("item").toObject().value("id").toString();
        QVERIFY(!eventId.isEmpty());
        QVERIFY(!todoId.isEmpty());
        store.flush();
    }
    {
        PimStore store(directory.path());
        auto calendars = parseObject(store.snapshot()).value("calendars").toArray();
        QCOMPARE(calendars.size(), 5);
        QCOMPARE(calendars.last().toObject().value("name").toString(), QString("Learning"));
        QVERIFY(!parseObject(store.removeCalendar("default")).value("ok").toBool());
        QVERIFY(parseObject(store.removeCalendar(id)).value("ok").toBool());
        QVERIFY(!parseObject(store.removeCalendar(id)).value("ok").toBool());
        store.flush();
    }
    {
        PimStore store(directory.path());
        const auto snapshot = parseObject(store.snapshot());
        QCOMPARE(snapshot.value("calendars").toArray().size(), 4);
        const auto event = snapshot.value("events").toArray().first().toObject();
        const auto todo = snapshot.value("todos").toArray().first().toObject();
        QCOMPARE(event.value("id").toString(), eventId);
        QCOMPARE(todo.value("id").toString(), todoId);
        QCOMPARE(event.value("calendarId").toString(), QString("default"));
        QCOMPARE(todo.value("calendarId").toString(), QString("default"));
        QCOMPARE(todo.value("listId").toString(), QString("inbox"));
    }
}

void PimStoreTest::calendarCategoriesPreserveTodoLists()
{
    QTemporaryDir directory;
    QString uid;
    {
        PimStore store(directory.path());
        const auto created = parseObject(store.createTodo(encode({
            {QStringLiteral("title"), QStringLiteral("Run")},
            {QStringLiteral("listId"), QStringLiteral("inbox")},
            {QStringLiteral("calendarId"), QStringLiteral("sport")},
            {QStringLiteral("due"), QStringLiteral("2026-10-28T18:00:00")},
            {QStringLiteral("reminderMinutes"), 15},
        })));
        QVERIFY(created.value(QStringLiteral("ok")).toBool());
        uid = created.value(QStringLiteral("item")).toObject().value(QStringLiteral("id")).toString();
        auto item = parseObject(store.updateTodo(uid, encode({
            {QStringLiteral("calendarId"), QStringLiteral("work")},
        }))).value(QStringLiteral("item")).toObject();
        QCOMPARE(item.value(QStringLiteral("calendarId")).toString(), QStringLiteral("work"));
        QCOMPARE(item.value(QStringLiteral("listId")).toString(), QStringLiteral("inbox"));
        QCOMPARE(item.value(QStringLiteral("reminderMinutes")).toInt(), 15);
    }
    PimStore store(directory.path());
    const auto item = parseObject(store.snapshot()).value(QStringLiteral("todos")).toArray().first().toObject();
    QCOMPARE(item.value(QStringLiteral("id")).toString(), uid);
    QCOMPARE(item.value(QStringLiteral("calendarId")).toString(), QStringLiteral("work"));
    QCOMPARE(item.value(QStringLiteral("listId")).toString(), QStringLiteral("inbox"));
}

void PimStoreTest::eventPersistsAcrossRestart()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    QString uid;
    {
        PimStore store(directory.path());
        const QJsonObject response = parseObject(store.createEvent(encode({
            {QStringLiteral("title"), QStringLiteral("Design review")},
            {QStringLiteral("description"), QStringLiteral("Review the PIM boundary")},
            {QStringLiteral("location"), QStringLiteral("Studio")},
            {QStringLiteral("start"), QStringLiteral("2026-09-02T09:00:00+08:00")},
            {QStringLiteral("end"), QStringLiteral("2026-09-02T10:00:00+08:00")},
            {QStringLiteral("timeZone"), QStringLiteral("Asia/Shanghai")},
            {QStringLiteral("reminderMinutes"), 15},
        })));
        QVERIFY2(response.value(QStringLiteral("ok")).toBool(),
                 qPrintable(response.value(QStringLiteral("error")).toObject()
                                .value(QStringLiteral("message")).toString()));
        uid = response.value(QStringLiteral("item")).toObject()
                  .value(QStringLiteral("id")).toString();
        QVERIFY(!uid.isEmpty());
        // Writes are debounced, so the file appears only after flush()
        // (or, outside tests, after the debounce timer fires).
        store.flush();
        QVERIFY(QFileInfo::exists(directory.filePath(QStringLiteral("calendar.ics"))));
    }

    PimStore reloaded(directory.path());
    const QJsonObject snapshot = parseObject(reloaded.snapshot());
    QCOMPARE(snapshot.value(QStringLiteral("schemaVersion")).toInt(), 1);
    const QJsonArray events = snapshot.value(QStringLiteral("events")).toArray();
    QCOMPARE(events.size(), 1);
    QCOMPARE(events.first().toObject().value(QStringLiteral("id")).toString(), uid);
    QCOMPARE(events.first().toObject().value(QStringLiteral("reminderMinutes")).toInt(), 15);
}

void PimStoreTest::widgetSnapshotRefreshesAfterMutation()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    PimStore store(directory.path());
    const QJsonObject created = parseObject(store.createTodo(encode({
        {QStringLiteral("title"), QStringLiteral("Visible on the desktop")},
        {QStringLiteral("due"), QDateTime::currentDateTime().addSecs(3600)
             .toString(Qt::ISODate)},
    })));
    QVERIFY(created.value(QStringLiteral("ok")).toBool());
    store.flush();

    QFile snapshotFile(directory.filePath(QStringLiteral("widget-snapshot.json")));
    QVERIFY(snapshotFile.open(QIODevice::ReadOnly));
    const QJsonObject widget = QJsonDocument::fromJson(snapshotFile.readAll()).object();
    QCOMPARE(widget.value(QStringLiteral("schemaVersion")).toInt(), 1);
    QCOMPARE(widget.value(QStringLiteral("todos")).toArray().size(), 1);
    QCOMPARE(widget.value(QStringLiteral("todos")).toArray().first().toObject()
                 .value(QStringLiteral("title")).toString(),
             QStringLiteral("Visible on the desktop"));
}

void PimStoreTest::recurringEventExpandsForRange()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    PimStore store(directory.path());
    const QJsonObject created = parseObject(store.createEvent(encode({
        {QStringLiteral("title"), QStringLiteral("Daily stand-up")},
        {QStringLiteral("start"), QStringLiteral("2026-09-01T09:00:00+08:00")},
        {QStringLiteral("end"), QStringLiteral("2026-09-01T09:20:00+08:00")},
        {QStringLiteral("timeZone"), QStringLiteral("Asia/Shanghai")},
        {QStringLiteral("recurrence"), QStringLiteral("daily")},
        {QStringLiteral("recurrenceCount"), 3},
    })));
    QVERIFY(created.value(QStringLiteral("ok")).toBool());

    const QJsonObject range = parseObject(store.eventsForRange(
        QStringLiteral("2026-09-01"), QStringLiteral("2026-09-05")));
    QVERIFY(range.value(QStringLiteral("ok")).toBool());
    QCOMPARE(range.value(QStringLiteral("occurrences")).toArray().size(), 3);
}

void PimStoreTest::todoListsAndCompletionPersist()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    PimStore store(directory.path());
    const QJsonObject listResponse = parseObject(store.createList(encode({
        {QStringLiteral("name"), QStringLiteral("Release")},
        {QStringLiteral("color"), QStringLiteral("#ffb84d")},
    })));
    QVERIFY(listResponse.value(QStringLiteral("ok")).toBool());
    const QString listId = listResponse.value(QStringLiteral("item")).toObject()
                               .value(QStringLiteral("id")).toString();

    const QJsonObject createResponse = parseObject(store.createTodo(encode({
        {QStringLiteral("title"), QStringLiteral("Write release notes")},
        {QStringLiteral("listId"), listId},
        {QStringLiteral("due"), QStringLiteral("2026-09-03T18:00:00+08:00")},
        {QStringLiteral("priority"), 2},
    })));
    QVERIFY(createResponse.value(QStringLiteral("ok")).toBool());
    const QString uid = createResponse.value(QStringLiteral("item")).toObject()
                            .value(QStringLiteral("id")).toString();
    const QJsonObject updateResponse = parseObject(store.updateTodo(uid, encode({
        {QStringLiteral("completed"), true},
    })));
    QVERIFY(updateResponse.value(QStringLiteral("ok")).toBool());
    store.flush();

    PimStore reloaded(directory.path());
    const QJsonObject snapshot = parseObject(reloaded.snapshot());
    const QJsonArray todos = snapshot.value(QStringLiteral("todos")).toArray();
    QCOMPARE(todos.size(), 1);
    QVERIFY(todos.first().toObject().value(QStringLiteral("completed")).toBool());
    QCOMPARE(todos.first().toObject().value(QStringLiteral("listId")).toString(), listId);
}

void PimStoreTest::recurringTodoCanUseDueDate()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    PimStore store(directory.path());
    const QJsonObject created = parseObject(store.createTodo(encode({
        {QStringLiteral("title"), QStringLiteral("Daily journal")},
        {QStringLiteral("due"), QStringLiteral("2026-09-03T18:00:00+08:00")},
        {QStringLiteral("recurrence"), QStringLiteral("daily")},
        {QStringLiteral("recurrenceCount"), 5},
        {QStringLiteral("reminderMinutes"), 15},
    })));
    QVERIFY2(created.value(QStringLiteral("ok")).toBool(),
             qPrintable(created.value(QStringLiteral("error")).toObject()
                            .value(QStringLiteral("message")).toString()));
    const QJsonObject item = created.value(QStringLiteral("item")).toObject();
    QCOMPARE(item.value(QStringLiteral("recurrence")).toString(), QStringLiteral("daily"));
    QCOMPARE(item.value(QStringLiteral("reminderMinutes")).toInt(), 15);
    store.flush();

    PimStore reloaded(directory.path());
    const QJsonArray todos = parseObject(reloaded.snapshot())
                                 .value(QStringLiteral("todos")).toArray();
    QCOMPARE(todos.size(), 1);
    QCOMPARE(todos.first().toObject().value(QStringLiteral("recurrence")).toString(),
             QStringLiteral("daily"));
    QCOMPARE(todos.first().toObject().value(QStringLiteral("reminderMinutes")).toInt(), 15);
}

void PimStoreTest::recurringTodoExpandsForCalendarRange()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    PimStore store(directory.path());
    QVERIFY(parseObject(store.createTodo(encode({
        {QStringLiteral("title"), QStringLiteral("Calendar-visible task")},
        {QStringLiteral("due"), QStringLiteral("2026-09-03T18:00:00+08:00")},
        {QStringLiteral("recurrence"), QStringLiteral("daily")},
        {QStringLiteral("recurrenceCount"), 3},
    }))).value(QStringLiteral("ok")).toBool());

    const QJsonObject range = parseObject(store.eventsForRange(
        QStringLiteral("2026-09-01"), QStringLiteral("2026-09-08")));
    QVERIFY(range.value(QStringLiteral("ok")).toBool());
    const QJsonArray occurrences = range.value(QStringLiteral("todoOccurrences")).toArray();
    QCOMPARE(occurrences.size(), 3);
    QCOMPARE(occurrences.first().toObject().value(QStringLiteral("due"))
                 .toString().left(10), QStringLiteral("2026-09-03"));
}

void PimStoreTest::linkedEventAndTodoStayInSync()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    QString eventId;
    QString todoId;
    {
        PimStore store(directory.path());
        const QJsonObject created = parseObject(store.createEvent(encode({
            {QStringLiteral("title"), QStringLiteral("Release planning")},
            {QStringLiteral("description"), QStringLiteral("Prepare the milestone")},
            {QStringLiteral("start"), QStringLiteral("2026-09-10T09:00:00+08:00")},
            {QStringLiteral("end"), QStringLiteral("2026-09-10T10:30:00+08:00")},
            {QStringLiteral("linkedTodo"), true},
            {QStringLiteral("todoListId"), QStringLiteral("personal")},
            {QStringLiteral("todoPriority"), 2},
        })));
        QVERIFY2(created.value(QStringLiteral("ok")).toBool(),
                 qPrintable(created.value(QStringLiteral("error")).toObject()
                                .value(QStringLiteral("message")).toString()));
        const QJsonObject createdEvent = created.value(QStringLiteral("item")).toObject();
        eventId = createdEvent.value(QStringLiteral("id")).toString();
        todoId = createdEvent.value(QStringLiteral("linkedTodoId")).toString();
        QVERIFY(!eventId.isEmpty());
        QVERIFY(!todoId.isEmpty());

        QJsonObject snapshot = parseObject(store.snapshot());
        QCOMPARE(snapshot.value(QStringLiteral("todos")).toArray().size(), 1);
        QJsonObject todo = snapshot.value(QStringLiteral("todos")).toArray()
                               .first().toObject();
        QCOMPARE(todo.value(QStringLiteral("id")).toString(), todoId);
        QCOMPARE(todo.value(QStringLiteral("linkedEventId")).toString(), eventId);
        // Preserve the original minute precision while comparing absolute
        // time: calendar SDKs may normalize sub-minute fields differently.
        QCOMPARE(QDateTime::fromString(todo.value(QStringLiteral("due")).toString(), Qt::ISODate).toSecsSinceEpoch() / 60,
                 QDateTime::fromString(QStringLiteral("2026-09-10T09:00:00+08:00"), Qt::ISODate).toSecsSinceEpoch() / 60);
        QCOMPARE(todo.value(QStringLiteral("priority")).toInt(), 2);

        QVERIFY(parseObject(store.updateEvent(eventId, encode({
            {QStringLiteral("title"), QStringLiteral("Release readiness")},
            {QStringLiteral("start"), QStringLiteral("2026-09-10T11:00:00+08:00")},
            {QStringLiteral("end"), QStringLiteral("2026-09-10T12:30:00+08:00")},
        }))).value(QStringLiteral("ok")).toBool());
        todo = parseObject(store.snapshot()).value(QStringLiteral("todos"))
                   .toArray().first().toObject();
        QCOMPARE(todo.value(QStringLiteral("title")).toString(),
                 QStringLiteral("Release readiness"));
        QCOMPARE(QDateTime::fromString(todo.value(QStringLiteral("due")).toString(), Qt::ISODate).toSecsSinceEpoch() / 60,
                 QDateTime::fromString(QStringLiteral("2026-09-10T11:00:00+08:00"), Qt::ISODate).toSecsSinceEpoch() / 60);

        QVERIFY(parseObject(store.updateTodo(todoId, encode({
            {QStringLiteral("title"), QStringLiteral("Ship release")},
            {QStringLiteral("due"), QStringLiteral("2026-09-11T14:00:00+08:00")},
            {QStringLiteral("completed"), true},
        }))).value(QStringLiteral("ok")).toBool());
        snapshot = parseObject(store.snapshot());
        const QJsonObject event = snapshot.value(QStringLiteral("events"))
                                      .toArray().first().toObject();
        QCOMPARE(event.value(QStringLiteral("title")).toString(),
                 QStringLiteral("Ship release"));
        QCOMPARE(QDateTime::fromString(event.value(QStringLiteral("start")).toString(), Qt::ISODate).toSecsSinceEpoch() / 60,
                 QDateTime::fromString(QStringLiteral("2026-09-11T14:00:00+08:00"), Qt::ISODate).toSecsSinceEpoch() / 60);
        QCOMPARE(QDateTime::fromString(event.value(QStringLiteral("end")).toString(), Qt::ISODate).toSecsSinceEpoch() / 60,
                 QDateTime::fromString(QStringLiteral("2026-09-11T15:30:00+08:00"), Qt::ISODate).toSecsSinceEpoch() / 60);
        QVERIFY(event.value(QStringLiteral("linkedTodoCompleted")).toBool());
    }

    PimStore reloaded(directory.path());
    const QJsonObject snapshot = parseObject(reloaded.snapshot());
    QCOMPARE(snapshot.value(QStringLiteral("events")).toArray().first().toObject()
                 .value(QStringLiteral("linkedTodoId")).toString(), todoId);
    QCOMPARE(snapshot.value(QStringLiteral("todos")).toArray().first().toObject()
                 .value(QStringLiteral("linkedEventId")).toString(), eventId);
}

void PimStoreTest::removingLinkedItemPreservesCounterpart()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    PimStore store(directory.path());
    const QJsonObject created = parseObject(store.createEvent(encode({
        {QStringLiteral("title"), QStringLiteral("Keep the task")},
        {QStringLiteral("start"), QStringLiteral("2026-09-12T09:00:00Z")},
        {QStringLiteral("end"), QStringLiteral("2026-09-12T10:00:00Z")},
        {QStringLiteral("linkedTodo"), true},
        {QStringLiteral("reminderMinutes"), 15},
    })));
    QVERIFY(created.value(QStringLiteral("ok")).toBool());
    const QString eventId = created.value(QStringLiteral("item")).toObject()
                                .value(QStringLiteral("id")).toString();

    QVERIFY(parseObject(store.removeEvent(eventId))
                .value(QStringLiteral("ok")).toBool());
    const QJsonObject snapshot = parseObject(store.snapshot());
    QCOMPARE(snapshot.value(QStringLiteral("events")).toArray().size(), 0);
    QCOMPARE(snapshot.value(QStringLiteral("todos")).toArray().size(), 1);
    QVERIFY(snapshot.value(QStringLiteral("todos")).toArray().first().toObject()
                .value(QStringLiteral("linkedEventId")).toString().isEmpty());
    QCOMPARE(snapshot.value(QStringLiteral("todos")).toArray().first().toObject()
                 .value(QStringLiteral("reminderMinutes")).toInt(), 15);

    const QJsonObject second = parseObject(store.createEvent(encode({
        {QStringLiteral("title"), QStringLiteral("Keep the event")},
        {QStringLiteral("start"), QStringLiteral("2026-09-13T09:00:00Z")},
        {QStringLiteral("end"), QStringLiteral("2026-09-13T10:00:00Z")},
        {QStringLiteral("linkedTodo"), true},
    })));
    QVERIFY(second.value(QStringLiteral("ok")).toBool());
    const QString secondTodoId = second.value(QStringLiteral("item")).toObject()
                                     .value(QStringLiteral("linkedTodoId")).toString();
    QVERIFY(parseObject(store.removeTodo(secondTodoId))
                .value(QStringLiteral("ok")).toBool());
    const QJsonArray events = parseObject(store.snapshot())
                                  .value(QStringLiteral("events")).toArray();
    QCOMPARE(events.size(), 1);
    QVERIFY(events.first().toObject().value(QStringLiteral("linkedTodoId"))
                .toString().isEmpty());
}

void PimStoreTest::invalidUpdatesDoNotMutateItems()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    PimStore store(directory.path());

    const QJsonObject eventResponse = parseObject(store.createEvent(encode({
        {QStringLiteral("title"), QStringLiteral("Original event")},
        {QStringLiteral("start"), QStringLiteral("2026-09-02T09:00:00+08:00")},
        {QStringLiteral("end"), QStringLiteral("2026-09-02T10:00:00+08:00")},
    })));
    QVERIFY(eventResponse.value(QStringLiteral("ok")).toBool());
    const QString eventId = eventResponse.value(QStringLiteral("item")).toObject()
                                .value(QStringLiteral("id")).toString();
    const QJsonObject badEventUpdate = parseObject(store.updateEvent(eventId, encode({
        {QStringLiteral("title"), QStringLiteral("Leaked event title")},
        {QStringLiteral("end"), QStringLiteral("2026-09-02T08:00:00+08:00")},
    })));
    QVERIFY(!badEventUpdate.value(QStringLiteral("ok")).toBool());

    const QJsonObject todoResponse = parseObject(store.createTodo(encode({
        {QStringLiteral("title"), QStringLiteral("Original todo")},
    })));
    QVERIFY(todoResponse.value(QStringLiteral("ok")).toBool());
    const QString todoId = todoResponse.value(QStringLiteral("item")).toObject()
                               .value(QStringLiteral("id")).toString();
    const QJsonObject badTodoUpdate = parseObject(store.updateTodo(todoId, encode({
        {QStringLiteral("title"), QStringLiteral("Leaked todo title")},
        {QStringLiteral("listId"), QStringLiteral("missing-list")},
    })));
    QVERIFY(!badTodoUpdate.value(QStringLiteral("ok")).toBool());

    const QJsonObject snapshot = parseObject(store.snapshot());
    const QJsonArray events = snapshot.value(QStringLiteral("events")).toArray();
    const QJsonArray todos = snapshot.value(QStringLiteral("todos")).toArray();
    QCOMPARE(events.size(), 1);
    QCOMPARE(todos.size(), 1);
    QCOMPARE(events.first().toObject().value(QStringLiteral("title")).toString(),
             QStringLiteral("Original event"));
    QCOMPARE(todos.first().toObject().value(QStringLiteral("title")).toString(),
             QStringLiteral("Original todo"));
}

void PimStoreTest::exportsAndImportsIcalendar()
{
    QTemporaryDir sourceDirectory;
    QTemporaryDir destinationDirectory;
    QVERIFY(sourceDirectory.isValid());
    QVERIFY(destinationDirectory.isValid());
    PimStore source(sourceDirectory.path());
    QVERIFY(parseObject(source.createEvent(encode({
        {QStringLiteral("title"), QStringLiteral("Portable event")},
        {QStringLiteral("start"), QStringLiteral("2026-09-04T10:00:00Z")},
        {QStringLiteral("end"), QStringLiteral("2026-09-04T11:00:00Z")},
    }))).value(QStringLiteral("ok")).toBool());
    const QString exportPath = sourceDirectory.filePath(QStringLiteral("export.ics"));
    QVERIFY(parseObject(source.exportIcalendar(exportPath))
                .value(QStringLiteral("ok")).toBool());

    PimStore destination(destinationDirectory.path());
    const QJsonObject imported = parseObject(destination.importIcalendar(exportPath, false));
    QVERIFY(imported.value(QStringLiteral("ok")).toBool());
    QCOMPARE(imported.value(QStringLiteral("imported")).toInt(), 1);
    QCOMPARE(parseObject(destination.snapshot()).value(QStringLiteral("events"))
                 .toArray().size(), 1);
}

void PimStoreTest::holidayImportPreservesPersonalData()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString path = directory.filePath(QStringLiteral("holidays.ics"));
    QString personalUid;
    {
        PimStore store(directory.path());
        const auto personal = parseObject(store.createEvent(encode({
            {QStringLiteral("title"), QStringLiteral("Personal event")},
            {QStringLiteral("calendarId"), QStringLiteral("personal")},
            {QStringLiteral("start"), QStringLiteral("2030-01-02T10:00:00Z")},
            {QStringLiteral("end"), QStringLiteral("2030-01-02T11:00:00Z")},
        })));
        QVERIFY(personal.value(QStringLiteral("ok")).toBool());
        personalUid = personal.value(QStringLiteral("item")).toObject()
                          .value(QStringLiteral("id")).toString();
        QVERIFY(!personalUid.isEmpty());
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        const QByteArray ics = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//KOS//Test//EN\r\n"
            "BEGIN:VEVENT\r\nUID:holiday-test\r\nDTSTAMP:20260101T000000Z\r\n"
            "DTSTART;VALUE=DATE:20300101\r\nDTEND;VALUE=DATE:20300102\r\n"
            "SUMMARY:Imported holiday\r\nRRULE:FREQ=YEARLY\r\n"
            "BEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT15M\r\n"
            "DESCRIPTION:Unwanted holiday alarm\r\nEND:VALARM\r\nEND:VEVENT\r\n"
            "BEGIN:VEVENT\r\nUID:" + personalUid.toUtf8() + "\r\n"
            "DTSTAMP:20260101T000000Z\r\nDTSTART;VALUE=DATE:20300102\r\n"
            "DTEND;VALUE=DATE:20300103\r\nSUMMARY:Conflicting import\r\nEND:VEVENT\r\n"
            "BEGIN:VTODO\r\nUID:ignored-todo\r\nDTSTAMP:20260101T000000Z\r\n"
            "SUMMARY:Not a holiday\r\nEND:VTODO\r\nEND:VCALENDAR\r\n";
        QCOMPARE(file.write(ics), ics.size());
        file.close();

        const auto result = parseObject(store.importHolidays(path));
        QVERIFY(result.value(QStringLiteral("ok")).toBool());
        QCOMPARE(result.value(QStringLiteral("imported")).toInt(), 1);
        QCOMPARE(result.value(QStringLiteral("skipped")).toInt(), 2);
        const auto repeated = parseObject(store.importHolidays(path));
        QVERIFY(repeated.value(QStringLiteral("ok")).toBool());
        QCOMPARE(repeated.value(QStringLiteral("imported")).toInt(), 0);
        QCOMPARE(repeated.value(QStringLiteral("skipped")).toInt(), 3);

        const QString emptyPath = directory.filePath(QStringLiteral("empty.ics"));
        QFile empty(emptyPath);
        QVERIFY(empty.open(QIODevice::WriteOnly));
        empty.write("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR\r\n");
        empty.close();
        const auto before = parseObject(store.snapshot());
        QVERIFY(!parseObject(store.importHolidays(emptyPath)).value(QStringLiteral("ok")).toBool());
        const auto after = parseObject(store.snapshot());
        QCOMPARE(after.value(QStringLiteral("revision")), before.value(QStringLiteral("revision")));
        QCOMPARE(after.value(QStringLiteral("events")), before.value(QStringLiteral("events")));
        QCOMPARE(after.value(QStringLiteral("todos")), before.value(QStringLiteral("todos")));
    }
    PimStore reloaded(directory.path());
    const auto snapshot = parseObject(reloaded.snapshot());
    QCOMPARE(snapshot.value(QStringLiteral("events")).toArray().size(), 2);
    QVERIFY(snapshot.value(QStringLiteral("todos")).toArray().isEmpty());
    for (const auto &entry : snapshot.value(QStringLiteral("events")).toArray()) {
        const auto event = entry.toObject();
        if (event.value(QStringLiteral("id")).toString() == personalUid) {
            QCOMPARE(event.value(QStringLiteral("title")).toString(), QStringLiteral("Personal event"));
            QCOMPARE(event.value(QStringLiteral("calendarId")).toString(), QStringLiteral("personal"));
        } else {
            QCOMPARE(event.value(QStringLiteral("calendarId")).toString(), QStringLiteral("holidays"));
            QVERIFY(event.value(QStringLiteral("allDay")).toBool());
            QCOMPARE(event.value(QStringLiteral("recurrence")).toString(), QStringLiteral("custom"));
            QCOMPARE(event.value(QStringLiteral("reminderMinutes")).toInt(), -1);
        }
    }
    const auto range = parseObject(reloaded.eventsForRange(
        QStringLiteral("2031-01-01"), QStringLiteral("2031-01-02")));
    QVERIFY(range.value(QStringLiteral("ok")).toBool());
    QCOMPARE(range.value(QStringLiteral("occurrences")).toArray().size(), 1);
}

void PimStoreTest::managedHolidayCalendars()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    auto writeCalendar = [&](const QString &path, const QByteArray &title) {
        QFile file(path);
        if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) return false;
        return file.write("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//KOS//Test//EN\r\n"
            "BEGIN:VEVENT\r\nUID:shared-uid\r\nDTSTAMP:20260101T000000Z\r\n"
            "DTSTART;VALUE=DATE:20300101\r\nDTEND;VALUE=DATE:20300102\r\n"
            "RRULE:FREQ=YEARLY\r\nSUMMARY:" + title + "\r\n"
            "BEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT15M\r\nDESCRIPTION:Alarm\r\nEND:VALARM\r\n"
            "END:VEVENT\r\nEND:VCALENDAR\r\n") > 0;
    };
    const auto firstPath = directory.filePath("first.ics");
    const auto secondPath = directory.filePath("second.ics");
    QVERIFY(writeCalendar(firstPath, "First"));
    QVERIFY(writeCalendar(secondPath, "Second"));
    QString firstId, secondId, personalId;
    {
        PimStore store(directory.filePath("pim"));
        QVERIFY(parseObject(store.snapshot()).value("holidayCalendars").toArray().isEmpty());
        QVERIFY(!parseObject(store.snapshot()).value("holidaySources").toArray().isEmpty());
        personalId = parseObject(store.createEvent(encode({{"title", "Personal"},
            {"start", "2030-01-01T10:00:00Z"}, {"end", "2030-01-01T11:00:00Z"}})))
            .value("item").toObject().value("id").toString();
        QVERIFY(!personalId.isEmpty());
        auto added = parseObject(store.addHolidayCalendar(encode({{"type", "file"},
            {"name", "First calendar"}, {"path", QUrl::fromLocalFile(firstPath).toString()}})));
        QVERIFY2(added.value("ok").toBool(), qPrintable(encode(added)));
        firstId = added.value("item").toObject().value("id").toString();
        QVERIFY(!parseObject(store.addHolidayCalendar(encode({{"type", "file"},
            {"name", "Duplicate"}, {"path", firstPath}}))).value("ok").toBool());
        added = parseObject(store.addHolidayCalendar(encode({{"type", "file"},
            {"name", "Second calendar"}, {"path", secondPath}})));
        QVERIFY(added.value("ok").toBool());
        secondId = added.value("item").toObject().value("id").toString();
        QVERIFY(firstId != secondId);
        auto snapshot = parseObject(store.snapshot());
        QCOMPARE(snapshot.value("events").toArray().size(), 3);
        QCOMPARE(snapshot.value("holidayCalendars").toArray().size(), 2);
        for (const auto &entry : snapshot.value("events").toArray()) {
            const auto event = entry.toObject();
            if (event.value("id").toString() == personalId) continue;
            QCOMPARE(event.value("reminderMinutes").toInt(), -1);
            QVERIFY(event.value("allDay").toBool());
            QVERIFY(event.value("id").toString().startsWith(event.value("calendarId").toString() + ':'));
            QVERIFY(!parseObject(store.removeEvent(event.value("id").toString())).value("ok").toBool());
            QVERIFY(!parseObject(store.updateEvent(event.value("id").toString(), encode({{"title", "Edit"}}))).value("ok").toBool());
        }
        QVERIFY(parseObject(store.setHolidayCalendarEnabled(firstId, false)).value("ok").toBool());
        QVERIFY(writeCalendar(firstPath, "Updated first"));
        QVERIFY(parseObject(store.refreshHolidayCalendar(firstId)).value("ok").toBool());
        snapshot = parseObject(store.snapshot());
        QCOMPARE(snapshot.value("events").toArray().size(), 3);
        QVERIFY(!snapshot.value("holidayCalendars").toArray().first().toObject().value("enabled").toBool());
        QFile broken(firstPath);
        QVERIFY(broken.open(QIODevice::WriteOnly | QIODevice::Truncate));
        broken.write("invalid calendar"); broken.close();
        QVERIFY(!parseObject(store.refreshHolidayCalendar(firstId)).value("ok").toBool());
        QCOMPARE(parseObject(store.snapshot()).value("events"), snapshot.value("events"));
        store.flush();
    }
    PimStore reloaded(directory.filePath("pim"));
    auto snapshot = parseObject(reloaded.snapshot());
    QCOMPARE(snapshot.value("holidayCalendars").toArray().size(), 2);
    QVERIFY(!snapshot.value("holidayCalendars").toArray().first().toObject().value("enabled").toBool());
    QCOMPARE(parseObject(reloaded.eventsForRange("2031-01-01", "2031-01-03")).value("occurrences").toArray().size(), 2);
    QVERIFY(parseObject(reloaded.removeHolidayCalendar(firstId)).value("ok").toBool());
    snapshot = parseObject(reloaded.snapshot());
    QCOMPARE(snapshot.value("events").toArray().size(), 2);
    QCOMPARE(snapshot.value("holidayCalendars").toArray().first().toObject().value("id").toString(), secondId);
    QVERIFY(parseObject(reloaded.removeHolidayCalendar(secondId)).value("ok").toBool());
    snapshot = parseObject(reloaded.snapshot());
    QCOMPARE(snapshot.value("events").toArray().size(), 1);
    QCOMPARE(snapshot.value("events").toArray().first().toObject().value("id").toString(), personalId);
}

QTEST_GUILESS_MAIN(PimStoreTest)

#include "PimStoreTest.moc"
