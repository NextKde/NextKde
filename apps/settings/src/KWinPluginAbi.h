#pragma once

#include <QByteArray>
#include <QString>
#include <QStringList>

struct KWinPluginAbiStatus {
    bool checked = false;
    bool mismatch = false;
    QString kwinVersion;
    QString pluginVersion;
    QStringList mismatchedPlugins;
};

QString parseKWinVersionOutput(const QString& output);
QString parseKWinConfigHeader(const QString& headerText);
QString parseEffectPluginIid(const QString& iid);
QString extractEffectPluginAbiFromBytes(const QByteArray& bytes);
QString readEffectPluginAbi(const QString& pluginPath);
QStringList discoverInstalledKWinEffectPlugins(
    const QString& manifestPath, const QStringList& fallbackDirs = {});
QString detectSystemKWinVersion(
    const QString& configHeaderPath = QStringLiteral("/usr/include/kwin/config-kwin.h"));
KWinPluginAbiStatus inspectKWinPluginAbi(
    const QString& kwinVersion, const QStringList& pluginPaths);
KWinPluginAbiStatus inspectInstalledKWinPluginAbi();
