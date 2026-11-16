#include "PlatformServer.h"
#include "PlatformProcess.h"

#include <QByteArray>
#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonValue>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTimer>

namespace KosPlatform {
using namespace Detail;

namespace {

constexpr int kAudioCacheTtlMs = 30000;

QJsonObject parseAudio(const QByteArray &output, int exitCode)
{
    const QString text = QString::fromUtf8(output);
    const QRegularExpression match(QStringLiteral("Volume:\\s*([0-9.]+)"));
    const auto m = match.match(text);
    if (exitCode != 0 || !m.hasMatch())
        return QJsonObject{{QStringLiteral("available"), false}};
    const double value = qBound(0.0, m.captured(1).toDouble(), 1.5);
    return QJsonObject{{QStringLiteral("available"), true},
                       {QStringLiteral("percent"), qRound(value * 100.0)},
                       {QStringLiteral("muted"), text.contains(QStringLiteral("[MUTED]"))}};
}

QJsonObject parseAudioApplications(const QByteArray &output, int exitCode)
{
    if (exitCode != 0)
        return QJsonObject{{QStringLiteral("available"), false}};

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(output, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isArray())
        return QJsonObject{{QStringLiteral("available"), false}};

    QJsonArray applications;
    for (const QJsonValue &value : document.array()) {
        const QJsonObject stream = value.toObject();
        const QJsonObject properties = stream.value(QStringLiteral("properties")).toObject();
        QString name = properties.value(QStringLiteral("application.name")).toString().trimmed();
        if (name.isEmpty())
            name = properties.value(QStringLiteral("media.name")).toString().trimmed();
        if (name.isEmpty())
            name = QStringLiteral("音频应用");

        const QJsonObject volume = stream.value(QStringLiteral("volume")).toObject();
        double volumePercent = 0.0;
        for (auto it = volume.constBegin(); it != volume.constEnd(); ++it) {
            const QJsonObject channel = it.value().toObject();
            const QString percent = channel.value(QStringLiteral("value_percent")).toString();
            if (!percent.isEmpty()) {
                volumePercent = percent.left(percent.indexOf(QLatin1Char('%'))).toDouble();
                break;
            }
        }

        applications.append(QJsonObject{
            {QStringLiteral("id"), stream.value(QStringLiteral("index")).toInt()},
            {QStringLiteral("name"), name},
            {QStringLiteral("percent"), qBound(0, qRound(volumePercent), 150)},
            {QStringLiteral("muted"), stream.value(QStringLiteral("mute")).toBool()},
            {QStringLiteral("icon"), properties.value(QStringLiteral("application.icon-name")).toString()}
        });
    }
    return QJsonObject{{QStringLiteral("available"), true},
                       {QStringLiteral("applications"), applications}};
}

} // namespace

// One resident `pactl subscribe` replaces the per-poll wpctl/pactl spawns:
// every event line marks the audio reply cache stale, so the next poll
// re-reads only when something actually changed.
void PlatformServer::startAudioEventWatcher(const QString &pactl)
{
    if (m_audioEventWatcher)
        return;
    auto *process = new QProcess(this);
    m_audioEventWatcher = process;
    process->setProgram(pactl);
    process->setArguments({QStringLiteral("subscribe")});
    // Resident watchers must not retain an unread stderr buffer indefinitely.
    process->setProcessChannelMode(QProcess::ForwardedErrorChannel);
    process->setProperty("startedAt", QDateTime::currentMSecsSinceEpoch());
    connect(process, &QProcess::readyReadStandardOutput, this, [this, process]() {
        if (!process->readAllStandardOutput().isEmpty())
            invalidateReplies(QStringLiteral("audio."));
    });
    const auto restart = [this, process]() {
        // A subscribe that exits immediately after every start is a
        // permanently broken helper, not a dropped connection -- back off to
        // a slow retry instead of fork-spinning.
        const qint64 ran = QDateTime::currentMSecsSinceEpoch()
            - process->property("startedAt").toLongLong();
        QTimer::singleShot(ran < 10000 ? 60000 : 2000, this, [this, process]() {
            if (process != m_audioEventWatcher
                || process->state() != QProcess::NotRunning)
                return;
            process->setProperty("startedAt", QDateTime::currentMSecsSinceEpoch());
            process->start();
        });
    };
    connect(process, &QProcess::finished, this, restart);
    // FailedToStart does not always emit finished(); route it through the
    // same backoff restart so the watcher cannot silently die.
    connect(process, &QProcess::errorOccurred, this, restart);
    process->start();
}

void PlatformServer::runAudioOutputs(QLocalSocket *socket, const QJsonObject &request)
{
    // Cached like every other audio read: the resident `pactl subscribe`
    // watcher invalidates audio.* on each event, so the control centre's
    // periodic poll is a cache hit unless a device actually changed.
    if (serveCachedReply(socket, request, QStringLiteral("audio.outputs"))
        || queueIfInFlight(QStringLiteral("audio.outputs"), socket, request))
        return;
    const QString pactl = QStandardPaths::findExecutable(QStringLiteral("pactl"));
    if (pactl.isEmpty()) {
        completeInFlight(QStringLiteral("audio.outputs"), false, {},
                         QStringLiteral("audio-unavailable"),
                         QStringLiteral("音频设备服务不可用（需要 pactl）"), true, kAudioCacheTtlMs);
        return;
    }
    auto *process = new QProcess(this);
    process->setProgram(pactl);
    process->setArguments({QStringLiteral("--format=json"), QStringLiteral("info")});
    connect(process, &QProcess::errorOccurred, this,
            [this, process](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart) return;
        completeInFlight(QStringLiteral("audio.outputs"), false, {},
                         QStringLiteral("audio-unavailable"),
                         QStringLiteral("无法读取音频设备"), true, kAudioCacheTtlMs);
        process->deleteLater();
    });
    connect(process, &QProcess::finished, this,
            [this, process, first = true, defaultName = QString()]
            (int code, QProcess::ExitStatus status) mutable {
        QJsonParseError error;
        const auto document = QJsonDocument::fromJson(process->readAllStandardOutput(), &error);
        if (code != 0 || status != QProcess::NormalExit || error.error != QJsonParseError::NoError
            || (first ? !document.isObject() : !document.isArray())) {
            completeInFlight(QStringLiteral("audio.outputs"), false, {},
                             QStringLiteral("audio-unavailable"),
                             QStringLiteral("无法读取音频设备，请重试"), true, kAudioCacheTtlMs);
            process->deleteLater();
            return;
        }
        if (first) {
            defaultName = document.object().value(QStringLiteral("default_sink_name")).toString();
            first = false;
            process->setArguments({QStringLiteral("--format=json"), QStringLiteral("list"), QStringLiteral("sinks")});
            process->start();
            return;
        }
        QJsonArray outputs;
        for (const auto &value : document.array()) {
            const auto sink = value.toObject();
            const QString name = sink.value(QStringLiteral("name")).toString();
            if (name.isEmpty()) continue;
            const QString description = sink.value(QStringLiteral("description")).toString();
            outputs.append(QJsonObject{{QStringLiteral("name"), name},
                {QStringLiteral("description"), description.isEmpty() ? name : description},
                {QStringLiteral("isDefault"), name == defaultName}});
        }
        completeInFlight(QStringLiteral("audio.outputs"), true,
                {{QStringLiteral("outputs"), outputs}, {QStringLiteral("available"), true}},
                {}, {}, true, kAudioCacheTtlMs);
        process->deleteLater();
    });
    // One watchdog bounds the complete two-command operation.
    armProcessWatchdog(process, 10000);
    process->start();
}

