#include "PlatformProcess.h"

#include <QByteArray>
#include <QProcess>
#include <QPointer>
#include <QTimer>

namespace KosPlatform::Detail {

QJsonObject parseOutput(const QByteArray &output, int exitCode)
{
    return QJsonObject{{QStringLiteral("exitCode"), exitCode},
                       {QStringLiteral("stdout"), QString::fromUtf8(output)}};
}

// A wedged helper (bluetoothctl waiting on a dead BlueZ, cliphist on a hung
// store, nmcli on a suspended NetworkManager) used to pile up one process
// per poll forever. Every short-lived query process gets a kill watchdog;
// interactive tools opt out explicitly at the call site.
void armProcessWatchdog(QProcess *process, int timeoutMs)
{
    if (timeoutMs <= 0)
        return;
    const QPointer<QProcess> guard(process);
    QTimer::singleShot(timeoutMs, process, [guard]() {
        if (guard && guard->state() != QProcess::NotRunning)
            guard->kill();
    });
}

} // namespace KosPlatform::Detail
