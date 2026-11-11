import QtQuick
import QtQuick.Effects
import "../../../shared/Icons" as Symbols

// Semantic shell adapter. Only branded artwork uses Image.
Item {
    id: root
    // Feature role from ShellIconMap.mjs; raw glyph names remain compatible.
    property string name: ""
    property color color: "#ffffff"
    property real size: 18
    property bool colorized: true
    property bool outlined: false
    property color outlineColor: Qt.rgba(0, 0, 0, 0.5)
    implicitWidth: size
    implicitHeight: size
    readonly property string resolvedName: BundledIcons.resolveName(name)
    readonly property bool fontGlyph: Symbols.IconRegistry.has(resolvedName) || resolvedName === "placeholder-dot"
    readonly property string source: BundledIcons.source(name)
    Symbols.Icon {
        // Controls stretch contentItem to the hit area; keep the requested glyph size.
        size: Math.min(root.size, root.width, root.height)
        anchors.fill: parent
        visible: root.fontGlyph
        name: root.resolvedName
        color: root.color
        outlined: root.outlined
        outlineColor: root.outlineColor
    }
    Image {
        anchors.fill: parent
        visible: !root.fontGlyph
        source: root.fontGlyph ? "" : root.source
        sourceSize: Qt.size(root.size * 2, root.size * 2)
        fillMode: Image.PreserveAspectFit
        layer.enabled: root.colorized || root.outlined
        layer.effect: MultiEffect {
            colorization: root.colorized ? 1.0 : 0.0
            colorizationColor: root.color
            shadowEnabled: root.outlined
            shadowColor: root.outlineColor
            shadowBlur: 0.22
        }
    }
}
