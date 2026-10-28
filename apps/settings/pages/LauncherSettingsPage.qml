import Kos.Demo as Demo
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../../../shared/qml/controls" as LiquidControls
import "../../../shared/qml/foundation" as Foundation
import "../../../shared/qml/i18n"
import "../components" as Controls

ColumnLayout {
    id: launcherPage
    required property var colors
    property bool materialForm: false

    Layout.fillWidth: true
    spacing: 12
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
        if (!snapshot)
            return;
        if (snapshot.displayMode !== undefined) {
            displayMode = snapshot.displayMode;
            const idx = displayModes.indexOf(displayMode);
            displayModeIndex = idx >= 0 ? idx : 0;
        }
        const profiles = snapshot.layoutProfiles;
        const profile = profiles && profiles[displayMode] ? profiles[displayMode] : null;
        if (!profile)
            return;
        iconSize = iconSizes.indexOf(profile.iconSize) >= 0 ? profile.iconSize : "medium";
        density = densities.indexOf(profile.density) >= 0 ? profile.density : "balanced";
        fontWeight = fontWeights.indexOf(profile.fontWeight) >= 0 ? profile.fontWeight : "normal";
        iconSizeIndex = iconSizes.indexOf(iconSize);
        densityIndex = densities.indexOf(density);
        fontWeightIndex = fontWeights.indexOf(fontWeight);
    }

    function reloadFromBridge() {
        if (!bridge)
            return;
        bridge.launcherSnapshot();
    }

    // The picker rows keep the optimistic local update they had; the
    // authoritative snapshot arrives on launcherSnapshotChanged below.
    function saveDisplayMode(index) {
        displayModeIndex = index;
        displayMode = displayModes[index] || "bottom";
        if (bridge)
            bridge.updateLauncherDisplayMode(displayMode);
    }

    function saveFontWeight(index) {
        fontWeightIndex = index;
        fontWeight = fontWeights[index] || "normal";
        if (bridge)
            bridge.updateLauncherProfileFontWeight(displayMode, fontWeight);
    }

    function saveIconSize(index) {
        iconSizeIndex = index;
        iconSize = iconSizes[index] || "medium";
        if (bridge)
            bridge.updateLauncherProfileIconSize(displayMode, iconSize);
    }

    function saveDensity(index) {
        densityIndex = index;
        density = densities[index] || "balanced";
        if (bridge)
            bridge.updateLauncherProfileDensity(displayMode, density);
    }

    function resetCurrentProfile() {
        if (!bridge)
            return;
        bridge.resetLauncherLayoutProfile(displayMode);
    }

    Connections {
        target: launcherPage.bridge
        enabled: launcherPage.bridge !== null
        function onLauncherSnapshotChanged(snap) {
            launcherPage.applySnapshot(snap);
            if (launcherPage.bridge.lastError)
                launcherPage.errorText = I18n.tr(launcherPage.bridge.lastError);
        }
    }

    Component.onCompleted: reloadFromBridge()

    Demo.SettingsGroup {
        title: I18n.tr("Display shape")
        backgroundColor: colors.card

        Demo.SettingsItem {
            title: I18n.tr("Launcher shape")

            Controls.SettingsSelect {
                id: launcherModeNavBar
                objectName: "launcherDisplayModeSelect"
                textRole: "label"
                colors: launcherPage.colors
                materialForm: launcherPage.materialForm
                model: [
                    {
                        id: "bottom",
                        label: I18n.tr("Dock to bottom")
                    },
                    {
                        id: "bottomWide",
                        label: I18n.tr("Compact bottom")
                    },
                    {
                        id: "center",
                        label: I18n.tr("Center on screen")
                    },
                    {
                        id: "fullscreen",
                        label: I18n.tr("Fullscreen")
                    }
                ]

                currentIndex: launcherPage.displayModeIndex
                onSelectionChanged: function (index) {
                    launcherPage.saveDisplayMode(index);
                }
            }
        }
    }

    Demo.SettingsGroup {
        title: I18n.tr("Grid, icons and text")
        backgroundColor: colors.card

        Demo.SettingsItem {
            title: I18n.tr("Icon Size")

            Controls.SettingsSelect {
                textRole: "label"
                colors: launcherPage.colors
                materialForm: launcherPage.materialForm
                model: [
                    {
                        id: "small",
                        label: I18n.tr("Small")
                    },
                    {
                        id: "medium",
                        label: I18n.tr("Medium")
                    },
                    {
                        id: "large",
                        label: I18n.tr("Large")
                    }
                ]

                currentIndex: launcherPage.iconSizeIndex
                onSelectionChanged: function (index) {
                    launcherPage.saveIconSize(index);
                }
            }
        }

        Demo.SettingsItem {
            title: I18n.tr("Grid density")

            Controls.SettingsSelect {
                textRole: "label"
                colors: launcherPage.colors
                materialForm: launcherPage.materialForm
                model: [
                    {
                        id: "compact",
                        label: I18n.tr("Compact")
                    },
                    {
                        id: "balanced",
                        label: I18n.tr("Standard")
                    },
                    {
                        id: "spacious",
                        label: I18n.tr("Comfortable")
                    }
                ]

                currentIndex: launcherPage.densityIndex
                onSelectionChanged: function (index) {
                    launcherPage.saveDensity(index);
                }
            }
        }

        Demo.SettingsItem {
            title: I18n.tr("Font weight")

            Controls.SettingsSelect {
                id: launcherFontWeightNavBar
                textRole: "label"
                colors: launcherPage.colors
                materialForm: launcherPage.materialForm
                model: [
                    {
                        id: "normal",
                        label: I18n.tr("General")
                    },
                    {
                        id: "medium",
                        label: I18n.tr("Medium black")
                    },
                    {
                        id: "bold",
                        label: I18n.tr("Bold")
                    }
                ]

                currentIndex: launcherPage.fontWeightIndex
                onSelectionChanged: function (index) {
                    launcherPage.saveFontWeight(index);
                }
            }
        }

        Demo.SettingsItem {
            title: I18n.tr("Restore recommended layout")
            description: I18n.tr("Current shape only")
            Demo.LiquidActionButton {
                text: I18n.tr("Restore")
                materialForm: true
                implicitHeight: 24
                cornerRadius: 6
                onClicked: launcherPage.resetCurrentProfile()
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
