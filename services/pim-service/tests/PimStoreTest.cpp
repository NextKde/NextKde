#include "PimStore.h"

#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTemporaryDir>
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
    void eventPersistsAcrossRestart();
    void recurringEventExpandsForRange();
    void todoListsAndCompletionPersist();
    void recurringTodoCanUseDueDate();
    void invalidUpdatesDoNotMutateItems();
    void exportsAndImportsIcalendar();
};

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

    PimStore reloaded(directory.path());
    const QJsonArray todos = parseObject(reloaded.snapshot())
                                 .value(QStringLiteral("todos")).toArray();
    QCOMPARE(todos.size(), 1);
    QCOMPARE(todos.first().toObject().value(QStringLiteral("recurrence")).toString(),
             QStringLiteral("daily"));
    QCOMPARE(todos.first().toObject().value(QStringLiteral("reminderMinutes")).toInt(), 15);
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

QTEST_GUILESS_MAIN(PimStoreTest)

#include "PimStoreTest.moc"
