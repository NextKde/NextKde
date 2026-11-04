#include "DesktopTransitionMonitor.h"

#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>
#include <QStringList>

namespace KosPlatform {

DesktopTransitionMonitor::DesktopTransitionMonitor(const QDBusConnection &bus, QObject *parent)
    : QObject(parent), m_bus(bus)
{
    m_pollTimer.setSingleShot(true);
    m_pollTimer.setInterval(32);
    connect(&m_pollTimer, &QTimer::timeout, this, &DesktopTransitionMonitor::poll);
    m_deadline.setSingleShot(true);
    m_deadline.setInterval(5000);
    connect(&m_deadline, &QTimer::timeout, this, &DesktopTransitionMonitor::finish);
}

bool DesktopTransitionMonitor::observeDesktop(const QString &desktopId)
{
    if (desktopId.isEmpty()) {
        reset();
        return false;
    }
    if (desktopId == m_desktopId)
        return m_active;
    const bool initial = m_desktopId.isEmpty();
    m_desktopId = desktopId;
    if (initial)
        return false;
    ++m_generation;
    m_active = true;
    m_elapsed.restart();
    m_deadline.start();
    m_pollTimer.start();
    return true;
}

void DesktopTransitionMonitor::poll()
{
    const quint64 generation = m_generation;
    auto request = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"),
        QStringLiteral("/Effects"), QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("Get"));
    request << QStringLiteral("org.kde.kwin.Effects") << QStringLiteral("activeEffects");
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(request, 250), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, generation, watcher] {
        const QDBusPendingReply<QDBusVariant> reply = *watcher;
        watcher->deleteLater();
        if (generation != m_generation || !m_active)
            return;
        if (reply.isError()) {
            finish(); // Missing/disconnected KWin must never leave Stage invisible.
            return;
        }
        const QStringList effects = reply.value().variant().toStringList();
        const bool switching = effects.contains(QStringLiteral("slide"))
            || effects.contains(QStringLiteral("cubeslide"))
            || effects.contains(QStringLiteral("fadedesktop"));
        // A desktop notification can precede effect activation by a frame.
        // With animations disabled, release after this short startup grace.
        if (!switching && m_elapsed.elapsed() >= 80)
            finish();
        else
            m_pollTimer.start();
    });
}

void DesktopTransitionMonitor::finish()
{
    m_pollTimer.stop();
    m_deadline.stop();
    ++m_generation;
    if (!m_active)
        return;
    m_active = false;
    emit settled(m_desktopId);
}

void DesktopTransitionMonitor::reset()
{
    finish();
    m_desktopId.clear();
}

} // namespace KosPlatform
