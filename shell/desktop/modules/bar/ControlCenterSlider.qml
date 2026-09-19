import QtQuick
import qs.desktop.modules.common
import "../../../shared/qml/controls" as LiquidControls

// One visual language for every slider inside Control Center. Feature rows
// provide only geometry, value, and behavior; track/thumb styling lives here.
//
// The form belongs to the shell, not to the row: a tonal shell gets the
// Material 3 slider (scheme colours on its own track and handle), a glass shell
// keeps the liquid thumb over the translucent track. Rows never choose.
LiquidControls.LiquidSlider {
    height: 30
    materialForm: AppearanceTokens.surface.paintInQml
    trackHeight: 4
    // Material 3: the inactive track rides on the surface variant and the active
    // track + handle take the primary role. Glass: white over the translucent
    // card, which is what the compositor's frost is read against.
    trackColor: AppearanceTokens.surface.pick(
        AppearanceTokens.colors.surfaceVariant, Qt.rgba(1, 1, 1, 0.17))
    accentColor: AppearanceTokens.surface.pick(
        AppearanceTokens.colors.primary, Qt.rgba(1, 1, 1, 0.42))
    thumbColor: "#ffffff"
    thumbBorderColor: "transparent"
}
