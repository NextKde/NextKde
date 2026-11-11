#include "UpdateController.h"

#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QSaveFile>
#include <QStandardPaths>
#include <QStringList>
#include <QUrl>

namespace {
constexpr int checkLimitSeconds = 5 * 60;
constexpr int updateLimitSeconds = 90 * 60;
constexpr int statusBytes = 256 * 1024;

// Same resolution order as the agent and tools/kosctl, so both sides open the
// same record without a shared library.
QString releaseRecordPath()
{
    const QString fromEnvironment = qEnvironmentVariable("KOS_RELEASE_RECORD");
    if (!fromEnvironment.isEmpty()) return fromEnvironment;
    QString prefix = qEnvironmentVariable("KOS_PREFIX");
    if (prefix.isEmpty()) prefix = QDir::homePath() + QStringLiteral("/.local");
    return prefix + QStringLiteral("/share/kos/release.json");
}

QString stateDirectory()
{
    QString home = qEnvironmentVariable("XDG_STATE_HOME");
    if (home.isEmpty()) home = QDir::homePath() + QStringLiteral("/.local/state");
    return home + QStringLiteral("/kos/update");
}

QString channelFilePath()
{
    QString config = qEnvironmentVariable("XDG_CONFIG_HOME");
    if (config.isEmpty()) config = QDir::homePath() + QStringLiteral("/.config");
    return config + QStringLiteral("/kos/update-channel");
}

bool isKnownChannel(const QString &channel)
{
    return channel == QLatin1String("stable") || channel == QLatin1String("main");
}
}

UpdateController::Status UpdateController::statusFromJson(const QByteArray &json)
{
    Status status;
    const QJsonDocument document = QJsonDocument::fromJson(json);
    if (!document.isObject()) return status;
    const QJsonObject object = document.object();
    status.valid = true;
    status.state = object.value(QStringLiteral("state")).toString();
    if (status.state.isEmpty()) status.state = QStringLiteral("idle");
    status.stage = object.value(QStringLiteral("stage")).toString();
    status.checkedAt = object.value(QStringLiteral("checkedAt")).toString();
    status.startedAt = object.value(QStringLiteral("startedAt")).toString();
    status.finishedAt = object.value(QStringLiteral("finishedAt")).toString();
    status.sourceRoot = object.value(QStringLiteral("sourceRoot")).toString();
    status.branch = object.value(QStringLiteral("branch")).toString();
    status.upstream = object.value(QStringLiteral("upstream")).toString();
    status.channel = object.value(QStringLiteral("channel")).toString();
    status.installedVersion = object.value(QStringLiteral("installedVersion")).toString();
    status.installedRevision = object.value(QStringLiteral("installedRevision")).toString();
    status.sourceVersion = object.value(QStringLiteral("sourceVersion")).toString();
    status.sourceRevision = object.value(QStringLiteral("sourceRevision")).toString();
    status.logPath = object.value(QStringLiteral("logPath")).toString();
    status.error = object.value(QStringLiteral("error")).toString();
    status.ahead = object.value(QStringLiteral("ahead")).toInt();
    status.behind = object.value(QStringLiteral("behind")).toInt();
    status.dirty = object.value(QStringLiteral("dirty")).toBool();
    status.canFastForward = object.value(QStringLiteral("canFastForward")).toBool();
    status.needsRestart = object.value(QStringLiteral("needsRestart")).toBool();
    status.sourceAhead = object.value(QStringLiteral("sourceAhead")).toBool();
    return status;
}

UpdateController::UpdateController(QObject *parent)
    : QObject(parent)
{
    m_stateDir = stateDirectory();
    m_statusPath = m_stateDir + QStringLiteral("/status.json");
    m_poll.setInterval(1000);
    connect(&m_poll, &QTimer::timeout, this, &UpdateController::refresh);
    const auto watchedChange = [this] {
        refresh();
        rewatch();
    };
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, watchedChange);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, watchedChange);
    QFile channelFile(channelFilePath());
    if (channelFile.open(QIODevice::ReadOnly) && channelFile.size() <= 32) {
        const QString saved = QString::fromUtf8(channelFile.readAll()).trimmed();
        if (isKnownChannel(saved)) {
            m_channel = saved;
            m_channelSaved = true;
        }
    }
    readRecord();
    readStatus();
    rewatch();
}

