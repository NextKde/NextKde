import QtQuick
import qs.desktop.modules.bar
import qs.desktop.modules.common
import "../../../../shared/qml/i18n"

KosFloatPanel {
    id: sessionConfirm
    objectName: "control-center-session-confirmation"
    property string actionLabel: ""
    signal cancelRequested()
    signal confirmRequested()
    modal: true
    backdropMode: "none"
    dismissOnBackdrop: false
    contentPadding: 0
    radius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 24)
    onBackdropClicked: sessionConfirm.cancelRequested()

    Item {
        width: 300
        height: 204

        Rectangle {
            width: 56
            height: 56
            radius: width / 2
            anchors {
                top: parent.top
                topMargin: 20
                horizontalCenter: parent.horizontalCenter
            }
            color: Qt.rgba(sessionConfirm.contentForegroundColor.r,
                sessionConfirm.contentForegroundColor.g,
                sessionConfirm.contentForegroundColor.b, 0.08)
            border.width: 1
            border.color: Qt.rgba(sessionConfirm.contentForegroundColor.r,
                sessionConfirm.contentForegroundColor.g,
                sessionConfirm.contentForegroundColor.b, 0.34)

            BundledIcon {

                // Same readability edge the bar text carries (Text.Outline).

                outlined: AppearanceTokens.isDarkTheme

                outlineColor: Qt.rgba(0, 0, 0, 0.40)
                anchors.centerIn: parent
                width: 26
                height: 26
                name: BundledIcons.roleName(sessionConfirm.actionLabel === "poweroff"
                    ? "powerOff"
                    : (sessionConfirm.actionLabel === "reboot" ? "reboot" : "logout"))
                color: sessionConfirm.contentForegroundColor
            }
        }

        Text {
            anchors {
                top: parent.top
                topMargin: 88
                left: parent.left
                right: parent.right
            }
            horizontalAlignment: Text.AlignHCenter
            text: sessionConfirm.actionLabel === "poweroff" ? I18n.tr("Power off now?")
                : (sessionConfirm.actionLabel === "reboot" ? I18n.tr("Restart now?") : I18n.tr("Log out now?"))
            color: sessionConfirm.contentForegroundColor
            font { pixelSize: 16; weight: Font.Bold; family: AppearanceTokens.typography.textFamily }
        }

        Text {
            anchors {
                top: parent.top
                topMargin: 114
                left: parent.left
                right: parent.right
            }
            horizontalAlignment: Text.AlignHCenter
            text: I18n.tr("Unsaved work may be lost")
            color: sessionConfirm.contentSecondaryColor
            font { pixelSize: 12; family: AppearanceTokens.typography.textFamily }
        }

        Row {
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: 18
            }
            spacing: 12

            Rectangle {
                width: 104
                height: 32
                radius: height / 2
                color: sessionConfirm.contentControlFill

                Text {
                    anchors.centerIn: parent
                    text: I18n.tr("Cancel")
                    color: sessionConfirm.contentForegroundColor
                    font { pixelSize: 13; weight: Font.Medium; family: AppearanceTokens.typography.textFamily }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: sessionConfirm.cancelRequested()
                }
            }

            Rectangle {
                width: 104
                height: 32
                radius: height / 2
                // Same face as the neutral button, red label only.
                color: sessionConfirm.contentControlFill

                Text {
                    anchors.centerIn: parent
                    text: sessionConfirm.actionLabel === "poweroff" ? I18n.tr("Power Off")
                        : (sessionConfirm.actionLabel === "reboot" ? I18n.tr("Restart") : I18n.tr("Log Out"))
                    color: "#ff3b30"
                    font { pixelSize: 13; weight: Font.Medium; family: AppearanceTokens.typography.textFamily }
                }

                ControlCenterSelection {
                    pointer: executeConfirmMouse
                    cornerRadius: 9
                }
                MouseArea {
                    id: executeConfirmMouse
                    objectName: "executeConfirmMouse"
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: sessionConfirm.confirmRequested()
                }
            }
        }
    }
}
