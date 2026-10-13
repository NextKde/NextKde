import QtQuick

// Text with the glass readability outline baked in. Root type is Text, so
// every property (anchors, font, elide, nested MouseArea, Text.* enums)
// passes through natively — swap `Text {` for `GlassText {` on white/light
// text that sits on translucent glass or directly on the wallpaper.
// Light appearance uses clean black type. Dark appearance keeps the existing
// white type with a restrained black readability edge. Callers can still
// override the default color where semantic or accent text is required.
Text {
    // The Bar's mac-style ground paints a plate under the text, so the
    // readability edge has nothing left to do there — it turns this off and
    // lets its own ink carry the contrast.
    property bool outlineEnabled: true
    color: AppearanceTokens.isDarkTheme ? "#ffffff" : "#000000"
    style: outlineEnabled && AppearanceTokens.isDarkTheme
        ? Text.Outline : Text.Normal
    styleColor: outlineEnabled && AppearanceTokens.isDarkTheme
        ? Qt.rgba(0.03, 0.045, 0.07, 0.36) : "transparent"
}
