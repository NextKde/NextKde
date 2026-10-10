import QtQuick
import QtTest
Item {
    property var windowSettings: backend
    QtObject {
        id: backend
        property var state: ({enabled:true, radius:20, shadow:true, hideAnimation:"scale", closeAnimation:"scale"})
        property string error: ""
        property var calls: []
        function refresh() {}
        function change(key, value) {
            calls = calls.concat([{key:key, value:value}])
            state = Object.assign({}, state, {[key]:value})
        }
        function setRadius(value) { change("radius", value); return true }
        function setShadow(value) { change("shadow", value); return true }
        function setTakeover(value) { change("enabled", value); return true }
        function setAnimation(kind, value) { change(kind + "Animation", value); return true }
    }
    TestCase {
        name: "WindowSettingsInteractions"
        when: windowShown
        property var app: null
        function init() {
            backend.calls = []
            backend.state = {enabled:true, radius:20, shadow:true, hideAnimation:"scale", closeAnimation:"scale"}
            const component = Qt.createComponent("../../main.qml")
            compare(component.status, Component.Ready, component.errorString())
            app = component.createObject(null, {currentPage:11})
            verify(app !== null)
            tryVerify(() => findChild(app.contentItem, "windowAppearancePage") !== null)
        }
        function cleanup() { app.destroy(); app = null }
        function control(name) {
            const item = findChild(app.contentItem, name)
            verify(item !== null, name)
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
        function test_animation_choices() {
            for (const kind of ["hide", "close"]) {
                const picker=control(kind === "hide" ? "windowHideAnimation" : "windowCloseAnimation")
                const styles=kind === "hide" ? ["none","scale","genie"] : ["none","fade","scale"]
                for (let i=0;i<3;++i) {
                    mouseClick(picker, picker.width * (i+0.5)/3, picker.height/2)
                    compare(backend.state[kind+"Animation"], styles[i])
                }
            }
        }
    }
}
