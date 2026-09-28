import QtQuick
import QtTest

Item {
    property var settingsBridge: bridge
    QtObject {
        id: bridge
        property bool sourceTreeEntry: false
        property string sessionShellDir: ""
        property bool developmentBannerDismissed: false
        property string lastError: ""
        property var snapshot: ({shellStyle: "macos", widgetStyle: "color", iconMode: "color"})
        property var calls: []
        signal appearanceSnapshotChanged(var state)
        signal systemAppearanceApplied(bool accepted)
        function appearanceSnapshot() { appearanceSnapshotChanged(snapshot) }
        function updateWidgetStyle(style) { calls = calls.concat([style]) }
    }
    TestCase {
        name: "WidgetAppearanceSettings"
        when: windowShown
        function test_confirmed_selection() {
            const component = Qt.createComponent("../../main.qml")
            compare(component.status, Component.Ready, component.errorString())
            const app = component.createObject(null, {currentPage: 1})
            verify(app !== null)
            tryVerify(() => findChild(app.contentItem, "widget-style-picker") !== null)
            const picker = findChild(app.contentItem, "widget-style-picker")
            const scroll = findChild(app.contentItem, "settings-page-scroll")
            scroll.contentY = picker.mapToItem(scroll.contentItem, 0, 0).y - 80
            verify(waitForRendering(picker))
            compare(picker.currentIndex, 0)
            mouseClick(picker, picker.width * 0.75, picker.height / 2)
            compare(bridge.calls.length, 1)
            compare(bridge.calls[0], "glass")
            compare(picker.currentIndex, 0, "unconfirmed request preserves displayed state")
            bridge.snapshot = Object.assign({}, bridge.snapshot, {widgetStyle: "glass"})
            bridge.appearanceSnapshot()
            compare(picker.currentIndex, 1, "reply updates the binding")
            compare(bridge.snapshot.iconMode, "color", "widget request leaves icons coloured")
            mouseClick(picker, picker.width * 0.25, picker.height / 2)
            compare(bridge.calls[1], "color")
            bridge.lastError = "save failed"
            bridge.appearanceSnapshotChanged({})
            compare(picker.currentIndex, 1, "failure keeps the last confirmed style")
            bridge.lastError = ""
            bridge.snapshot = Object.assign({}, bridge.snapshot, {widgetStyle: "color", iconMode: "grayscale"})
            bridge.appearanceSnapshot()
            compare(picker.currentIndex, 0, "later external snapshot still updates the picker")
            compare(bridge.calls.length, 2, "snapshots never write settings")
            bridge.snapshot = Object.assign({}, bridge.snapshot, {shellStyle: "material"})
            bridge.appearanceSnapshot()
            verify(picker.disabled, "Material keeps its tonal surface policy")
            app.destroy()
        }
    }
}
