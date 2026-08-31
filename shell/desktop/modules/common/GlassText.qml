import QtQuick

// Text with the glass readability outline baked in. Root type is Text, so
// every property (anchors, font, elide, nested MouseArea, Text.* enums)
// passes through natively — swap `Text {` for `GlassText {` on white/light
// text that sits on translucent glass or directly on the wallpaper.
// The outline is invisible on dark backgrounds and lifts the glyph on bright
// ones. Files that set their own styleColor keep theirs (inline override).
Text {
    style: Text.Outline
    styleColor: Qt.rgba(0.05, 0.08, 0.12, 0.38)
}
