import QtQuick
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../../shared/qml/i18n"

ControlCenterCard {
    id: bluetoothCard
    objectName: "control-center-bluetoothcard"
    required property var service
    signal pageRequested()
    ControlCenterSelection {
        pointer: bluetoothPagePointer
        cornerRadius: bluetoothCard.cardRadius
        selected: bluetoothCard.service.bluetoothPowered
        hovered: bluetoothPagePointer.containsMouse || bluetoothTogglePointer.containsMouse
        pressed: bluetoothPagePointer.pressed || bluetoothTogglePointer.pressed
    }
    cardScale: bluetoothPagePointer.pressed ? 0.97 : bluetoothPagePointer.containsMouse ? 1.015 : 1
    Behavior on cardScale { NumberAnimation { duration: AppearanceTokens.motion.fastDuration; easing.type: Easing.OutCubic } }
    cardOpacity: bluetoothCard.service.bluetoothAvailable ? 1 : 0.48
    Rectangle {
        id: bluetoothToggleDisc
        width: 39; height: 39; radius: width / 2
        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
        color: bluetoothCard.service.bluetoothPowered
            ? ThemeService.tileActiveFill
            : (AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.05)))
        opacity: bluetoothCard.service.bluetoothChangeInProgress ? 0.55 : 1.0
        scale: bluetoothTogglePointer.pressed ? 0.92
            : (bluetoothTogglePointer.containsMouse ? 1.04 : 1.0)
        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        Canvas {
            id: controlBtGlyph
            anchors.centerIn: parent
            width: 21; height: 21
            property bool active: bluetoothCard.service.bluetoothPowered
            property color glyphColor: ThemeService.tileGlyph
            opacity: bluetoothCard.service.bluetoothChangeInProgress ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 140 } }
            onActiveChanged: requestPaint()
            onGlyphColorChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.strokeStyle = glyphColor
                ctx.lineWidth = 2.0
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                ctx.scale(0.78, 0.78)
                ctx.beginPath()
                ctx.moveTo(13.5, 2.5)
                ctx.lineTo(20, 9)
                ctx.lineTo(13.5, 15)
                ctx.lineTo(20, 21)
                ctx.lineTo(13.5, 26.5)
                ctx.lineTo(13.5, 2.5)
                ctx.moveTo(7, 8.5)
                ctx.lineTo(13.5, 15)
                ctx.lineTo(7, 21.5)
                ctx.stroke()
            }
            Connections {
                target: ThemeService
                function onIsDarkChanged() { controlBtGlyph.requestPaint() }
            }
        }
        // Powering BlueZ's adapter genuinely takes a second or more; a
        // flat opacity dim alone reads as "stuck", not "working". Spin an
        // indeterminate arc in its place, macOS Control Center style.
        Item {
            id: bluetoothBusySpinner
            anchors.centerIn: parent
            width: 21; height: 21
            opacity: bluetoothCard.service.bluetoothChangeInProgress ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 140 } }

            Canvas {
                id: bluetoothBusyArc
                anchors.fill: parent
                property color glyphColor: ThemeService.tileGlyph
                onGlyphColorChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    ctx.strokeStyle = glyphColor
                    ctx.lineWidth = 2.0
                    ctx.lineCap = "round"
                    const cx = width / 2, cy = height / 2, r = width / 2 - 1.5
                    ctx.beginPath()
                    ctx.arc(cx, cy, r, 0, Math.PI * 1.5)
                    ctx.stroke()
                }
                Connections {
                    target: ThemeService
                    function onIsDarkChanged() { bluetoothBusyArc.requestPaint() }
                }
                Component.onCompleted: requestPaint()
            }

            RotationAnimation on rotation {
                running: bluetoothBusySpinner.visible && bluetoothCard.service.bluetoothChangeInProgress
                loops: Animation.Infinite
                from: 0; to: 360
                duration: 900
            }
        }
        MouseArea {
            id: bluetoothTogglePointer
            objectName: "bluetoothTogglePointer"
            anchors.fill: parent
            enabled: bluetoothCard.service.bluetoothAvailable && !bluetoothCard.service.bluetoothChangeInProgress
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: bluetoothCard.service.setBluetoothEnabled(!bluetoothCard.service.bluetoothPowered)
        }
    }
    Column {
        anchors { left: parent.left; right: parent.right; leftMargin: 58; rightMargin: 18; verticalCenter: parent.verticalCenter }
        spacing: 1
        GlassText {
            width: parent.width
            text: "Bluetooth"
            color: bluetoothCard.materialForegroundColor
            font { pixelSize: 12; weight: Font.Bold; family: AppearanceTokens.typography.textFamily }
        }
        GlassText {
            width: parent.width
            text: bluetoothCard.service.bluetoothPowered
                ? I18n.tr("On") : I18n.tr("Off")
            color: bluetoothCard.materialSecondaryForegroundColor
            opacity: 1.0
            font { pixelSize: 10; family: AppearanceTokens.typography.textFamily }
        }
    }
    GlassText {
        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
        text: "›"
        color: bluetoothCard.materialSecondaryForegroundColor
        opacity: 0.60
        font { pixelSize: 14; weight: Font.Bold }
    }
    MouseArea {
        id: bluetoothPagePointer
        objectName: "bluetoothPagePointer"
        anchors {
            top: parent.top
            right: parent.right
            bottom: parent.bottom
            left: parent.left
            leftMargin: 49
        }
        enabled: bluetoothCard.service.bluetoothAvailable
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: bluetoothCard.pageRequested()
    }
}
