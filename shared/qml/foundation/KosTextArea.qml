import QtQuick
import QtQuick.Controls

TextArea {
    id: root
    padding: 12
    color: AppTheme.text
    placeholderTextColor: AppTheme.mutedText
    selectionColor: AppTheme.accent
    selectedTextColor: AppTheme.accentText
    background: KosSurface {
        radius: AppTheme.smallRadius; fillColor: AppTheme.fieldSurface
        elevation: 0; focused: root.activeFocus
    }
}
