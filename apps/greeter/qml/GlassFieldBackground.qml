import QtQuick
import Quickshell

Rectangle {
    id: root
    property Item backdrop
    property point sampleOrigin: Qt.point(0, 0)
    property bool focused: false
    readonly property bool effectsEnabled: GraphicsInfo.api !== GraphicsInfo.Software && Quickshell.env("QT_QUICK_BACKEND") !== "software" && Quickshell.env("KOS_GREETER_DISABLE_EFFECTS") !== "1"
    radius: height / 2
    color: effect.status === Loader.Ready ? "transparent" : "#800e1b28"
    Loader {
        id: effect
        anchors.fill: parent
        active: root.effectsEnabled && root.backdrop !== null
        source: "GaussianGlass.qml"
        onLoaded: {
            item.backdrop = Qt.binding(function() { return root.backdrop; });
            item.sampleOrigin = Qt.binding(function() { return root.sampleOrigin; });
        }
    }
    Rectangle {
        anchors.fill: parent; radius: root.radius
        gradient: Gradient {
            GradientStop { position: 0; color: "#40ffffff" }
            GradientStop { position: 0.45; color: "#12ffffff" }
            GradientStop { position: 1; color: "#24000000" }
        }
        border.width: 1
        border.color: root.focused ? "#70ffffff" : "#48ffffff"
    }
    Rectangle {
        anchors.fill: parent; anchors.margins: 2; radius: Math.max(0, root.radius - 2)
        color: "transparent"; border.width: 1; border.color: "#20ffffff"
    }
}
