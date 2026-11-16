pragma Singleton
import QtQuick
import "IconMap.js" as Map

QtObject {
    readonly property FontLoader loader: FontLoader { source: Qt.resolvedUrl("NextKdeIcons.ttf") }
    readonly property string family: loader.name
    readonly property bool ready: loader.status === FontLoader.Ready
    readonly property var names: Object.keys(Map.glyphs)
    function resolve(name, filled) {
        const key = Map.aliases[name] || name
        return filled && Map.glyphs[key + "_fill"] ? key + "_fill" : key
    }
    function has(name) { return !!Map.glyphs[resolve(name, false)] }
    function glyph(name, filled) {
        if (!name || name === "placeholder-dot") return ""
        return Map.glyphs[resolve(name, filled)] || Map.glyphs.question_square
    }
}
