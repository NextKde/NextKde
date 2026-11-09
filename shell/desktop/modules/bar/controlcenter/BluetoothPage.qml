import QtQuick
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../../shared/qml/i18n"
import "../../../../Kos/Ui"

Item {
    id: bluetoothSubmenuView
    objectName: "control-center-bluetoothpage"
    required property var service
    signal settingsRequested(string module)
    Item {
        anchors.fill: parent
        visible: !bluetoothSubmenuView.service.bluetoothPowered

        Column {
            anchors.centerIn: parent
            spacing: 8
            GlassText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.tr("Bluetooth is off")
                color: AppearanceTokens.content.glassInk()
                font { pixelSize: 13; weight: Font.Bold; family: AppearanceTokens.typography.textFamily }
            }
            GlassText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.tr("Turn on the switch above to connect devices")
                color: AppearanceTokens.content.glassInk()
                font { pixelSize: 11; family: AppearanceTokens.typography.textFamily }
            }
        }
    }

    Item {
        anchors.fill: parent
        visible: bluetoothSubmenuView.service.bluetoothPowered

        Item {
            id: btSectionHeader
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                leftMargin: 14
                rightMargin: 14
            }
            height: 22

            GlassText {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: I18n.tr("Devices")
                color: AppearanceTokens.content.glassInk()
                font { pixelSize: 10; weight: Font.DemiBold; family: AppearanceTokens.typography.textFamily }
            }

            GlassText {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                visible: bluetoothSubmenuView.service.bluetoothDevicesRefreshInProgress
                text: I18n.tr("Refreshing…")
                color: AppearanceTokens.content.glassInk()
                font { pixelSize: 9; family: AppearanceTokens.typography.textFamily }
            }
        }

        ListView {
            id: submenuBtList
            anchors {
                top: btSectionHeader.bottom
                topMargin: 2
                left: parent.left
                right: parent.right
                // btFooter is a sibling of this state container; use
                // local geometry rather than an invalid cross-parent
                // anchor so paired devices receive a real list height.
                bottom: parent.bottom
                leftMargin: 8
                rightMargin: 8
                bottomMargin: 42
            }
            clip: true
            spacing: 2
            model: bluetoothSubmenuView.service.bluetoothDevices

            delegate: Rectangle {
                required property var modelData
                required property int index
                width: submenuBtList.width
                height: 42
                radius: 10
                color: AppearanceTokens.surface.selectionHighlightStyle !== "glass"
                    && btRowMouse.containsMouse
                    ? (AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06)))
                    : "transparent"
                Behavior on color { ColorAnimation { duration: 100 } }

                GlassText {
                    visible: !!modelData.connected
                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    text: "✓"
                    color: AppearanceTokens.content.glassInk()
                    font { pixelSize: 13; weight: Font.Bold }
                }

                Canvas {
                    anchors {
                        left: parent.left
                        leftMargin: 26
                        verticalCenter: parent.verticalCenter
                    }
                    width: 16
                    height: 16
                    readonly property color ink: AppearanceTokens.content.glassInk()
                    onInkChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        ctx.strokeStyle = modelData.connected ? "#0a84ff" : ink
                        ctx.lineWidth = 1.6
                        ctx.lineCap = "round"
                        ctx.lineJoin = "round"
                        ctx.scale(0.55, 0.55)
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
                }

                Column {
                    anchors {
                        left: parent.left
                        right: btBatteryArea.left
                        leftMargin: 50
                        rightMargin: 6
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 1

                    GlassText {
                        width: parent.width
                        text: modelData.name || I18n.tr("Unknown device")
                        elide: Text.ElideRight
                        color: AppearanceTokens.content.glassInk()
                        font { pixelSize: 11; weight: modelData.connected ? Font.DemiBold : Font.Normal; family: AppearanceTokens.typography.textFamily }
                    }

                    GlassText {
                        text: modelData.connected ? I18n.tr("Connected") : I18n.tr("Not connected")
                        color: AppearanceTokens.content.glassInk()
                        font { pixelSize: 9; family: AppearanceTokens.typography.textFamily }
                    }
                }

                Item {
                    id: btBatteryArea
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    width: btBatteryText.implicitWidth
                    height: 16
                    visible: modelData.battery !== undefined && modelData.battery !== null

                    GlassText {
                        id: btBatteryText
                        anchors.centerIn: parent
                        text: (modelData.battery || 0) + "%"
                        color: AppearanceTokens.content.glassInk()
                        font { pixelSize: 10; family: AppearanceTokens.typography.textFamily }
                    }
                }

                ControlCenterSelection {
                    pointer: btRowMouse
                    cornerRadius: 10
                    selected: !!modelData.connected
                }
                MouseArea {
                    id: btRowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !bluetoothSubmenuView.service.bluetoothDeviceChangeInProgress
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: bluetoothSubmenuView.service.setBluetoothDeviceConnected(modelData, !modelData.connected)
                }
            }

            GlassText {
                anchors.centerIn: parent
                visible: submenuBtList.count === 0 && !bluetoothSubmenuView.service.bluetoothDevicesRefreshInProgress
                text: I18n.tr("No paired devices found")
                color: AppearanceTokens.content.glassInk()
                font { pixelSize: 11; family: AppearanceTokens.typography.textFamily }
            }

            KosKineticScroll { flickable: submenuBtList }
        }
    }

    Item {
        id: btFooter
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 38

        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 12; rightMargin: 12 }
            height: 1
            color: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))
        }

        GlassText {
            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
            text: I18n.tr("Bluetooth settings…")
            color: AppearanceTokens.content.glassInk()
            font { pixelSize: 11; weight: Font.DemiBold; family: AppearanceTokens.typography.textFamily }
        }

        GlassText {
            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            text: "›"
            color: AppearanceTokens.content.glassInk()
            font { pixelSize: 13; weight: Font.Bold }
        }

        ControlCenterSelection {
            pointer: btSettingsMouse
            cornerRadius: 8
        }
        MouseArea {
            id: btSettingsMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: bluetoothSubmenuView.settingsRequested("kcm_bluetooth")
        }
    }
}
