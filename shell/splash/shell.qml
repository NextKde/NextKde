// The login screen, drawn by its own small Quickshell instance.
//
// The desktop Shell builds every window on one GUI thread, and that thread is
// busy for the whole time the login screen is up. Anything animated from
// inside it stands still exactly when it matters, so the spinner lives here
// instead: this config owns nothing but a black (dark appearance) or white
// (light appearance) surface with three dots, and its event loop has nothing
// else to do. Started by kos-shell.service in parallel with the Shell, stopped
// by StartupSplash.qml once the arrival animation begins.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    // The desktop's dark/light decision is a KOS appearance rule, not just the
    // KDE palette: the glass styles stay dark unless they opt into following
    // the appearance mode. Read the persisted settings so the splash matches
    // whatever the desktop will draw after the handover; fall back to the KDE
    // palette on a machine that has never saved settings.
    SystemPalette {
        id: palette
        colorGroup: SystemPalette.Active
    }
    readonly property bool paletteDark: palette.window.r * 0.2126
        + palette.window.g * 0.7152 + palette.window.b * 0.0722 < 0.5

    readonly property string appearanceFile: {
        const stateHome = String(Quickshell.env("XDG_STATE_HOME") || "")
        const base = stateHome.length > 0 ? stateHome
            : String(Quickshell.env("HOME") || "") + "/.local/state"
        return base + "/quickshell/kos/appearance/config.json"
    }
    property bool dark: paletteDark

    FileView {
        path: root.appearanceFile
        preload: true
        printErrors: false
        onLoadedChanged: if (loaded) root.readAppearance(text())
    }

    function readAppearance(raw) {
        try {
            const settings = JSON.parse(raw)
            const resolved = settings.themeMode === "dark" ? true
                : settings.themeMode === "light" ? false : paletteDark
            dark = (settings.shellStyle === "material"
                || settings.glassFollowsAppearanceMode === true)
                ? resolved : true
        } catch (_) {
            // Keep the palette-derived value.
        }
    }

    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            required property var modelData
            screen: modelData
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            // Above the Shell's own surfaces and Plasma's splash so the login
            // screen is the only thing on screen until the arrival starts.
            WlrLayershell.namespace: "kos-splash"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            anchors { top: true; left: true; right: true; bottom: true }
            // Click-through: the session is already usable underneath.
            mask: Region {}

            Rectangle {
                anchors.fill: parent
                color: root.dark ? "#000000" : "#ffffff"
            }
            Item {
                anchors.centerIn: parent
                width: 44
                height: 44
                RotationAnimation on rotation {
                    from: 0
                    to: 360
                    duration: 900
                    loops: Animation.Infinite
                    running: true
                }
                Repeater {
                    model: 3
                    delegate: Rectangle {
                        width: 9
                        height: 9
                        radius: 4.5
                        color: root.dark ? "#ffffff" : "#000000"
                        opacity: [1, 0.6, 0.25][index]
                        x: 22 - width / 2
                            + Math.cos((index * 120 - 90) * Math.PI / 180) * 14
                        y: 22 - height / 2
                            + Math.sin((index * 120 - 90) * Math.PI / 180) * 14
                    }
                }
            }
        }
    }

    // Fallback if the Shell never reaches its arrival animation (crash, stuck
    // service): do not keep an invisible full-screen surface alive forever.
    Timer {
        interval: 30000
        running: true
        onTriggered: Qt.quit()
    }
}
