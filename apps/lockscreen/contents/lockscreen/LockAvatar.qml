/*
    SPDX-FileCopyrightText: 2026 KOS

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Effects

// The account's face, cut to a circle.
//
// The mask is MultiEffect, which is a shader, and that is a trade that was
// made deliberately: on the GPU session this runs in, the avatar is round; if
// the greeter ever comes up on a software renderer the shader paints nothing
// and the avatar is simply absent. It is decoration -- the name underneath it
// is plain text and cannot fail, and that is the part that has to survive.
//
// It is its own file for the same reason SessionMenu.qml is: an import that
// does not resolve inside the greeter takes down the file that declared it.
// Here the blast radius is one picture instead of the whole lock screen.
Item {
    id: avatar

    // Filled in by the Loader in LockScreen.qml.
    property url source: ""

    Image {
        id: face

        anchors.fill: parent
        source: avatar.source
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        // MultiEffect renders it; showing it as well would draw it twice.
        visible: false
    }

    Rectangle {
        id: cutout

        anchors.fill: parent
        radius: width / 2
        color: "black"
        visible: false
    }

    MultiEffect {
        anchors.fill: parent
        sourceItem: face
        maskEnabled: true
        maskSource: cutout
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }

    // One device pixel of lit edge, so the circle still has a contour when the
    // picture behind it is pale. Drawn here rather than by the mask because the
    // mask is the one thing here that is allowed to fail.
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: Math.max(1, Screen.devicePixelRatio * 0.5)
        border.color: Qt.rgba(1, 1, 1, 0.22)
    }
}