QString UpdateController::error() const
{
    if (!m_problem.isEmpty()) return m_problem;
    if (!m_status.error.isEmpty()) return m_status.error;
    return m_configError;
}

QString UpdateController::logPath() const
{
    // Only expose a path once the agent has written the file: a path that opens
    // nothing would show a working-looking button that does nothing.
    if (!m_status.logPath.isEmpty() && QFileInfo::exists(m_status.logPath))
        return m_status.logPath;
    const QString fallback = m_stateDir + QStringLiteral("/agent.log");
    return QFileInfo::exists(fallback) ? fallback : QString();
}

void UpdateController::setChannel(const QString &channel)
{
    if (m_active || !isKnownChannel(channel) || channel == m_channel) return;
    m_channel = channel;
    m_channelSaved = true;
    const QString path = channelFilePath();
    QDir().mkpath(QFileInfo(path).absolutePath());
    QSaveFile file(path);
    if (file.open(QIODevice::WriteOnly)) {
        file.write(m_channel.toUtf8() + '\n');
        file.commit();
    }
    // A result from the previous channel no longer applies; a finished update
    // still needs its restart.
    const bool needsRestart = m_status.needsRestart;
    m_status = Status();
    m_status.needsRestart = needsRestart;
    m_problem.clear();
    emit changed();
}

void UpdateController::check()
{
    launch(QStringLiteral("--check"), checkLimitSeconds);
}

void UpdateController::update()
{
    if (canUpdate()) launch(QStringLiteral("--run"), updateLimitSeconds);
}

void UpdateController::restart()
{
    if (m_sourceRoot.isEmpty()) return;
    const QString kosctl = m_sourceRoot + QStringLiteral("/tools/kosctl");
    if (!QProcess::startDetached(kosctl, {QStringLiteral("start")}, m_sourceRoot)) {
        m_problem = QStringLiteral("Could not start kosctl to restart KOS.");
        emit changed();
        return;
    }
    m_restarted = true;
    emit changed();
}

void UpdateController::openLog()
{
    const QString path = logPath();
    if (path.isEmpty() || !QFileInfo::exists(path)) return;
    QDesktopServices::openUrl(QUrl::fromLocalFile(path));
}

void UpdateController::readRecord()
{
    m_configError.clear();
    // A missing record is normal while kosctl install rewrites it; keep the last
    // known paths instead of blanking them for that second.
    QFile file(releaseRecordPath());
    if (file.open(QIODevice::ReadOnly) && file.size() <= statusBytes) {
        const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
        if (document.isObject()) {
            const QJsonObject record = document.object();
            m_currentVersion = record.value(QStringLiteral("version")).toString();
            m_sourceRoot = record.value(QStringLiteral("sourceRoot")).toString();
            if (!m_channelSaved) {
                const QString tag = record.value(QStringLiteral("tag")).toString();
                m_channel = tag.isEmpty() ? QStringLiteral("main")
                                          : QStringLiteral("stable");
            }
        }
    }
    // Installs made before kosctl recorded sourceRoot land here: there is nothing
    // safe to update until the user runs install once from the checkout.
    if (m_sourceRoot.isEmpty()) {
        m_configError = QStringLiteral("This KOS install does not record its source "
                                       "checkout. Run ./tools/kosctl install once, then "
                                       "reopen Settings.");
    } else if (!QFileInfo(m_sourceRoot).isDir()) {
        m_configError = QStringLiteral("The recorded source checkout (%1) is gone. "
                                       "Run ./tools/kosctl install from a valid checkout.")
                            .arg(m_sourceRoot);
    }
}

