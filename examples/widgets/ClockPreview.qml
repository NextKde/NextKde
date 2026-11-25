import QtQuick
import QtQuick.Controls
import "org.nextkde.example.clock" as Clock

ApplicationWindow {
    id: root
    width: 460
    height: 360
    visible: true
    title: "数字时钟 · QML 组件原型"

    readonly property bool live: dataMode.currentIndex === 1
    readonly property var widgetSize: sizeMode.currentIndex === 0 ? [2, 2] : [3, 2]
    property date now: new Date()
    property bool format24h: true
    readonly property var appearance: ({
        isDark: root.palette.window.hsvValue < 0.5,
        foreground: root.palette.windowText,
        transparent: transparentMode.checked
    })
    readonly property var clockData: live ? {
        timeText: root.format24h ? Qt.formatTime(now, "HH:mm") : Qt.formatTime(now, "h:mm AP"),
        dateText: Qt.formatDate(now, "yyyy-MM-dd")
    } : snapshot.getSnapshot(widgetSize)

    Clock.Snapshot { id: snapshot }

    onLiveChanged: if (live) now = new Date()
    Timer {
        interval: 1000
        repeat: true
        running: root.live
        onTriggered: root.now = new Date()
    }

    header: ToolBar {
        Row {
            anchors.centerIn: parent
            spacing: 12
            ComboBox { id: sizeMode; model: ["2×2", "3×2"] }
            ComboBox { id: dataMode; model: ["样例", "实时"] }
            CheckBox { id: transparentMode; text: "透明模式" }
        }
    }

    // A busy backdrop so the transparent-mode outline (Widget.qml) has
    // something to prove itself against -- a flat window colour behind a
    // transparent card would make the outline look pointless.
    Rectangle {
        anchors.fill: parent
        visible: transparentMode.checked
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "#2d6a4f" }
            GradientStop { position: 0.5; color: "#f4a300" }
            GradientStop { position: 1; color: "#7209b7" }
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: root.widgetSize[0] * 120
        height: root.widgetSize[1] * 100
        radius: 22
        color: transparentMode.checked ? "transparent" : root.palette.window
        border.width: transparentMode.checked ? 0 : 1
        border.color: root.palette.mid
        clip: true

        Clock.Widget {
            anchors.fill: parent
            data: root.clockData
            widgetSize: root.widgetSize
            appearance: root.appearance
        }
    }

    // Demonstrates the SDK's optional Settings.qml convention (section 6 of
    // the component guide) end to end, outside Quickshell: the same view
    // this package would hand the host's floating settings popup, editing
    // the same `root.format24h` that the live clock face above reads.
    footer: ToolBar {
        Clock.Settings {
            anchors.centerIn: parent
            data: ({ format24h: root.format24h })
            onApply: next => root.format24h = next.format24h
        }
    }
}

