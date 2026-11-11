#pragma once

#include <QByteArray>
#include <QDateTime>
#include <QFileSystemWatcher>
#include <QObject>
#include <QString>
#include <QTimer>

// Front end for the out-of-process update agent. All work (git, build, install,
// sudo) happens in tools/update/kos-update-agent.py; this class only reads its
// release record and status file, starts it, and opens its log. No privilege and
// no platform/IPC operation lives here.
class UpdateController final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString state READ state NOTIFY changed)
    Q_PROPERTY(QString stage READ stage NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(bool available READ available NOTIFY changed)
    Q_PROPERTY(bool upToDate READ upToDate NOTIFY changed)
    Q_PROPERTY(bool blocked READ blocked NOTIFY changed)
    Q_PROPERTY(bool failed READ failed NOTIFY changed)
    Q_PROPERTY(bool updated READ updated NOTIFY changed)
    Q_PROPERTY(bool needsRestart READ needsRestart NOTIFY changed)
    Q_PROPERTY(bool sourceAhead READ sourceAhead NOTIFY changed)
    Q_PROPERTY(QString currentVersion READ currentVersion NOTIFY changed)
    Q_PROPERTY(QString currentRevision READ currentRevision NOTIFY changed)
    Q_PROPERTY(QString currentTag READ currentTag NOTIFY changed)
    Q_PROPERTY(QString sourceVersion READ sourceVersion NOTIFY changed)
    Q_PROPERTY(int commitsBehind READ commitsBehind NOTIFY changed)
    Q_PROPERTY(QString branch READ branch NOTIFY changed)
    Q_PROPERTY(QString upstream READ upstream NOTIFY changed)
    Q_PROPERTY(QString channel READ channel WRITE setChannel NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(QString logPath READ logPath NOTIFY changed)
    Q_PROPERTY(QString sourceRoot READ sourceRoot NOTIFY changed)
    Q_PROPERTY(bool canCheck READ canCheck NOTIFY changed)
    Q_PROPERTY(bool canUpdate READ canUpdate NOTIFY changed)
public:
    // Mirrors status.json (schemaVersion 1). Missing keys keep these defaults, so
    // a partial or older file still maps to something sane. `valid` is false when
    // the bytes are not a JSON object, which tells readStatus to keep the last
    // good state instead of resetting it.
    struct Status {
        bool valid = false;
        QString state = QStringLiteral("idle");
        QString stage;
        QString checkedAt, startedAt, finishedAt;
        QString sourceRoot, branch, upstream;
        // Update channel the agent ran for; empty in records written before it.
        QString channel;
        QString installedVersion, installedRevision;
        QString sourceVersion, sourceRevision;
        QString logPath, error;
        int ahead = 0, behind = 0;
        bool dirty = false, canFastForward = false, needsRestart = false;
        bool sourceAhead = false;
    };
    static Status statusFromJson(const QByteArray &json);

    explicit UpdateController(QObject *parent = nullptr);

    QString state() const { return m_status.state; }
    QString stage() const { return m_status.stage; }
    bool busy() const { return m_active; }
    bool available() const { return m_status.state == QLatin1String("available"); }
    bool upToDate() const { return m_status.state == QLatin1String("up-to-date"); }
    bool blocked() const { return m_status.state == QLatin1String("blocked"); }
    bool failed() const { return m_status.state == QLatin1String("failed"); }
    bool updated() const { return m_status.state == QLatin1String("updated"); }
    bool needsRestart() const { return m_status.needsRestart && !m_restarted; }
    bool sourceAhead() const { return m_status.sourceAhead; }
    QString currentVersion() const { return m_currentVersion; }
    QString currentRevision() const { return m_currentRevision; }
    QString currentTag() const { return m_currentTag; }
    QString sourceVersion() const { return m_status.sourceVersion; }
    int commitsBehind() const { return m_status.behind; }
    QString branch() const { return m_status.branch; }
    QString upstream() const { return m_status.upstream; }
    QString channel() const { return m_channel; }
    void setChannel(const QString &channel);
    QString error() const;
    QString logPath() const;
    QString sourceRoot() const { return m_sourceRoot; }
    bool canCheck() const { return m_configError.isEmpty() && !m_active; }
    bool canUpdate() const { return canCheck() && available(); }

    Q_INVOKABLE void check();
    Q_INVOKABLE void update();
    Q_INVOKABLE void restart();
    Q_INVOKABLE void openLog();

signals:
    void changed();

private:
    void readRecord();
    void readStatus();
    void rewatch();
    void refresh();
    void launch(const QString &mode, int limitSeconds);
    void adopt(const Status &status);
    void fail(const QString &message);

    Status m_status;
    QFileSystemWatcher m_watcher;
    QTimer m_poll;
    QDateTime m_deadline;
    // UTC time of the click that started the current agent run; compared with the
    // status file's startedAt so a stale result is not taken for a fresh one.
    QDateTime m_launchedAt;
    QString m_stateDir, m_statusPath;
    QString m_sourceRoot, m_currentVersion, m_currentRevision, m_currentTag;
    // Agent flag of the run this window started: "--run" keeps "available" a
    // waypoint, since that run only ends at updated/failed/blocked/up-to-date.
    QString m_mode;
    QString m_configError, m_problem;
    // "stable" or "main". A saved choice outranks the release record's tag, which
    // moves with every install.
    QString m_channel = QStringLiteral("main");
    bool m_channelSaved = false;
    bool m_active = false, m_sawBusy = false;
    // The agent cannot know a restart happened; keep the acknowledgement here so
    // watching the state directory does not resurrect needsRestart=true.
    bool m_restarted = false;
};
