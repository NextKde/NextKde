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
    id: glassDebugPage
    required property var colors
    property bool materialForm: false
    required property var glassStyles
    Layout.fillWidth: true
    spacing: 12
    property var bridge: null
    property var controls: []
    property bool showAdvanced: false
    property string errorText: ""
    // Which glass style's preset the 材质 rows edit; the shell owns that preset
    // and rewrites kwinrc from it on every appearance sync. The label comes
    // from the same style list the 材质风格 row renders.
    property string presetStyle: "liquid"
    readonly property string presetStyleLabel: glassStyles.labelOf(presetStyle)
    readonly property var visibleControls: controls.filter(function (control) {
        if (showAdvanced)
            return true;
        if (control.section === "Colour")
            return ["Brightness", "Saturation", "Contrast"].indexOf(control.key) >= 0;
        if (control.section !== "Material")
            return false;
        // Keep only controls that visibly contribute to the selected
        // material. Shader-development controls remain under 高级参数.
        const keys = presetStyle === "soft" ? ["RefractionStrength", "MaterialSoftness"] : presetStyle === "frosted" ? ["MaterialSoftness", "MaterialReflectionStrength"] : ["RefractionStrength", "RefractionEdgeSize", "RefractionOffsetStrength"];
        return keys.indexOf(control.key) >= 0;
    })
    function refresh() {
        if (!bridge)
            return;
        bridge.glassDebugSnapshot();
    }
    function updateValue(key, value) {
        if (!bridge) {
            errorText = I18n.tr("Settings bridge unavailable");
            return;
        }
        // Fire-and-forget: the reply re-reads what was actually stored
        // (a preset-backed value passes through the shell's own clamping)
        // and lands on glassDebugSnapshotChanged below.
        bridge.updateGlassDebugValue(key, value);
    }

    Connections {
        target: glassDebugPage.bridge
        enabled: glassDebugPage.bridge !== null
        function onGlassDebugSnapshotChanged(controls, presetStyle) {
            glassDebugPage.controls = controls;
            glassDebugPage.presetStyle = presetStyle;
            glassDebugPage.errorText = I18n.tr(glassDebugPage.bridge.lastError) || "";
        }
    }

    Component.onCompleted: refresh()
    onVisibleChanged: {
        if (visible)
            refresh();
    }

    readonly property var visibleSections: [...new Set(visibleControls.map(control => control.section))]
    Demo.SettingsGroup {
        backgroundColor: colors.card
        Demo.SettingsItem {
            description: I18n.tr("The Material group IS the current material style (") + glassDebugPage.presetStyleLabel + I18n.tr(" ) preset: changes are written to that preset, apply immediately, survive restarts, and switching material styles swaps in the other set.") + I18n.tr("Refraction strength is multiplied by Liquid strength above; effective value = liquid strength × this value.") + I18n.tr("Other groups write straight to kwinrc [Effect-blurplus]; the appearance theme does not manage them and the changes persist;") + I18n.tr("Rows marked Designed value come from the appearance theme and are read-only.")
        }
        Demo.SettingsItem {
            title: I18n.tr("Advanced parameters")
            description: glassDebugPage.showAdvanced ? I18n.tr("Showing all KWin parameters") : I18n.tr("Shows only the core parameters that affect the glass look")
            Controls.SettingsSwitch {
                checked: glassDebugPage.showAdvanced
                onToggled: glassDebugPage.showAdvanced = checked
            }
        }
    }
    Repeater {
        model: glassDebugPage.visibleSections
        delegate: Demo.SettingsGroup {
            id: debugGroup
            required property string modelData
            title: I18n.tr(modelData)
            backgroundColor: colors.card
            Repeater {
                model: glassDebugPage.visibleControls.filter(control => control.section === debugGroup.modelData)
                delegate: Demo.SettingsItem {
                    id: debugRow
                    required property var modelData
                    readonly property var debugItem: modelData
                    property real currentNumber: Number(modelData.value)
                    property bool currentBool: modelData.value === true || String(modelData.value) === "true"
                    property string currentText: String(modelData.value)
                    title: I18n.tr(modelData.label)
                    description: modelData.readOnly === true ? I18n.tr("Designed value") : modelData.presetBacked === true ? I18n.tr("Preset") : ""
                    Text {
                        visible: modelData.type !== "bool" && modelData.type !== "string" && modelData.key !== "TintMode"
                        text: modelData.type === "int" ? String(Math.round(currentNumber)) : currentNumber.toFixed(2)
                        color: colors.secondaryText
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignRight
                    }
                    Controls.SettingsSlider {
                        // The shared controls carry the host's palette, so the
                        // Material form has to hand them the Material accent: their own
                        // default is the iPadOS blue this window was designed with.
                        accentColor: colors.accent

                        visible: (modelData.type === "int" || modelData.type === "real") && modelData.key !== "TintMode" && modelData.readOnly !== true
                        // Ctrl+滚轮一档 = 这个参数自己的 step（整数参数就是 1）
                        wheelStep: (modelData.type === "int" ? 1 : Number(modelData.step)) / Math.max(Number(modelData.max) - Number(modelData.min), 0.001)
                        value: (currentNumber - Number(modelData.min)) / Math.max(Number(modelData.max) - Number(modelData.min), 0.001)
                        trackColor: colors.divider
                        onPreviewChanged: function (position) {
                            const raw = Number(modelData.min) + position * (Number(modelData.max) - Number(modelData.min));
                            currentNumber = modelData.type === "int" ? Math.round(raw) : Math.round(raw / Number(modelData.step)) * Number(modelData.step);
                        }
                        onCanceled: currentNumber = Qt.binding(function () {
                            return Number(modelData.value);
                        })
                        onCommitRequested: glassDebugPage.updateValue(modelData.key, currentNumber)
                    }
                    Controls.SettingsSelect {
                        textRole: "label"
                        visible: modelData.key === "TintMode"
                        colors: glassDebugPage.colors
                        materialForm: glassDebugPage.materialForm
                        model: [
                            {
                                value: 0,
                                label: I18n.tr("Off")
                            },
                            {
                                value: 1,
                                label: I18n.tr("Constant dark")
                            },
                            {
                                value: 2,
                                label: I18n.tr("Follow theme")
                            }
                        ]
                        currentIndex: Math.round(debugRow.currentNumber)
                        onSelectionChanged: function (index) {
                            debugRow.currentNumber = index;
                            glassDebugPage.updateValue(debugRow.debugItem.key, index);
                        }
                    }
                    Controls.SettingsSwitch {
                        visible: modelData.type === "bool"
                        checked: currentBool
                        onToggled: {
                            currentBool = checked;
                            glassDebugPage.updateValue(modelData.key, checked);
                        }
                    }
                    Demo.LiquidTextField {
                        visible: modelData.type === "string"
                        implicitWidth: 170
                        implicitHeight: 24
                        Layout.preferredWidth: 170
                        Layout.minimumWidth: 80
                        text: currentText
                        onEditingFinished: {
                            currentText = text;
                            glassDebugPage.updateValue(modelData.key, text);
                        }
                    }
                }
            }
        }
    }
    Text {
        visible: glassDebugPage.errorText.length > 0
        text: glassDebugPage.errorText
        color: "#ff453a"
        font.pixelSize: 12
    }
}