bool PlatformServer::handleAudioOperation(QLocalSocket *socket, const QJsonObject &request)
{
    const QString op = operation(request);
    const QJsonObject payload = request.value(QStringLiteral("payload")).toObject();
    if (op == QStringLiteral("audio.outputs")) {
        runAudioOutputs(socket, request);
        return true;
    }
    if (op == QStringLiteral("audio.output.set-default")) {
        const QString name = payload.value(QStringLiteral("name")).toString();
        static const QRegularExpression validName(QStringLiteral("^[A-Za-z0-9_][A-Za-z0-9_.:-]{0,511}$"));
        if (!validName.match(name).hasMatch()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-audio-output"),
                    QStringLiteral("音频输出设备无效"), false);
            return true;
        }
        invalidateReplies(QStringLiteral("audio."));
        runCommand(socket, request, QStringLiteral("pactl"),
                   {QStringLiteral("set-default-sink"), name},
                   [this](const QByteArray &output, int code) {
            invalidateReplies(QStringLiteral("audio."));
            return parseOutput(output, code);
        }, 10000);
        return true;
    }
    if (op == QStringLiteral("audio.get")) {
        runCommand(socket, request, QStringLiteral("wpctl"),
                   {QStringLiteral("get-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@")},
                   parseAudio, kDefaultCommandTimeoutMs,
                   QStringLiteral("audio.get"), kAudioCacheTtlMs);
        return true;
    }
    if (op == QStringLiteral("audio.set-volume")) {
        const int value = qBound(0, payload.value(QStringLiteral("percent")).toInt(), 150);
        runCommand(socket, request, QStringLiteral("wpctl"),
                   {QStringLiteral("set-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@"),
                    QString::number(value / 100.0, 'f', 3)},
                   [this](const QByteArray &output, int exitCode) {
            invalidateReplies(QStringLiteral("audio."));
            return parseOutput(output, exitCode);
        }, 10000);
        return true;
    }
    if (op == QStringLiteral("audio.set-mute")) {
        runCommand(socket, request, QStringLiteral("wpctl"),
                   {QStringLiteral("set-mute"), QStringLiteral("@DEFAULT_AUDIO_SINK@"),
                    payload.value(QStringLiteral("muted")).toBool() ? QStringLiteral("1") : QStringLiteral("0")},
                   [this](const QByteArray &output, int exitCode) {
            invalidateReplies(QStringLiteral("audio."));
            return parseOutput(output, exitCode);
        }, 10000);
        return true;
    }
    if (op == QStringLiteral("audio.applications")) {
        const QString pactl = QStandardPaths::findExecutable(QStringLiteral("pactl"));
        if (pactl.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("audio-unavailable"),
                    QStringLiteral("音频服务不可用"), true);
            return true;
        }
        runCommand(socket, request, pactl,
                   {QStringLiteral("--format=json"), QStringLiteral("list"),
                    QStringLiteral("sink-inputs")}, parseAudioApplications,
                   10000, QStringLiteral("audio.applications"), kAudioCacheTtlMs);
        return true;
    }
    if (op == QStringLiteral("audio.application.set-volume")) {
        const int id = payload.value(QStringLiteral("id")).toInt(-1);
        const int value = qBound(0, payload.value(QStringLiteral("percent")).toInt(), 150);
        if (id < 0) {
            respond(socket, request, false, {}, QStringLiteral("invalid-audio-stream"),
                    QStringLiteral("音频应用无效"), false);
            return true;
        }
        const QString pactl = QStandardPaths::findExecutable(QStringLiteral("pactl"));
        if (pactl.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("audio-unavailable"),
                    QStringLiteral("音频服务不可用"), true);
            return true;
        }
        runCommand(socket, request, pactl,
                   {QStringLiteral("set-sink-input-volume"), QString::number(id),
                    QString::number(value) + QLatin1Char('%')},
                   [this](const QByteArray &output, int exitCode) {
            invalidateReplies(QStringLiteral("audio.applications"));
            return parseOutput(output, exitCode);
        }, 10000);
        return true;
    }
    if (op == QStringLiteral("audio.application.set-mute")) {
        const int id = payload.value(QStringLiteral("id")).toInt(-1);
        if (id < 0) {
            respond(socket, request, false, {}, QStringLiteral("invalid-audio-stream"),
                    QStringLiteral("音频应用无效"), false);
            return true;
        }
        const QString pactl = QStandardPaths::findExecutable(QStringLiteral("pactl"));
        if (pactl.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("audio-unavailable"),
                    QStringLiteral("音频服务不可用"), true);
            return true;
        }
        runCommand(socket, request, pactl,
                   {QStringLiteral("set-sink-input-mute"), QString::number(id),
                    payload.value(QStringLiteral("muted")).toBool() ? QStringLiteral("1") : QStringLiteral("0")},
                   [this](const QByteArray &output, int exitCode) {
            invalidateReplies(QStringLiteral("audio.applications"));
            return parseOutput(output, exitCode);
        }, 10000);
        return true;
    }
    return false;
}

} // namespace KosPlatform
