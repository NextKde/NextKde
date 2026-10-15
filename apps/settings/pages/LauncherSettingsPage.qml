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
    id: launcherPage

    Layout.fillWidth: true
    spacing: 7
    property var bridge: null
    property string displayMode: "bottom"
    readonly property var displayModes: ["bottom", "bottomWide", "center", "fullscreen"]
    property int displayModeIndex: 0
    property string iconSize: "medium"
    property string density: "balanced"
    property string fontWeight: "normal"
    readonly property var iconSizes: ["small", "medium", "large"]
    readonly property var densities: ["compact", "balanced", "spacious"]
    property int iconSizeIndex: 1
    property int densityIndex: 1
    readonly property var fontWeights: ["normal", "medium", "bold"]
    property int fontWeightIndex: 0
    property string errorText: ""

    function applySnapshot(snapshot) {
        if (!snapshot) return
        if (snapshot.displayMode !== undefined) {
            displayMode = snapshot.displayMode
            const idx = displayModes.indexOf(displayMode)
            displayModeIndex = idx >= 0 ? idx : 0
        }
        const profiles = snapshot.layoutProfiles
        const profile = profiles && profiles[displayMode] ? profiles[displayMode] : null
        if (!profile)
            return
        iconSize = iconSizes.indexOf(profile.iconSize) >= 0 ? profile.iconSize : "medium"
        density = densities.indexOf(profile.density) >= 0 ? profile.density : "balanced"
        fontWeight = fontWeights.indexOf(profile.fontWeight) >= 0 ? profile.fontWeight : "normal"
        iconSizeIndex = iconSizes.indexOf(iconSize)
        densityIndex = densities.indexOf(density)
        fontWeightIndex = fontWeights.indexOf(fontWeight)
    }

    function reloadFromBridge() {
        if (!bridge) return
        bridge.launcherSnapshot()
    }

    // The picker rows keep the optimistic local update they had; the
    // authoritative snapshot arrives on launcherSnapshotChanged below.
    function saveDisplayMode(index) {
        displayModeIndex = index
        displayMode = displayModes[index] || "bottom"
        if (bridge)
            bridge.updateLauncherDisplayMode(displayMode)
    }

    function saveFontWeight(index) {
        fontWeightIndex = index
        fontWeight = fontWeights[index] || "normal"
        if (bridge)
            bridge.updateLauncherProfileFontWeight(displayMode, fontWeight)
    }

    function saveIconSize(index) {
        iconSizeIndex = index
        iconSize = iconSizes[index] || "medium"
        if (bridge)
            bridge.updateLauncherProfileIconSize(displayMode, iconSize)
    }

    function saveDensity(index) {
        densityIndex = index
        density = densities[index] || "balanced"
        if (bridge)
            bridge.updateLauncherProfileDensity(displayMode, density)
    }

    function resetCurrentProfile() {
        if (!bridge)
            return
        bridge.resetLauncherLayoutProfile(displayMode)
    }

    Connections {
        target: launcherPage.bridge
        enabled: launcherPage.bridge !== null
        function onLauncherSnapshotChanged(snap) {
            launcherPage.applySnapshot(snap)
            if (launcherPage.bridge.lastError)
                launcherPage.errorText = I18n.tr(launcherPage.bridge.lastError)
        }
    }

    Component.onCompleted: reloadFromBridge()

    Text {
        text: I18n.tr("Display shape").toUpperCase()
        color: colors.secondaryText
        font.pixelSize: 12
        font.weight: Font.DemiBold
        Layout.leftMargin: 13
    }

    Rectangle {
        Layout.fillWidth: true
        color: colors.card
        radius: 18
        implicitHeight: 54

        Item {
            anchors.fill: parent
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12
                Controls.SettingIcon {
                    colors: launcherPage.colors
                    materialForm: launcherPage.materialForm
                    symbol: "❖"
                    tint: "#ff9500"
                }
                Text {
                    text: I18n.tr("Launcher shape")
                    color: colors.primaryText
                    font.pixelSize: 14
                }
                Item { Layout.fillWidth: true }
                Controls.SettingsNavBar {
                    colors: launcherPage.colors
                    materialForm: launcherPage.materialForm
                    id: launcherModeNavBar
                    model: [
                        { id: "bottom",     label: I18n.tr("Dock to bottom") },
                        { id: "bottomWide", label: I18n.tr("Compact bottom") },
                        { id: "center",     label: I18n.tr("Center on screen") },
                        { id: "fullscreen", label: I18n.tr("Fullscreen") }
                    ]
                    itemWidthOverride: 76
                    currentIndex: launcherPage.displayModeIndex
                    onSelectionChanged: function(index) {
                        launcherPage.saveDisplayMode(index)
                    }
                }
            }
        }
    }

    Text {
        text: I18n.tr("Grid, icons and text").toUpperCase()
        color: colors.secondaryText
        font.pixelSize: 12
        font.weight: Font.DemiBold
        Layout.leftMargin: 13
        Layout.topMargin: 14
    }

    Rectangle {
        Layout.fillWidth: true
        color: colors.card
        radius: 18
        implicitHeight: 221

        Column {
            anchors.fill: parent

            Item {
                width: parent.width
                height: 54
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12
                    Controls.SettingIcon {
                        colors: launcherPage.colors
                        materialForm: launcherPage.materialForm
                        symbol: "◉"
                        tint: "#ff9500"
                    }
                    Text {
                        text: I18n.tr("Icon Size")
                        color: colors.primaryText
                        font.pixelSize: 14
                    }
                    Item { Layout.fillWidth: true }
                    Controls.SettingsNavBar {
                        colors: launcherPage.colors
                        materialForm: launcherPage.materialForm
                        model: [
                            { id: "small", label: I18n.tr("Small") },
                            { id: "medium", label: I18n.tr("Medium") },
                            { id: "large", label: I18n.tr("Large") }
                        ]
                        itemWidthOverride: 56
                        currentIndex: launcherPage.iconSizeIndex
                        onSelectionChanged: function(index) {
                            launcherPage.saveIconSize(index)
                        }
                    }
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 53
                height: 1
                color: colors.separator
            }

            Item {
                width: parent.width
                height: 54
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12
                    Controls.SettingIcon {
                        colors: launcherPage.colors
                        materialForm: launcherPage.materialForm
                        symbol: "↔"
                        tint: "#5ac8fa"
                    }
                    Text {
                        text: I18n.tr("Grid density")
                        color: colors.primaryText
                        font.pixelSize: 14
                    }
                    Item { Layout.fillWidth: true }
                    Controls.SettingsNavBar {
                        colors: launcherPage.colors
                        materialForm: launcherPage.materialForm
                        model: [
                            { id: "compact", label: I18n.tr("Compact") },
                            { id: "balanced", label: I18n.tr("Standard") },
                            { id: "spacious", label: I18n.tr("Comfortable") }
                        ]
                        itemWidthOverride: 56
                        currentIndex: launcherPage.densityIndex
                        onSelectionChanged: function(index) {
                            launcherPage.saveDensity(index)
                        }
                    }
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 53
                height: 1
                color: colors.separator
            }

            Item {
                width: parent.width
                height: 54
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12
                    Controls.SettingIcon {
                        colors: launcherPage.colors
                        materialForm: launcherPage.materialForm
                        symbol: "B"
                        tint: "#ff9500"
                    }
                    Text {
                        text: I18n.tr("Font weight")
                        color: colors.primaryText
                        font.pixelSize: 14
                    }
                    Item { Layout.fillWidth: true }
                    Controls.SettingsNavBar {
                        colors: launcherPage.colors
                        materialForm: launcherPage.materialForm
                        id: launcherFontWeightNavBar
                        model: [
                            { id: "normal", label: I18n.tr("General") },
                            { id: "medium", label: I18n.tr("Medium black") },
                            { id: "bold",   label: I18n.tr("Bold") }
                        ]
                        itemWidthOverride: 56
                        currentIndex: launcherPage.fontWeightIndex
                        onSelectionChanged: function(index) {
                            launcherPage.saveFontWeight(index)
                        }
                    }
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 53
                height: 1
                color: colors.separator
            }

            Item {
                width: parent.width
                height: 54
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12
                    Controls.SettingIcon {
                        colors: launcherPage.colors
                        materialForm: launcherPage.materialForm
                        symbol: "↺"
                        tint: "#8e8e93"
                    }
                    Text {
                        text: I18n.tr("Restore recommended layout")
                        color: colors.primaryText
                        font.pixelSize: 14
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: I18n.tr("Current shape only")
                        color: colors.secondaryText
                        font.pixelSize: 11
                    }
                    Rectangle {
                        width: 52
                        height: 26
                        radius: 13
                        color: resetProfileMouse.containsMouse
                            ? Qt.rgba(0.04, 0.52, 1.0, 0.20)
                            : Qt.rgba(0.04, 0.52, 1.0, 0.12)
                        Text {
                            anchors.centerIn: parent
                            text: I18n.tr("Restore")
                            color: colors.dark ? "#64b5ff" : "#0066cc"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                        MouseArea {
                            id: resetProfileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: launcherPage.resetCurrentProfile()
                        }
                    }
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 13
        Layout.rightMargin: 13
        visible: launcherPage.errorText.length > 0
        text: launcherPage.errorText
        color: "#ff453a"
        font.pixelSize: 12
        wrapMode: Text.Wrap
    }
}
