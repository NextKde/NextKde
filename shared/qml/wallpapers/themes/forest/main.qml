import QtQuick
// 显式导入自身目录:文档位于被 import 的模块目录树内时,同目录隐式类型
// 解析会被模块机制短路,限定导入绕开该行为。
import "." as Theme

// 萤火森林:月光薄雾与近景萤火(NatureWallpaper 的 forest 分支 + ForestFireflies)。
Item {
    id: root
    // ---- pack contract ----
    property var host: null
    signal frameReady()
    property string themeId: "forest"
    property real phase: host ? host.phase : 0
    property bool foreground: host ? host.foreground : false
    property bool economical: host ? host.economical : false
    property var widgetRects: host ? host.widgetRects : []
    property vector4d pointer: host ? host.pointer : Qt.vector4d(-10,-10,0,0)
    property vector4d clickPulse: host ? host.clickPulse : Qt.vector4d(-10,-10,-100,0)
    // ---- scene ----
    Theme.NatureWallpaper {
        anchors.fill: parent
        themeId: "forest"
        phase: root.phase
        foreground: root.foreground
        economical: root.economical
        pointer: root.pointer
        clickPulse: root.clickPulse
        widgetRects: root.widgetRects
        onFrameReady: root.frameReady()
    }
}
