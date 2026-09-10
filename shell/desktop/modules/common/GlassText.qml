import QtQuick
import QtQuick.Effects

// Text with a soft glass readability shadow baked in. Root type is Text, so
// every property (anchors, font, elide, nested MouseArea, Text.* enums)
// passes through natively — swap `Text {` for `GlassText {` on white/light
// text that sits on translucent glass or directly on the wallpaper.
// The text itself stays sharp; only a centred, diffuse shadow separates it
// from detailed content beneath the glass.
Text {
    id: root

    readonly property real inkLuminance: color.r * 0.2126
        + color.g * 0.7152 + color.b * 0.0722
    // Small UI text needs a stronger halo than an icon: with zero offset the
    // glyph itself covers the shadow centre, so only its diffuse falloff is
    // visible. Keep the ink sharp and put the extra energy outside it.
    // Keep the separation diffuse but lighter: on pale backgrounds the prior
    // shadow could read as a dark lower-edge contour rather than glass depth.
    property real glassShadowOpacity: inkLuminance >= 0.55 ? 0.46 : 0.42
    property real glassShadowBlur: 0.52

    style: Text.Normal
    layer.enabled: root.visible && root.opacity > 0.001
    layer.effect: MultiEffect {
        autoPaddingEnabled: true
        shadowEnabled: true
        shadowColor: root.inkLuminance >= 0.55
            ? Qt.rgba(0.015, 0.025, 0.050, 0.92)
            : Qt.rgba(1.0, 1.0, 1.0, 0.88)
        shadowOpacity: root.glassShadowOpacity
        shadowBlur: root.glassShadowBlur
        // Zero offset creates a soft radial separation, rather than a
        // directional drop shadow or a hard glyph outline.
        shadowHorizontalOffset: 0.0
        shadowVerticalOffset: 0.0
        shadowScale: 1.05
    }
}
