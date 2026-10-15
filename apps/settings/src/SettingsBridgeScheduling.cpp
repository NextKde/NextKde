#include "SettingsBridge.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>

QString SettingsBridge::fgSchedConfigPath()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
        + QStringLiteral("/fg-sched/config.json");
}

QString SettingsBridge::fgSchedKnownAppsPath()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
        + QStringLiteral("/fg-sched/known-apps.json");
}

bool SettingsBridge::writeFgSchedConfig(const std::function<void(QJsonObject&)>& mutate)
{
    QJsonObject obj;
    {
        QFile in(fgSchedConfigPath());
        if (in.open(QIODevice::ReadOnly))
            obj = QJsonDocument::fromJson(in.readAll()).object();
    }
    mutate(obj);
    if (!QDir().mkpath(QFileInfo(fgSchedConfigPath()).absolutePath()))
        return false;
    QSaveFile out(fgSchedConfigPath());
    if (!out.open(QIODevice::WriteOnly))
        return false;
    out.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    return out.commit();
}

void SettingsBridge::fgSchedRunningApps()
{
    callShell(QStringLiteral("fg-sched"), { QStringLiteral("runningApps") },
        QStringLiteral("Running apps list request failed"), RequestKind::FgSchedApps);
}

void SettingsBridge::fgSchedSnapshot()
{
    QVariantMap out;
    out.insert(QStringLiteral("resourceSchedulingAvailable"),
        !QStandardPaths::findExecutable(QStringLiteral("fg-schedd")).isEmpty()
            || QFileInfo(QStringLiteral("/usr/local/sbin/fg-schedd")).isExecutable()
            || QFileInfo(QStringLiteral("/usr/sbin/fg-schedd")).isExecutable());
    QJsonObject obj;
    {
        QFile in(fgSchedConfigPath());
        if (in.open(QIODevice::ReadOnly))
            obj = QJsonDocument::fromJson(in.readAll()).object();
    }
    out.insert(QStringLiteral("freezeEnabled"),
        obj.value(QStringLiteral("freeze_minimized_after_s")).toInt() > 0);
    out.insert(QStringLiteral("reclaimMode"),
        obj.value(QStringLiteral("reclaim"))
            .toObject()
            .value(QStringLiteral("mode"))
            .toString(QStringLiteral("once")));
    QStringList full;
    const auto fullArray = obj.value(QStringLiteral("never_demote_apps")).toArray();
    for (const auto& v : fullArray)
        full << v.toString();
    out.insert(QStringLiteral("fullResources"), full);
    const auto bg = obj.value(QStringLiteral("background")).toObject();
    out.insert(QStringLiteral("bgNice"), bg.value(QStringLiteral("nice")).toDouble());
    // affinity_cpus 三态：显式数组原样列出；"auto"/缺省 = 守护启动时
    // 自动探测（异构→效率核，同构→不限核）。UI 只需知道模式不必知道
    // 具体核号，跨机器通用。
    const auto cpuValue = bg.value(QStringLiteral("affinity_cpus"));
    if (cpuValue.isArray()) {
        QStringList cpus;
        const auto cpuArray = cpuValue.toArray();
        for (const auto& v : cpuArray)
            cpus << QString::number(v.toInt());
        out.insert(QStringLiteral("bgCpus"), cpus.join(QStringLiteral(",")));
        out.insert(QStringLiteral("bgCpusAuto"), false);
    } else {
        out.insert(QStringLiteral("bgCpus"), QStringLiteral("auto"));
        out.insert(QStringLiteral("bgCpusAuto"), true);
    }
    QStringList known;
    QFile knownFile(fgSchedKnownAppsPath());
    if (knownFile.open(QIODevice::ReadOnly)) {
        const auto arr = QJsonDocument::fromJson(knownFile.readAll()).array();
        for (const auto& v : arr)
            known << v.toString();
    }
    out.insert(QStringLiteral("knownApps"), known);
    // 台前侧栏总开关的落盘态（StageModeService 的 stage-mode flag）
    QFile stageFlag(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
        + QStringLiteral("/fg-sched/stage-mode"));
    if (stageFlag.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QString flagValue = QString::fromUtf8(stageFlag.readAll()).trimmed();
        out.insert(QStringLiteral("stageEnabled"), flagValue == QStringLiteral("1"));
    } else {
        out.insert(QStringLiteral("stageEnabled"), false);
    }
    emit fgSchedSnapshotChanged(out);
}

void SettingsBridge::fgSchedSetFreeze(bool on)
{
    if (!writeFgSchedConfig([&](QJsonObject& obj) {
            obj.insert(QStringLiteral("freeze_minimized_after_s"), on ? 180 : 0);
        }))
        return;
    fgSchedSnapshot();
}

void SettingsBridge::fgSchedSetReclaim(const QString& mode)
{
    if (mode != QStringLiteral("off") && mode != QStringLiteral("once")
        && mode != QStringLiteral("aggressive") && mode != QStringLiteral("kill"))
        return;
    if (!writeFgSchedConfig([&](QJsonObject& obj) {
            QJsonObject rec = obj.value(QStringLiteral("reclaim")).toObject();
            rec.insert(QStringLiteral("mode"), mode);
            obj.insert(QStringLiteral("reclaim"), rec);
        }))
        return;
    fgSchedSnapshot();
}

