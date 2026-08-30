pragma Singleton

import QtQuick

QtObject {
    id: theme

    readonly property SystemPalette systemPalette: SystemPalette {
        colorGroup: SystemPalette.Active
    }

    readonly property bool dark: {
        const base = systemPalette.window
        return base.r * 0.2126 + base.g * 0.7152 + base.b * 0.0722 < 0.5
    }

    readonly property color window: dark ? "#111318" : "#eef2f8"
    readonly property color windowRaised: dark ? "#191c23" : "#ffffff"
    readonly property color sidebar: dark ? "#161920" : "#e3e9f2"
    readonly property color card: dark
        ? Qt.rgba(1, 1, 1, 0.075)
        : Qt.rgba(1, 1, 1, 0.76)
    readonly property color cardHover: dark
        ? Qt.rgba(1, 1, 1, 0.12)
        : Qt.rgba(1, 1, 1, 0.94)
    readonly property color border: dark
        ? Qt.rgba(1, 1, 1, 0.11)
        : Qt.rgba(0.10, 0.16, 0.25, 0.13)
    readonly property color text: dark ? "#f5f7fb" : "#172033"
    readonly property color mutedText: dark ? "#a9b0bd" : "#657087"
    readonly property color accent: "#4f8cff"
    readonly property color positive: "#39c487"
    readonly property color warning: "#ffb84d"
    readonly property color destructive: "#ff5f68"

    readonly property int smallRadius: 10
    readonly property int mediumRadius: 16
    readonly property int largeRadius: 24
    readonly property int spacing: 12
    readonly property int pageMargin: 24

    function withAlpha(colorValue, alpha) {
        return Qt.rgba(colorValue.r, colorValue.g, colorValue.b, alpha)
    }
}
