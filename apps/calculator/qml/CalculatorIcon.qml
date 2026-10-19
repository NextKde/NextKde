import QtQuick

// Outline glyphs for the chrome the reference draws but the keypad does not
// label: the two round title-strip buttons, the history column's trash can,
// the calculator badge the wide key turns into while that column is open, and
// the marks the mode menu puts beside its items. Same inline-SVG technique as
// the shared VectorIcon, kept local so the app carries no dependency on a
// module it does not otherwise use.
//
// `basic` is the menu's own "basic calculator" mark — the four operators set
// two by two — traced from the reference rather than typeset, because the four
// glyphs have to sit on one optical grid.
Item {
    id: root

    property string name: "trash"
    property color color: "white"
    property real size: 18
    // The chrome buttons are drawn a size up from the keypad's glyphs and want
    // a proportionally heavier line; everything else keeps the keypad's weight.
    property real strokeWidth: 1.5
    // `calculator` is a knockout — a filled body with the display and the dot
    // grid cut out of it — in both references, so it is painted rather than
    // stroked. Everything else here is a line drawing.
    property bool filled: name === "calculator"

    implicitWidth: size
    implicitHeight: size

    readonly property var paths: ({
        trash: "M4 6.5h16M9.5 6.5V3.5h5v3M6.5 6.5l1 14h9l1-14M10.5 10v7M13.5 10v7",
        // Measured off both references — the iOS title-strip badge and the
        // macOS keypad badge agree to within a pixel — and drawn to the full
        // 24-unit box so it can share a size with the clock beside it. Body
        // 0.69 as wide as it is tall; the display 75% of the body's width and
        // 24% of its height, hung 9.5% below the top; nine dots of 17% of the
        // body's width, pitched 27.5% apart.
        calculator: "M7 1.2h10a2.4 2.4 0 0 1 2.4 2.4v16.8a2.4 2.4 0 0 1-2.4 2.4H7a2.4 2.4 0 0 1-2.4-2.4V3.6A2.4 2.4 0 0 1 7 1.2z"
            + "M7.35 3.25h9.3a.9.9 0 0 1 .9.9v3.38a.9.9 0 0 1-.9.9h-9.3a.9.9 0 0 1-.9-.9V4.15a.9.9 0 0 1 .9-.9z"
            + "M6.69 11.1a1.24 1.24 0 1 0 2.48 0a1.24 1.24 0 1 0-2.48 0"
            + "M10.76 11.1a1.24 1.24 0 1 0 2.48 0a1.24 1.24 0 1 0-2.48 0"
            + "M14.83 11.1a1.24 1.24 0 1 0 2.48 0a1.24 1.24 0 1 0-2.48 0"
            + "M6.69 15.3a1.24 1.24 0 1 0 2.48 0a1.24 1.24 0 1 0-2.48 0"
            + "M10.76 15.3a1.24 1.24 0 1 0 2.48 0a1.24 1.24 0 1 0-2.48 0"
            + "M14.83 15.3a1.24 1.24 0 1 0 2.48 0a1.24 1.24 0 1 0-2.48 0"
            + "M6.69 19.3a1.24 1.24 0 1 0 2.48 0a1.24 1.24 0 1 0-2.48 0"
            + "M10.76 19.3a1.24 1.24 0 1 0 2.48 0a1.24 1.24 0 1 0-2.48 0"
            + "M14.83 19.3a1.24 1.24 0 1 0 2.48 0a1.24 1.24 0 1 0-2.48 0",
        // Nine o'clock: the reference's hands leave the centre upward and to the
        // left, the vertical about 71% of the radius and the horizontal 62%.
        clock: "M21.6 12a9.6 9.6 0 1 1-19.2 0 9.6 9.6 0 1 1 19.2 0M12 5.2v6.8h-5.9",
        basic: "M4 6.5h6M7 3.5v6M14 6.5h6M4.5 15l5 5M9.5 15l-5 5M14 17.5h6M17 14v.8M17 20.2v.8",
        convert: "M21 8.5H4M7.5 5.5L4 8.5l3.5 3M3 15.5h17M16.5 12.5l3.5 3-3.5 3",
        // The done button's mark. Measured off the reference's disc: the tick
        // inks out 42% of the disc and is very nearly as tall as it is wide
        // (43x42), which is what makes the long arm so steep.
        check: "M3.5 12.5L9.8 19L20.5 2",
        // The convert view's swap control: an up arrow beside a down arrow, the
        // two heads at opposite ends. Measured off the reference at 22.2 by 17.4
        // logical, which at a size of 22.2 is the full 24-unit box across and
        // 19.5 units down.
        swap: "M4.2 21V3M0.9 6.3L4.2 3l3.3 3.3M19.8 3v18M16.5 17.7L19.8 21l3.3-3.3",
        // The unit picker's disclosure mark: a stacked up/down chevron pair,
        // 11.8 by 16.6 logical with a 1.6 logical stroke — so the box is the
        // pair's height and the chevrons are narrower than it.
        chevron: "M3.45 9.6L12 1.2l8.55 8.4M3.45 14.4L12 22.8l8.55-8.4",
        // The unit picker's search field: a ring with the handle leaving it at
        // the lower right, drawn to the same 24-unit box as everything else.
        search: "M10.4 3.6a6.8 6.8 0 1 0 0 13.6 6.8 6.8 0 0 0 0-13.6M15.4 15.4L21 21",
        // The scientific keypad's delete key: the reference's tag — a rounded
        // body with its left edge drawn out to a point — with an × inside it.
        // Measured off that key at 39 by 33 device px in a 148 by 89 cell, i.e.
        // 26% of the key's width and 37% of its height, which is 1.17 as wide
        // as it is tall. Drawn to 20.1 by 17.2 units of the box to keep that.
        backspace: "M1.9 12l5.4-8.6h13.2a1.5 1.5 0 0 1 1.5 1.5v14.2a1.5 1.5 0 0 1-1.5 1.5h-13.2z"
            + "M11.9 9.2L17.4 14.8M17.4 9.2L11.9 14.8"
    })

    readonly property string rgb: "rgb(" + Math.round(root.color.r * 255) + ","
        + Math.round(root.color.g * 255) + "," + Math.round(root.color.b * 255) + ")"

    Image {
        anchors.fill: parent
        sourceSize: Qt.size(Math.ceil(root.size * 2), Math.ceil(root.size * 2))
        source: "data:image/svg+xml;utf8," + encodeURIComponent(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path '
            + (root.filled
                ? 'fill="' + root.rgb + '" fill-opacity="' + root.color.a
                    + '" fill-rule="evenodd" stroke="none"'
                : 'fill="none" stroke="' + root.rgb + '" stroke-opacity="' + root.color.a
                    + '" stroke-width="' + root.strokeWidth
                    + '" stroke-linecap="round" stroke-linejoin="round"')
            + ' d="' + (root.paths[root.name] || root.paths.trash) + '"/></svg>')
    }
}
