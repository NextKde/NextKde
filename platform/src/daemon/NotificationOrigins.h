#pragma once

#include <QObject>
#include <QJsonObject>
#include <QList>
#include <QProcess>
#include <functional>

namespace KosPlatform {

class NotificationOrigins : public QObject {
public:
    explicit NotificationOrigins(QObject *parent);
    ~NotificationOrigins() override;
    void resolve(const QJsonObject &notification, std::function<void(int)> callback);

private:
    struct Origin { QJsonObject notification; qint64 timestamp; };
    QProcess m_observer;
    QByteArray m_buffer;
    QList<Origin> m_origins;
    bool m_ready = false;
    int m_pending = 0;
    int take(const QJsonObject &notification);
};

} // namespace KosPlatform
