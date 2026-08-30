#pragma once

#include <QObject>

#include <memory>

class PimStore : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.nextkde.Kos.Pim1")

public:
    explicit PimStore(const QString &storageDirectory = {}, QObject *parent = nullptr);
    ~PimStore() override;

public slots:
    QString snapshot() const;
    QString eventsForRange(const QString &startDate, const QString &endDate) const;

    QString createEvent(const QString &payload);
    QString updateEvent(const QString &uid, const QString &payload);
    QString removeEvent(const QString &uid);

    QString createTodo(const QString &payload);
    QString updateTodo(const QString &uid, const QString &payload);
    QString removeTodo(const QString &uid);

    QString createList(const QString &payload);
    QString updateList(const QString &id, const QString &payload);
    QString removeList(const QString &id);

    QString importIcalendar(const QString &path, bool replaceExisting);
    QString exportIcalendar(const QString &path) const;

signals:
    void changed(qulonglong revision);

private:
    class Private;
    std::unique_ptr<Private> d;
};
