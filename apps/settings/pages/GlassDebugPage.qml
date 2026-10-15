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
    required property var glassStyles
    id: glassDebugPage
    Layout.fillWidth: true
    spacing: 7
    property var bridge: null
    property var controls: []
    property bool showAdvanced: false
    property string errorText: ""
    // Which glass style's preset the 材质 rows edit; the shell owns that preset
    // and rewrites kwinrc from it on every appearance sync. The label comes
    // from the same style list the 材质风格 row renders.
    property string presetStyle: "liquid"
    readonly property string presetStyleLabel: glassStyles.labelOf(presetStyle)
    readonly property var visibleControls: controls.filter(function(control) {
        if (showAdvanced)
            return true
        if (control.section === "Colour")
            return ["Brightness", "Saturation", "Contrast"]
                .indexOf(control.key) >= 0
        if (control.section !== "Material")
            return false
        // Keep only controls that visibly contribute to the selected
        // material. Shader-development controls remain under 高级参数.
        const keys = presetStyle === "soft"
            ? ["RefractionStrength", "MaterialSoftness"]
            : presetStyle === "frosted"
                ? ["MaterialSoftness", "MaterialReflectionStrength"]
                : ["RefractionStrength", "RefractionEdgeSize",
                    "RefractionOffsetStrength"]
        return keys.indexOf(control.key) >= 0
    })
    function refresh() {
        if (!bridge) return
        bridge.glassDebugSnapshot()
    }
    function updateValue(key, value) {
        if (!bridge) {
            errorText = I18n.tr("Settings bridge unavailable")
            return
        }
        // Fire-and-forget: the reply re-reads what was actually stored
        // (a preset-backed value passes through the shell's own clamping)
        // and lands on glassDebugSnapshotChanged below.
        bridge.updateGlassDebugValue(key, value)
    }

    Connections {
        target: glassDebugPage.bridge
        enabled: glassDebugPage.bridge !== null
        function onGlassDebugSnapshotChanged(controls, presetStyle) {
            glassDebugPage.controls = controls
            glassDebugPage.presetStyle = presetStyle
            glassDebugPage.errorText = I18n.tr(glassDebugPage.bridge.lastError) || ""
        }
    }

    Component.onCompleted: refresh()
    onVisibleChanged: {
        if (visible)
            refresh()
    }

    Text {
        Layout.fillWidth: true
        text: I18n.tr("The Material group IS the current material style (") + glassDebugPage.presetStyleLabel
            + I18n.tr(" ) preset: changes are written to that preset, apply immediately, survive restarts, and switching material styles swaps in the other set.")
            + I18n.tr("Refraction strength is multiplied by Liquid strength above; effective value = liquid strength × this value.")
            + I18n.tr("Other groups write straight to kwinrc [Effect-blurplus]; the appearance theme does not manage them and the changes persist;")
            + I18n.tr("Rows marked Designed value come from the appearance theme and are read-only.")
        color: colors.secondaryText
        font.pixelSize: 12
        wrapMode: Text.Wrap
        Layout.leftMargin: 13
        Layout.rightMargin: 13
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 13
        Layout.rightMargin: 13
        Text {
            Layout.fillWidth: true
            text: glassDebugPage.showAdvanced
                ? I18n.tr("Showing all KWin parameters") : I18n.tr("Shows only the core parameters that affect the glass look")
            color: colors.secondaryText
            font.pixelSize: 12
        }
        Switch {
            checked: glassDebugPage.showAdvanced
            onToggled: glassDebugPage.showAdvanced = checked
        }
        Text {
            text: I18n.tr("Advanced parameters")
            color: colors.primaryText
            font.pixelSize: 12
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: debugRows.implicitHeight + 8
        radius: 18
        color: colors.card

        Column {
            id: debugRows
            width: parent.width
            Repeater {
                model: glassDebugPage.visibleControls
                delegate: Item {
                    required property var modelData
                    required property int index
                    // Outer modelData alias: the TintMode Repeater shadows
                    // `modelData` with its own {value,label} items, so the
                    // key-based write-back must reach the debug control's
                    // spec through this name instead.
                    readonly property var debugItem: modelData
                    property real currentNumber: Number(modelData.value)
                    property bool currentBool: modelData.value === true
                        || String(modelData.value) === "true"
                    property string currentText: String(modelData.value)
                    width: debugRows.width
                    height: 72
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.top: parent.top
                        anchors.topMargin: 4
                        text: I18n.tr(modelData.section)
                        visible: index === 0 || glassDebugPage.visibleControls[index - 1].section !== modelData.section
                        color: colors.secondaryText
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                    RowLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 52
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        Text { text: I18n.tr(modelData.label); color: colors.primaryText; font.pixelSize: 13 }
                        Text {
                            // The rows the shell owns: their value is stored in
                            // the active material preset, not in kwinrc.
                            visible: modelData.presetBacked === true
                            text: I18n.tr("Preset")
                            color: colors.secondaryText
                            font.pixelSize: 10
                        }
                        Text {
                            // Derived from a design value on every appearance
                            // sync, so it is shown for reference but offers no
                            // control: an edit here would silently revert.
                            visible: modelData.readOnly === true
                            text: I18n.tr("Designed value")
                            color: colors.secondaryText
                            font.pixelSize: 10
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            visible: modelData.type !== "bool" && modelData.type !== "string"
                                && modelData.key !== "TintMode"
                            text: modelData.type === "int" ? String(Math.round(currentNumber))
                                : currentNumber.toFixed(2)
                            color: colors.secondaryText
                            font.pixelSize: 12
                            Layout.preferredWidth: 48
                            horizontalAlignment: Text.AlignRight
                        }
                        LiquidControls.LiquidSlider {
                            // The shared controls carry the host's palette, so the
                            // Material form has to hand them the Material accent: their own
                            // default is the iPadOS blue this window was designed with.
                            accentColor: colors.accent
                            Layout.preferredWidth: 220
                            visible: (modelData.type === "int" || modelData.type === "real")
                                && modelData.key !== "TintMode"
                                && modelData.readOnly !== true
                            // Ctrl+滚轮一档 = 这个参数自己的 step（整数参数就是 1）
                            wheelStep: (modelData.type === "int"
                                ? 1 : Number(modelData.step))
                                / Math.max(Number(modelData.max)
                                           - Number(modelData.min), 0.001)
                            value: (currentNumber - Number(modelData.min))
                                / Math.max(Number(modelData.max) - Number(modelData.min), 0.001)
                            trackColor: colors.divider
                            onPreviewChanged: function(position) {
                                const raw = Number(modelData.min) + position
                                    * (Number(modelData.max) - Number(modelData.min))
                                currentNumber = modelData.type === "int" ? Math.round(raw)
                                    : Math.round(raw / Number(modelData.step)) * Number(modelData.step)
                            }
                            onCanceled: currentNumber = Qt.binding(function() { return Number(modelData.value) })
                            onCommitRequested: glassDebugPage.updateValue(modelData.key, currentNumber)
                        }
                        Row {
                            visible: modelData.key === "TintMode"
                            spacing: 6
                            property var modes: [
                                { value: 0, label: I18n.tr("Off") },
                                { value: 1, label: I18n.tr("Constant dark") },
                                { value: 2, label: I18n.tr("Follow theme") }
                            ]
                            Repeater {
                                model: parent.modes
                                Rectangle {
                                    required property var modelData
                                    width: 74
                                    height: 30
                                    radius: 15
                                    color: modelData.value === Math.round(currentNumber)
                                        ? (colors.dark ? "#2a6fb0" : "#0066cc")
                                        : colors.divider
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        color: modelData.value === Math.round(currentNumber)
                                            ? "#ffffff" : colors.primaryText
                                        font.pixelSize: 12
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            currentNumber = modelData.value
                                            glassDebugPage.updateValue(debugItem.key, modelData.value)
                                        }
                                    }
                                }
                            }
                        }
                        Switch {
                            visible: modelData.type === "bool"
                            checked: currentBool
                            onToggled: {
                                currentBool = checked
                                glassDebugPage.updateValue(modelData.key, checked)
                            }
                        }
                        TextField {
                            visible: modelData.type === "string"
                            Layout.preferredWidth: 220
                            text: currentText
                            color: colors.primaryText
                            onEditingFinished: {
                                currentText = text
                                glassDebugPage.updateValue(modelData.key, text)
                            }
                        }
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 53
                        anchors.bottom: parent.bottom
                        height: 1
                        color: colors.separator
                        visible: index < glassDebugPage.visibleControls.length - 1
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
