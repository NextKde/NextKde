import Quickshell
import QtQuick
import qs.desktop.modules.common
import qs.desktop.modules.dock

// Reusable date/time cluster shared by the standalone top Bar and the
// bottom unified Dock host. It owns no layer-shell geometry.
Item {
    id: root

    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Row {
        id: content
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        GlassText {
            id: timeText
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(clock.date, "h:mm")
            color: ThemeService.foregroundColor
            renderType: Text.NativeRendering
            font {
                family: AppearanceTokens.typography.displayFamily
                pixelSize: 14
                weight: Font.Medium
            }
        }

        GlassText {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(clock.date, "M月d日 dddd")
            color: ThemeService.foregroundColor
            renderType: Text.NativeRendering
            font {
                family: AppearanceTokens.typography.displayFamily
                pixelSize: 14
                weight: Font.Medium
            }
        }
    }
}
