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

// Canonicalises the parent directory but keeps the final directory entry
// unresolved, so rename/transfer/trash operate on a shortcut symlink itself
// instead of the installed file it points at.
QString cleanEntryPath(const QString &path);

QStringList cleanEntryPaths(const QJsonValue &value);

QJsonArray jsonPaths(const QStringList &paths);

QStringList localClipboardPaths(const QMimeData *mime);

QString mimeOperation(const QMimeData *mime);

QString resolveDesktopFile(const QString &id);

QString resolveOwnExecutable(const QString &name);

} // namespace KosPlatform::Detail
