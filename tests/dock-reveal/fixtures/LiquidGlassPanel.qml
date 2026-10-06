import QtQuick

// Visual-only stand-in: no compositor/glass plugin is required for pointer
// and auto-hide tests. The shipping handle and all its input items are loaded.
Item {
    property real radius: 0
    property real cornerExponent: 2
    property var blurAnchor: null
    property var blurRegion: null
    property color baseColor: "transparent"
    property real surfaceOpacity: 1
    property color ambientPrimary: "transparent"
    property color ambientSecondary: "transparent"
    property real ambientStrength: 0
    property real materialDepth: 0
    property string material: "clear"
    property int ambientTransitionDuration: 0
    property bool bottomEdgeVisible: true
    property bool scrimEnabled: false
    property string scrimLevel: "transparent"
    property real scrimCap: 0.5
    property real scrimDecay: 1.0
}
