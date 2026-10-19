import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../../shared/qml/i18n"

ControlCenterCard {
    id: stageModeCard
    objectName: "control-center-stagemodecard"
    required property var stageMode
    ControlCenterSelection {
        pointer: stagePointer
        cornerRadius: stageModeCard.cardRadius
        selected: stageModeCard.stageMode.enabled
    }
    visible: cardShown && coordinator.cardAnchor !== null
    Rectangle {
        id: stageDisc
        width: 34; height: 34; radius: 17
        anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter }
        color: stageModeCard.stageMode.enabled
            ? ThemeService.tileActiveFill
            : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.05))
        opacity: stagePointer.containsMouse && !stagePointer.pressed ? 1.0 : 0.92
        Behavior on color { ColorAnimation { duration: 140 } }

        Image {
            anchors.centerIn: parent
            width: 18; height: 18
            source: BundledIcons.source("window")
            sourceSize.width: 36; sourceSize.height: 36
            fillMode: Image.PreserveAspectFit
            smooth: true
            layer.enabled: true
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: stageModeCard.stageMode.enabled
                    ? ThemeService.tileActiveGlyph : ThemeService.tileGlyph
            }
        }
    }
    GlassText {
        objectName: "control-center-stage-title"
        anchors { left: stageDisc.right; leftMargin: 8; right: parent.right; rightMargin: 8; top: parent.top; topMargin: 8 }
        text: I18n.tr("Stage")
        elide: Text.ElideRight
        color: ThemeService.foregroundColor
        font { pixelSize: 12; weight: Font.Medium; family: AppearanceTokens.typography.textFamily }
    }
    GlassText {
        anchors { left: stageDisc.right; leftMargin: 8; right: parent.right; rightMargin: 8; bottom: parent.bottom; bottomMargin: 7 }
        elide: Text.ElideRight
        text: stageModeCard.stageMode.enabled ? I18n.tr("On") : I18n.tr("Off")
        color: stageModeCard.stageMode.enabled
            ? ThemeService.tileActiveGlyph : ThemeService.foregroundColor
        opacity: stageModeCard.stageMode.enabled ? 0.9 : 0.5
        font { pixelSize: 11; family: AppearanceTokens.typography.textFamily }
    }
    ToolTip.visible: stagePointer.containsMouse
    ToolTip.delay: 500
    ToolTip.text: I18n.tr("Stage scheduling")
    Accessible.name: I18n.tr("Stage scheduling")
    Accessible.role: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: stageModeCard.stageMode.enabled
    Accessible.onPressAction: stageModeCard.stageMode.toggle()
    MouseArea {
        id: stagePointer
        objectName: "stagePointer"
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: stageModeCard.stageMode.toggle()
    }
}
