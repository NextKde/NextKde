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
            const topLevel = ["NotificationsSettingsPage", "WallpaperSettingsPage", "ServicesSettingsPage"].indexOf(name) >= 0
            const component = Qt.createComponent((topLevel ? "../../" : "../../pages/") + name + ".qml")
            compare(component.status, Component.Ready, component.errorString())
            const properties = name === "NotificationsSettingsPage"
                ? {theme: harness.palette, width: 700} : {colors: harness.palette, width: 700}
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
        function collectSettingsItems(root) {
            let items = []
            if (root.isSettingsItem === true && root.visible) items.push(root)
            if (root.children && root.visible) {
                for (const child of root.children) items = items.concat(collectSettingsItems(child))
            }
            return items
        }
        function test_trailing_alignment_data() {
            const pages = ["ThemeSettingsPage", "DisplaySettingsPage", "DockSettingsPage",
                "BarSettingsPage", "LauncherSettingsPage", "WindowAnimationSettingsPage",
                "IconAppearanceSection", "WidgetAppearanceSection", "GlassDebugPage",
                "FgSchedSettingsPage", "ResourceSchedulingSettings", "ShortcutsSettingsPage",
                "IntegrationStatusPage", "PowerSettingsPage", "NotificationsSettingsPage",
                "WallpaperSettingsPage", "ServicesSettingsPage"]
            const cases = []
            for (const name of pages) {
                for (const width of [560, 306]) cases.push({tag: name + "-" + width, name: name, width: width})
            }
            return cases
        }
        function test_trailing_alignment(data) {
            const page = makePage(data.name)
            page.width = data.width
            if (data.name === "IconAppearanceSection") page.modeIndex = 2
            if (data.name === "NotificationsSettingsPage") page.state = {
                sources: [{key:"test",appName:"A notification source with a long name"}], blockedKeys: []
            }
            if (data.name === "ShortcutsSettingsPage") page.shortcuts = [{
                id:"test", description:"A shortcut", combo:"Meta+Space", defaultCombo:"Meta+Space", custom:true
            }]
            if (data.name === "ResourceSchedulingSettings")
                page.snapshot = {resourceSchedulingAvailable: true}
            if (data.name === "GlassDebugPage") {
                page.showAdvanced = true
                page.controls = [
                    {section:"Material",key:"RefractionStrength",label:"Refraction",type:"real",value:0.4,min:0,max:1,step:0.1},
                    {section:"Material",key:"Enabled",label:"Enabled",type:"bool",value:true},
                    {section:"Colour",key:"TintMode",label:"Tint",type:"int",value:1,min:0,max:2,step:1},
                    {section:"Colour",key:"Name",label:"Name",type:"string",value:"test"}
                ]
            }
            tryVerify(() => collectSettingsItems(page).length > 0)
            const rows = collectSettingsItems(page)
            for (const row of rows) {
                if (!row.hasControls) continue
                const slot = row.children.find(child => String(child).indexOf("QQuickRowLayout") >= 0)
                verify(slot !== undefined, row.title)
                tryVerify(() => Math.abs(slot.x + slot.width - (row.width - 16)) < 0.6,
                    1000, data.name + ": " + row.title + " controls must keep the right inset")
                const controls = slot.children.filter(child => child.visible && child.width > 0)
                for (const control of controls) {
                    if (control.labels !== undefined)
                        verify(control.labels.length < 3, row.title + " with 3 or more choices must use a dropdown")
                }
                if (!controls.length) continue
                const last = controls[controls.length - 1]
                tryVerify(() => Math.abs(last.x + last.width - slot.width) < 0.6, 1000,
                    data.name + ": " + row.title + " control must reach its slot's right edge: " + last.x + "+" + last.width + " vs " + slot.width)
                verify(last.height <= row.height, row.title + " must not clip the control")
            }
        }
        function test_settingsDropdowns_data() {
            return [
                {tag:"material", name:"ThemeSettingsPage", objectName:"themeMaterialStyleSelect", count:3},
                {tag:"display-material", name:"DisplaySettingsPage", objectName:"displayMaterialStyleSelect", count:3},
                {tag:"launcher", name:"LauncherSettingsPage", objectName:"launcherDisplayModeSelect", count:4},
                {tag:"icon-presets", name:"IconAppearanceSection", objectName:"iconTintPresetSelect", count:4}
            ]
        }
        function test_settingsDropdowns(data) {
            const page = makePage(data.name)
            if (data.name === "IconAppearanceSection") page.modeIndex = 2
            const picker = findChild(page, data.objectName)
            verify(picker !== null, data.objectName)
            compare(picker.model.length, data.count)
            compare(picker.indicatorStyle, "upDown")
            verify(picker.plainTrigger)
            verify(picker.indicatorBackground && picker.popupMaterialForm && picker.neutralOptionHighlight)
            compare(picker.sheetColor, "#f0f0f1")
            compare(picker.height, 24)
            compare(picker.textRole, "label")
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
        function test_history_toolbar_navigation() {
            const component = Qt.createComponent("../../main.qml")
            compare(component.status, Component.Ready, component.errorString())
            const app = createTemporaryObject(component, harness, {currentPage: 1})
            verify(app !== null, component.errorString())
            compare(app.width, 850)
            compare(app.height, 650)
            verify(!app.canGoBack)
            verify(!app.canGoForward)
            const actions = findChild(app.contentItem, "settingsHistoryNavigation")
            const title = findChild(app.contentItem, "settingsPageTitle")
            const lights = findChild(app.contentItem, "settingsWindowControls")
            const kdeSettings = findChild(app.contentItem, "settingsOpenKdeSettings")
            verify(actions !== null && title !== null && lights !== null && kdeSettings !== null)
            verify(waitForRendering(actions))
            const centerY = item => item.mapToItem(app.contentItem, item.width / 2, item.height / 2).y
            compare(centerY(actions), centerY(lights))
            compare(centerY(title), centerY(lights))
            compare(centerY(kdeSettings), centerY(lights))
            compare(kdeSettings.height, 26)
            const kdeLogo = findChild(kdeSettings, "settingsKdeLogo")
            verify(kdeLogo !== null)
            tryCompare(kdeLogo, "status", Image.Ready)
            const left = item => item.mapToItem(app.contentItem, 0, 0).x
            for (const width of [600, 850]) {
                app.width = width
                tryVerify(() => left(kdeSettings) + kdeSettings.width < left(lights))
                tryVerify(() => left(title) + title.width <= left(kdeSettings))
            }
            app.currentPage = 3
            app.currentPage = 2
            verify(app.canGoBack)
            const corner = grabImage(actions).pixel(0, 0)
            const rightCorner = grabImage(actions).pixel(actions.width - 1, 0)
            mouseMove(actions, 13, 13)
            verify(waitForRendering(actions))
            compare(grabImage(actions).pixel(0, 0), corner,
                    "hover must not fill the outside of the capsule")
            mouseClick(actions, 13, 13)
            compare(app.currentPage, 3)
            verify(app.canGoForward)
            mouseMove(actions, 39, 13)
            verify(waitForRendering(actions))
            compare(grabImage(actions).pixel(actions.width - 1, 0), rightCorner,
                    "forward hover must preserve the right endcap")
            mouseClick(actions, 39, 13)
            compare(app.currentPage, 2)
            mouseClick(actions, 13, 13)
            app.currentPage = 4
            verify(!app.canGoForward, "a new route after going back discards forward history")
            mouseClick(actions, 39, 13)
            compare(app.currentPage, 4, "disabled forward action cannot change the page")
            mouseClick(actions, 13, 13)
            compare(app.currentPage, 3)
            mouseClick(actions, 13, 13)
            compare(app.currentPage, 1)
            verify(!app.canGoBack)
            tryCompare(app, "displayedPage", 1)
            compare(title.text, app.contentByPage[1].subtitle)
            const initial = createTemporaryObject(component, harness, {currentPage: 11})
            verify(initial !== null)
            verify(!initial.canGoBack, "a directly opened page starts its own history")
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
