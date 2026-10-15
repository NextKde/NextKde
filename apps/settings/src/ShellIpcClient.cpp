#include "ShellIpcClient.h"

#include <QDir>
#include <QFileInfo>
#include <QProcess>
#include <QStandardPaths>
#include <QTimer>
#include <functional>
#include <utility>

ShellIpcClient::ShellIpcClient(QObject* parent)
    : ShellIpcClient(QStringLiteral("quickshell"), shellDirectories(), 5000, parent)
{
}

ShellIpcClient::ShellIpcClient(
    const QString& program, const QStringList& directories, int timeoutMs, QObject* parent)
    : QObject(parent)
    , m_program(program)
    , m_directories(directories)
    , m_timeoutMs(timeoutMs)
{
}

QString ShellIpcClient::installedShellDirectory()
{
    return QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
        + QStringLiteral("/quickshell/kos");
}

bool ShellIpcClient::isInstalledShellDirectory(const QString& shellPath)
{
    if (shellPath.isEmpty())
        return false;
    return QDir::cleanPath(shellPath) == QDir::cleanPath(installedShellDirectory());
}

QStringList ShellIpcClient::shellDirectories()
{
    QStringList directories;
    const QString configured = qEnvironmentVariable("KOS_SHELL_DIR");
    if (!configured.isEmpty())
        directories.append(configured);

    // Then the installed session: an end user only ever runs that one, and
    // it is the session this binary belongs to. Its directory is an
    // absolute path under the config location, so it does not depend on
    // the current working directory or on any inherited environment.
    directories.append(installedShellDirectory());

    // The compile-time source tree is a fallback for `qs -p <dir>`
    // sessions, NOT a first choice: it exists on any machine that built
    // this binary (a Nix store copy, or the checkout itself), so trying it
    // first would aim every ordinary launch at a Shell that is not
    // running. Both spellings of the literal are offered because
    // Quickshell matches instances by the path it was launched with, and
    // only comparably-spelled paths hit: the cleaned form handles the `..`
    // segments (apps/settings/../../shell), the canonical form handles a
    // checkout reached through a symlink (a synced or linked folder).
    const QString declared = QDir::cleanPath(QStringLiteral(SETTINGS_SHELL_DIR));
    const QString canonical = QFileInfo(declared).canonicalFilePath();
    for (const QString& source : { declared, canonical }) {
        if (source.isEmpty() || directories.contains(source))
            continue;
        if (QFileInfo::exists(QDir(source).filePath(QStringLiteral("shell.qml"))))
            directories.append(source);
    }

    directories.removeDuplicates();
    return directories;
}

QStringList ShellIpcClient::connectArgsFor(const QString& shellPath)
{
    if (shellPath == installedShellDirectory())
        return { QStringLiteral("-c"), QStringLiteral("kos") };
    return { QStringLiteral("--path"), shellPath };
}

bool ShellIpcClient::isIpcDiagnostic(const QString& reply)
{
    static const QStringList diagnostics = {
        QStringLiteral("Target not found."),
        QStringLiteral("Function not found."),
        QStringLiteral("Function required to send message."),
    };
    return diagnostics.contains(reply);
}

void ShellIpcClient::request(const QString& target, const QStringList& arguments,
    const QString& fallbackError, Completion completion)
{
    if (m_directories.isEmpty()) {
        // Keep even a locally rejected request asynchronous to match QProcess.
        QTimer::singleShot(0, this, [completion = std::move(completion), fallbackError] {
            completion({ { }, { }, fallbackError });
        });
        return;
    }
    const QString key = target + QLatin1Char('\x1f') + arguments.join(QLatin1Char('\x1e'));
    const auto it = m_inFlight.find(key);
    if (it != m_inFlight.end()) {
        it->completions.append(std::move(completion));
        return;
    }
    InFlight flight;
    flight.fallbackError = fallbackError;
    flight.completions.append(std::move(completion));
    m_inFlight.insert(key, std::move(flight));
    startAttempt(target, arguments, fallbackError, m_directories, 0, 0, {});
}

