#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <qqmlintegration.h>

class QDBusPendingCallWatcher;
class QDBusServiceWatcher;

class PimClient : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool ready READ ready NOTIFY snapshotChanged)
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(bool writable READ writable NOTIFY snapshotChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)
    Q_PROPERTY(qulonglong revision READ revision NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantList calendars READ calendars NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantList groups READ groups NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantList lists READ lists NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantList holidayCalendars READ holidayCalendars NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantList holidaySources READ holidaySources NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantList events READ events NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantList occurrences READ occurrences NOTIFY occurrencesChanged)
    Q_PROPERTY(QVariantList todoOccurrences READ todoOccurrences NOTIFY occurrencesChanged)
    Q_PROPERTY(QVariantList todos READ todos NOTIFY snapshotChanged)

public:
    explicit PimClient(QObject *parent = nullptr);

    bool ready() const;
    bool connected() const;
    bool busy() const;
    bool writable() const;
    QString errorMessage() const;
    qulonglong revision() const;
    QVariantList calendars() const;
    QVariantList groups() const;
    QVariantList lists() const;
    QVariantList holidayCalendars() const;
    QVariantList holidaySources() const;
    QVariantList events() const;
    QVariantList occurrences() const;
    QVariantList todoOccurrences() const;
    QVariantList todos() const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void setEventRange(const QString &startDate, const QString &endDate);

    Q_INVOKABLE void createEvent(const QVariantMap &event);
    Q_INVOKABLE void updateEvent(const QString &uid, const QVariantMap &event);
    Q_INVOKABLE void removeEvent(const QString &uid);

    Q_INVOKABLE void createTodo(const QVariantMap &todo);
    Q_INVOKABLE void updateTodo(const QString &uid, const QVariantMap &todo);
    Q_INVOKABLE void removeTodo(const QString &uid);

    Q_INVOKABLE void createCalendar(const QVariantMap &calendar);
    Q_INVOKABLE void updateCalendar(const QString &id, const QVariantMap &calendar);
    Q_INVOKABLE void removeCalendar(const QString &id);

    Q_INVOKABLE void saveGroup(const QString &id, const QVariantMap &values);
    Q_INVOKABLE void removeGroup(const QString &id);
    Q_INVOKABLE void saveSection(const QString &listId, const QString &id, const QVariantMap &values);
    Q_INVOKABLE void removeSection(const QString &listId, const QString &id);
    Q_INVOKABLE void createList(const QVariantMap &list);
    Q_INVOKABLE void updateList(const QString &id, const QVariantMap &list);
    Q_INVOKABLE void removeList(const QString &id);

    Q_INVOKABLE void importIcalendar(const QString &path, bool replaceExisting = false);
    Q_INVOKABLE void importHolidays(const QString &path);
    Q_INVOKABLE void addHolidayCalendar(const QVariantMap &calendar);
    Q_INVOKABLE void refreshHolidayCalendar(const QString &id);
    Q_INVOKABLE void setHolidayCalendarEnabled(const QString &id, bool enabled);
    Q_INVOKABLE void removeHolidayCalendar(const QString &id);
    Q_INVOKABLE void exportIcalendar(const QString &path);

signals:
    void snapshotChanged();
    void occurrencesChanged();
    void connectedChanged();
    void busyChanged();
    void errorMessageChanged();
    void operationSucceeded(const QString &operation, const QString &itemId);
    void operationFailed(const QString &operation, const QString &message);

private slots:
    void onServiceChanged(const QString &service, const QString &oldOwner,
                          const QString &newOwner);
    void onRemoteChanged(qulonglong revision);

private:
    enum class ReplyKind {
        Snapshot,
        Range,
        Mutation,
    };

    void invoke(const QString &method, const QVariantList &arguments, ReplyKind kind,
                const QString &operation = {}, const QString &itemId = {});
    void handleReply(QDBusPendingCallWatcher *watcher, ReplyKind kind,
                     const QString &operation, const QString &itemId);
    void requestRange();
    void setConnected(bool connected);
    void setErrorMessage(const QString &message);
    void changePending(int delta);

    QDBusServiceWatcher *m_serviceWatcher = nullptr;
    bool m_ready = false;
    bool m_connected = false;
    bool m_writable = false;
    int m_pendingCalls = 0;
    QString m_errorMessage;
    QString m_rangeStart;
    QString m_rangeEnd;
    qulonglong m_revision = 0;
    quint64 m_serviceGeneration = 0;
    quint64 m_snapshotSerial = 0;
    quint64 m_rangeSerial = 0;
    QVariantList m_groups;
    QVariantList m_lists;
    QVariantList m_calendars;
    QVariantList m_holidayCalendars;
    QVariantList m_holidaySources;
    QVariantList m_events;
    QVariantList m_occurrences;
    QVariantList m_todoOccurrences;
    QVariantList m_todos;
};
