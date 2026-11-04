#include "NotesExtension.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QProcess>
#include <QSettings>
#include <QStandardPaths>

namespace {

const QString kServiceName = QStringLiteral("org.nextkde.Notes");
const QString kDataLeaf = QStringLiteral("nextkde-notes");

QStringList sourceCandidates(const QString& preferred)
{
    QStringList candidates;
    if (!preferred.isEmpty())
        candidates << preferred;
    const QString appDir = QCoreApplication::applicationDirPath();
    candidates << QDir(appDir).absoluteFilePath(QStringLiteral("../../share/kos/Notes"));
    candidates << QStringLiteral("/usr/share/kos/Notes");
    candidates << QStringLiteral("/usr/local/share/kos/Notes");
    return candidates;
}

} // namespace

NotesExtension::NotesExtension(const QString& sourceDirectory, QObject* parent)
    : QObject(parent)
    , m_source(sourceDirectory)
{
    m_state = {{QStringLiteral("available"), false},
               {QStringLiteral("installed"), false},
               {QStringLiteral("running"), false},
               {QStringLiteral("busy"), false},
               {QStringLiteral("needsBuild"), false},
               {QStringLiteral("stage"), QString()},
               {QStringLiteral("message"), QString()},
               {QStringLiteral("code"), QString()},
               {QStringLiteral("version"), QString()},
               {QStringLiteral("logPath"), QString()},
               {QStringLiteral("storageRoot"), QString()}};

    connect(&m_install, &QProcess::finished, this, &NotesExtension::finishInstall);
    connect(&m_install, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart && m_installing)
            fail(QStringLiteral("START_FAILED"));
    });
    connect(&m_install, &QProcess::readyReadStandardOutput, this, [this] {
        const QString chunk = QString::fromUtf8(m_install.readAllStandardOutput());
        for (const auto& line : chunk.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
            if (line.contains(QLatin1String("编译")) || line.contains(QLatin1String("安装"))
                || line.contains(QLatin1String("配置")))
                setFlag(QStringLiteral("stage"), line.trimmed());
        }
    });

    // 每秒确认一次总线名：用户在悬浮球/托盘里退出后，面板会自动回到「开启」。
    m_poll.setInterval(1500);
    connect(&m_poll, &QTimer::timeout, this, &NotesExtension::syncRunning);
    m_poll.start();

    refresh();
}

NotesExtension::~NotesExtension() = default;

void NotesExtension::setFlag(const QString& key, const QVariant& value)
{
    if (m_state.value(key) == value)
        return;
    m_state[key] = value;
    emit changed();
}

QString NotesExtension::resolveSource() const
{
    for (const auto& candidate : sourceCandidates(m_source)) {
        if (QFileInfo::exists(candidate + QStringLiteral("/install.sh"))
            || QFileInfo::exists(candidate + QStringLiteral("/CMakeLists.txt")))
            return candidate;
    }
    return {};
}

QString NotesExtension::dataDirectory() const
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
        + QLatin1Char('/') + kDataLeaf;
}

QString NotesExtension::markerPath() const
{
    return dataDirectory() + QStringLiteral("/installed.json");
}

QString NotesExtension::binaryPath() const
{
    return dataDirectory() + QStringLiteral("/current/bin/kos-notes");
}

bool NotesExtension::serviceRegistered() const
{
    const auto bus = QDBusConnection::sessionBus();
    if (!bus.isConnected() || !bus.interface())
        return false;
    return bus.interface()->isServiceRegistered(kServiceName);
}

void NotesExtension::reloadMarker()
{
    QFile marker(markerPath());
    bool installed = false;
    bool built = false;
    QString version;
    if (marker.open(QIODevice::ReadOnly)) {
        const auto doc = QJsonDocument::fromJson(marker.readAll()).object();
        installed = doc.value(QStringLiteral("installed")).toBool();
        built = doc.value(QStringLiteral("built")).toBool();
        version = doc.value(QStringLiteral("version")).toString();
    }
    // 标记丢了但二进制在，也算已安装（用户可能手动构建过）。
    if (!installed && QFileInfo::exists(binaryPath()))
        installed = built = true;

    setFlag(QStringLiteral("installed"), installed);
    setFlag(QStringLiteral("needsBuild"), installed && !built);
    setFlag(QStringLiteral("version"), version);

    // 笔记目录与设置共用一个 QSettings 文件，读出来给面板显示。
    QSettings settings(QStringLiteral("NextKde"), QStringLiteral("kos-notes"));
    setFlag(QStringLiteral("storageRoot"),
            settings.value(QStringLiteral("storage/root"),
                           QDir::homePath() + QStringLiteral("/Notes"))
                .toString());
}

