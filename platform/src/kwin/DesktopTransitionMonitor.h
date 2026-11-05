#pragma once

#include <QDBusConnection>
#include <QElapsedTimer>
#include <QObject>
#include <QString>
#include <QTimer>

namespace KosPlatform {

// Only poll while a desktop change is in flight. Stage keeps painting the
// displayed desktop's cards and commits the new model after the effect settles.
class DesktopTransitionMonitor final : public QObject {
    Q_OBJECT
public:
    explicit DesktopTransitionMonitor(const QDBusConnection &bus, QObject *parent = nullptr);
    bool observeDesktop(const QString &desktopId);
    void reset();

signals:
    void settled(const QString &desktopId);

private:
    void poll();
    void finish();

    QDBusConnection m_bus;
    QString m_desktopId;
    QTimer m_pollTimer;
    QTimer m_deadline;
    QElapsedTimer m_elapsed;
    quint64 m_generation = 0;
    bool m_active = false;
};

} // namespace KosPlatform
