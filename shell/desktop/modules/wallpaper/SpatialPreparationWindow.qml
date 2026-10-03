import Quickshell
import qs.desktop.modules.common

// The shared dialog owns its overlay surface and blur region.
Scope {
    id: root
    property var screen: null
    property bool visible: false
    SpatialPreparationOverlay {
        targetScreen: root.screen
        presentationAllowed: root.visible
    }
}
