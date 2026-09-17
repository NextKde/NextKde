// Stands in for the wallpaper item kscreenlocker_greet injects. Verification
// only.
//
// The shape matters more than the pixels: the real package is a parent item
// holding the still image it resolved, and LockScreen walks that tree to find
// it. The parent's own rendering is a flat colour on purpose -- in the real
// package it is a C++ item whose texture can come out smaller than the display,
// which is the whole reason the theme draws the file itself. If that takeover
// ever breaks, the preview goes back to flat blue-grey and it is obvious.
import QtQuick

Item {
    Rectangle {
        anchors.fill: parent
        color: "#3a4a63"
    }

    // The file the package resolved. Kept invisible so the preview shows the
    // theme's own copy rather than this one; the walk does not look at
    // visibility (the real package also hides a copy behind its blur loader).
    // The URL is absolute on purpose: the real backend hands over a file URL,
    // and a relative one cannot be re-resolved from the theme.
    Image {
        anchors.fill: parent
        visible: false
        source: Qt.resolvedUrl("wallpaper-sample.png")
        fillMode: Image.PreserveAspectCrop
    }
}
