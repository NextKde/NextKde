import QtQuick

// Text with the glass readability outline baked in. Root type is Text, so
// every property (anchors, font, elide, nested MouseArea, Text.* enums)
// passes through natively — swap `Text {` for `GlassText {` on white/light
// text that sits on translucent glass or directly on the wallpaper.
// The outline follows the ink luminance, protecting both light text on bright
// content and dark text on dark content. Callers can still override styleColor.
Text {
    readonly property real inkLuminance: color.r * 0.2126
        + color.g * 0.7152 + color.b * 0.0722
    style: Text.Outline
    // Vibrancy-like protection in both directions: light ink receives a dark
    // edge and dark ink a soft white edge. The glass stays transparent; only
    // the one-pixel glyph boundary adapts to whatever is moving underneath.
    styleColor: inkLuminance >= 0.55
        ? Qt.rgba(0.03, 0.045, 0.07, 0.36)
        : Qt.rgba(1, 1, 1, 0.42)
}
