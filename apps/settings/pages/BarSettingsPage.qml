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
    id: barPage
    required property var colors
    property bool materialForm: false

    Layout.fillWidth: true
    spacing: 12

    property var bridge: null
    property bool barIntegratedWithDock: false
    property int barVisibilityModeIndex: 0
    readonly property var barVisibilityModes: ["always", "smart", "persistent"]
    property int barLayoutModeIndex: 2
    readonly property var barLayoutModes: ["full", "floating", "transparent"]
    // The mac style is a style choice with one intensity knob: the
    // selector turns it on and off, and the tint slider only applies while
    // it is on. Off is the default Bar, outlines and all.
    property bool barMacStyle: false
    // The tint opacity. The shell clamps it to 0..1 (AppearanceConfigService);
    // the slider only ever produces values inside this narrower range, which
    // runs from "barely there" to "nearly opaque plate".
    property real barMacTint: 0.30
    readonly property real minBarMacTint: 0.05
    readonly property real maxBarMacTint: 0.85
    property bool tintDirty: false
    property string errorText: ""

    function barVisibilityModeIndexFromString(mode) {
        const idx = barVisibilityModes.indexOf(mode);
        return idx >= 0 ? idx : 0;
    }

    function barLayoutModeIndexFromString(mode) {
        const idx = barLayoutModes.indexOf(mode);
        return idx >= 0 ? idx : 0;
    }

    function applyState(state) {
        if (!state)
            return;
        barIntegratedWithDock = Boolean(state.barIntegratedWithDock);
        barVisibilityModeIndex = barVisibilityModeIndexFromString(state.barVisibilityMode);
        barLayoutModeIndex = barLayoutModeIndexFromString(state.barLayoutMode);
        barMacStyle = state.barMacStyle === true;
        const macTint = Number(state.barMacTint);
        barMacTint = Number.isFinite(macTint) ? Math.max(minBarMacTint, Math.min(maxBarMacTint, macTint)) : 0.30;
        tintDirty = false;
        errorText = "";
    }

    function refresh() {
        if (!bridge) {
            errorText = I18n.tr("The Settings bridge has not been built");
            return;
        }
        bridge.appearanceSnapshot();
    }

    function setBarMacStyle(enabled) {
        if (!bridge) {
            errorText = I18n.tr("The Settings bridge has not been built");
            return;
        }
        bridge.updateBarMacStyle(enabled);
    }

    // The tint slider previews while dragging and commits on release, like
    // the Dock curvature slider: the shell writes the config once, and the
    // snapshot that comes back is authoritative. It is gated by the style
    // selector, so it only ever runs while the mac style is on.
    function previewBarMacTint(position) {
        const next = Math.round((minBarMacTint + position * (maxBarMacTint - minBarMacTint)) * 100) / 100;
        if (Math.abs(next - barMacTint) <= 0.001)
            return;
        barMacTint = next;
        tintDirty = true;
    }

    function commitBarMacTint() {
        if (!tintDirty)
            return;
        tintDirty = false;
        if (bridge)
            bridge.updateBarMacTint(barMacTint);
    }

    function setBarIntegratedWithDock(enabled) {
        if (!bridge) {
            errorText = I18n.tr("The Settings bridge has not been built");
            return;
        }
        bridge.updateBarIntegratedWithDock(enabled);
    }

    function saveBarVisibilityMode(index) {
        if (!bridge)
            return;
        const mode = barVisibilityModes[index];
        bridge.updateBarVisibilityMode(mode);
    }

    function saveBarLayoutMode(index) {
        if (!bridge)
            return;
        const mode = barLayoutModes[index];
        bridge.updateBarLayoutMode(mode);
    }
    Connections {
        target: barPage.bridge
        enabled: barPage.bridge !== null
        function onAppearanceSnapshotChanged(state) {
            barPage.applyState(state);
            if (barPage.bridge.lastError)
                barPage.errorText = I18n.tr(barPage.bridge.lastError);
        }
    }

    Component.onCompleted: refresh()

    Demo.SettingsGroup {
        id: barLayoutCol
        title: I18n.tr("Display and layout")
        backgroundColor: colors.card

        Demo.SettingsItem {
            title: I18n.tr("Top bar shape")

            Controls.SettingsSelect {
                id: barLayoutNavBar
                textRole: "label"
                colors: barPage.colors
                materialForm: barPage.materialForm
                objectName: "bar-layout-picker"
                model: [
                    {
                        id: "full",
                        label: I18n.tr("Full-width edge to edge")
                    },
                    {
                        id: "floating",
                        label: I18n.tr("Floating capsule")
                    },
                    {
                        id: "transparent",
                        label: I18n.tr("Fully transparent")
                    }
                ]

                currentIndex: barPage.barLayoutModeIndex
                onSelectionChanged: function (index) {
                    barPage.saveBarLayoutMode(index);
                }
            }
        }

        Demo.SettingsItem {
            title: I18n.tr("Bar display")

            Controls.SettingsSelect {
                id: barVisibilityNavBar
                textRole: "label"
                colors: barPage.colors
                materialForm: barPage.materialForm
                objectName: "bar-visibility-picker"
                model: [
                    {
                        id: "always",
                        label: I18n.tr("Always show")
                    },
                    {
                        id: "smart",
                        label: I18n.tr("Smart hide")
                    },
                    {
                        id: "persistent",
                        label: I18n.tr("Keep hidden")
                    }
                ]

                currentIndex: barPage.barVisibilityModeIndex
                onSelectionChanged: function (index) {
                    barPage.saveBarVisibilityMode(index);
                }
            }
        }

        Demo.SettingsItem {
            title: I18n.tr("Bar merges into Dock")
            description: I18n.tr("Only applies when the Dock sits at the bottom; side Docks keep the top Bar automatically")

            Controls.SettingsSwitch {
                checked: barPage.barIntegratedWithDock
                accentColor: colors.role("primary", "#0a84ff")
                trackColor: colors.divider
                onToggled: function (checked) {
                    barPage.setBarIntegratedWithDock(checked);
                }
            }
        }
    }

    Demo.SettingsGroup {
        id: macStyleCol
        title: I18n.tr("Bar style")
        backgroundColor: colors.card

        Demo.SettingsItem {
            title: I18n.tr("mac style")
            description: barPage.barMacStyle ? I18n.tr("Frosted tint layer, outlines removed, ink follows the background") : I18n.tr("Keeps the default style when off (outline and shadow unchanged)")

            Controls.SettingsNavBar {
                id: barMacStyleNavBar
                colors: barPage.colors
                materialForm: barPage.materialForm
                model: [
                    {
                        id: "default",
                        label: I18n.tr("Default")
                    },
                    {
                        id: "mac",
                        label: I18n.tr("mac style")
                    }
                ]
                itemWidthOverride: 76
                currentIndex: barPage.barMacStyle ? 1 : 0
                onSelectionChanged: function (index) {
                    barPage.setBarMacStyle(index === 1);
                }
            }
        }

        Demo.SettingsItem {
            title: I18n.tr("Tint strength")
            description: barPage.barMacStyle ? I18n.tr("Dark gray over light wallpapers, light gray over dark ones; higher is more opaque") : I18n.tr("Only takes effect while “mac style” is on")

            Text {
                // Fixed width so the slider does not jog as the
                // readout grows 9% -> 10% mid-drag.
                horizontalAlignment: Text.AlignRight
                text: Math.round(barPage.barMacTint * 100) + "%"
                color: barPage.barMacStyle ? colors.secondaryText : colors.tertiaryText
                font.pixelSize: 12
            }
            Controls.SettingsSlider {
                id: barMacTintSlider
                accentColor: colors.accent
                trackColor: colors.divider
                // The slider dims itself to 45% while disabled, so
                // the gate is one binding and no extra styling.
                enabled: barPage.barMacStyle
                value: (barPage.barMacTint - barPage.minBarMacTint) / (barPage.maxBarMacTint - barPage.minBarMacTint)
                onPreviewChanged: function (position) {
                    barPage.previewBarMacTint(position);
                }
                onCanceled: {
                    barPage.tintDirty = false;
                    barPage.refresh();
                }
                onCommitRequested: barPage.commitBarMacTint()
            }
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 13
        Layout.rightMargin: 13
        visible: barPage.errorText.length > 0
        text: barPage.errorText
        color: "#ff453a"
        font.pixelSize: 12
        wrapMode: Text.Wrap
    }
}