void SettingsBridge::callStage(const QStringList& arguments)
{
    callShell(QStringLiteral("stage-config"), arguments,
        QStringLiteral("Stage scheduling parameters request failed"), RequestKind::StageConfig);
}

void SettingsBridge::stageConfigSnapshot() { callStage({ QStringLiteral("snapshot") }); }

void SettingsBridge::stageConfigSet(const QString& key, const QString& value)
{
    callStage({ QStringLiteral("set"), key, value });
}

void SettingsBridge::stageSidebarSet(bool on)
{
    // ⚠️ 必须 enable/disable：quickshell 的 ipc CLI 把 "show" 当自己
    // 的关键字（ipc show = 列 verb），`ipc call <t> show` 只打印列表
    // 不派发——旧实现发 show 的那一半永远到不了 shell（开关"开不
    // 了"的真根因之一）
    callShell(QStringLiteral("stage-sidebar"),
        { on ? QStringLiteral("enable") : QStringLiteral("disable") },
        QStringLiteral("Stage sidebar toggle request failed"), RequestKind::StageSidebar);
}

QVariantMap SettingsBridge::stageConfigFromReply(const QString& payload)
{
    // 空应答 = void IPC 复用本 Kind（stage-sidebar enable/disable）或
    // 传输失败——不是"参数被清空"。回 last-good，别把整页滑杆打成
    // 默认值
    if (payload.isEmpty())
        return m_lastStageConfig;
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        setLastError(QStringLiteral("Stage scheduling parameters response is invalid"));
        return m_lastStageConfig;
    }
    const QJsonObject object = document.object();
    // set 失败应答 {ok:false,error:...} 不带参数：报错并保持 last-good
    if (object.value(QStringLiteral("ok")).toBool(false) == false
        && object.contains(QStringLiteral("error"))
        && !object.contains(QStringLiteral("revision"))) {
        setLastError(object.value(QStringLiteral("error"))
                .toString(QStringLiteral("Failed to write stage scheduling parameters")));
        return m_lastStageConfig;
    }
    setLastError({ });
    QVariantMap out;
    for (auto it = object.begin(); it != object.end(); ++it)
        out.insert(it.key(), it.value().toVariant());
    m_lastStageConfig = out;
    return out;
}

void SettingsBridge::fgSchedMemStatus()
{
    QVariantMap out;
    QFile f(QStringLiteral("/proc/meminfo"));
    if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const auto lines = QString::fromUtf8(f.readAll()).split(QLatin1Char('\n'));
        for (const QString& line : lines) {
            const int colon = line.indexOf(QLatin1Char(':'));
            if (colon <= 0)
                continue;
            const QString key = line.left(colon);
            const qint64 kb = line.mid(colon + 1)
                                  .split(QLatin1Char(' '), Qt::SkipEmptyParts)
                                  .value(0)
                                  .toLongLong();
            if (key == QLatin1String("MemTotal"))
                out.insert(QStringLiteral("memTotalKb"), kb);
            else if (key == QLatin1String("MemAvailable"))
                out.insert(QStringLiteral("memAvailableKb"), kb);
            else if (key == QLatin1String("SwapTotal"))
                out.insert(QStringLiteral("swapTotalKb"), kb);
            else if (key == QLatin1String("SwapFree"))
                out.insert(QStringLiteral("swapFreeKb"), kb);
        }
    }
    QFile z(QStringLiteral("/sys/block/zram0/mm_stat"));
    if (z.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const auto fields
            = QString::fromUtf8(z.readAll()).split(QLatin1Char(' '), Qt::SkipEmptyParts);
        if (fields.size() >= 3) {
            out.insert(QStringLiteral("zramOrigKb"), fields.value(0).toLongLong() / 1024);
            out.insert(QStringLiteral("zramComprKb"), fields.value(1).toLongLong() / 1024);
        }
    }
    emit fgSchedMemStatusChanged(out);
}

void SettingsBridge::fgSchedAddFull(const QString& klass)
{
    const QString trimmed = klass.trimmed();
    if (trimmed.isEmpty())
        return;
    if (!writeFgSchedConfig([&](QJsonObject& obj) {
            auto arr = obj.value(QStringLiteral("never_demote_apps")).toArray();
            for (const auto& v : arr) {
                if (v.toString() == trimmed)
                    return;
            }
            arr.append(trimmed);
            obj.insert(QStringLiteral("never_demote_apps"), arr);
        }))
        return;
    fgSchedSnapshot();
}

void SettingsBridge::fgSchedRemoveFull(const QString& klass)
{
    if (!writeFgSchedConfig([&](QJsonObject& obj) {
            auto arr = obj.value(QStringLiteral("never_demote_apps")).toArray();
            QJsonArray kept;
            for (const auto& v : arr) {
                if (v.toString() != klass)
                    kept.append(v);
            }
            obj.insert(QStringLiteral("never_demote_apps"), kept);
        }))
        return;
    fgSchedSnapshot();
}
