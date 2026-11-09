import QtQuick
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../../shared/qml/i18n"

ControlCenterCard {
    id: slotCard6
    objectName: "control-center-brightnesscard"
    required property var service
    property real brightnessPreview: 0
    signal pageRequested(string page)
    signal brightnessPreviewRequested(real value)
    signal draggingBrightnessRequested(bool value)
    ControlCenterSelection {
        pointer: brightnessPagePointer
        cornerRadius: slotCard6.cardRadius
        hovered: brightnessPagePointer.containsMouse || brightnessSlider._hovered
        pressed: brightnessPagePointer.pressed || brightnessSlider._pressed
    }
    Row {
        anchors { left: parent.left; top: parent.top; leftMargin: 14; topMargin: 8 }
        spacing: 4
        GlassText {
            text: I18n.tr("Display Brightness")
            color: ThemeService.foregroundColor
            font { pixelSize: 11; weight: Font.DemiBold; family: AppearanceTokens.typography.textFamily }
        }
    }
    GlassText {
        anchors { right: parent.right; top: parent.top; rightMargin: 30; topMargin: 8 }
        text: slotCard6.service.brightnessAvailable
            ? Math.round(slotCard6.brightnessPreview) + "%" : I18n.tr("No brightness device")
        color: ThemeService.foregroundColor
        opacity: 0.50
        font { pixelSize: 9; family: AppearanceTokens.typography.textFamily }
    }
    GlassText {
        anchors { right: parent.right; top: parent.top; rightMargin: 13; topMargin: 5 }
        text: "›"
        color: ThemeService.foregroundColor
        font { pixelSize: 15; weight: Font.Bold }
    }
    MouseArea {
        id: brightnessPagePointer
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 27
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: slotCard6.pageRequested("brightness")
    }
    ControlCenterSlider {
        id: brightnessSlider
        objectName: "brightnessSlider"
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 31; rightMargin: 31; bottomMargin: 8 }
        value: slotCard6.brightnessPreview / 100
        enabled: slotCard6.service.brightnessAvailable
        onPreviewChanged: function(v) {
            slotCard6.draggingBrightnessRequested(true)
            slotCard6.brightnessPreviewRequested(Math.round(v * 100))
        }
        onCanceled: {
            slotCard6.draggingBrightnessRequested(false)
            slotCard6.brightnessPreviewRequested(slotCard6.service.brightnessPercent)
        }
        onCommitRequested: function(v) {
            slotCard6.draggingBrightnessRequested(false)
            slotCard6.service.setBrightness(Math.round(v * 100))
        }
    }
    GlassText {
        anchors { left: parent.left; leftMargin: 12; bottom: parent.bottom; bottomMargin: 12 }
        text: "☀"
        color: ThemeService.foregroundColor
        opacity: 0.65
        font.pixelSize: 13
    }
}
