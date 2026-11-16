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
    id: iconAppearance
    required property var colors
    property bool materialForm: false

    Layout.fillWidth: true
    spacing: 12
    property var bridge: null
    property int modeIndex: 0
    readonly property var modes: ["color", "grayscale", "tint"]
    property real iconOpacity: 0.5
    property string tintColor: "#a855f7"
    property real huePosition: 0.75
    property real tonePosition: 0.5
    property bool opacityDirty: false
    readonly property color pureHue: Qt.hsva(huePosition, 1, 1, 1)
    readonly property color selectedColor: toneColor(tonePosition)
    readonly property var presets: [
        {
            label: I18n.tr("Purple"),
            color: "#a855f7"
        },
        {
            label: I18n.tr("Red"),
            color: "#ef4444"
        },
        {
            label: I18n.tr("Blue"),
            color: "#3b82f6"
        },
        {
            label: I18n.tr("Orange"),
            color: "#f97316"
        }
    ]
    readonly property var hueRamp: [Qt.hsva(0 / 6, 1, 1, 1), Qt.hsva(1 / 6, 1, 1, 1), Qt.hsva(2 / 6, 1, 1, 1), Qt.hsva(3 / 6, 1, 1, 1), Qt.hsva(4 / 6, 1, 1, 1), Qt.hsva(5 / 6, 1, 1, 1), Qt.hsva(6 / 6, 1, 1, 1)]
    readonly property var toneRamp: [Qt.rgba(1, 1, 1, 1), blend(Qt.rgba(1, 1, 1, 1), pureHue, 1 / 3), blend(Qt.rgba(1, 1, 1, 1), pureHue, 2 / 3), pureHue, blend(pureHue, Qt.rgba(0, 0, 0, 1), 1 / 3), blend(pureHue, Qt.rgba(0, 0, 0, 1), 2 / 3), Qt.rgba(0, 0, 0, 1)]

    function blend(first, second, amount) {
        return Qt.rgba(first.r + (second.r - first.r) * amount, first.g + (second.g - first.g) * amount, first.b + (second.b - first.b) * amount, 1);
    }
    function toneColor(position) {
        return position <= 0.5 ? blend(Qt.rgba(1, 1, 1, 1), pureHue, position * 2) : blend(pureHue, Qt.rgba(0, 0, 0, 1), (position - 0.5) * 2);
    }
    function colorHex(color) {
        function channel(value) {
            return Math.round(value * 255).toString(16).padStart(2, "0");
        }
        return "#" + channel(color.r) + channel(color.g) + channel(color.b);
    }
    function colorFromHex(value) {
        const hex = String(value).replace("#", "");
        return hex.length === 6 ? Qt.rgba(parseInt(hex.slice(0, 2), 16) / 255, parseInt(hex.slice(2, 4), 16) / 255, parseInt(hex.slice(4, 6), 16) / 255, 1) : Qt.rgba(0.66, 0.33, 0.97, 1);
    }
    function hueFor(color) {
        const max = Math.max(color.r, color.g, color.b);
        const min = Math.min(color.r, color.g, color.b);
        const delta = max - min;
        if (delta < 0.0001)
            return huePosition;
        let hue = max === color.r ? (color.g - color.b) / delta : (max === color.g ? (color.b - color.r) / delta + 2 : (color.r - color.g) / delta + 4);
        return ((hue / 6) + 1) % 1;
    }
    function nearestTone(color) {
        let best = 0.5;
        let distance = Number.MAX_VALUE;
        for (let step = 0; step <= 100; ++step) {
            const candidate = toneColor(step / 100);
            const delta = Math.pow(candidate.r - color.r, 2) + Math.pow(candidate.g - color.g, 2) + Math.pow(candidate.b - color.b, 2);
            if (delta < distance) {
                distance = delta;
                best = step / 100;
            }
        }
        return best;
    }
    function applyState(state) {
        if (!state)
            return;
        const index = modes.indexOf(state.iconMode);
        modeIndex = index >= 0 ? index : 0;
        iconOpacity = Number.isFinite(Number(state.iconOpacity)) ? Number(state.iconOpacity) : 0.5;
        tintColor = String(state.iconTintColor || "#a855f7").toLowerCase();
        const color = colorFromHex(tintColor);
        huePosition = hueFor(color);
        tonePosition = nearestTone(color);
        opacityDirty = false;
    }
    function refresh() {
        if (bridge)
            bridge.appearanceSnapshot();
    }
    function saveMode(index) {
        if (bridge)
            bridge.updateGlobalIconMode(modes[index]);
    }
    function saveTint(color) {
        if (bridge)
            bridge.updateGlobalIconTintColor(color);
    }
    function commitOpacity() {
        if (!opacityDirty || !bridge)
            return;
        opacityDirty = false;
        bridge.updateGlobalIconOpacity(iconOpacity);
    }

    Connections {
        target: iconAppearance.bridge
        enabled: iconAppearance.bridge !== null
        function onAppearanceSnapshotChanged(state) {
            iconAppearance.applyState(state);
        }
    }

    // Embedded in DisplaySettingsPage, which a composing page may already
    // cover with its own single request.
    property bool suppressInitialRequest: false

    Component.onCompleted: if (!suppressInitialRequest)
        refresh()

    Demo.SettingsGroup {
        id: appearanceRows
        title: I18n.tr("Icon appearance")
        backgroundColor: colors.card

        Demo.SettingsItem {
            title: I18n.tr("Icon color")

            Controls.SettingsSelect {
                textRole: "label"
                colors: iconAppearance.colors
                materialForm: iconAppearance.materialForm
                model: [
                    {
                        id: "color",
                        label: I18n.tr("Colorful")
                    },
                    {
                        id: "grayscale",
                        label: I18n.tr("Black and white")
                    },
                    {
                        id: "tint",
                        label: I18n.tr("Tinted")
                    }
                ]
                currentIndex: iconAppearance.modeIndex
                onSelectionChanged: function (index) {
                    iconAppearance.saveMode(index);
                }
            }
        }

        Demo.SettingsItem {
            visible: iconAppearance.modeIndex > 0
            title: I18n.tr("Opacity")

            Text {
                text: Math.round(iconAppearance.iconOpacity * 100) + "%"
                color: colors.secondaryText
                font.pixelSize: 12
            }
            Controls.SettingsSlider {
                value: iconAppearance.iconOpacity
                trackColor: colors.divider
                // The shared controls carry the host's palette, so the
                // Material form has to hand them the Material accent: their own
                // default is the iPadOS blue this window was designed with.
                accentColor: colors.accent
                onPreviewChanged: function (position) {
                    iconAppearance.iconOpacity = Math.max(0.1, position);
                    iconAppearance.opacityDirty = true;
                }
                onCanceled: {
                    iconAppearance.opacityDirty = false;
                    iconAppearance.refresh();
                }
                onCommitRequested: iconAppearance.commitOpacity()
            }
        }

        Demo.SettingsItem {
            visible: iconAppearance.modeIndex === 2
            title: I18n.tr("Color")

            Controls.SettingsSelect {
                objectName: "iconTintPresetSelect"
                textRole: "label"
                colors: iconAppearance.colors
                materialForm: iconAppearance.materialForm
                model: iconAppearance.presets
                currentIndex: 0
                onSelectionChanged: function (index) {
                    iconAppearance.saveTint(iconAppearance.presets[index].color);
                }
            }
        }

        Demo.SettingsItem {
            visible: iconAppearance.modeIndex === 2
            title: I18n.tr("Custom")

            LiquidControls.ColorRampSlider {
                Layout.preferredWidth: 170
                Layout.preferredHeight: 24
                thumbDiameter: 14
                trackHeight: 4
                value: iconAppearance.huePosition
                rampColors: iconAppearance.hueRamp
                thumbColor: iconAppearance.pureHue
                onPreviewChanged: function (position) {
                    iconAppearance.huePosition = position;
                }
                onCommitRequested: function (position) {
                    iconAppearance.huePosition = position;
                    iconAppearance.saveTint(iconAppearance.colorHex(iconAppearance.selectedColor));
                }
            }
        }

        Demo.SettingsItem {
            visible: iconAppearance.modeIndex === 2
            title: I18n.tr("Light and dark")

            LiquidControls.ColorRampSlider {
                Layout.preferredWidth: 170
                Layout.preferredHeight: 24
                thumbDiameter: 14
                trackHeight: 4
                value: iconAppearance.tonePosition
                rampColors: iconAppearance.toneRamp
                thumbColor: iconAppearance.selectedColor
                onPreviewChanged: function (position) {
                    iconAppearance.tonePosition = position;
                }
                onCommitRequested: function (position) {
                    iconAppearance.tonePosition = position;
                    iconAppearance.saveTint(iconAppearance.colorHex(iconAppearance.selectedColor));
                }
            }
        }
    }
}
