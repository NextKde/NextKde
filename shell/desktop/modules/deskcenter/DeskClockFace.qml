import QtQuick

// Keep the dial in the scene graph: Canvas text is rasterized into the dial's
// texture and resampled when the desktop scales or the widget changes size.
Item {
    id: face

    property date date: new Date()
    property color faceColor: "transparent"
    property color rimColor: "transparent"
    property color numeralColor: "#242126"
    property color markColor: "#171717"
    property color hourColor: markColor
    property color minuteColor: markColor
    property color secondColor: "#ee7659"
    property color hubColor: secondColor
    property bool monochrome: false

    readonly property real dialRadius: Math.max(0, Math.min(width, height) / 2 - 3)
    readonly property real numeralRadius: dialRadius * 0.68
    readonly property int numeralSize: Math.max(10, Math.round(dialRadius * 0.18))
    readonly property real strokeScale: Math.max(1, dialRadius / 100)

    // Glass artwork is monochrome. Resolve the small set of dial colours here
    // instead of flattening its text into a saturation-effect texture.
    function ink(value) {
        if (!monochrome)
            return value
        const gray = value.r * 0.2126 + value.g * 0.7152 + value.b * 0.0722
        return Qt.rgba(gray, gray, gray, value.a)
    }

    Rectangle {
        anchors.centerIn: parent
        width: face.dialRadius * 2
        height: width
        radius: width / 2
        color: face.ink(face.faceColor)
        border.color: face.ink(face.rimColor)
        border.width: 1
        antialiasing: true
    }

    Repeater {
        model: 12

        delegate: Rectangle {
            id: mark
            required property int index
            readonly property bool cardinal: index % 3 === 0
            width: (cardinal ? 1.8 : 0.8) * face.strokeScale
            height: (cardinal ? 6 : 3) * face.strokeScale
            radius: width / 2
            x: face.width / 2 - width / 2
            y: face.height / 2 - face.dialRadius + 4 * face.strokeScale
            color: face.ink(face.markColor)
            antialiasing: true
            transform: Rotation {
                origin.x: mark.width / 2
                origin.y: face.dialRadius - 4 * face.strokeScale
                angle: mark.index * 30
            }
        }
    }

    Repeater {
        model: 12

        delegate: Text {
            required property int index
            readonly property real angle: (index + 1) * Math.PI / 6
            text: String(index + 1)
            x: Math.round(face.width / 2 + Math.sin(angle) * face.numeralRadius - width / 2)
            y: Math.round(face.height / 2 - Math.cos(angle) * face.numeralRadius - height / 2)
            color: face.ink(face.numeralColor)
            font.pixelSize: face.numeralSize
            font.weight: Font.Bold
            renderType: Text.QtRendering
        }
    }

    // Only the hands change each second. Leave room inside the numeral ring
    // so the thicker minute hand does not obscure an hour label.
    Rectangle {
        id: hourHand
        width: 2.5 * face.strokeScale
        height: face.dialRadius * 0.48
        radius: width / 2
        x: face.width / 2 - width / 2
        y: face.height / 2 - height
        color: face.ink(face.hourColor)
        antialiasing: true
        transform: Rotation {
            origin.x: hourHand.width / 2
            origin.y: hourHand.height
            angle: (face.date.getHours() % 12 + face.date.getMinutes() / 60) * 30
        }
    }

    Rectangle {
        id: minuteHand
        width: 1.8 * face.strokeScale
        height: face.dialRadius * 0.58
        radius: width / 2
        x: face.width / 2 - width / 2
        y: face.height / 2 - height
        color: face.ink(face.minuteColor)
        antialiasing: true
        transform: Rotation {
            origin.x: minuteHand.width / 2
            origin.y: minuteHand.height
            angle: face.date.getMinutes() * 6
        }
    }

    Rectangle {
        id: secondHand
        width: face.strokeScale
        height: face.dialRadius * 0.76
        radius: width / 2
        x: face.width / 2 - width / 2
        y: face.height / 2 - height
        color: face.ink(face.secondColor)
        antialiasing: true
        transform: Rotation {
            origin.x: secondHand.width / 2
            origin.y: secondHand.height
            angle: face.date.getSeconds() * 6
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: 4.4 * face.strokeScale
        height: width
        radius: width / 2
        color: face.ink(face.hubColor)
        antialiasing: true
    }
}
