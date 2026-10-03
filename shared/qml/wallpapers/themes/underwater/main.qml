import QtQuick
// 显式导入自身目录:文档位于被 import 的模块目录树内时,同目录隐式类型
// 解析会被模块机制短路,限定导入绕开该行为。
import "." as Theme

// 水下光影:流动焦散与穿透水光(NatureWallpaper 的水下分支)。
Item {
    id: root
    // ---- pack contract ----
    property var host: null
    signal frameReady()
    property string themeId: "underwater"
    property real phase: host ? host.phase : 0
    property bool foreground: host ? host.foreground : false
    property bool economical: host ? host.economical : false
    property var widgetRects: host ? host.widgetRects : []
    property vector4d pointer: host ? host.pointer : Qt.vector4d(-10,-10,0,0)
    property vector4d clickPulse: host ? host.clickPulse : Qt.vector4d(-10,-10,-100,0)
    // ---- scene ----
    Theme.NatureWallpaper {
        anchors.fill: parent
        themeId: "underwater"
        phase: root.phase
        foreground: root.foreground
        economical: root.economical
        pointer: root.pointer
        clickPulse: root.clickPulse
        widgetRects: root.widgetRects
        onFrameReady: root.frameReady()
    }
}
