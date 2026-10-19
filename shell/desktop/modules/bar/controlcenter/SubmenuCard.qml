import QtQuick
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../../shared/qml/i18n"

ControlCenterCard {
    id: submenuCard
    required property string page
    required property var network
    required property var service
    signal backRequested()
    property real volumePreview: 0
    signal volumePreviewRequested(real value)
    signal draggingVolumeRequested(bool value)
    signal settingsRequested(string module)
    signal wifiNetworkSelected(var network)
    Behavior on cardHeight {
        // Only animate between real pages. Once the card unmaps (the
        // crossfade finished), the resting height snaps in place
        // immediately -- animating it would run a pointless resize on an
        // invisible card and force the next open to grow from stale
        // geometry.
        enabled: submenuCard.visible
        NumberAnimation {
            duration: AppearanceTokens.motion.normalDuration
            easing.type: Easing.OutCubic
        }
    }
    Item {
        id: submenuHeader
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            topMargin: 12
            leftMargin: 12
            rightMargin: 12
        }
        height: 28

        // Back button
        Rectangle {
            id: submenuBackBtn
            scale: submenuBackMouse.pressed ? 0.92 : 1
            Behavior on scale { NumberAnimation { duration: AppearanceTokens.motion.fastDuration; easing.type: Easing.OutCubic } }
            width: 26
            height: 26
            radius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 13)
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            color: submenuBackMouse.pressed
                ? (AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.26) : Qt.rgba(0, 0, 0, 0.14)))
                : (submenuBackMouse.containsMouse
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
                pointer: submenuBackMouse
                cornerRadius: 9
            }
            MouseArea {
                id: submenuBackMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: submenuCard.backRequested()
            }
        }

        // Title
        GlassText {
            anchors {
                left: submenuBackBtn.right
                leftMargin: 8
                verticalCenter: parent.verticalCenter
            }
            text: submenuCard.page === "wifi" ? "Wi‑Fi"
                : (submenuCard.page === "bluetooth" ? I18n.tr("Bluetooth")
                : (submenuCard.page === "brightness" ? I18n.tr("Display Brightness")
                : (submenuCard.page === "sound" ? I18n.tr("Sound") : "")))
            color: AppearanceTokens.content.glassInk()
            font { pixelSize: 13; weight: Font.Bold; family: AppearanceTokens.typography.textFamily }
        }

        // Right toggle switch for Wi-Fi and Bluetooth
        Rectangle {
            id: submenuToggleSwitch
            visible: submenuCard.page === "wifi" || submenuCard.page === "bluetooth"
            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            width: 38
            height: 22
            radius: 11
            readonly property bool isChecked: submenuCard.page === "wifi"
                ? submenuCard.network.wifiEnabled : submenuCard.service.bluetoothPowered
            readonly property bool inProgress: submenuCard.page === "wifi"
                ? submenuCard.network.wifiToggleInProgress : submenuCard.service.bluetoothChangeInProgress

            color: isChecked
                ? "#0a84ff"
                : (AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.14)))
            opacity: inProgress ? 0.6 : 1.0
            Behavior on color { ColorAnimation { duration: 160 } }

            Rectangle {
                width: 18
                height: 18
                radius: 9
                anchors.verticalCenter: parent.verticalCenter
                x: submenuToggleSwitch.isChecked ? parent.width - width - 2 : 2
                Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                color: "#ffffff"
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                enabled: !submenuToggleSwitch.inProgress
                onClicked: {
                    if (submenuCard.page === "wifi") {
                        submenuCard.network.setWifiEnabled(!submenuCard.network.wifiEnabled)
                    } else if (submenuCard.page === "bluetooth") {
                        submenuCard.service.setBluetoothEnabled(!submenuCard.service.bluetoothPowered)
                    }
                }
            }
        }
    }

    // Header divider
    Rectangle {
        id: submenuDivider
        anchors {
            top: submenuHeader.bottom
            topMargin: 9
            left: parent.left
            right: parent.right
            leftMargin: 12
            rightMargin: 12
        }
        height: 1
        color: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08))
    }

    // ── View A: Wi-Fi ──
    WifiPage {
        id: wifiSubmenuView
        visible: submenuCard.page === "wifi"
        anchors {
            top: submenuDivider.bottom
            topMargin: 6
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }

        network: submenuCard.network
        onSettingsRequested: module => submenuCard.settingsRequested(module)
        onWifiNetworkSelected: network => submenuCard.wifiNetworkSelected(network)
    }

    // ── View B: Bluetooth ──
    BluetoothPage {
        id: bluetoothSubmenuView
        visible: submenuCard.page === "bluetooth"
        anchors {
            top: submenuDivider.bottom
            topMargin: 6
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }

        service: submenuCard.service
        onSettingsRequested: module => submenuCard.settingsRequested(module)
    }

    // ── View C: Per-display brightness ──
    BrightnessPage {
        id: brightnessSubmenuView
        visible: submenuCard.page === "brightness"
        anchors {
            top: submenuDivider.bottom
            topMargin: 8
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }

        service: submenuCard.service
        onSettingsRequested: module => submenuCard.settingsRequested(module)
    }

    // ── View D: Sound ──
    SoundPage {
        id: soundSubmenuView
        visible: submenuCard.page === "sound"
        anchors {
            top: submenuDivider.bottom
            topMargin: 6
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }

        service: submenuCard.service
        volumePreview: submenuCard.volumePreview
        onSettingsRequested: module => submenuCard.settingsRequested(module)
        onVolumePreviewRequested: value => submenuCard.volumePreviewRequested(value)
        onDraggingVolumeRequested: value => submenuCard.draggingVolumeRequested(value)
    }
}
