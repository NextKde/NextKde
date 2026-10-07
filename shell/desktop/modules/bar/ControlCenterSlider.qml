import QtQuick
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../shared/qml/controls" as LiquidControls

// One visual language for every slider inside Control Center. Feature rows
// provide only geometry, value, and behavior; track/thumb styling lives here.
//
// The form belongs to the shell, not to the row: a tonal shell gets the
// Material 3 slider (scheme colours on its own track and handle), a glass shell
// keeps the liquid thumb over the translucent track. Rows never choose.
LiquidControls.LiquidSlider {
    id: root
    height: 30
    materialForm: AppearanceTokens.surface.paintInQml
    trackHeight: 5
    thumbWidth: 30
    thumbHeight: 16
    chromaticAberration: false
    wobbleEnabled: false

    // macOS contrast model:
    // In dark mode: subtle translucent white track, bright white/accent active progress.
    // In light mode: subtle translucent dark track, solid ink/accent active progress.
    trackColor: AppearanceTokens.surface.pick(
        AppearanceTokens.colors.surfaceContainerHighest,
        AppearanceTokens.isDarkTheme ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.10))
    accentColor: AppearanceTokens.surface.pick(
        AppearanceTokens.colors.primary,
        AppearanceTokens.isDarkTheme ? Qt.rgba(1, 1, 1, 0.90) : Qt.rgba(0, 0, 0, 0.72))
    thumbColor: AppearanceTokens.isDarkTheme
        ? Qt.rgba(1, 1, 1, 0.38)
        : Qt.rgba(1, 1, 1, 0.72)
    thumbBorderColor: AppearanceTokens.isDarkTheme
        ? Qt.rgba(1, 1, 1, 0.45)
        : Qt.rgba(0, 0, 0, 0.16)
}
