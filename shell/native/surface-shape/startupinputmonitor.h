#pragma once

#include <QObject>

// Observe before QQuickWindow hit testing; never take focus or consume input.
class StartupInputMonitor : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
public:
    explicit StartupInputMonitor(QObject *parent = nullptr);
    ~StartupInputMonitor() override;
    bool active() const { return m_active; }
    void setActive(bool active);
    Q_INVOKABLE void prepareFrame();

signals:
    void activeChanged();
    void activity();
    void framePrepared();

private slots:
    void globalActivity();

protected:
    bool eventFilter(QObject *object, QEvent *event) override;

private:
    bool m_active = false;
};
