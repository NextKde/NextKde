import QtQuick
import QtQuick.Controls

TextArea {
    id: editor
    property bool filled: false
    // Standalone title/notes/URL region: identical text origin and typography.
    property bool blockInput: false
    property color fillColor: AppTheme.dark ? "#2C2C2E" : "#E5E5E8"
    implicitWidth: 150
    padding: filled ? 6 : 0
    leftPadding: blockInput ? 12 : padding
    rightPadding: blockInput ? 12 : padding
    topPadding: blockInput ? 4 : padding
    bottomPadding: topPadding
    font.weight: Font.Normal
    font.pixelSize: 12
    color: AppTheme.text
    placeholderTextColor: AppTheme.mutedText
    selectionColor: AppTheme.accent
    selectedTextColor: AppTheme.accentText
    wrapMode: TextEdit.Wrap
    selectByMouse: true
    background: Rectangle { radius: 6; color: editor.filled ? editor.fillColor : "transparent" }
}
