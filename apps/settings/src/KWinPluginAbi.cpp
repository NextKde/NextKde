#include "KWinPluginAbi.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonObject>
#include <QPluginLoader>
#include <QProcess>
#include <QRegularExpression>
#include <QSet>
#include <QStandardPaths>
#include <QTextStream>

namespace {

constexpr qint64 kMaxPluginScanBytes = 16 * 1024 * 1024;
constexpr int kKWinVersionTimeoutMs = 1500;
const QString kEffectIidPrefix = QStringLiteral("org.kde.kwin.EffectPluginFactory");

bool isVersionChar(char c)
{
    return (c >= '0' && c <= '9')
        || (c >= 'a' && c <= 'z')
        || (c >= 'A' && c <= 'Z')
        || c == '.' || c == '-' || c == '_';
}

QStringList defaultEffectPluginDirs()
{
    return {
        QStringLiteral("/usr/lib64/qt6/plugins/kwin/effects/plugins"),
        QStringLiteral("/usr/lib/qt6/plugins/kwin/effects/plugins"),
    };
}

QStringList managedEffectPluginFilenames()
{
    return {
        QStringLiteral("glass.so"),
        QStringLiteral("kos_bridge.so"),
        QStringLiteral("kos_context_menu_input.so"),
        QStringLiteral("kos_dock_window_animation.so"),
        QStringLiteral("stageanim13.so"),
    };
}

} // namespace

QString parseKWinVersionOutput(const QString& output)
{
    static const QRegularExpression pattern(
        QStringLiteral(R"(^kwin\s+([0-9]+\.[0-9]+\.[0-9]+(?:[A-Za-z0-9._-]*)?))"),
        QRegularExpression::MultilineOption);
    const QRegularExpressionMatch match = pattern.match(output);
    return match.hasMatch() ? match.captured(1) : QString();
}

