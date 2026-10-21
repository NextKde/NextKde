import QtQuick
import qs.desktop.modules.common

// One tray entry rendered through the same AppIcon styling the Dock uses.
// Artwork is never substituted: color mode draws the application's own
// pixels, grayscale and tint run the shared shader, and opacity follows the
// global icon setting.
AppIcon {
    id: root
    property var entry: null
    property string originalSource: entry?.icon || ""

    source: originalSource
    opacityMultiplier: IconAppearanceService.mode === "color"
        ? 1.0 : IconAppearanceService.opacity
    saturation: IconAppearanceService.saturation
    tintEnabled: IconAppearanceService.tintEnabled
    tintColor: IconAppearanceService.tintColor
}
