import QtQuick
import QtTest
Item {
    property var windowSettings: backend
    property var settingsBridge: bridgeBackend
    QtObject {
        id: bridgeBackend
        property var apps: []
        property int runningAppsRequests: 0
        signal fgSchedRunningAppsChanged(var apps)
        function fgSchedRunningApps() {
            runningAppsRequests += 1
            fgSchedRunningAppsChanged(apps)
        }
    }
    QtObject {
        id: backend
        property var state: ({enabled:true, radius:20, shadow:true, hideAnimation:"scale", closeAnimation:"scale", buttonGlyphMode:"always", buttonExclusions:[], independentButtonBackground:false})
        property bool animationBusy: false
        property string error: ""
        property var calls: []
        function refresh() {}
        function change(key, value) {
            calls = calls.concat([{key:key, value:value}])
            state = Object.assign({}, state, {[key]:value})
        }
        function setRadius(value) { change("radius", value); return true }
        function setSquareMaximized(value) { change("squareMaximized", value); return true }
        function setShadow(value) { change("shadow", value); return true }
        function setTakeover(value) { change("enabled", value); return true }
        function requestAnimation(kind, value) { change(kind + "Animation", value); return true }
        function setIndependentButtonBackground(value) { change("independentButtonBackground", value); return true }
        function setButtonGlyphMode(value) { change("buttonGlyphMode", value); return true }
        function setButtonExclusion(value, excluded) {
            const klass = value.trim()
            if (!klass) return false
            let exclusions = (state.buttonExclusions || []).filter(item => item !== klass)
            if (excluded) exclusions.push(klass)
            exclusions.sort()
            change("buttonExclusions", exclusions)
            return true
        }
    }
    TestCase {
        name: "WindowSettingsInteractions"
        when: windowShown
        property var app: null
        function init() {
            backend.calls = []
            backend.state = {enabled:true, radius:20, shadow:true, hideAnimation:"scale", closeAnimation:"scale", buttonGlyphMode:"always", buttonExclusions:[], independentButtonBackground:false}
            bridgeBackend.apps = [{name:"Firefox", appId:"firefox"}, {name:"Obsidian", appId:"md.obsidian.Obsidian"}]
            bridgeBackend.runningAppsRequests = 0
            const component = Qt.createComponent("../../main.qml")
            compare(component.status, Component.Ready, component.errorString())
            app = component.createObject(null, {currentPage:11})
            verify(app !== null)
            tryVerify(() => findChild(app.contentItem, "windowAppearancePage") !== null)
            tryVerify(() => bridgeBackend.runningAppsRequests === 1)
            verify(waitForRendering(app.contentItem))
        }
        function cleanup() { app.destroy(); app = null }
        function control(name) {
            const item = findChild(app.contentItem, name)
            verify(item !== null, name)
            const scroll = findChild(app.contentItem, "settings-page-scroll")
            verify(scroll !== null)
            scroll.contentY = Math.max(0, Math.min(scroll.contentHeight - scroll.height,
                item.mapToItem(scroll.contentItem, 0, 0).y - 100))
            verify(waitForRendering(item))
            return item
        }
        function test_switches() {
            const shadow = control("windowShadowSwitch")
            mouseClick(shadow, shadow.width/2, shadow.height/2)
            compare(backend.state.shadow, false)
            const takeover = control("windowTakeoverSwitch")
            mouseClick(takeover, takeover.width/2, takeover.height/2)
            compare(backend.state.enabled, false)
            verify(!control("windowRadiusSlider").enabled)
            compare(backend.state.hideAnimation, "scale", "appearance switch leaves animations independent")
        }
        function test_radius_stops() {
            const slider = control("windowRadiusSlider")
            const stops = [0,8,12,20,28,36]
            for (let i=0; i<stops.length; ++i) {
                mouseClick(slider, slider.edgeInset + slider.travel * i/5, slider.height/2)
                compare(backend.state.radius, stops[i])
            }
            const count=backend.calls.length
            slider.previewChanged(0.4)
            compare(backend.calls.length, count, "preview does not save")
            slider.canceled()
            compare(backend.state.radius, 36, "cancel preserves saved radius")
        }
        function test_square_maximized() {
            const toggle = control("windowSquareMaximizedSwitch")
            compare(toggle.checked, false, "older snapshots keep the existing rounded behavior")
            mouseClick(toggle, toggle.width/2, toggle.height/2)
            compare(backend.state.squareMaximized, true)
            compare(backend.state.radius, 20, "normal-window radius is preserved")
            mouseClick(toggle, toggle.width/2, toggle.height/2)
            compare(backend.state.squareMaximized, false)
            backend.state = Object.assign({}, backend.state, {squareMaximized:true})
            tryCompare(toggle, "checked", true, 1000, "show the confirmed backend preference")
            backend.state = Object.assign({}, backend.state, {enabled:false})
            tryCompare(toggle, "enabled", false)
            const count = backend.calls.length
            mouseClick(toggle, toggle.width/2, toggle.height/2)
            compare(backend.calls.length, count, "disabled appearance cannot save")
        }
        function test_animation_choices() {
            for (const kind of ["hide", "close"]) {
                const picker=control(kind === "hide" ? "windowHideAnimation" : "windowCloseAnimation")
                const styles=kind === "hide" ? ["none","scale","genie"] : ["none","fade","scale"]
                for (let i=0;i<3;++i) {
                    mouseClick(picker, picker.width / 2, picker.height / 2)
                    tryVerify(() => picker.popupOpened)
                    keyClick(Qt.Key_Home)
                    for (let next = 0; next < i; ++next) keyClick(Qt.Key_Down)
                    keyClick(Qt.Key_Return)
                    tryVerify(() => !picker.popupOpened)
                    compare(backend.state[kind+"Animation"], styles[i])
                }
            }
        }
        function test_running_app_exclusion() {
            const picker = control("windowButtonRunningApps")
            tryVerify(() => picker.model.length === 2)
            compare(picker.model[0].appId, "firefox")
            const add = control("addRunningWindowButtonExclusion")
            mouseClick(add, add.width / 2, add.height / 2)
            compare(backend.state.buttonExclusions, ["firefox"])
            tryVerify(() => picker.model.length === 1)
            compare(picker.model[0].appId, "md.obsidian.Obsidian", "excluded apps cannot be added twice")
            verify(findChild(app.contentItem, "windowButtonExclusionRow_firefox") !== null)
        }
        function test_manual_exclusion_and_removal() {
            const input = control("windowButtonExclusionInput")
            const add = control("addManualWindowButtonExclusion")
            verify(!add.enabled)
            input.text = "   "
            verify(!add.enabled)
            input.text = " firefox "
            mouseClick(add, add.width / 2, add.height / 2)
            compare(backend.state.buttonExclusions, ["firefox"])
            compare(input.text, "")
            input.text = "firefox"
            mouseClick(add, add.width / 2, add.height / 2)
            compare(backend.state.buttonExclusions, ["firefox"], "duplicate manual entry remains one exclusion")
            const row = control("windowButtonExclusionRow_firefox")
            const remove = findChild(row, "removeWindowButtonExclusion")
            verify(remove !== null)
            mouseClick(remove, remove.width / 2, remove.height / 2)
            compare(backend.state.buttonExclusions, [])
            tryVerify(() => findChild(app.contentItem, "windowButtonExclusionRow_firefox") === null)
        }
        function test_running_apps_refresh_keeps_manual_fallback() {
            bridgeBackend.apps = []
            bridgeBackend.fgSchedRunningApps()
            const picker = control("windowButtonRunningApps")
            compare(picker.model.length, 0)
            verify(!picker.enabled)
            verify(!control("addRunningWindowButtonExclusion").enabled)
            const refresh = control("refreshWindowButtonRunningApps")
            const requests = bridgeBackend.runningAppsRequests
            mouseClick(refresh, refresh.width / 2, refresh.height / 2)
            compare(bridgeBackend.runningAppsRequests, requests + 1)
            const input = control("windowButtonExclusionInput")
            input.text = "md.obsidian.Obsidian"
            verify(control("addManualWindowButtonExclusion").enabled)
        }
        function test_refresh_nonempty_running_apps_preserves_selection() {
            const picker = control("windowButtonRunningApps")
            picker.activated(1)
            compare(picker.model[picker.currentIndex].appId, "md.obsidian.Obsidian")
            bridgeBackend.apps = [
                {name:"Kate", appId:"org.kde.kate"},
                {name:"Firefox", appId:"firefox"},
                {name:"Obsidian", appId:"md.obsidian.Obsidian"}
            ]
            const requests = bridgeBackend.runningAppsRequests
            const refresh = control("refreshWindowButtonRunningApps")
            mouseClick(refresh, refresh.width / 2, refresh.height / 2)
            compare(bridgeBackend.runningAppsRequests, requests + 1)
            compare(picker.model.length, 3)
            compare(picker.model[picker.currentIndex].appId, "md.obsidian.Obsidian")
            const add = control("addRunningWindowButtonExclusion")
            mouseClick(add, add.width / 2, add.height / 2)
            compare(backend.state.buttonExclusions, ["md.obsidian.Obsidian"])
            compare(picker.model[picker.currentIndex].appId, "org.kde.kate")
            verify(control("windowButtonExclusionIcon_md.obsidian.Obsidian").visible)
        }
        function test_independent_cover() {
            const toggle = control("windowIndependentButtonBackground")
            mouseClick(toggle, toggle.width/2, toggle.height/2)
            compare(backend.state.independentButtonBackground, true)
            mouseClick(toggle, toggle.width/2, toggle.height/2)
            compare(backend.state.independentButtonBackground, false)
            backend.state = Object.assign({}, backend.state, {enabled:false})
            tryCompare(toggle, "enabled", false)
            const count = backend.calls.length
            mouseClick(toggle, toggle.width/2, toggle.height/2)
            compare(backend.calls.length, count, "disabled cover switch cannot save")
        }
        function test_button_glyph_mode() {
            const picker = control("windowButtonGlyphMode")
            const modes = ["always", "hover"]
            for (let i = 0; i < 2; ++i) {
                mouseClick(picker, picker.width * (i + 0.5) / 2, picker.height / 2)
                compare(backend.state.buttonGlyphMode, modes[i])
            }
        }
    }
}
