#pragma once

#include <QJsonArray>
#include <QString>
#include <QStringList>

namespace KosPlatform {

// Global-shortcut ownership for kglobalaccel.
//
// KOS owns its shortcuts through `<id>.desktop` service entries
// (`X-KDE-GlobalAccel-CommandShortcut=true`) plus `[services]` sections in
// `kglobalshortcutsrc`, and asks kglobalaccel over D-Bus to (un)register
// them. Two callers share this module:
//
//   - the `kos-platform shortcuts install|uninstall` CLI, which reads
//     shared/contracts/shortcuts.v1.json and composes `qs -c kos ...`
//     Exec lines, and
//   - PlatformServer's `shortcuts.apply` / `shortcuts.uninstall`
//     operations, where the Shell composes the Exec line itself so it
//     matches how that Shell instance was launched (dev `-p` vs installed
//     `-c kos`).
//
// Every shortcut object carries `id`, `description`, `combo` (already in
// kglobalaccel's PortableText form, e.g. "Meta+Shift+Space") and `exec`
// (the full desktop Exec line). Installation is all-or-nothing: any combo
// already bound to a different service aborts the whole set with a
// human-readable conflict message.

bool installShortcutSet(const QJsonArray &shortcuts,
                        const QStringList &legacyIds,
                        QString *error = nullptr);

bool uninstallShortcutIds(const QStringList &ids,
                          const QStringList &legacyIds,
                          QString *error = nullptr);

// Desktop entries produced by earlier KOS generations whose Exec lines no
// longer match any launch mode. Removed on every install/uninstall. User
// created entries (net.local.qs*) are deliberately left alone.
QStringList legacyKosShortcutIds();

// Trims display variants ("Meta+X,Meta+X") down to the primary binding.
QString normalizedShortcutCombo(QString value);

} // namespace KosPlatform
