#include "cursoroverride.h"

#include <QCursor>
#include <QDebug>
#include <QGuiApplication>

CursorOverride::CursorOverride(QObject *parent)
    : QObject(parent)
{
}

CursorOverride::~CursorOverride()
{
    if (m_busy)
        QGuiApplication::restoreOverrideCursor();
}

void CursorOverride::setBusy(bool busy)
{
    if (m_busy == busy)
        return;

    m_busy = busy;
    if (m_busy)
        QGuiApplication::setOverrideCursor(QCursor(Qt::WaitCursor));
    else
        QGuiApplication::restoreOverrideCursor();
    qInfo().noquote() << "[CursorOverride] busy=" << (m_busy ? "true" : "false");
    Q_EMIT busyChanged();
}
