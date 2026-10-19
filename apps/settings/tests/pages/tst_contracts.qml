import QtQuick
import QtTest

Item {
    id: harness
    width: 1000
    height: 800

    // No application window, context properties or real IPC service: a page
    // must be usable solely through the inputs documented in pages/README.md.
    readonly property var palette: ({
        dark: false, background: "#eff0f1", sidebar: "#eff0f1",
        contentSurface: "#e3e5e7", primaryText: "#1c1c1e",
        secondaryText: "#6d6d72", tertiaryText: "#8e8e93",
        card: "#ffffff", separator: "#e5e5ea", divider: "#d1d1d6",
        searchField: "#e3e3e8", selected: "#d9e9ff", selectedContainer: "#eeeeee",
        sidebarHover: "#eeeeee", chevron: "#c7c7cc", iconForeground: "#ffffff",
        iconMuted: "#6d6d72", selectedForeground: "#00325b", accent: "#0a84ff",
        floatingBorder: "#dddddd", floatingShadow: "#aaaaaa", previewPane: "#eef2f7",
        previewBar: "#ffffff", previewTaskbar: "#eeeeee", previewDock: "#ffffff",
        previewIcon: "#7c8290", role: function(name, fallback) { return fallback }
    })
    readonly property var styles: ({
        options: [{id: "liquid", label: "Liquid"}, {id: "soft", label: "Soft"},
                  {id: "frosted", label: "Frosted"}],
        indexOf: function(value) { return this.options.findIndex(x => x.id === value) },
        labelOf: function(value) { return String(value) }
    })
    // The appearance bridge the font switch is checked against. Its reply is
    // asynchronous, like the Shell's: the write goes out now and the snapshot
    // that moves the page value comes back on a later event-loop turn. A switch
    // that guessed its own new state instead of waiting for that snapshot would
    // pass a synchronous fake and fail against this one.
    QtObject {
        id: appearanceBridge
        property string lastError: ""
        property var fontCalls: []
        property bool useSystemFont: false
        property int replyDelay: 0
        signal appearanceSnapshotChanged(var state)

        function updateUseSystemFont(enabled) {
            fontCalls = fontCalls.concat([enabled])
            replyTimer.wanted = enabled
            replyTimer.restart()
        }
        function appearanceSnapshot() {
            appearanceSnapshotChanged(snapshot(useSystemFont))
        }
        function snapshot(enabled) {
            return {globalBlurStrength: 0.4, globalLiquidStrength: 1,
                glassStyle: "liquid", shellStyle: "macos",
                useSystemFont: enabled, systemFontFamily: "Maple Mono NF CN",
                glassFollowsAppearanceMode: false, spatialWallpaperEnabled: false}
        }
    }
    Timer {
        id: replyTimer
        property bool wanted: false
        repeat: false
        interval: appearanceBridge.replyDelay
        onTriggered: {
            appearanceBridge.useSystemFont = wanted
            appearanceBridge.appearanceSnapshotChanged(
                appearanceBridge.snapshot(wanted))
        }
    }

    SignalSpy { id: styleSpy; signalName: "shellStyleObserved" }
    SignalSpy { id: seedSpy; signalName: "materialSeedObserved" }
    SignalSpy { id: settingSpy; signalName: "settingRequested" }

    TestCase {
        name: "SettingsPageContracts"
        when: windowShown

        function init() {
            failOnWarning(/ReferenceError|TypeError|Unable to assign|Binding loop|Cannot assign/)
        }
        function cleanup() {
            styleSpy.target = null
            seedSpy.target = null
            settingSpy.target = null
            styleSpy.clear()
            seedSpy.clear()
            settingSpy.clear()
        }
        function makePage(name) {
            const component = Qt.createComponent("../../pages/" + name + ".qml")
            compare(component.status, Component.Ready, component.errorString())
            const properties = {colors: harness.palette, width: 700}
            if (["ThemeSettingsPage", "DisplaySettingsPage", "GlassDebugPage"].indexOf(name) >= 0)
                properties.glassStyles = harness.styles
            const page = createTemporaryObject(component, harness, properties)
            verify(page !== null, component.errorString())
            return page
        }
        function test_isolated_load_data() {
            return ["FgSchedSettingsPage", "IntegrationStatusPage", "DockSettingsPage",
                    "DisplaySettingsPage", "GlassDebugPage", "WidgetAppearanceSection",
                    "IconAppearanceSection", "WindowAnimationSettingsPage", "ThemeSettingsPage",
                    "BarSettingsPage", "ShortcutsSettingsPage", "LauncherSettingsPage",
                    "ResourceSchedulingSettings"]
                .map(name => ({tag: name, name: name}))
        }
        function test_isolated_load(data) {
            const page = makePage(data.name)
            if (data.name === "ResourceSchedulingSettings") {
                compare(page.implicitHeight, 0, "unavailable scheduler hides resource controls")
                page.snapshot = {resourceSchedulingAvailable: true}
            }
            tryVerify(() => page.implicitHeight > 0)
        }
        function test_theme_reports_confirmed_state() {
            const page = makePage("ThemeSettingsPage")
            styleSpy.target = page
            seedSpy.target = page
            page.applyState({shellStyle: "invalid"})
            compare(styleSpy.count, 0)
            page.applyState({shellStyle: "material", materialColorScheme: "monet",
                materialColorSwatches: '[{"id":"monet","colors":["#123456"]}]'})
            compare(styleSpy.count, 1)
            compare(styleSpy.signalArguments[0][0], "material")
            compare(seedSpy.signalArguments[0][0], "#123456")
            page.applyState({shellStyle: "macos", materialColorSwatches: "broken-json"})
            compare(seedSpy.signalArguments[1][0], "")
        }
        // 使用系统字体: one click must be enough. The switch's `checked` is a
        // binding to the page value, and QML does not restore a binding that was
        // assigned to, so an onToggled handler that writes the confirmed value
        // back into `checked` kills the binding on the first click. The switch
        // then keeps showing the old state while the Shell has already applied
        // the new one, and the next click re-sends the same request -- the
        // "needs several clicks" report this test exists to prevent.
        function test_system_font_switch_needs_one_click() {
            appearanceBridge.fontCalls = []
            appearanceBridge.useSystemFont = false
            appearanceBridge.replyDelay = 0
            const page = createTemporaryObject(
                Qt.createComponent("../../pages/DisplaySettingsPage.qml"), harness,
                {colors: harness.palette, width: 700, glassStyles: harness.styles,
                    bridge: appearanceBridge})
            verify(page !== null)
            page.applyState(appearanceBridge.snapshot(false))
            let control = null
            function walk(item) {
                for (let i = 0; i < item.children.length; ++i) {
                    const child = item.children[i]
                    if (child.objectName === "use-system-font-switch")
                        control = child
                    walk(child)
                }
            }
            walk(page)
            verify(control !== null, "the font switch is laid out")
            compare(control.checked, false, "the saved value is off")

            // Click, then let the asynchronous reply land.
            mouseClick(control)
            compare(appearanceBridge.fontCalls.length, 1, "one click sends one write")
            tryVerify(() => control.checked === true, 1000)
            compare(page.useSystemFont, true)

            // And back, which is where a destroyed binding showed up as a switch
            // that refused to move at all.
            mouseClick(control)
            compare(appearanceBridge.fontCalls.length, 2)
            compare(appearanceBridge.fontCalls[1], false)
            tryVerify(() => control.checked === false, 1000)
        }

        function test_navigation_releases_inactive_pages() {
            const component = Qt.createComponent("../../main.qml")
            compare(component.status, Component.Ready, component.errorString())
            const app = createTemporaryObject(component, harness, {currentPage: 1})
            verify(app !== null, component.errorString())
            const routes = [
                [1, "ThemeSettingsPageLoader"], [3, "DockSettingsPageLoader"],
                [4, "LauncherSettingsPageLoader"], [5, "ShortcutsSettingsPageLoader"],
                [6, "IntegrationStatusPageLoader"], [7, "GlassDebugPageLoader"],
                [10, "FgSchedSettingsPageLoader"], [2, "BarSettingsPageLoader"],
                [11, "windowPageLoader"], [1, "ThemeSettingsPageLoader"]
            ]
            let previous = null
            for (const route of routes) {
                app.currentPage = route[0]
                const loader = findChild(app.contentItem, route[1])
                verify(loader !== null, route[1])
                tryVerify(() => loader.item !== null, 3000)
                compare(loader.status, Loader.Ready)
                verify(loader.visible)
                if (previous !== null) {
                    tryVerify(() => previous.item === null)
                    verify(!previous.visible, "inactive page must not leave a layout gap")
                }
                previous = loader
            }
        }
    }
}
