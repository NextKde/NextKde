#pragma once

#include <QObject>

class CursorOverride : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy WRITE setBusy NOTIFY busyChanged)

public:
    explicit CursorOverride(QObject *parent = nullptr);
    ~CursorOverride() override;

    bool busy() const { return m_busy; }
    void setBusy(bool busy);

Q_SIGNALS:
    void busyChanged();

private:
    bool m_busy = false;
};
