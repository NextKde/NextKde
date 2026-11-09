import QtQuick
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../../shared/qml/i18n"

ControlCenterCard {
    id: sessionCard
    objectName: "control-center-sessioncard"
    required property var service
    signal backRequested()
    signal actionRequested(string action)
    Item {
        anchors.fill: parent

        // Header: same shape as the Wi-Fi/Bluetooth pages -- back button on the
        // left, identity on the right -- instead of a title with a close box.
        Item {
            id: sessionHeader
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                topMargin: 12
                leftMargin: 12
                rightMargin: 12
            }
            height: 28

            Rectangle {
                id: sessionBackBtn
                width: 26
                height: 26
                radius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 13)
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                color: sessionBackMouse.pressed
                    ? (AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.26) : Qt.rgba(0, 0, 0, 0.14)))
                    : (sessionBackMouse.containsMouse
                        ? (AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.09)))
                        : (AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.05))))
                border.width: 1
                border.color: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.08))
                Behavior on color { ColorAnimation { duration: 110 } }

                GlassText {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: -1
                    text: "‹"
                    color: AppearanceTokens.content.glassInk()
                    font { pixelSize: 18; weight: Font.Bold }
                }

                ControlCenterSelection {
                    pointer: sessionBackMouse
                    cornerRadius: 9
                }
                MouseArea {
                    id: sessionBackMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: sessionCard.backRequested()
                }
            }

            Row {
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                spacing: 8

                GlassText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: sessionCard.service.currentUserName
                    color: ThemeService.foregroundColor
                    font { pixelSize: 12; weight: Font.Bold; family: AppearanceTokens.typography.textFamily }
                }

                Rectangle {
                    width: 28
                    height: 28
                    radius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 14)
                    color: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.06))
                    border.width: 1
                    border.color: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(0, 0, 0, 0.10))

                    BundledIcon {

                        // Same readability edge the bar text carries (Text.Outline).

                        outlined: AppearanceTokens.isDarkTheme

                        outlineColor: Qt.rgba(0, 0, 0, 0.40)
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        name: BundledIcons.roleName("switchUser")
                        color: ThemeService.foregroundColor
                    }
                }
            }
        }

        // Divider line
        Rectangle {
            id: sessionDivider
            anchors {
                top: sessionHeader.bottom
                topMargin: 8
                left: parent.left
                right: parent.right
                leftMargin: 12
                rightMargin: 12
            }
            height: 1
            color: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08))
        }

        // A plain list, the same shape as the Wi-Fi/Bluetooth pages: one row
        // per action, the whole row highlights on hover, and the destructive
        // three sit at the bottom in dark red.
        Column {
            id: actionsList
            anchors {
                top: sessionDivider.bottom
                topMargin: 4
                left: parent.left
                right: parent.right
                leftMargin: 6
                rightMargin: 6
            }

            Repeater {
                model: [
                    { icon: "lock", label: I18n.tr("Lock Screen"), danger: false, action: "lock" },
                    { icon: "suspend", label: I18n.tr("Sleep"), danger: false, action: "suspend" },
                    { icon: "switchUser", label: I18n.tr("Switch User"), danger: false, action: "switch" },
                    { icon: "logout", label: I18n.tr("Log Out"), danger: true, action: "logout" },
                    { icon: "reboot", label: I18n.tr("Restart"), danger: true, action: "reboot" },
                    { icon: "powerOff", label: I18n.tr("Power Off"), danger: true, action: "poweroff" }
                ]

                delegate: Item {
                    required property var modelData
                    required property int index
                    width: actionsList.width
                    height: 44
                    scale: sessionRow.pressed ? 0.98 : 1
                    Behavior on scale { NumberAnimation { duration: AppearanceTokens.motion.fastDuration; easing.type: Easing.OutCubic } }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: 9
                        color: sessionRow.containsMouse
                            ? (modelData.danger
                                ? Qt.rgba(1.0, 0.23, 0.19, 0.14)
                                : (ThemeService.isDark
                                    ? Qt.rgba(1, 1, 1, 0.10)
                                    : Qt.rgba(0, 0, 0, 0.06)))
                            : "transparent"
                        Behavior on color { ColorAnimation { duration: 110 } }
                    }

                    Row {
                        anchors {
                            left: parent.left
                            leftMargin: 12
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 10

                        BundledIcon {

                            // Same readability edge the bar text carries (Text.Outline).

                            outlined: AppearanceTokens.isDarkTheme

                            outlineColor: Qt.rgba(0, 0, 0, 0.40)
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20
                            height: 20
                            name: BundledIcons.roleName(modelData.icon)
                            color: modelData.danger
                                ? "#ff3b30" : ThemeService.foregroundColor
                        }

                        GlassText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            color: modelData.danger
                                ? "#ff3b30" : ThemeService.foregroundColor
                            font { pixelSize: 13; weight: Font.Medium; family: AppearanceTokens.typography.textFamily }
                        }
                    }

                    ControlCenterSelection {
                        pointer: sessionRow
                        cornerRadius: 9
                    }
                    MouseArea {
                        id: sessionRow
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sessionCard.actionRequested(modelData.action)
                    }
                }
            }
        }

        // Error / Status bar
        GlassText {
            anchors {
                bottom: parent.bottom
                bottomMargin: 6
                horizontalCenter: parent.horizontalCenter
            }
            visible: sessionCard.service.lastSessionError.length > 0
            text: "⚠ " + sessionCard.service.lastSessionError
            color: "#ff453a"
            font { pixelSize: 10; weight: Font.Medium; family: AppearanceTokens.typography.textFamily }
        }
    }
}
