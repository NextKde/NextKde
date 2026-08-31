import QtQuick
import qs.desktop.modules.dock

Item {
    id: root

    property string label: ""
    property string detail: ""
    property real value: 0
    property color accentColor: ThemeService.accentColor

    implicitWidth: 152
    implicitHeight: 86

    Canvas {
        id: ring
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        width: 68
        height: 68
        onPaint: {
            const ctx = getContext("2d")
            const center = width / 2
            const radius = 27
            const start = -Math.PI / 2
            const amount = Math.max(0, Math.min(1, root.value))
            ctx.reset()
            ctx.lineWidth = 7
            ctx.lineCap = "round"
            ctx.strokeStyle = Qt.rgba(ThemeService.foregroundColor.r, ThemeService.foregroundColor.g, ThemeService.foregroundColor.b, 0.14)
            ctx.beginPath()
            ctx.arc(center, center, radius, 0, Math.PI * 2)
            ctx.stroke()
            ctx.strokeStyle = root.accentColor
            ctx.beginPath()
            ctx.arc(center, center, radius, start, start + Math.PI * 2 * amount)
            ctx.stroke()
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: root
            function onValueChanged() { ring.requestPaint() }
            function onAccentColorChanged() { ring.requestPaint() }
        }

        Text {
            anchors.centerIn: parent
            text: Math.round(root.value * 100) + "%"
            color: ThemeService.foregroundColor
            font { family: "SF Pro Display"; pixelSize: 15; weight: Font.DemiBold }
        }
    }

    Column {
        anchors { left: ring.right; leftMargin: 10; right: parent.right; verticalCenter: parent.verticalCenter }
        spacing: 3
        Text {
            text: root.label
            color: ThemeService.foregroundColor
            font { family: "Noto Sans CJK SC"; pixelSize: 13; weight: Font.DemiBold }
        }
        Text {
            width: parent.width
            text: root.detail
            elide: Text.ElideRight
            color: Qt.rgba(ThemeService.foregroundColor.r, ThemeService.foregroundColor.g, ThemeService.foregroundColor.b, 0.62)
            font { family: "SF Pro Display"; pixelSize: 10 }
        }
    }
}
