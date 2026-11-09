import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../../shared/qml/i18n"

ControlCenterCard {
    id: keepAwakeCard
    objectName: "control-center-keepawakecard"
    required property var service
    ControlCenterSelection {
        pointer: keepAwakePointer
        cornerRadius: keepAwakeCard.cardRadius
        selected: keepAwakeCard.service.keepAwakeEnabled
    }
    visible: cardShown && coordinator.cardAnchor !== null
    Rectangle {
        id: keepAwakeDisc
        width: 34; height: 34; radius: 17
        anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter }
        color: keepAwakeCard.service.keepAwakeEnabled
            ? ThemeService.tileActiveFill
            : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.05))
        opacity: keepAwakePointer.containsMouse && !keepAwakePointer.pressed ? 1.0 : 0.92
        Behavior on color { ColorAnimation { duration: 140 } }

        Image {
            anchors.centerIn: parent
            width: 18; height: 18
            source: BundledIcons.source("keep-awake")
            sourceSize.width: 36; sourceSize.height: 36
            fillMode: Image.PreserveAspectFit
            smooth: true
            layer.enabled: true
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: keepAwakeCard.service.keepAwakeEnabled
                    ? ThemeService.tileActiveGlyph : ThemeService.tileGlyph
            }
        }
    }
    GlassText {
        anchors { left: keepAwakeDisc.right; leftMargin: 8; right: parent.right; rightMargin: 8; top: parent.top; topMargin: 8 }
        text: I18n.tr("Keep Awake")
        elide: Text.ElideRight
        color: ThemeService.foregroundColor
        font { pixelSize: 12; weight: Font.Medium; family: AppearanceTokens.typography.textFamily }
    }
    GlassText {
        anchors { left: keepAwakeDisc.right; leftMargin: 8; right: parent.right; rightMargin: 8; bottom: parent.bottom; bottomMargin: 7 }
        elide: Text.ElideRight
        text: keepAwakeCard.service.keepAwakeChangeInProgress ? I18n.tr("Switching…")
            : !keepAwakeCard.service.keepAwakeAvailable ? I18n.tr("Unavailable")
            : keepAwakeCard.service.keepAwakeError ? I18n.tr("Switch failed")
            : keepAwakeCard.service.keepAwakeEnabled ? I18n.tr("On") : I18n.tr("Off")
        color: keepAwakeCard.service.keepAwakeEnabled
            ? ThemeService.tileActiveGlyph : ThemeService.foregroundColor
        opacity: keepAwakeCard.service.keepAwakeEnabled ? 0.9 : 0.5
        font { pixelSize: 11; family: AppearanceTokens.typography.textFamily }
    }
    ToolTip.visible: keepAwakePointer.containsMouse
    ToolTip.delay: 500
    ToolTip.text: keepAwakeCard.service.keepAwakeError
        || (!keepAwakeCard.service.keepAwakeAvailable ? I18n.tr("Requires KDE power management and lock screen services")
            : I18n.tr("Blocks automatic sleep, screen lock and suspend; turning it off restores power saving"))
    Accessible.name: I18n.tr("Keep Awake")
    Accessible.description: keepAwakeCard.service.keepAwakeEnabled ? I18n.tr("On") : I18n.tr("Off")
    Accessible.role: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: keepAwakeCard.service.keepAwakeEnabled
    Accessible.onPressAction: keepAwakeCard.service.toggleKeepAwake()
    MouseArea {
        id: keepAwakePointer
        objectName: "keepAwakePointer"
        anchors.fill: parent
        hoverEnabled: true
        enabled: keepAwakeCard.service.keepAwakeAvailable && !keepAwakeCard.service.keepAwakeChangeInProgress
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: keepAwakeCard.service.toggleKeepAwake()
    }
}