void ShellIpcClient::startAttempt(const QString& target, const QStringList& arguments,
    const QString& fallbackErrorIn, const QStringList& directories, int index, int attempt,
    Completion completion)
{
    // An empty completion marks the merged path: the flight (every waiting
    // completion for this key) lives in m_inFlight and travels through the
    // retry chain as a callable that fans the final result out to all of them.
    using Finish = std::function<void(const ShellIpcClient::Result&)>;
    Finish finish;
    QString fallbackError = fallbackErrorIn;
    if (completion) {
        finish = [completion = std::move(completion)](const ShellIpcClient::Result& result) {
            completion(result);
        };
    } else {
        const QString key = target + QLatin1Char('\x1f') + arguments.join(QLatin1Char('\x1e'));
        InFlight flight = m_inFlight.take(key);
        fallbackError = flight.fallbackError;
        finish = [this, key, completions = std::move(flight.completions)](
                     const ShellIpcClient::Result& result) mutable {
            m_inFlight.remove(key);
            for (const auto& c : completions)
                c(result);
        };
    }
    const QString shellPath = directories.at(index);
    QStringList command = connectArgsFor(shellPath);
    command << QStringLiteral("ipc") << QStringLiteral("call") << target;
    command.append(arguments);

    auto* process = new QProcess(this);
    auto* watchdog = new QTimer(process);
    watchdog->setSingleShot(true);
    watchdog->setInterval(m_timeoutMs);
    connect(process, &QProcess::started, watchdog, qOverload<>(&QTimer::start));
    connect(watchdog, &QTimer::timeout, process, [process] {
        process->setProperty("timedOut", true);
        process->kill();
    });
    // Both exit failure and FailedToStart use the same retry policy. Only
    // FailedToStart is handled in errorOccurred; crashes complete in finished.
    // std::function (not a mutable lambda): the two QProcess lambdas below
    // capture it by copy and must call it as const.
    std::function<void(const QString&)> advance
        = [this, target, arguments, fallbackError, directories, index, attempt, shellPath,
              finish](const QString& reason) mutable {
        const int maxAttempts = index == 0 ? 2 : 1;
        if (attempt + 1 < maxAttempts) {
            startAttempt(
                target, arguments, fallbackError, directories, index, attempt + 1, std::move(finish));
        } else if (index + 1 < directories.size()) {
            startAttempt(target, arguments, fallbackError, directories, index + 1, 0, std::move(finish));
        } else {
            finish({ { }, shellPath,
                QStringLiteral("%1（IPC：%2；Shell：%3）").arg(reason, target, shellPath) });
        }
    };
    connect(process, &QProcess::finished, this,
        [process, shellPath, fallbackError, finish, advance](
            int exitCode, QProcess::ExitStatus exitStatus) {
            const QString output = QString::fromUtf8(process->readAllStandardOutput()).trimmed();
            if (exitStatus == QProcess::NormalExit && exitCode == 0 && !isIpcDiagnostic(output)) {
                finish({ output, QDir::cleanPath(shellPath), { } });
            } else {
                QString reason = QString::fromUtf8(process->readAllStandardError()).trimmed();
                if (process->property("timedOut").toBool())
                    reason = QStringLiteral(
                        "The desktop environment did not respond (over 5 seconds)");
                else if ((exitStatus == QProcess::NormalExit && exitCode == 0) || reason.isEmpty())
                    reason = fallbackError;
                advance(reason);
            }
            process->deleteLater();
        });
    connect(
        process, &QProcess::errorOccurred, this, [process, advance](QProcess::ProcessError error) {
            if (error != QProcess::FailedToStart)
                return;
            advance(QStringLiteral("Could not start the Quickshell IPC"));
            process->deleteLater();
        });
    process->start(m_program, command);
}
