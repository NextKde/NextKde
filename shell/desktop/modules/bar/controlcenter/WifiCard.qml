import QtQuick
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../../shared/qml/i18n"

ControlCenterCard {
    id: wifiCard
    objectName: "control-center-wificard"
    required property var network
    signal pageRequested()
    ControlCenterSelection {
        pointer: wifiPagePointer
        cornerRadius: wifiCard.cardRadius
        selected: wifiCard.network.wifiEnabled
        hovered: wifiPagePointer.containsMouse || wifiTogglePointer.containsMouse
        pressed: wifiPagePointer.pressed || wifiTogglePointer.pressed
    }
    cardScale: wifiPagePointer.pressed ? 0.97 : wifiPagePointer.containsMouse ? 1.015 : 1
    Behavior on cardScale { NumberAnimation { duration: AppearanceTokens.motion.fastDuration; easing.type: Easing.OutCubic } }
    Rectangle {
        id: wifiToggleDisc
        width: 39; height: 39; radius: width / 2
        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
        color: wifiCard.network.wifiEnabled
            ? ThemeService.tileActiveFill
            : (AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.05)))
        opacity: wifiCard.network.wifiToggleInProgress ? 0.55 : 1.0
        Behavior on opacity { NumberAnimation { duration: AppearanceTokens.motion.fastDuration } }
        scale: wifiTogglePointer.pressed ? 0.92
            : (wifiTogglePointer.containsMouse ? 1.04 : 1.0)
        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        WifiSignalIcon {
            // Matches the readability edge the popup text already carries.
            outlined: AppearanceTokens.isDarkTheme
            outlineColor: Qt.rgba(0, 0, 0, 0.40)
            anchors.centerIn: parent
            width: 20; height: 20
            opacity: wifiCard.network.wifiToggleInProgress ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 140 } }
            wifiEnabled: wifiCard.network.wifiEnabled
            connected: wifiCard.network.deviceState === "connected"
                && wifiCard.network.connectionType === "wifi"
            signalStrength: wifiCard.network.signalStrength
            glyphColor: wifiCard.network.wifiEnabled
                ? ThemeService.tileActiveGlyph : ThemeService.tileGlyph
        }
        // Toggling NetworkManager's radio is not instant either; mirror
        // the Bluetooth disc's busy arc so both read as "working", not
        // "stuck", while the toggle is in flight.
        Item {
            id: wifiBusySpinner
            anchors.centerIn: parent
            width: 21; height: 21
            opacity: wifiCard.network.wifiToggleInProgress ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 140 } }

            Canvas {
                id: wifiBusyArc
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
                    function onIsDarkChanged() { wifiBusyArc.requestPaint() }
                }
                Component.onCompleted: requestPaint()
            }

            RotationAnimation on rotation {
                running: wifiBusySpinner.visible && wifiCard.network.wifiToggleInProgress
                loops: Animation.Infinite
                from: 0; to: 360
                duration: 900
            }
        }
        MouseArea {
            id: wifiTogglePointer
            objectName: "wifiTogglePointer"
            anchors.fill: parent
            enabled: wifiCard.network.available
                && !wifiCard.network.wifiToggleInProgress
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: wifiCard.network.setWifiEnabled(
                !wifiCard.network.wifiEnabled)
        }
    }
    Column {
        anchors { left: parent.left; right: parent.right; leftMargin: 58; rightMargin: 18; verticalCenter: parent.verticalCenter }
        spacing: 1
        GlassText {
            width: parent.width
            text: "Wi‑Fi"
            color: wifiCard.materialForegroundColor
            font { pixelSize: 12; weight: Font.Bold; family: AppearanceTokens.typography.textFamily }
        }
        GlassText {
            width: parent.width
            text: wifiCard.network.wifiEnabled
                ? (wifiCard.network.ssid || I18n.tr("Not connected")) : I18n.tr("Off")
            elide: Text.ElideRight
            color: wifiCard.materialSecondaryForegroundColor
            opacity: 1.0
            font { pixelSize: 10; family: AppearanceTokens.typography.textFamily }
        }
    }
    GlassText {
        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
        text: "›"
        color: wifiCard.materialSecondaryForegroundColor
        opacity: 0.60
        font { pixelSize: 14; weight: Font.Bold }
    }
    MouseArea {
        id: wifiPagePointer
        objectName: "wifiPagePointer"
        anchors {
            top: parent.top
            right: parent.right
            bottom: parent.bottom
            left: parent.left
            leftMargin: 49
        }
        enabled: wifiCard.network.available
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: wifiCard.pageRequested()
    }
}
