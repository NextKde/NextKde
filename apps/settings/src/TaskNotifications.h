#pragma once

#include <QObject>
#include <QString>

// Desktop notifications are asynchronous; a missing notification service must
// never change the installation result or interrupt its owner process.
class TaskNotifications final : public QObject {
    Q_OBJECT
public:
    explicit TaskNotifications(QObject* parent = nullptr);
    void sendUpdates(int count);
signals:
    void updatesDelivered();
private slots:
    void notificationAction(uint id, const QString& action);
public:
    Q_INVOKABLE void send(const QString& summary, const QString& body);
private:
    uint m_updateNotification = 0;
};
