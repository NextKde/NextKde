import QtQuick
import QtQuick.Controls

Pane {
    id: root

    padding: Math.round(18 * AppTheme.densityScale)

    background: KosSurface {
        radius: AppTheme.mediumRadius
        fillColor: AppTheme.cardSurface
        strokeWidth: 1
        strokeColor: AppTheme.border
        elevation: 0.38
    }
}
