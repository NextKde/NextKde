import QtQuick

// Brief, non-interactive feedback shared by Shell actions. Hosts include
// blurRegion in their window's blur union, just like other glass panels.
LiquidGlassPanel {
    id: root

    property string message: ""
    property string iconName: "check"
    property int timeout: 1600
    property bool shown: false

    function show(text, icon) {
        message = text
        iconName = icon || "check"
        shown = true
        hold.restart()
    }
    function dismiss() {
        hold.stop()
        shown = false
    }

    implicitWidth: content.implicitWidth + 28
    implicitHeight: 36
    width: implicitWidth
    height: implicitHeight
    radius: height / 2
    material: "regular"
    scrimEnabled: AppearanceTokens.surface.usesBackdrop
    scrimLevel: "readable"
    useKwinEffect: AppearanceTokens.surface.usesKwinBlur
    fallbackEnabled: AppearanceTokens.surface.paintInQml
    blurAnchor: root
    enabled: false
    visible: opacity > 0
    opacity: shown ? 1 : 0
    scale: shown ? 1 : 0.96
    Accessible.name: message
    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 7
        BundledIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.iconName
            size: 15
            color: root.foregroundColor
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.message
            color: root.foregroundColor
            font.pixelSize: 12
            font.weight: Font.Medium
        }
    }
    Timer {
        id: hold
        interval: root.timeout
        onTriggered: root.shown = false
    }
}
