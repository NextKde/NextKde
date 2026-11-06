#pragma once

#include <QObject>
#include <QString>

// Desktop notifications are asynchronous; a missing notification service must
// never change the installation result or interrupt its owner process.
class TaskNotifications final : public QObject {
    Q_OBJECT
public:
    using QObject::QObject;
    Q_INVOKABLE void send(const QString& summary, const QString& body);
};
