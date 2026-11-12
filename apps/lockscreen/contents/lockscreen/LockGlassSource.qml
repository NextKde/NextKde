// SPDX-FileCopyrightText: 2026 KOS
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Window
import QtQuick.Effects

// One shared texture for all cards. Only the wallpaper scene is sampled: never
// passwords, windows underneath the lock, or the cards themselves.
Item {
    id: root
    property Item backdrop: null
    readonly property alias texture: texture
    MultiEffect {
        id: blurred
        anchors.fill: parent
        source: root.backdrop
        blurEnabled: true
        blurMax: 48
        blur: 0.65
        autoPaddingEnabled: false
    }
    ShaderEffectSource {
        id: texture
        anchors.fill: parent
        sourceItem: blurred
        hideSource: true
        visible: false
        live: true
        mipmap: true
        textureSize: Qt.size(Math.max(1, Math.round(root.width * Screen.devicePixelRatio / 2)),
                             Math.max(1, Math.round(root.height * Screen.devicePixelRatio / 2)))
    }
}
