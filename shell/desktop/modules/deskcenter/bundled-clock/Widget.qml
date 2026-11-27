import QtQuick

Item {
    id: root

    required property var data
    required property var widgetSize
    required property var appearance
    readonly property bool wide: Number(widgetSize?.[0] ?? 1) >= 2
    readonly property var backgroundSpec: appearance.isDark
        ? ({ startColor: "#263d62", endColor: "#141d35" })
        : ({ startColor: "#d9efff", endColor: "#f3e8ff" })

    // Item.data is also Qt Quick's default child list. Keep the SDK input
    // named data and assign the visual child through Item.children.
    children: Column {
        anchors.centerIn: parent
        width: parent.width * 0.86
        spacing: root.height * 0.04

        Text {
            width: parent.width
            height: root.wide ? root.height * 0.42 : root.height * 0.40
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            fontSizeMode: Text.Fit
            font.pixelSize: Math.max(1, Math.floor(height * 0.90))
            font.weight: Font.DemiBold
            color: root.appearance.foreground
            text: root.data.timeText
            // appearance.transparent means the host painted no card behind
            // this content at all (not just "glass"), so there is no
            // guaranteed contrast against whatever sits behind it -- an
            // outline keeps the digits legible over any wallpaper.
            style: root.appearance.transparent ? Text.Outline : Text.Normal
            styleColor: root.appearance.isDark ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(1, 1, 1, 0.65)
        }

        Text {
            visible: root.wide
            width: parent.width
            height: root.height * 0.18
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            fontSizeMode: Text.Fit
            font.pixelSize: Math.max(1, Math.floor(height * 0.78))
            color: root.appearance.foreground
            text: root.data.dateText
            style: root.appearance.transparent ? Text.Outline : Text.Normal
            styleColor: root.appearance.isDark ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(1, 1, 1, 0.65)
        }
    }
}