void UpdateController::readStatus()
{
    QFile file(m_statusPath);
    if (!file.open(QIODevice::ReadOnly) || file.size() > statusBytes) return;
    const Status status = statusFromJson(file.readAll());
    if (!status.valid) return;
    // A result for another channel does not describe this one: stay idle until
    // the agent writes for the selected channel. Old files without the key load.
    if (!status.channel.isEmpty() && !m_channel.isEmpty() && status.channel != m_channel)
        return;
    m_status = status;
    if (m_status.state != QLatin1String("updated")) m_restarted = false;
    const bool running = m_status.state == QLatin1String("checking")
        || m_status.state == QLatin1String("updating");
    if (running) {
        // Adopt a run started by another Settings window or by the previous one.
        m_sawBusy = true;
        if (!m_active) adopt(m_status);
        return;
    }
    // Before the agent's first write the file still holds the previous result.
    // Ignore it unless it was written for this run: a fast check can finish
    // before the poll ever sees "checking", and its startedAt (or, failing that,
    // a newer mtime) is what tells the two apart.
    if (m_active) {
        const QDateTime started
            = QDateTime::fromString(m_status.startedAt, Qt::ISODate).toUTC();
        bool fresh = m_sawBusy;
        if (!fresh && m_launchedAt.isValid()) {
            fresh = started.isValid()
                ? started >= m_launchedAt
                : QFileInfo(m_statusPath).lastModified().toUTC() >= m_launchedAt;
        }
        // A run repeats the check before it merges, so "available" is only a
        // waypoint there: the install has not started yet and the agent may
        // still be waiting for the sudo prompt.
        const bool waypoint = m_mode == QLatin1String("--run")
            && m_status.state == QLatin1String("available");
        if (fresh && !waypoint) {
            m_active = false;
            m_poll.stop();
            m_sawBusy = false;
        }
    }
}

void UpdateController::rewatch()
{
    const QStringList wanted{m_statusPath, m_stateDir};
    for (const QString &path : wanted) {
        if (!QFileInfo::exists(path) || m_watcher.files().contains(path)
            || m_watcher.directories().contains(path))
            continue;
        m_watcher.addPath(path);
    }
}

void UpdateController::refresh()
{
    readRecord();
    readStatus();
    if (m_active && m_deadline.isValid() && QDateTime::currentDateTime() > m_deadline) {
        fail(QStringLiteral("The update agent stopped reporting progress. See the log, "
                            "then check again."));
        return;
    }
    emit changed();
}

void UpdateController::launch(const QString &mode, int limitSeconds)
{
    if (m_active) return;
    readRecord();
    if (!m_configError.isEmpty()) {
        emit changed();
        return;
    }
    const QString python = QStandardPaths::findExecutable(QStringLiteral("python3"));
    const QString agent = m_sourceRoot + QStringLiteral("/tools/update/kos-update-agent.py");
    m_problem.clear();
    if (python.isEmpty()) {
        fail(QStringLiteral("python3 is required to run the update agent."));
        return;
    }
    if (!QFileInfo::exists(agent)) {
        fail(QStringLiteral("The update agent is missing from this checkout. Run "
                            "./tools/kosctl install."));
        return;
    }
    m_deadline = QDateTime::currentDateTime().addSecs(limitSeconds);
    m_mode = mode;
    m_launchedAt = QDateTime::currentDateTimeUtc();
    m_sawBusy = false;
    m_restarted = false;
    m_active = true;
    m_poll.start();
    if (QProcess::startDetached(python, {agent, mode, QStringLiteral("--channel"), m_channel},
                                m_sourceRoot))
        emit changed();
    else fail(QStringLiteral("Could not start the update agent."));
}

void UpdateController::adopt(const Status &status)
{
    m_active = true;
    // Adopted run: no click of ours to compare against, but its busy state was
    // already seen, so readStatus clears it on the first terminal write.
    m_launchedAt = QDateTime();
    m_mode = status.state == QLatin1String("checking") ? QStringLiteral("--check")
                                                       : QStringLiteral("--run");
    const int limit = status.state == QLatin1String("checking") ? checkLimitSeconds
                                                                : updateLimitSeconds;
    const QDateTime started = QDateTime::fromString(status.startedAt, Qt::ISODate);
    m_deadline = (started.isValid() ? started : QDateTime::currentDateTime()).addSecs(limit);
    m_poll.start();
}

void UpdateController::fail(const QString &message)
{
    m_active = false;
    m_poll.stop();
    m_problem = message;
    m_status.state = QStringLiteral("failed");
    emit changed();
}
