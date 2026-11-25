// The login screen, drawn by its own small Quickshell instance.
//
// The desktop Shell builds every window on one GUI thread, and that thread is
// busy for the whole time the login screen is up. Anything animated from
// inside it stands still exactly when it matters, so the spinner lives here
// instead: this config owns nothing but a background with three dots, and its
// event loop has nothing else to do. The background is the appearance's black
// (dark) or white (light) surface, or the picture chosen in Settings → Theme →
// Desktop arrival. Started by kos-shell.service in parallel with the Shell,
// stopped by StartupSplash.qml once the arrival animation begins.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "SplashBackgroundPolicy.mjs" as SplashBackground

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

    // The picture chosen in Settings → Theme → Desktop arrival. This process
    // starts before the desktop's appearance service exists, so it reads the
    // fields straight from the same appearance file. A hand-edited or stale
    // value falls back to the solid surface: the mode must be "image" and the
    // path must be a local absolute path before it reaches Image.source.
    property string splashBackgroundMode: "solid"
    property string splashBackgroundImage: ""
    readonly property string splashImage: SplashBackground.activeImage(
        splashBackgroundMode, splashBackgroundImage)

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
            const mode = String(settings.splashBackgroundMode ?? "")
            splashBackgroundMode = SplashBackground.isValidBackgroundMode(mode)
                ? mode : "solid"
            splashBackgroundImage = SplashBackground.normalizeImagePath(
                settings.splashBackgroundImage)
        } catch (_) {
            // Keep the palette-derived value.
        }
    }

    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            id: splashSurface
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

            // A visible picture is always dimmed black, so the spinner and the
            // signature switch to light ink no matter which appearance the
            // solid surface would have used. Without a picture this is just
            // the light/dark appearance decision.
            readonly property bool lightInk: root.dark || pictureLayer.visible

            Rectangle {
                anchors.fill: parent
                color: root.dark ? "#000000" : "#ffffff"
            }
            // The chosen picture, dimmed so the spinner and the signature keep
            // their contrast on any photo. A picture has no guaranteed
            // luminance, so this layer always uses a black scrim and light ink
            // rather than following the appearance; the solid surface keeps
            // its light/dark pairing. Both appear at once, so the ink never
            // flips before there is a picture behind it.
            Item {
                id: pictureLayer
                anchors.fill: parent
                visible: picture.status === Image.Ready
                Image {
                    id: picture
                    anchors.fill: parent
                    source: root.splashImage
                    // Decode at the size the surface actually paints, not at
                    // the source photo's full resolution: an 8K picture must
                    // not cost 100 MB of texture while the desktop builds.
                    sourceSize: Qt.size(
                        Math.max(1, Math.ceil(width * Screen.devicePixelRatio)),
                        Math.max(1, Math.ceil(height * Screen.devicePixelRatio)))
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    smooth: true
                }
                Rectangle {
                    anchors.fill: parent
                    color: "#000000"
                    opacity: 0.45
                }
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
                        color: splashSurface.lightInk ? "#ffffff" : "#000000"
                        opacity: [1, 0.6, 0.25][index]
                        x: 22 - width / 2
                            + Math.cos((index * 120 - 90) * Math.PI / 180) * 14
                        y: 22 - height / 2
                            + Math.sin((index * 120 - 90) * Math.PI / 180) * 14
                    }
                }
            }
            // Brand lockup in the corner, laid out like Plasma's splash: the
            // text, then the mark, anchored to the bottom-right. Plasma themes
            // measure this in grid units (one for the margin, two for the mark)
            // and use the system font for the text; derive the same unit from
            // the default font so the sizes stay proportional to the session's
            // font settings. The logo loads from the same light/dark asset pair
            // the About page uses. Decoration only: the spinner stays the one
            // moving element so the splash remains cheap on software renderers.
            TextMetrics {
                id: units
                text: "M"
            }
            Row {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: units.boundingRect.height
                spacing: Math.max(2, Math.floor(units.boundingRect.height / 2))
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "by NextKDE"
                    color: splashSurface.lightInk ? "#eff0f1" : "#232629"
                }
                Image {
                    width: units.boundingRect.height * 2
                    height: units.boundingRect.height * 2
                    source: splashSurface.lightInk ? "nextkde-logo-dark.svg" : "nextkde-logo.svg"
                    sourceSize: Qt.size(units.boundingRect.height * 4,
                        units.boundingRect.height * 4)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
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
