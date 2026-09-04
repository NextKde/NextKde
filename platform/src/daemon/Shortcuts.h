#pragma once

#include <QJsonArray>
#include <QString>

namespace KosPlatform {

// KOS global shortcuts, registered through the KGlobalAccel client library —
// the same mechanism the plasma powerdevil daemon uses. The daemon owns one
// QAction per shortcut, all under the single "org.kos.Platform" component:
// kglobalaccel persists the bindings, shows ONE entry in System Settings →
// Shortcuts, and delivers activations back to this daemon, which runs the
// Exec line the Shell supplied in the apply payload (so it always addresses
// the live Shell instance, dev or installed).
//
// No service desktop files are involved. Earlier generations wrote
// per-shortcut *.desktop files plus [services] sections in
// kglobalshortcutsrc; cleanShortcutLayouts() removes those leftovers.

// Registers or updates the whole set. Every shortcut object carries `id`,
// `description`, `combo` (kglobalaccel PortableText, e.g. "Meta+Shift+Space")
// and `exec` (the command line to run on activation). All-or-nothing: a
// malformed item aborts before any QAction is touched.
bool applyShortcutSet(const QJsonArray &shortcuts, QString *error = nullptr);

// Unregisters every KOS action (bindings become inactive) and drops the
// leftover files from superseded layouts.
void removeShortcuts();

// Removes desktop files and kglobalshortcutsrc sections written by
// superseded shortcut layouts. Idempotent; safe to call on every apply.
void cleanShortcutLayouts();

// Trims display variants ("Meta+X,Meta+X") down to the primary binding.
QString normalizedShortcutCombo(QString value);

} // namespace KosPlatform
