import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../../../shared/qml/controls" as LiquidControls
import "../../../shared/qml/foundation" as Foundation
import "../../../shared/qml/i18n"

LiquidControls.LiquidNavBar {
    required property var colors
    id: root
    size: "tiny"
    sizeToLabels: true
    Layout.minimumWidth: 0
    Layout.preferredWidth: implicitWidth
    Layout.maximumWidth: parent ? parent.width * 0.65 : implicitWidth
    accentColor: colors.role("primary", colors.dark ? "#64b5ff" : "#0066cc")
    selectedItemColor: root.materialForm
        ? colors.role("on_primary", "#ffffff") : accentColor
    itemColor: colors.dark ? "#ffffff" : "#1c1c1e"
    trackColor: colors.dark
        ? Qt.rgba(1, 1, 1, 0.10) : "#d1d1d6"
    labelFontPixelSize: 10
    labelFontWeight: Font.DemiBold
}
