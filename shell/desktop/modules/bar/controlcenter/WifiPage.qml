import QtQuick
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../../shared/qml/i18n"
import "../../../../Kos/Ui"

Item {
    id: wifiSubmenuView
    objectName: "control-center-wifipage"
    required property var network
    signal settingsRequested(string module)
    signal wifiNetworkSelected(var network)
    // Wi-Fi Off state
    Item {
        anchors.fill: parent
        visible: !wifiSubmenuView.network.wifiEnabled

        Column {
            anchors.centerIn: parent
            spacing: 8
            GlassText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.tr("Wi‑Fi is off")
                color: AppearanceTokens.content.glassInk()
                font { pixelSize: 14; weight: Font.Bold; family: AppearanceTokens.typography.textFamily }
            }
            GlassText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.tr("Turn on the switch above to see nearby networks")
                color: AppearanceTokens.content.glassInk()
                font { pixelSize: 12; weight: Font.DemiBold; family: AppearanceTokens.typography.textFamily }
            }
        }
    }

    // Wi-Fi On state
    Item {
        anchors.fill: parent
        visible: wifiSubmenuView.network.wifiEnabled

        Item {
            id: wifiSectionHeader
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
                text: I18n.tr("Nearby Networks")
                color: AppearanceTokens.content.glassInk()
                font { pixelSize: 11; weight: Font.Bold; family: AppearanceTokens.typography.textFamily }
            }

            GlassText {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                visible: wifiSubmenuView.network.wifiScanInProgress
                text: I18n.tr("Scanning…")
                color: AppearanceTokens.content.glassInk()
                font { pixelSize: 10; weight: Font.DemiBold; family: AppearanceTokens.typography.textFamily }
            }
        }

        ListView {
            id: submenuWifiList
            anchors {
                top: wifiSectionHeader.bottom
                topMargin: 2
                left: parent.left
                right: parent.right
                // wifiFooter is a sibling of this state container, so
                // it cannot be used as an anchor target. Reserve its
                // height locally; cross-parent anchoring collapses the
                // ListView and makes all scanned networks invisible.
                bottom: parent.bottom
                leftMargin: 8
                rightMargin: 8
                bottomMargin: 42
            }
            clip: true
            spacing: 2
            model: wifiSubmenuView.network.nearbyWifi

            delegate: Rectangle {
                required property var modelData
                required property int index
                width: submenuWifiList.width
                height: 42
                radius: 10
                color: AppearanceTokens.surface.selectionHighlightStyle !== "glass"
                    && wifiRowMouse.containsMouse
                    ? (AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06)))
                    : "transparent"
                Behavior on color { ColorAnimation { duration: AppearanceTokens.motion.instant.duration; easing.type: AppearanceTokens.motion.enterCurve } }

                BundledIcon {
                    visible: !!modelData.active
                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    name: "network.connected"
                    color: AppearanceTokens.content.glassInk()
                    size: 13
                }

                WifiSignalIcon {

                    // Matches the readability edge the popup text already carries.

                    outlined: AppearanceTokens.isDarkTheme

                    outlineColor: Qt.rgba(0, 0, 0, 0.40)
                    anchors {
                        left: parent.left
                        leftMargin: 26
                        verticalCenter: parent.verticalCenter
                    }
                    width: 16
                    height: 16
                    wifiEnabled: true
                    connected: !!modelData.active
                    signalStrength: modelData.signalStrength !== undefined ? modelData.signalStrength : 70
                    glyphColor: modelData.active ? ThemeService.tileAccent : ThemeService.tileGlyph
                }

                GlassText {
                    anchors {
                        left: parent.left
                        right: wifiRowRightArea.left
                        leftMargin: 48
                        rightMargin: 6
                        verticalCenter: parent.verticalCenter
                    }
                    text: modelData.ssid || I18n.tr("Hidden network")
                    elide: Text.ElideRight
                    color: AppearanceTokens.content.glassInk()
                    font {
                        pixelSize: 12
                        weight: modelData.active ? Font.Bold : Font.DemiBold
                        family: AppearanceTokens.typography.textFamily
                    }
                }

                Row {
                    id: wifiRowRightArea
                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    spacing: 6

                    BundledIcon {
                        visible: modelData.security && modelData.security !== "none"
                        anchors.verticalCenter: parent.verticalCenter
                        width: 12; height: 14
                        name: "network.secured"
                        color: AppearanceTokens.content.glassInk()
                    }

                    Rectangle {
                        visible: !!modelData.active
                        width: 38
                        height: 20
                        radius: 10
                        color: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08))
                        border.width: 1
                        border.color: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.10))
                        GlassText {
                            anchors.centerIn: parent
                            text: I18n.tr("Disconnect")
                            color: AppearanceTokens.content.glassInk()
                            font { pixelSize: 10; weight: Font.DemiBold; family: AppearanceTokens.typography.textFamily }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: wifiSubmenuView.network.disconnectActiveWifi()
                        }
                    }
                }

                ControlCenterSelection {
                    pointer: wifiRowMouse
                    cornerRadius: 10
                    selected: !!modelData.active
                }
                MouseArea {
                    id: wifiRowMouse
                    objectName: "wifiRowMouse"
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (modelData.active) return
                        if (modelData.savedProfileUuid) {
                            wifiSubmenuView.network.connectWifi(modelData.ssid, "", modelData.savedProfileUuid)
                        } else if (!modelData.security || modelData.security === "none") {
                            wifiSubmenuView.network.connectWifi(modelData.ssid, "", "")
                        } else {
                            // Copy the delegate value before closing;
                            // the ListView may destroy this delegate as
                            // soon as the control center is unloaded.
                            const network = Object.assign({}, modelData, {
                                secured: Boolean(modelData.secured
                                    || (modelData.security
                                        && modelData.security !== "none"))
                            })
                            wifiSubmenuView.wifiNetworkSelected(network)
                        }
                    }
                }
            }

            GlassText {
                anchors.centerIn: parent
                visible: submenuWifiList.count === 0 && !wifiSubmenuView.network.wifiScanInProgress
                text: I18n.tr("No Wi‑Fi networks detected")
                color: AppearanceTokens.content.glassInk()
                font { pixelSize: 12; weight: Font.DemiBold; family: AppearanceTokens.typography.textFamily }
            }

            KosKineticScroll { flickable: submenuWifiList }
        }
    }

    Item {
        id: wifiFooter
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 38

        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 12; rightMargin: 12 }
            height: 1
            color: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))
        }

        GlassText {
            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
            text: I18n.tr("Network settings…")
            color: AppearanceTokens.content.glassInk()
            font { pixelSize: 12; weight: Font.Bold; family: AppearanceTokens.typography.textFamily }
        }

        BundledIcon {
            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            name: "network.settings"
            color: AppearanceTokens.content.glassInk()
            size: 13
        }

        ControlCenterSelection {
            pointer: wifiSettingsMouse
            cornerRadius: 8
        }
        MouseArea {
            id: wifiSettingsMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: wifiSubmenuView.settingsRequested("kcm_networkmanagement")
        }
    }
}
