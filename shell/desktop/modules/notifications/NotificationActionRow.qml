import QtQuick
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../Kos/Ui"

// One action row in the shell's row-button language (see MenuItemRow):
// a glass selection plate over the chips' resting fill, a centered label.
// Shared by the banner's expanded overflow list and the history cards.
// Both feed a display-ready (already translated) label and answer the
// activated signal with their own invoke path; the row owns only looks.
Rectangle {
    id: row

    property string label: ""
    property color textColor: ThemeService.foregroundColor
    signal activated()

    width: parent ? parent.width : 0
    height: 32
    radius: AppearanceTokens.shape.medium
    color: AppearanceTokens.surface.selectionHighlightStyle === "glass"
        ? (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.04))
        : (rowMouse.containsMouse
            ? (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.10))
            : "transparent")

    SelectionHighlight {
        anchors.fill: parent
        cornerRadius: parent.radius
        enabled: AppearanceTokens.surface.selectionHighlightStyle === "glass"
        hovered: rowMouse.containsMouse
        pressed: rowMouse.pressed
        dark: ThemeService.isDark
        fillStrength: 0.85
    }

    GlassText {
        anchors.centerIn: parent
        width: parent.width - 20
        text: row.label
        color: row.textColor
        font.pixelSize: 12
        elide: Text.ElideRight
    }

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.activated()
    }
}
