import QtQuick

Item {
    id: root
    property bool opened: false
    property bool showIcons: true
    property bool showGlass: true
    readonly property alias iconGrid: icons
    readonly property alias glassLayer: glass
    width: 1100
    height: 650
    GlassLayer {
        id: glass
        anchors.fill: parent
        opened: root.opened
        visible: root.showGlass
    }
    LauncherIconGrid {
        id: icons
        anchors.centerIn: parent
        opened: root.opened
        visible: root.showIcons
    }
}