void NotesExtension::syncRunning()
{
    const bool running = serviceRegistered();
    if (m_state.value(QStringLiteral("running")).toBool() != running) {
        setFlag(QStringLiteral("running"), running);
        if (!running)
            reloadMarker();
    }
}

void NotesExtension::refresh()
{
    reloadMarker();
    setFlag(QStringLiteral("available"), !resolveSource().isEmpty());
    setFlag(QStringLiteral("logPath"), m_logPath);
    syncRunning();
}

void NotesExtension::fail(const QString& code)
{
    setFlag(QStringLiteral("busy"), false);
    setFlag(QStringLiteral("code"), code);
    m_installing = false;
}

void NotesExtension::install()
{
    if (m_installing)
        return;
    const QString source = resolveSource();
    if (source.isEmpty()) {
        fail(QStringLiteral("SOURCE_MISSING"));
        return;
    }

    m_installing = true;
    m_elapsed.start();
    m_logPath = dataDirectory() + QStringLiteral("/install.log");
    QDir().mkpath(dataDirectory());

    setFlag(QStringLiteral("busy"), true);
    setFlag(QStringLiteral("code"), QString());
    setFlag(QStringLiteral("stage"), QStringLiteral("正在构建…"));
    setFlag(QStringLiteral("logPath"), m_logPath);

    // 构建输出同时进日志文件，失败时面板上可以直接打开查看。
    m_install.setProcessChannelMode(QProcess::MergedChannels);
    m_install.setStandardOutputFile(m_logPath, QIODevice::WriteOnly | QIODevice::Truncate);
    m_install.setWorkingDirectory(source);
    m_install.start(QStringLiteral("bash"),
                    {source + QStringLiteral("/install.sh"), QStringLiteral("--build-only")});
}

void NotesExtension::finishInstall(int exitCode, QProcess::ExitStatus status)
{
    m_installing = false;
    setFlag(QStringLiteral("busy"), false);
    setFlag(QStringLiteral("stage"), QString());
    if (status != QProcess::NormalExit || exitCode != 0) {
        setFlag(QStringLiteral("code"), QStringLiteral("BUILD_FAILED"));
        return;
    }
    m_state.insert(QStringLiteral("code"), QString());
    refresh();
}

void NotesExtension::launch()
{
    if (!QFileInfo::exists(binaryPath())) {
        // 没构建过就先构建，构建完成后由用户再点一次「开启」。
        install();
        return;
    }
    setFlag(QStringLiteral("code"), QString());
    // 独立进程：面板关掉也不影响笔记继续运行。
    const bool started = QProcess::startDetached(binaryPath(), {QStringLiteral("--background")});
    if (!started) {
        setFlag(QStringLiteral("code"), QStringLiteral("LAUNCH_FAILED"));
        return;
    }
    setFlag(QStringLiteral("running"), true);
    m_poll.start();
}

void NotesExtension::quit()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (bus.isConnected() && serviceRegistered()) {
        QDBusMessage message = QDBusMessage::createMethodCall(
            kServiceName, QStringLiteral("/Notes"), kServiceName, QStringLiteral("quit"));
        bus.call(message, QDBus::Block, 1500);
    }
    // 给进程一点时间干净退出；仍在就补一刀。
    QTimer::singleShot(600, this, [this] {
        if (!serviceRegistered()) {
            setFlag(QStringLiteral("running"), false);
            return;
        }
        QProcess::execute(QStringLiteral("pkill"), {QStringLiteral("-f"), binaryPath()});
        setFlag(QStringLiteral("running"), false);
    });
}

void NotesExtension::openMainWindow()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (bus.isConnected() && serviceRegistered()) {
        QDBusMessage message = QDBusMessage::createMethodCall(
            kServiceName, QStringLiteral("/Notes"), kServiceName, QStringLiteral("showNotes"));
        bus.call(message, QDBus::Block, 1500);
        return;
    }
    launch();
}

void NotesExtension::uninstall()
{
    QDir(dataDirectory()).removeRecursively();
    m_logPath.clear();
    setFlag(QStringLiteral("running"), false);
    refresh();
}
