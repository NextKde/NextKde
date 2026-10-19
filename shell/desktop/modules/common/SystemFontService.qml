pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "SystemFontPolicy.mjs" as FontPolicy

// KDE's own interface font, as configured in kdeglobals.
//
// 使用系统字体 (AppearanceConfigService.useSystemFont) makes every shell surface
// draw with the family KDE is set to instead of the families the shell was
// designed around. Qt already applies that font to the process through the KDE
// platform theme, but the shell cannot simply read Qt.application.font: the
// property is not observable from QML (binding to it never re-evaluates), and a
// session started without the platform theme -- a plain `qs -p shell` under
// weston, the offscreen test harness -- reports Qt's internal default instead.
// Reading `[General] font=` is the same value KDE's own applications use, and
// the FileView makes it follow a change made in System Settings without a shell
// restart.
//
// Only the family is taken. Size stays owned by each surface: the shell's
// layout is tuned for its own pixel sizes, and KDE's point size would reflow the
// Bar and Dock rather than restyle them. The toggle exists for the *face*.
QtObject {
    id: service

    readonly property string configPath: (Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")) + "/kdeglobals"

    // The raw `font=` value, kept so the parser owns every rule about its shape.
    property string fontSpec: ""
    // True once kdeglobals has been read (whether or not it carried a font).
    property bool loaded: false
    // The family the shell should draw with. Falls back to the platform font so
    // a machine whose kdeglobals names a family it does not have installed
    // still renders readable text -- Qt would otherwise panic-warn per glyph.
    readonly property string family: {
        const policy = FontPolicy.resolveFamily(fontSpec,
            Qt.application.font.family)
        return policy.length > 0 ? policy : Qt.application.font.family
    }
    // Accessing the singleton from shell.qml instantiates the FileView; this
    // keeps the startup dependency explicit, the way IconThemeReloadService
    // does.
    function initialize() {}

    function applyConfig(text) {
        const spec = FontPolicy.fontSpecFromConfig(text)
        // KConfig rewrites kdeglobals atomically; a read that lands between the
        // unlink and the rename is empty. Only a settled read replaces the
        // value, so a transient empty file cannot flip the shell back to Qt's
        // default for a frame.
        if (spec.length === 0 && loaded)
            return
        fontSpec = spec
        loaded = true
    }

    property FileView _kdeGlobals: FileView {
        id: kdeGlobals
        path: service.configPath
        watchChanges: true
        preload: true
        // A desktop without a font configured is a supported state, not an
        // error: the family then falls back to the one Qt already applied.
        printErrors: false
        // Delay the read until KConfig's atomic write has settled.
        onFileChanged: settleTimer.restart()
        onLoaded: service.applyConfig(text())
    }

    property Timer _settleTimer: Timer {
        id: settleTimer
        interval: 350
        repeat: false
        onTriggered: kdeGlobals.reload()
    }
}
