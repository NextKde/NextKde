import QtQuick
import Kos.Ui
import Kos.Demo as Demo

Item {
    id: root
    property Demo.LiquidBackdrop backdrop: null
    property real radius: 12
    property bool liquidEnabled: AppTheme.materialMode !== "solid" && !AppTheme.reduceTransparency
    property real coverage: 0.7
    property color fallbackColor: AppTheme.dark ? "#2C2C2E" : "#F7F7F9"
    readonly property real effectiveCoverage: Math.min(0.98, coverage * AppTheme.materialOpacity / 0.86)
    readonly property bool sampling: liquidEnabled && glass.sampling
    Demo.LiquidSurface {
        id: glass
        anchors.fill: parent
        radius: root.radius
        backdrop: root.liquidEnabled ? root.backdrop : null
        visible: root.sampling
        tintStrength: root.effectiveCoverage
    }
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: !root.sampling
        color: root.fallbackColor
    }
}
