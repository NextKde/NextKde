#pragma once

#include <QJsonArray>
#include <QJsonObject>
#include <QStringList>
#include <QMimeData>

// Implementation-only contracts; not part of the JSONL protocol.
namespace KosPlatform::Detail {

inline constexpr auto kGnomeFilesMime = "x-special/gnome-copied-files";

inline constexpr auto kClipboardCutMime = "application/x-kde-cutselection";

QString cleanCreatePath(const QString &path);

QString cleanPath(const QString &path);

QStringList cleanPaths(const QJsonValue &value);

QJsonArray jsonPaths(const QStringList &paths);

QStringList localClipboardPaths(const QMimeData *mime);

QString mimeOperation(const QMimeData *mime);

QString resolveDesktopFile(const QString &id);

QString resolveOwnExecutable(const QString &name);

} // namespace KosPlatform::Detail