QString parseKWinConfigHeader(const QString& headerText)
{
    static const QRegularExpression pattern(
        QStringLiteral(R"re(^#define\s+KWIN_PLUGIN_VERSION_STRING\s+"([^"]+)")re"),
        QRegularExpression::MultilineOption);
    const QRegularExpressionMatch match = pattern.match(headerText);
    return match.hasMatch() ? match.captured(1) : QString();
}

QString parseEffectPluginIid(const QString& iid)
{
    if (!iid.startsWith(kEffectIidPrefix))
        return {};
    const QString version = iid.mid(kEffectIidPrefix.size());
    static const QRegularExpression versionPattern(
        QStringLiteral(R"(^[0-9]+\.[0-9]+\.[0-9]+(?:[A-Za-z0-9._-]*)?$)"));
    return versionPattern.match(version).hasMatch() ? version : QString();
}

QString extractEffectPluginAbiFromBytes(const QByteArray& bytes)
{
    static const QByteArray marker("org.kde.kwin.EffectPluginFactory");
    qsizetype offset = 0;
    while (true) {
        const qsizetype pos = bytes.indexOf(marker, offset);
        if (pos < 0)
            return {};
        const qsizetype versionStart = pos + marker.size();
        qsizetype versionEnd = versionStart;
        while (versionEnd < bytes.size() && isVersionChar(bytes.at(versionEnd)))
            ++versionEnd;
        const QString candidate = QString::fromLatin1(
            bytes.mid(pos, versionEnd - pos));
        const QString parsed = parseEffectPluginIid(candidate);
        if (!parsed.isEmpty())
            return parsed;
        offset = versionStart;
    }
}

QString readEffectPluginAbi(const QString& pluginPath)
{
    if (pluginPath.isEmpty() || !QFileInfo::exists(pluginPath))
        return {};

    QPluginLoader loader(pluginPath);
    const QString metaIid = loader.metaData().value(QStringLiteral("IID")).toString();
    const QString metaVersion = parseEffectPluginIid(metaIid);
    if (!metaVersion.isEmpty())
        return metaVersion;

    QFile file(pluginPath);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return extractEffectPluginAbiFromBytes(file.read(kMaxPluginScanBytes));
}

QStringList discoverInstalledKWinEffectPlugins(
    const QString& manifestPath, const QStringList& fallbackDirs)
{
    QStringList paths;
    QSet<QString> seen;
    auto addUnique = [&paths, &seen](const QString& candidate) {
        const QFileInfo info(candidate);
        if (!info.exists() || !info.isFile())
            return;
        const QString canonical = info.canonicalFilePath();
        const QString key = canonical.isEmpty() ? info.absoluteFilePath() : canonical;
        if (seen.contains(key))
            return;
        seen.insert(key);
        paths.append(candidate);
    };

    if (!manifestPath.isEmpty()) {
        QFile manifest(manifestPath);
        if (manifest.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QTextStream stream(&manifest);
            while (!stream.atEnd()) {
                const QString line = stream.readLine().trimmed();
                if (line.contains(QStringLiteral("/effects/plugins/"))
                    && line.endsWith(QStringLiteral(".so"))) {
                    addUnique(line);
                }
            }
        }
    }

    if (!paths.isEmpty())
        return paths;

    const QStringList dirs = fallbackDirs.isEmpty() ? defaultEffectPluginDirs() : fallbackDirs;
    const QStringList names = managedEffectPluginFilenames();
    for (const QString& dir : dirs) {
        for (const QString& name : names)
            addUnique(QDir(dir).filePath(name));
    }
    return paths;
}

QString detectSystemKWinVersion(const QString& configHeaderPath)
{
    const QString kwinExecutable = QStandardPaths::findExecutable(QStringLiteral("kwin_wayland"));
    if (!kwinExecutable.isEmpty()) {
        QProcess process;
        process.start(kwinExecutable, { QStringLiteral("--version") });
        if (process.waitForFinished(kKWinVersionTimeoutMs)
            && process.exitStatus() == QProcess::NormalExit
            && process.exitCode() == 0) {
            const QString combined = QString::fromLocal8Bit(process.readAllStandardOutput())
                + QLatin1Char('\n') + QString::fromLocal8Bit(process.readAllStandardError());
            const QString version = parseKWinVersionOutput(combined);
            if (!version.isEmpty())
                return version;
        } else if (process.state() != QProcess::NotRunning) {
            process.kill();
            process.waitForFinished(250);
        }
    }

    if (!configHeaderPath.isEmpty()) {
        QFile header(configHeaderPath);
        if (header.open(QIODevice::ReadOnly | QIODevice::Text)) {
            const QString version = parseKWinConfigHeader(QString::fromUtf8(header.readAll()));
            if (!version.isEmpty())
                return version;
        }
    }
    return {};
}

KWinPluginAbiStatus inspectKWinPluginAbi(
    const QString& kwinVersion, const QStringList& pluginPaths)
{
    KWinPluginAbiStatus status;
    status.kwinVersion = kwinVersion;
    if (kwinVersion.isEmpty() || pluginPaths.isEmpty())
        return status;

    QStringList builtVersions;
    QStringList mismatchedVersions;
    for (const QString& path : pluginPaths) {
        const QString built = readEffectPluginAbi(path);
        if (built.isEmpty())
            continue;
        status.checked = true;
        if (!builtVersions.contains(built))
            builtVersions.append(built);
        if (built != kwinVersion) {
            status.mismatch = true;
            if (!mismatchedVersions.contains(built))
                mismatchedVersions.append(built);
            status.mismatchedPlugins.append(QFileInfo(path).completeBaseName());
        }
    }

    if (status.mismatch) {
        mismatchedVersions.sort();
        status.pluginVersion = mismatchedVersions.join(QStringLiteral(", "));
    } else if (status.checked) {
        builtVersions.sort();
        status.pluginVersion = builtVersions.join(QStringLiteral(", "));
    }
    return status;
}

KWinPluginAbiStatus inspectInstalledKWinPluginAbi()
{
    if (QFileInfo::exists(QStringLiteral("/etc/NIXOS")))
        return {};

    const QString prefix = qEnvironmentVariable("KOS_PREFIX",
        QDir::homePath() + QStringLiteral("/.local"));
    const QString manifestPath = QDir(prefix).filePath(
        QStringLiteral("share/kos/kwin-system-files.manifest"));
    const QStringList plugins = discoverInstalledKWinEffectPlugins(manifestPath);
    if (plugins.isEmpty())
        return {};
    return inspectKWinPluginAbi(detectSystemKWinVersion(), plugins);
}
