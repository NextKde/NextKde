#include "WidgetPackageIndex.h"

#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>
#include <QStandardPaths>

namespace KosPlatform::WidgetPackageIndex {
namespace {
constexpr int kMaxPackages = 512;
constexpr qint64 kMaxMetadataBytes = 64 * 1024;

bool validId(const QString &id)
{
    if (id.isEmpty() || id.size() > 192 || id.startsWith('.') || id.endsWith('.'))
        return false;
    const auto labels = id.split('.');
    if (labels.size() < 3)
        return false;
    for (const QString &label : labels) {
        if (label.isEmpty() || label.size() > 63 || !label.front().isLetterOrNumber()
            || !label.back().isLetterOrNumber())
            return false;
        for (const QChar ch : label) {
            if (!ch.isLetterOrNumber() && ch != QLatin1Char('-'))
                return false;
        }
    }
    return true;
}

bool validSize(const QJsonValue &value)
{
    if (!value.isArray()) return false;
    const QJsonArray pair = value.toArray();
    if (pair.size() != 2) return false;
    for (const QJsonValue &axis : pair) {
        if (!axis.isDouble()) return false;
        const double number = axis.toDouble();
        if (number < 1 || number > 4 || number != static_cast<int>(number)) return false;
    }
    return true;
}

QJsonObject readPackage(const QString &directoryName)
{
    if (!validId(directoryName)) return {};
    const QString root = QDir(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation))
        .filePath(QStringLiteral("kos/widgets/") + directoryName);
    const QFileInfo dirInfo(root);
    const QFileInfo metadataInfo(QDir(root).filePath(QStringLiteral("metadata.json")));
    if (!dirInfo.isDir() || dirInfo.isSymLink() || !metadataInfo.isFile()
        || metadataInfo.isSymLink() || metadataInfo.size() <= 0
        || metadataInfo.size() > kMaxMetadataBytes)
        return {};

    QFile file(metadataInfo.filePath());
    if (!file.open(QIODevice::ReadOnly)) return {};
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) return {};
    const QJsonObject metadata = document.object();
    const QString id = metadata.value(QStringLiteral("id")).toString();
    const QJsonValue version = metadata.value(QStringLiteral("version"));
    const QJsonValue sdkVersion = metadata.value(QStringLiteral("sdkVersion"));
    const QJsonValue sizesValue = metadata.value(QStringLiteral("sizes"));
    if (!validId(id) || id != directoryName || version.toString().isEmpty()
        || !sdkVersion.isDouble() || sdkVersion.toInt(-1) != 1
        || !metadata.value(QStringLiteral("name")).isString()
        || metadata.value(QStringLiteral("name")).toString().isEmpty()
        || !sizesValue.isArray() || sizesValue.toArray().isEmpty()) return {};

    const QJsonArray sizes = sizesValue.toArray();
    QSet<QString> seenSizes;
    for (const QJsonValue &size : sizes) {
        if (!validSize(size)) return {};
        const QString key = QString::fromUtf8(QJsonDocument(size.toArray()).toJson(QJsonDocument::Compact));
        if (seenSizes.contains(key)) return {};
        seenSizes.insert(key);
    }
    const QJsonValue defaultSize = metadata.value(QStringLiteral("defaultSize"));
    if (!validSize(defaultSize)) return {};
    const QString defaultKey = QString::fromUtf8(QJsonDocument(defaultSize.toArray()).toJson(QJsonDocument::Compact));
    if (!seenSizes.contains(defaultKey)) return {};

    const QDir packageDir(root);
    const QFileInfo widget(packageDir.filePath(QStringLiteral("Widget.qml")));
    const QFileInfo snapshot(packageDir.filePath(QStringLiteral("Snapshot.qml")));
    if (!widget.isFile() || widget.isSymLink() || !snapshot.isFile() || snapshot.isSymLink()) return {};

    QJsonObject result = metadata;
    result.insert(QStringLiteral("available"), true);
    return result;
}
}

QJsonObject snapshot()
{
    QJsonArray packages;
    QStringList roots = QStandardPaths::standardLocations(QStandardPaths::GenericDataLocation);
    if (roots.isEmpty()) roots.append(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation));
    QSet<QString> seen;
    for (const QString &dataRoot : roots) {
        QDir widgets(QDir(dataRoot).filePath(QStringLiteral("kos/widgets")));
        if (!widgets.exists()) continue;
        for (const QString &name : widgets.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name)) {
            if (seen.contains(name)) continue;
            const QJsonObject item = readPackage(name);
            if (item.isEmpty()) continue;
            seen.insert(name);
            packages.append(item);
            if (packages.size() >= kMaxPackages) break;
        }
        if (packages.size() >= kMaxPackages) break;
    }
    return {{QStringLiteral("sdkVersion"), 1}, {QStringLiteral("packages"), packages}};
}
}
