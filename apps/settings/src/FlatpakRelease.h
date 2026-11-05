#pragma once

#include <QByteArray>
#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <functional>

namespace FlatpakRelease {
using Cancelled = std::function<bool()>;
using Progress = std::function<void(const QString&, int)>;

bool configured(const QString& appId);
QByteArray publicKeys(const QString& appId);
QStringList fingerprints(const QString& appId);
int compareVersions(const QString& left, const QString& right, bool* valid = nullptr);
QVariantMap discover(const QString& appId, const QString& arch, const Cancelled& cancelled, const Progress& progress);
QVariantMap validateDownloaded(const QString& appId, const QVariantMap& discovery, const QString& path,
    const Cancelled& cancelled);
QVariantMap download(const QString& appId, const QVariantMap& discovery, const QString& directory,
    const Cancelled& cancelled, const Progress& progress);
}
