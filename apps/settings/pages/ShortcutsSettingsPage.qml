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
    id: shortcutsPage
    required property var colors
    property bool materialForm: false

    Layout.fillWidth: true
    spacing: 12
    property var bridge: null
    property var shortcuts: []
    property string errorText: ""
    readonly property var rowIcons: ({
            "net.local.kos-launcher": {
                symbol: "❖",
                tint: "#ff9500"
            },
            "net.local.kos-window-switcher": {
                symbol: "⌕",
                tint: "#0a84ff"
            },
            "net.local.kos-control-center": {
                symbol: "≋",
                tint: "#5ac8fa"
            },
            "net.local.kos-overview": {
                symbol: "▦",
                tint: "#af52de"
            },
            "net.local.kos-clipboard": {
                symbol: "⧉",
                tint: "#34c759"
            },
            "net.local.kos-show-desktop": {
                symbol: "⌂",
                tint: "#ff375f"
            }
        })

    function applyState(state) {
        if (!state)
            return;
        // A QVariantList nested in the bridge's QVariantMap arrives as an
        // array-LIKE object (has .length) but Array.isArray() is false,
        // so the list must be copied into a real JS array here or the
        // Repeater silently renders nothing.
        const raw = state.shortcuts;
        shortcuts = Array.isArray(raw) ? raw : (raw && raw.length !== undefined ? Array.prototype.slice.call(raw) : []);
        errorText = state.error || "";
    }

    function refresh() {
        if (!bridge) {
            errorText = I18n.tr("The Settings bridge has not been built");
            return;
        }
        bridge.shortcutsSnapshot();
    }

    function saveBinding(id, combo) {
        if (!bridge)
            return;
        bridge.updateShortcut(id, combo);
    }

    function resetBinding(id) {
        if (!bridge)
            return;
        bridge.resetShortcut(id);
    }

    Connections {
        target: shortcutsPage.bridge
        enabled: shortcutsPage.bridge !== null
        function onShortcutsSnapshotChanged(state) {
            shortcutsPage.applyState(state);
            if (shortcutsPage.bridge.lastError)
                shortcutsPage.errorText = I18n.tr(shortcutsPage.bridge.lastError);
        }
    }

    // Maps a raw key event to its kglobalaccel PortableText name.
    // Returns "" for lone modifier presses so recording keeps waiting.
    function keyDisplayName(event) {
        if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z)
            return String.fromCharCode(event.key);
        if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9)
            return String.fromCharCode(event.key);
        if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F24)
            return "F" + (event.key - Qt.Key_F1 + 1);
        switch (event.key) {
        case Qt.Key_Space:
            return "Space";
        case Qt.Key_Tab:
            return "Tab";
        case Qt.Key_Backspace:
            return "Backspace";
        case Qt.Key_Return:
            return "Return";
        case Qt.Key_Enter:
            return "Enter";
        case Qt.Key_Insert:
            return "Ins";
        case Qt.Key_Delete:
            return "Del";
        case Qt.Key_Home:
            return "Home";
        case Qt.Key_End:
            return "End";
        case Qt.Key_Left:
            return "Left";
        case Qt.Key_Up:
            return "Up";
        case Qt.Key_Right:
            return "Right";
        case Qt.Key_Down:
            return "Down";
        case Qt.Key_PageUp:
            return "PgUp";
        case Qt.Key_PageDown:
            return "PgDown";
        case Qt.Key_Print:
            return "Print";
        case Qt.Key_Pause:
            return "Pause";
        }
        const text = String(event.text || "");
        if (text.length === 1) {
            const upper = text;
            const code = upper.charCodeAt(0);
            if (code >= 0x21 && code <= 0x7e)
                return upper;
        }
        return "";
    }

    Component.onCompleted: refresh()

    Text {
        text: I18n.tr("Click a key capsule then press the new combination to rebind; Esc cancels.")
        color: colors.secondaryText
        font.pixelSize: 12
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        Layout.leftMargin: 13
        Layout.rightMargin: 13
    }

    Demo.SettingsGroup {
        backgroundColor: colors.card
        Repeater {
            model: shortcutsPage.shortcuts
            delegate: Demo.SettingsItem {
                id: shortcutRow
                required property var modelData
                readonly property string rowCombo: modelData.combo || ""
                title: modelData.description
                description: modelData.custom ? I18n.tr("Custom shortcut") : I18n.tr("Default shortcut")
                Demo.LiquidActionButton {
                    visible: shortcutRow.modelData.custom
                    text: I18n.tr("Reset to default")
                    materialForm: true
                    implicitHeight: 24
                    cornerRadius: 6
                    onClicked: shortcutsPage.resetBinding(shortcutRow.modelData.id)
                }
                Demo.LiquidActionButton {
                    id: comboPill
                    property bool recording: false
                    implicitWidth: 158
                    implicitHeight: 24
                    materialForm: true
                    cornerRadius: 6
                    text: recording ? I18n.tr("Press a new key combination…") : (shortcutRow.rowCombo || I18n.tr("Tap to configure"))
                    onClicked: {
                        forceActiveFocus();
                        recording = true;
                    }
                    Keys.onPressed: function (event) {
                        if (!comboPill.recording)
                            return;
                        event.accepted = true;
                        if (event.key === Qt.Key_Escape) {
                            comboPill.recording = false;
                            comboPill.focus = false;
                            return;
                        }
                        const name = shortcutsPage.keyDisplayName(event);
                        if (name === "")
                            return;
                        const parts = [];
                        if (event.modifiers & Qt.MetaModifier)
                            parts.push("Meta");
                        if (event.modifiers & Qt.ControlModifier)
                            parts.push("Ctrl");
                        if (event.modifiers & Qt.AltModifier)
                            parts.push("Alt");
                        if (event.modifiers & Qt.ShiftModifier)
                            parts.push("Shift");
                        parts.push(name);
                        comboPill.recording = false;
                        comboPill.focus = false;
                        shortcutsPage.saveBinding(shortcutRow.modelData.id, parts.join("+"));
                    }

                    onActiveFocusChanged: if (!activeFocus)
                        recording = false
                }
            }
        }
    }
    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 13
        Layout.rightMargin: 13
        visible: shortcutsPage.errorText.length > 0
        text: shortcutsPage.errorText
        color: "#ff453a"
        font.pixelSize: 12
        wrapMode: Text.Wrap
    }
}
