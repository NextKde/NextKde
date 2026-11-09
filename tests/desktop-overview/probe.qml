import QtQuick
import org.kde.kwin as KW

// Loaded inside the private KWin, exercising its actual background selector
// rather than a replacement implementation in the test process.
Item {
    id: root
    property int stage: 0
    property int attempts: 0
    property var widget: null
    property var wallpaper: null
    property var background: null

    function check(condition, message) {
        if (!condition) throw new Error(message)
    }
    function surfaces() {
        // The declarative Workspace exposes a QML list; windowList() belongs
        // to the separate JavaScript scripting wrapper.
        const windows = KW.Workspace.windows
        const result = []
        for (let index = 0; index < windows.length; ++index) {
            if (String(windows[index].resourceClass).includes("quickshell"))
                result.push(windows[index])
        }
        return result
    }
    Component {
        id: backgroundComponent
        KW.DesktopBackground {}
    }
    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            try {
                check(++root.attempts < 100, "surfaces did not become ready")
                const windows = root.surfaces()
                if (root.stage === 0) {
                    // Wait for both map orders to finish committing buffers.
                    if (windows.length < 2) return
                    check(windows.length === 2, "expected exactly two isolated shell surfaces")
                    root.wallpaper = windows.find(window => window.windowType === 1)
                    root.widget = windows.find(window => window.windowType === 2)
                    check(root.wallpaper && root.widget, "wallpaper must be Desktop and widgets must be Dock")
                    if (root.wallpaper.hidden || root.widget.hidden) return
                    check(root.widget.layer === 1 && root.wallpaper.layer === 1,
                        "both surfaces must retain Below stacking")
                    check(root.widget.onAllDesktops, "widgets must remain on every desktop")
                    check(root.widget.skipSwitcher && root.widget.skipPager && root.widget.skipTaskbar,
                        "widgets must stay out of application models")
                    const output = KW.Workspace.screens[0]
                    check(root.wallpaper.width === output.geometry.width
                        && root.wallpaper.height === output.geometry.height,
                        "wallpaper must cover the output")
                    // The isolated compositor runs with --no-kactivities.
                    // An empty activity asks DesktopBackground to dereference
                    // Workspace::activities(), which is null in that mode.
                    // Both shell surfaces belong to every activity, so an
                    // explicit activity still exercises the native selector.
                    root.background = backgroundComponent.createObject(root, {
                        outputName: output.name,
                        activity: "00000000-0000-0000-0000-000000000000"
                    })
                    check(root.background && root.background.client === root.wallpaper,
                        "native DesktopBackground selected transparent widgets instead of wallpaper")
                    KW.Workspace.activeWindow = root.widget
                    check(KW.Workspace.activeWindow === root.widget, "focus desktop widgets before shortcut checks")
                    KW.Workspace.slotWindowClose()
                    KW.Workspace.slotWindowMove()
                } else if (root.stage === 1) {
                    check(windows.includes(root.widget) && !root.widget.hidden,
                        "ordinary close/move shortcuts must preserve desktop widgets")
                    KW.Workspace.slotToggleShowDesktop()
                } else if (root.stage === 2) {
                    check(!root.widget.hidden && !root.wallpaper.hidden,
                        "Show Desktop must preserve both surfaces")
                    KW.Workspace.slotToggleShowDesktop()
                } else {
                    check(root.background.client === root.wallpaper,
                        "background selection must survive focus and Show Desktop")
                    console.log("DESKTOP_OVERVIEW_NATIVE_PASS")
                    stop()
                }
                root.stage++
            } catch (error) {
                console.error("DESKTOP_OVERVIEW_NATIVE_FAIL: " + error)
                stop()
            }
        }
    }
}
