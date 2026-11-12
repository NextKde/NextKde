#include "startupinputmonitor.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QEvent>
#include <QGuiApplication>
#include <QQuickWindow>
#include <memory>

StartupInputMonitor::StartupInputMonitor(QObject *parent)
    : QObject(parent)
{
    QDBusConnection::sessionBus().connect(QStringLiteral("org.kde.KWin"),
        QStringLiteral("/KOSContextMenuInput"),
        QStringLiteral("org.kos.KWin.ContextMenuInput"),
        QStringLiteral("startupInputActivity"), this, SLOT(globalActivity()));
}

StartupInputMonitor::~StartupInputMonitor()
{
    if (qApp)
        qApp->removeEventFilter(this);
}

void StartupInputMonitor::setActive(bool active)
{
    if (m_active == active)
        return;
    m_active = active;
    if (active)
        qApp->installEventFilter(this);
    else
        qApp->removeEventFilter(this);
    auto message = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"),
        QStringLiteral("/KOSContextMenuInput"),
        QStringLiteral("org.kos.KWin.ContextMenuInput"),
        QStringLiteral("watchStartupInput"));
    // Bounded even if the shell exits without disarming. No key identity leaves KWin.
    message.setArguments({active ? 3000 : 0});
    QDBusConnection::sessionBus().send(message);
    emit activeChanged();
}

void StartupInputMonitor::prepareFrame()
{
    // Configuration readiness precedes the first scene-graph render. Start the
    // clock only after exposed windows have submitted their initial frame.
    const auto remaining = std::make_shared<int>(0);
    for (auto *window : QGuiApplication::allWindows()) {
        auto *quickWindow = qobject_cast<QQuickWindow *>(window);
        if (!quickWindow || !quickWindow->isExposed())
            continue;
        ++*remaining;
        connect(quickWindow, &QQuickWindow::frameSwapped, this, [this, remaining] {
            if (--*remaining == 0)
                emit framePrepared();
        }, Qt::ConnectionType(Qt::QueuedConnection | Qt::SingleShotConnection));
        quickWindow->update();
    }
    if (*remaining == 0)
        QMetaObject::invokeMethod(this, &StartupInputMonitor::framePrepared, Qt::QueuedConnection);
}

void StartupInputMonitor::globalActivity()
{
    if (m_active)
        emit activity();
}

bool StartupInputMonitor::eventFilter(QObject *, QEvent *event)
{
    switch (event->type()) {
    case QEvent::KeyPress:
    case QEvent::KeyRelease:
    case QEvent::MouseButtonPress:
    case QEvent::MouseButtonRelease:
    case QEvent::MouseMove:
    case QEvent::Wheel:
    case QEvent::TouchBegin:
    case QEvent::TouchUpdate:
    case QEvent::TabletPress:
    case QEvent::TabletMove:
    case QEvent::NativeGesture:
        globalActivity();
        break;
    default:
        break;
    }
    return false;
}
