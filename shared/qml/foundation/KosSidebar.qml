import QtQuick
import QtQuick.Layouts

// The body keeps its expanded geometry while the viewport closes. Navigation
// controls are never destroyed, so filters, scroll position and focus survive.
Item {
    id: root
    default property alias contents: body.data
    property bool expanded: true
    property real expandedWidth: AppTheme.sidebarWidth
    Layout.fillHeight: true
    Layout.preferredWidth: expanded ? expandedWidth : 0
    Layout.minimumWidth: 0
    Layout.maximumWidth: Layout.preferredWidth
    clip: true
    enabled: expanded

    Behavior on Layout.preferredWidth {
        NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.InOutCubic }
    }
    Rectangle {
        id: body
        width: root.expandedWidth
        height: root.height
        radius: AppTheme.largeRadius
        color: AppTheme.sidebarSurface
        opacity: root.expanded ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: AppTheme.motionFast } }
    }
}
