#pragma once

#include <QObject>
#include <QPointer>
#include <QStringList>

class QQuickWindow;

namespace Kos::App {

class ApplicationActivation final : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.nextkde.Kos.Application1")

public:
    enum class AcquireResult {
        Primary,
        Forwarded,
        Error,
    };

    explicit ApplicationActivation(QString serviceName, QObject *parent = nullptr);

    // A secondary process forwards its arguments and compositor activation
    // token. The distinct error result prevents a failed hand-off from being
    // reported as a successful launch.
    AcquireResult acquireOrForward(const QStringList &arguments);
    void setWindow(QQuickWindow *window);

public slots:
    void Activate(const QStringList &arguments, const QString &activationToken,
                  const QString &workingDirectory);

signals:
    void activationRequested(const QStringList &arguments,
                             const QString &workingDirectory);

private:
    QString m_serviceName;
    QPointer<QQuickWindow> m_window;
};

} // namespace Kos::App
