#include "ApplicationActivation.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusError>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDebug>
#include <QDir>
#include <QQuickWindow>

#include <utility>

#if defined(KOS_HAVE_KWINDOWSYSTEM)
#include <KWindowSystem>
#endif

namespace Kos::App {

namespace {
constexpr auto objectPath = "/org/nextkde/Kos/Application";
constexpr auto interfaceName = "org.nextkde.Kos.Application1";
}

ApplicationActivation::ApplicationActivation(QString serviceName, QObject *parent)
    : QObject(parent)
    , m_serviceName(std::move(serviceName))
{
}

ApplicationActivation::AcquireResult ApplicationActivation::acquireOrForward(
    const QStringList &arguments)
{
    if (m_serviceName.isEmpty())
        return AcquireResult::Primary;

    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        qWarning() << "Session D-Bus is unavailable; single-instance activation is disabled";
        return AcquireResult::Primary;
    }

    if (bus.registerService(m_serviceName)) {
        if (!bus.registerObject(QString::fromLatin1(objectPath), this,
                                QDBusConnection::ExportAllSlots
                                    | QDBusConnection::ExportAllSignals)) {
            qWarning() << "Unable to export application activation object:"
                       << bus.lastError().message();
            bus.unregisterService(m_serviceName);
            return AcquireResult::Error;
        }
        return AcquireResult::Primary;
    }

    QDBusInterface primary(m_serviceName, QString::fromLatin1(objectPath),
                           QString::fromLatin1(interfaceName), bus);
    if (!primary.isValid()) {
        qWarning() << "Application service is owned but cannot be contacted:"
                   << bus.lastError().message();
        return AcquireResult::Error;
    }

    const QString activationToken = QString::fromLocal8Bit(
        qgetenv("XDG_ACTIVATION_TOKEN"));
    const QDBusReply<void> reply = primary.call(
        QStringLiteral("Activate"), arguments, activationToken,
        QDir::currentPath());
    if (!reply.isValid()) {
        qWarning() << "Unable to activate the existing application instance:"
                   << reply.error().message();
        return AcquireResult::Error;
    }
    return AcquireResult::Forwarded;
}

void ApplicationActivation::setWindow(QQuickWindow *window)
{
    m_window = window;
}

void ApplicationActivation::Activate(const QStringList &arguments,
                                     const QString &activationToken,
                                     const QString &workingDirectory)
{
    if (m_window) {
#if defined(KOS_HAVE_KWINDOWSYSTEM)
        if (!activationToken.isEmpty())
            KWindowSystem::setCurrentXdgActivationToken(activationToken);
#else
        Q_UNUSED(activationToken)
#endif
        m_window->show();
        m_window->raise();
#if defined(KOS_HAVE_KWINDOWSYSTEM)
        KWindowSystem::activateWindow(m_window);
#else
        m_window->requestActivate();
#endif
    }
    emit activationRequested(arguments, workingDirectory);
}

} // namespace Kos::App
