import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../../../shared/qml/controls" as LiquidControls
import "../../../shared/qml/foundation" as Foundation
import "../../../shared/qml/i18n"
import "../components" as Controls

ColumnLayout {
    required property var colors
    property bool materialForm: false
    id: windowPage
    objectName: "windowAppearancePage"
    spacing: 10
    property var backend: null
    readonly property var snapshot: backend ? backend.state : ({})
    readonly property var radiusStops: [0, 8, 12, 20, 28, 36]
    readonly property var radiusLabels: [I18n.tr("Square corner"), I18n.tr("Slight round"), I18n.tr("Small"), I18n.tr("Standard"), I18n.tr("Large"), I18n.tr("Larger")]
    property int previewRadius: -1
    readonly property int radiusIndex: {
        let best = 0
        for (let i = 1; i < radiusStops.length; ++i)
            if (Math.abs(radiusStops[i] - Number(snapshot.radius ?? 20))
                < Math.abs(radiusStops[best] - Number(snapshot.radius ?? 20))) best = i
        return best
    }
    Component.onCompleted: { if (backend) backend.refresh() }

    Text {
        text: I18n.tr("Window appearance")
        color: colors.secondaryText; font.pixelSize: 12; font.weight: Font.DemiBold
        Layout.leftMargin: 13
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: windowRows.implicitHeight
        radius: 18; color: colors.card
        Column {
            id: windowRows
            anchors.left: parent.left; anchors.right: parent.right
            Item {
                width: parent.width; height: 54
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16; spacing: 12
                    Controls.SettingIcon {
                        colors: windowPage.colors
                        materialForm: windowPage.materialForm
                        symbol: "▣"
                        tint: "#5856d6"
                    }
                    Text { text: I18n.tr("KOS window appearance"); color: colors.primaryText; font.pixelSize: 15; font.weight: Font.DemiBold }
                    Item { Layout.fillWidth: true }
                    LiquidControls.LiquidGlassSwitch {
                        width: 64; height: 25
                        enabled: windowPage.backend !== null
                        objectName: "windowTakeoverSwitch"
                        checked: windowPage.snapshot.enabled !== false
                        accentColor: colors.accent; trackColor: colors.divider
                        onToggled: function(checked) { windowPage.backend.setTakeover(checked) }
                    }
                }
            }
            Rectangle { width: parent.width - 53; x: 53; height: 1; color: colors.separator }
            Item {
                width: parent.width; height: 64
                enabled: windowPage.backend !== null && windowPage.snapshot.enabled !== false
                opacity: enabled ? 1 : 0.4
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16; spacing: 12
                    Controls.SettingIcon {
                        colors: windowPage.colors
                        materialForm: windowPage.materialForm
                        symbol: "▢"
                        tint: "#5ac8fa"
                    }
                    Text { text: I18n.tr("Corner radius"); color: colors.primaryText; font.pixelSize: 14 }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: windowPage.radiusLabels[windowPage.previewRadius >= 0 ? windowPage.previewRadius : windowPage.radiusIndex]
                            + " · " + (windowPage.previewRadius >= 0 ? windowPage.radiusStops[windowPage.previewRadius] : Number(windowPage.snapshot.radius ?? 20)) + " px"
                        color: colors.secondaryText; font.pixelSize: 12
                    }
                    LiquidControls.LiquidSlider {
                        objectName: "windowRadiusSlider"
                        enabled: windowPage.backend !== null && windowPage.snapshot.enabled !== false
                        Layout.preferredWidth: 190
                        accentColor: colors.accent; trackColor: colors.divider
                        wheelStep: 0.2
                        value: (windowPage.previewRadius >= 0 ? windowPage.previewRadius : windowPage.radiusIndex) / 5
                        onPreviewChanged: function(position) { windowPage.previewRadius = Math.round(position * 5) }
                        onCanceled: windowPage.previewRadius = -1
                        onCommitRequested: function(position) {
                            windowPage.backend.setRadius(windowPage.radiusStops[Math.round(position * 5)])
                            windowPage.previewRadius = -1
                        }
                    }
                }
            }
            Rectangle { width: parent.width - 53; x: 53; height: 1; color: colors.separator }
            Item {
                width: parent.width; height: 54
                enabled: windowPage.backend !== null && windowPage.snapshot.enabled !== false
                opacity: enabled ? 1 : 0.4
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16; spacing: 12
                    Controls.SettingIcon {
                        colors: windowPage.colors
                        materialForm: windowPage.materialForm
                        symbol: "◧"
                        tint: "#8e8e93"
                    }
                    Text { text: I18n.tr("Window shadow"); color: colors.primaryText; font.pixelSize: 14 }
                    Item { Layout.fillWidth: true }
                    LiquidControls.LiquidGlassSwitch {
                        width: 64; height: 25
                        objectName: "windowShadowSwitch"
                        checked: windowPage.snapshot.shadow !== false
                        accentColor: colors.accent; trackColor: colors.divider
                        onToggled: function(checked) { windowPage.backend.setShadow(checked) }
                    }
                }
            }
        }
    }
    Text {
        Layout.fillWidth: true; Layout.leftMargin: 13; Layout.rightMargin: 13
        text: I18n.tr("Turning off KOS window appearance restores the original decorator. Radius and shadow apply immediately; decorator switches take effect on next login.")
        color: colors.secondaryText; font.pixelSize: 11; wrapMode: Text.Wrap
    }
    Text {
        text: I18n.tr("Window animations")
        color: colors.secondaryText; font.pixelSize: 12; font.weight: Font.DemiBold
        Layout.leftMargin: 13; Layout.topMargin: 10
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: animationRows.implicitHeight
        radius: 18; color: colors.card
        Column {
            id: animationRows
            anchors.left: parent.left; anchors.right: parent.right
            Item {
                width: parent.width; height: 54
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16; spacing: 12
                    Controls.SettingIcon {
                        colors: windowPage.colors
                        materialForm: windowPage.materialForm
                        symbol: "↓"
                        tint: "#ff9500"
                    }
                    Text { text: I18n.tr("Hide and restore"); color: colors.primaryText; font.pixelSize: 14 }
                    Item { Layout.fillWidth: true }
                    Controls.SettingsNavBar {
                        colors: windowPage.colors
                        materialForm: windowPage.materialForm
                        objectName: "windowHideAnimation"
                        disabled: windowPage.backend === null
                        model: [{ id: "none", label: I18n.tr("None") }, { id: "scale", label: I18n.tr("Scale") }, { id: "genie", label: I18n.tr("Genie") }]
                        currentIndex: ["none", "scale", "genie"].indexOf(windowPage.snapshot.hideAnimation ?? "scale")
                        onSelectionChanged: function(index) { windowPage.backend.setAnimation("hide", model[index].id) }
                    }
                }
            }
            Rectangle { width: parent.width - 53; x: 53; height: 1; color: colors.separator }
            Item {
                width: parent.width; height: 54
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16; spacing: 12
                    Controls.SettingIcon {
                        colors: windowPage.colors
                        materialForm: windowPage.materialForm
                        symbol: "×"
                        tint: "#ff3b30"
                    }
                    Text { text: I18n.tr("Close window"); color: colors.primaryText; font.pixelSize: 14 }
                    Item { Layout.fillWidth: true }
                    Controls.SettingsNavBar {
                        colors: windowPage.colors
                        materialForm: windowPage.materialForm
                        objectName: "windowCloseAnimation"
                        disabled: windowPage.backend === null
                        itemWidthOverride: 80
                        model: [{ id: "none", label: I18n.tr("None") }, { id: "fade", label: I18n.tr("Fade out") }, { id: "scale", label: I18n.tr("Shrink and fade") }]
                        currentIndex: ["none", "fade", "scale"].indexOf(windowPage.snapshot.closeAnimation ?? "scale")
                        onSelectionChanged: function(index) { windowPage.backend.setAnimation("close", model[index].id) }
                    }
                }
            }
        }
    }
    Text {
        Layout.fillWidth: true; Layout.leftMargin: 13; Layout.rightMargin: 13
        text: I18n.tr("Hide means minimizing to the Dock. Choosing “None” makes KOS drop the animation and leave it to other enabled KWin effects.")
        color: colors.secondaryText; font.pixelSize: 11; wrapMode: Text.Wrap
    }
    Text {
        Layout.fillWidth: true; Layout.leftMargin: 13; Layout.rightMargin: 13
        visible: !windowPage.backend || windowPage.backend.error.length > 0
        text: windowPage.backend ? I18n.tr(windowPage.backend.error) : I18n.tr("Window settings backend unavailable")
        color: "#ff453a"; font.pixelSize: 12; wrapMode: Text.Wrap
    }
}
