#include "NotificationOrigins.h"

#include <QDateTime>
#include <QFile>
#include <QJsonDocument>
#include <QStandardPaths>
#include <QTimer>

namespace KosPlatform {

NotificationOrigins::NotificationOrigins(QObject *parent) : QObject(parent)
{
    QFile script(QStringLiteral(":/kos/src/daemon/notification-origin.py"));
    if (!script.open(QIODevice::ReadOnly))
        return;
    QString python = qEnvironmentVariable("KOS_NOTIFICATION_PYTHON");
    if (python.isEmpty())
        python = QFile::exists(QStringLiteral("/usr/bin/python3"))
            ? QStringLiteral("/usr/bin/python3") : QStandardPaths::findExecutable(QStringLiteral("python3"));
    if (python.isEmpty())
        return;
    // Metadata lives only in this bounded in-memory cache. The helper never
    // owns Notifications and never changes or acknowledges the messages.
    connect(&m_observer, &QProcess::readyReadStandardOutput, this, [this] {
        m_buffer += m_observer.readAllStandardOutput();
        if (m_buffer.size() > 512 * 1024) {
            m_buffer.clear();
            return;
        }
        qsizetype end;
        while ((end = m_buffer.indexOf('\n')) >= 0) {
            const auto value = QJsonDocument::fromJson(m_buffer.left(end)).object();
            m_buffer.remove(0, end + 1);
            if (value.value(QStringLiteral("ready")).toBool()) {
                m_ready = true;
            } else if (value.value(QStringLiteral("pid")).toInt() > 0) {
                m_origins.append({value, QDateTime::currentMSecsSinceEpoch()});
                while (m_origins.size() > 64)
                    m_origins.removeFirst();
            }
        }
    });
    connect(&m_observer, &QProcess::readyReadStandardError, this, [this] {
        m_observer.readAllStandardError(); // Optional helper; never log message payloads.
    });
    connect(&m_observer, &QProcess::finished, this, [this] { m_ready = false; });
    auto *expiryTimer = new QTimer(this);
    expiryTimer->setInterval(500);
    connect(expiryTimer, &QTimer::timeout, this, [this] {
        const qint64 now = QDateTime::currentMSecsSinceEpoch();
        while (!m_origins.isEmpty() && now - m_origins.first().timestamp >= 3000)
            m_origins.removeFirst();
    });
    expiryTimer->start();
    m_observer.start(python, {QStringLiteral("-u"), QStringLiteral("-c"), QString::fromUtf8(script.readAll())});
}

NotificationOrigins::~NotificationOrigins()
{
    m_observer.terminate();
    if (!m_observer.waitForFinished(500)) {
        m_observer.kill();
        m_observer.waitForFinished(500);
    }
}

int NotificationOrigins::take(const QJsonObject &notification)
{
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    while (!m_origins.isEmpty() && now - m_origins.first().timestamp > 3000)
        m_origins.removeFirst();
    for (qsizetype i = 0; i < m_origins.size(); ++i) {
        const auto &origin = m_origins.at(i).notification;
        if (origin.value(QStringLiteral("appName")) == notification.value(QStringLiteral("appName"))
            && origin.value(QStringLiteral("summary")) == notification.value(QStringLiteral("summary"))
            && origin.value(QStringLiteral("body")) == notification.value(QStringLiteral("body"))) {
            const int pid = origin.value(QStringLiteral("pid")).toInt();
            m_origins.removeAt(i);
            return pid;
        }
    }
    return 0;
}

void NotificationOrigins::resolve(const QJsonObject &notification, std::function<void(int)> callback)
{
    const int pid = take(notification);
    if (pid || !m_ready || m_pending >= 64) {
        callback(pid);
        return;
    }
    // The observer and UI consume the same bus call on separate connections.
    // Allow either arrival order, without blocking the daemon or a banner.
    auto *timer = new QTimer(this);
    ++m_pending;
    timer->setInterval(20);
    const qint64 deadline = QDateTime::currentMSecsSinceEpoch() + 200;
    connect(timer, &QTimer::timeout, this, [this, timer, notification, callback, deadline] {
        const int found = take(notification);
        if (found || QDateTime::currentMSecsSinceEpoch() >= deadline) {
            timer->stop();
            timer->deleteLater();
            --m_pending;
            callback(found);
        }
    });
    timer->start();
}

} // namespace KosPlatform
