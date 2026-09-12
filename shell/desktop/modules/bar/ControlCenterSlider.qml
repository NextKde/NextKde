import QtQuick
import "../../../shared/qml/controls" as LiquidControls

// One visual language for every slider inside Control Center. Feature rows
// provide only geometry, value, and behavior; track/thumb styling lives here.
LiquidControls.LiquidSlider {
    height: 30
    trackHeight: 4
    trackColor: Qt.rgba(1, 1, 1, 0.17)
    accentColor: Qt.rgba(1, 1, 1, 0.42)
    thumbColor: "#ffffff"
    thumbBorderColor: "transparent"
}
