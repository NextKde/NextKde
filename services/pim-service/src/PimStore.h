#pragma once

#include <QObject>
#include <QDBusContext>
#include <QJsonObject>
#include <functional>

#include <memory>

class PimStore : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.nextkde.Kos.Pim1")

public:
    explicit PimStore(const QString &storageDirectory = {}, QObject *parent = nullptr);
    ~PimStore() override;

    // Persist pending state immediately, bypassing the write debounce.
    // Called by the destructor; tests use it to observe on-disk state
    // without spinning the event loop.
    void flush();

public slots:
    QString snapshot() const;
    QString eventsForRange(const QString &startDate, const QString &endDate) const;

    QString createEvent(const QString &payload);
    QString updateEvent(const QString &uid, const QString &payload);
    QString removeEvent(const QString &uid);

    QString createTodo(const QString &payload);
    QString updateTodo(const QString &uid, const QString &payload);
    QString removeTodo(const QString &uid);

    QString createCalendar(const QString &payload);
    QString updateCalendar(const QString &id, const QString &payload);
    QString removeCalendar(const QString &id);

    QString saveGroup(const QString &id, const QString &payload);
    QString removeGroup(const QString &id);
    QString saveSection(const QString &listId, const QString &id, const QString &payload);
    QString removeSection(const QString &listId, const QString &id);

    QString createList(const QString &payload);
    QString updateList(const QString &id, const QString &payload);
    QString removeList(const QString &id);

    QString importIcalendar(const QString &path, bool replaceExisting);
    QString importHolidays(const QString &path);
    QString addHolidayCalendar(const QString &payload);
    QString refreshHolidayCalendar(const QString &id);
    QString setHolidayCalendarEnabled(const QString &id, bool enabled);
    QString removeHolidayCalendar(const QString &id);
    QString exportIcalendar(const QString &path) const;

signals:
    void changed(qulonglong revision);

private slots:
    void scheduleNextReminder();
    void deliverDueReminders();
    void writeWidgetSnapshot();
    void notificationAction(uint id, const QString &action);
    void notificationClosed(uint id, uint reason);
    void notificationToken(uint id, const QString &token);

private:
    QString importCalendarFile(const QString &path, bool replaceExisting, bool holidaysOnly);
    QString applyHolidayCalendar(const QJsonObject &calendar, const QByteArray &data);
    QString loadHolidayFile(const QJsonObject &calendar);
    QString fetchHolidayCalendar(const QJsonObject &calendar);
    void downloadHolidayCalendar(const QJsonObject &calendar, bool existing,
                                 std::function<void(const QString &)> finished);
    void refreshHolidaySubscriptions();
    class Private;
    std::unique_ptr<Private> d;
};
