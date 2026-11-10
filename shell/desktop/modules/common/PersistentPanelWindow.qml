import QtQuick
import Quickshell
import Quickshell.Wayland

// A panel window that stays mapped for the shell's whole lifetime and hides by
// transparency, mirroring how DockWindow treats its own surface. KOS popups that
// unmap on every close paid a 120~900 ms first-frame cost on NVIDIA/Wayland
// when they re-mapped (measurable: a bare PopupWindow maps in 16 ms, these
// panels did not), which read as "the panel takes a second to open and its
// slide animation is skipped". Keeping the surface alive moves that cost to
// shell start-up, where nobody sees it.
//
// The owner supplies a PopupMotion (its `motion` property) and drives open /
// close itself; this component only maps the window, follows the motion's
// progress and shapes input. Placement is derived from the surface the anchor
// lives in:
//   panelEdge   which screen edge the bar/dock sits on
//   panelOffset distance from that edge to the panel's near side
//   panelCenter coordinate of the anchor's centre along that edge
// The owner (BarStatusArea) knows the host window geometry and feeds these.
PanelWindow {
    id: window

    required property var motion
    property string panelEdge: "top"
    property real panelOffset: 48
    property real panelCenter: 0
    property real edgeMargin: 4
    property int motionOrigin: Item.Top

    readonly property bool verticalEdge: panelEdge === "left" || panelEdge === "right"
    readonly property var targetScreen: ScreenLifecycle.activeScreen
    readonly property var motionState: motion
    readonly property bool popupInteractive: !!motion && motion.interactive === true

    color: "transparent"
    visible: true
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "kos-popup"
    WlrLayershell.keyboardFocus: popupInteractive
        ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    contentItem.opacity: motion ? motion.progress : 0
    // Hiding the content while the panel is closed is what keeps an always
    // mapped surface free: animations inside it (media progress, waves, ...)
    // would otherwise keep repainting the whole window in the background.
    contentItem.visible: !!window.motion
        && (window.motion.requestedOpen || window.motion.progress > 0)
    contentItem.transformOrigin: window.motionOrigin
    contentItem.enabled: popupInteractive
    mask: popupInteractive ? null : emptyInputRegion

    Region { id: emptyInputRegion }

    // One dimension is sized by the implicit size and positioned by the margin;
    // the other is centred on the anchor along its edge.
    anchors: ({
        top: window.panelEdge === "top" || window.verticalEdge,
        bottom: window.panelEdge === "bottom",
        left: window.panelEdge === "left" || !window.verticalEdge,
        right: window.panelEdge === "right"
    })
    margins {
        top: window.panelEdge === "top"
            ? window.panelOffset
            : (window.verticalEdge
                ? Math.max(window.edgeMargin, Math.round(window.panelCenter
                    - window.implicitHeight / 2)) : 0)
        bottom: window.panelEdge === "bottom" ? window.panelOffset : 0
        left: window.panelEdge === "left"
            ? window.panelOffset
            : (!window.verticalEdge
                ? Math.max(window.edgeMargin, Math.min(
                    Math.round(window.panelCenter - window.implicitWidth / 2),
                    (window.targetScreen ? window.targetScreen.width : 1920)
                        - window.implicitWidth - window.edgeMargin)) : 0)
        right: window.panelEdge === "right" ? window.panelOffset : 0
    }

    // Screen-space rectangle, for the outside-click dismissal that the dock's
    // popup grab used to provide.
    readonly property real globalX: (window.targetScreen ? window.targetScreen.x : 0)
        + (window.anchors && window.anchors.left
            ? window.margins.left
            : (window.targetScreen ? window.targetScreen.width : 0)
                - window.margins.right - window.width)
    readonly property real globalY: (window.targetScreen ? window.targetScreen.y : 0)
        + (window.anchors && window.anchors.top
            ? window.margins.top
            : (window.targetScreen ? window.targetScreen.height : 0)
                - window.margins.bottom - window.height)
}
