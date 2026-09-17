/*
    SPDX-FileCopyrightText: 2026 KOS

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.plasma.private.sessions

// The way out of a locked session: one round glass button in the top-right
// corner, and the session actions behind it.
//
// This is the only file in the theme that imports a Plasma module, and that is
// exactly why LockScreen.qml loads it through a Loader instead of declaring
// it. An import that cannot be resolved inside the greeter fails the whole
// file that declared it, and a lock screen whose password field never loaded
// is a lock screen nobody can get past. Behind a Loader the worst case is a
// missing menu.
//
// Both the actions and their availability come from `SessionManagement`:
// `canSuspend`, `canHibernate`, `canShutdown`, `canReboot`, `canLogout` and
// `canSwitchUser` are answered by logind, so an action that cannot work on
// this machine is simply not drawn. Nothing here decides for itself whether
// the machine can hibernate.
//
// The icon is drawn rather than named. A lock screen has no icon theme loaded
// reliably enough to trust, and a missing icon in the only control on screen
// is worse than a plain glyph.
//
// The root item fills the screen even though the button is one small circle in
// a corner, because the menu needs to be dismissible by clicking anywhere --
// and because a root the size of the button would clip its own popup the
// moment anything set `clip` on an ancestor.
Item {
    id: menu

    readonly property int buttonSize: Math.round(Screen.height * 0.052)
    readonly property int itemHeight: Math.round(Screen.height * 0.044)
    readonly property int menuWidth: Math.round(Screen.height * 0.21)

    property bool open: false

    function close() {
        menu.open = false
    }

    SessionManagement {
        id: sessions
    }

    // Anywhere-but-the-menu dismisses it, the way tapping the wallpaper does
    // on a real lock screen. Disabled while closed, so the password field
    // keeps every click it would otherwise get.
    MouseArea {
        anchors.fill: parent
        enabled: menu.open
        onClicked: menu.close()
    }

    Rectangle {
        id: button

        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Math.round(Screen.height * 0.030)
        anchors.rightMargin: Math.round(Screen.width * 0.028)

        width: menu.buttonSize
        height: menu.buttonSize
        radius: width / 2

        color: buttonArea.containsMouse || menu.open
            ? Qt.rgba(1, 1, 1, 0.20)
            : Qt.rgba(1, 1, 1, 0.10)
        border.width: 1
        border.color: menu.open
            ? Qt.rgba(1, 1, 1, 0.34)
            : Qt.rgba(1, 1, 1, 0.20)

        Behavior on color {
            ColorAnimation {
                duration: 130
            }
        }
        Behavior on border.color {
            ColorAnimation {
                duration: 130
            }
        }

        // The universal power symbol: a ring with a gap at the top, and the
        // stem through it. Painted rather than typeset, because the glyph
        // (U+23FB) is present in maybe half the fonts on a given machine.
        Canvas {
            id: glyph

            anchors.centerIn: parent
            width: Math.round(menu.buttonSize * 0.46)
            height: width

            onPaint: {
                const ctx = getContext("2d")
                const r = width / 2
                const lw = Math.max(1.6, width * 0.10)
                // Half-angle of the gap in the ring, in radians.
                const gap = 0.42

                ctx.clearRect(0, 0, width, height)
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.92)
                ctx.lineWidth = lw
                ctx.lineCap = "round"

                ctx.beginPath()
                ctx.arc(r, r, Math.max(0.5, r - lw / 2 - 0.5),
                        -Math.PI / 2 + gap, -Math.PI / 2 - gap + Math.PI * 2)
                ctx.stroke()

                ctx.beginPath()
                ctx.moveTo(r, r * 0.14)
                ctx.lineTo(r, r * 0.70)
                ctx.stroke()
            }
        }

        MouseArea {
            id: buttonArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: menu.open = !menu.open
        }
    }

    Rectangle {
        id: card

        readonly property int padding: 8

        anchors.top: button.bottom
        anchors.right: button.right
        anchors.topMargin: Math.round(menu.buttonSize * 0.20)

        width: menu.menuWidth
        height: list.implicitHeight + padding * 2

        radius: 14
        color: Qt.rgba(0.03, 0.04, 0.06, 0.84)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.14)

        // Grows out of the button rather than appearing next to it.
        transformOrigin: Item.TopRight
        visible: opacity > 0
        opacity: menu.open ? 1 : 0
        scale: menu.open ? 1 : 0.92

        Behavior on opacity {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 190
                easing.type: Easing.OutBack
                easing.overshoot: 1.3
            }
        }

        Column {
            id: list

            anchors.top: parent.top
            anchors.topMargin: card.padding
            anchors.left: parent.left
            anchors.leftMargin: card.padding
            anchors.right: parent.right
            anchors.rightMargin: card.padding

            SessionAction {
                label: qsTr("切换用户")
                visible: sessions.canSwitchUser
                onTriggered: {
                    menu.close()
                    sessions.switchUser()
                }
            }

            SessionAction {
                label: qsTr("睡眠")
                visible: sessions.canSuspend
                onTriggered: {
                    menu.close()
                    sessions.suspend()
                }
            }

            SessionAction {
                label: qsTr("休眠")
                visible: sessions.canHibernate
                onTriggered: {
                    menu.close()
                    sessions.hibernate()
                }
            }

            Rectangle {
                width: parent.width
                height: visible ? 1 : 0
                visible: sessions.canLogout || sessions.canReboot || sessions.canShutdown
                color: Qt.rgba(1, 1, 1, 0.12)
            }

            SessionAction {
                label: qsTr("注销")
                visible: sessions.canLogout
                onTriggered: {
                    menu.close()
                    sessions.requestLogout()
                }
            }

            SessionAction {
                label: qsTr("重启")
                visible: sessions.canReboot
                onTriggered: {
                    menu.close()
                    sessions.requestReboot()
                }
            }

            SessionAction {
                label: qsTr("关机")
                dangerous: true
                visible: sessions.canShutdown
                onTriggered: {
                    menu.close()
                    sessions.requestShutdown()
                }
            }
        }
    }

    // Escape closes the menu. A Shortcut rather than a key handler, because the
    // password field owns the keyboard and must not be fought for it -- and
    // `Escape` is already the theme's "discard what I typed", so the menu only
    // claims it while it is open.
    Shortcut {
        sequence: "Escape"
        enabled: menu.open
        onActivated: menu.close()
    }

    component SessionAction: Item {
        id: entry

        required property string label
        property bool dangerous: false
        signal triggered()

        width: parent ? parent.width : 0
        height: menu.itemHeight

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: 9
            color: entryArea.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent"

            Behavior on color {
                ColorAnimation {
                    duration: 120
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            x: 16
            text: entry.label
            color: entry.dangerous
                ? Qt.rgba(1, 0.66, 0.66, 0.96)
                : Qt.rgba(1, 1, 1, 0.94)
            font.pixelSize: Math.round(menu.itemHeight * 0.34)
        }

        MouseArea {
            id: entryArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: entry.triggered()
        }
    }
}
