import QtQuick
import QtQuick.Controls

// A plain editor inside SettingsGroup; the group owns the only background.
TextField {
    id: editor
    property bool filled: false
    // Standalone title/notes/URL region: identical text origin and typography.
    property bool blockInput: false
    property color fillColor: AppTheme.dark ? "#2C2C2E" : "#E5E5E8"
    property bool invalid: false
    property color outlineColor: "transparent"
    implicitWidth: 150
    implicitHeight: 24
    topPadding: filled ? 3 : 0
    bottomPadding: topPadding
    padding: filled ? 6 : 0
    leftPadding: blockInput ? 12 : padding
    rightPadding: blockInput ? 12 : padding
    font.pixelSize: 12
    font.weight: Font.Normal
    color: AppTheme.text
    placeholderTextColor: AppTheme.mutedText
    selectionColor: AppTheme.accent
    selectedTextColor: AppTheme.accentText
    verticalAlignment: TextInput.AlignVCenter
    selectByMouse: true
    background: Rectangle { radius: 6; color: editor.filled ? editor.fillColor : "transparent" }
    Accessible.description: invalid ? qsTr("Invalid value") : ""
}
