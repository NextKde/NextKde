/*
    SPDX-FileCopyrightText: 2026 KOS

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts

// KOS sign-in screen (SDDM theme).
//
// Same constraints as the lock screen, and the same reason for them: this is
// SDDM's greeter process, not the shell. No Quickshell, no Kos.Ui, and -- for
// a theme that has to work on a machine where Plasma's QML plugins may not be
// reachable from the greeter -- no Plasma components either. What is left is
// plain QtQuick, so every material here is a gradient or a canvas path, for
// the reason the lock screen spells out in detail: a shader paints nothing
// under a software renderer, and a sign-in screen is not allowed to be blank.
Item {
    id: root

    width: Screen.width
    height: Screen.height

    property string notification: ""
    property bool rejecting: false
    property real shakeOffset: 0
    property int userIndex: 0

    readonly property int userCount: userProbe.count
    readonly property var currentUser: userRecord(root.userIndex)

    function userRecord(index) {
        if (typeof userModel === "undefined" || userModel === null)
            return null
        if (typeof userModel.get !== "function")
            return null
        return userModel.get(index)
    }

    function displayName(record) {
        if (!record)
            return ""
        const real = String(record.realName ?? "")
        return real.length > 0 ? real : String(record.name ?? "")
    }

    function userFace(record) {
        if (!record)
            return ""
        const path = String(record.icon ?? "")
        // A path, not a URL -- same as the lock screen gets from
        // kscreenlocker: it has to be prefixed and encoded segment by segment
        // before an Image will take it.
        return path !== ""
            ? "file://" + path.split("/").map(encodeURIComponent).join("/") : ""
    }

    function login() {
        if (!root.currentUser)
            return
        if (root.currentUser.needsPassword === false) {
            sddm.login(String(root.currentUser.name), "", sessionBox.currentIndex)
            return
        }
        if (passwordField.text === "")
            return
        sddm.login(String(root.currentUser.name), passwordField.text,
                   sessionBox.currentIndex)
    }

    Component.onCompleted: {
        root.userIndex = (typeof userModel !== "undefined"
            && typeof userModel.lastIndex === "number") ? userModel.lastIndex : 0
        passwordField.forceActiveFocus()
    }

    Connections {
        target: typeof sddm !== "undefined" ? sddm : null

        function onLoginFailed() {
            passwordField.text = ""
            root.notification = qsTr("登录失败")
            root.rejecting = true
            rejectAnimation.restart()
            passwordField.forceActiveFocus()
        }
    }

    Timer {
        interval: 3000
        running: root.notification !== ""
        repeat: false
        onTriggered: root.notification = ""
    }

    SequentialAnimation {
        id: rejectAnimation

        NumberAnimation { target: root; property: "shakeOffset"; to: -14; duration: 55 }
        NumberAnimation { target: root; property: "shakeOffset"; to: 11; duration: 55 }
        NumberAnimation { target: root; property: "shakeOffset"; to: -8; duration: 50 }
        NumberAnimation { target: root; property: "shakeOffset"; to: 5; duration: 45 }
        NumberAnimation { target: root; property: "shakeOffset"; to: 0; duration: 40 }
        ScriptAction { script: root.rejecting = false }
    }

    // A Repeater is the only model API that is safe to count on here: it works
    // whether the greeter hands over a list model or a QAbstractItemModel.
    Repeater {
        id: userProbe
        model: typeof userModel !== "undefined" ? userModel : []
        delegate: Item {}
    }

    // ---- background ------------------------------------------------------

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#161a22" }
            GradientStop { position: 1.0; color: "#0b0d12" }
        }
    }

    Image {
        anchors.fill: parent
        source: (typeof config !== "undefined" && String(config.background ?? "") !== "")
            ? "file://" + String(config.background).split("/").map(encodeURIComponent).join("/")
            : ""
        fillMode: Image.PreserveAspectCrop
        visible: source != ""
        asynchronous: true
    }

    // A scrim, so the controls hold up over a light picture.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.28) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.55) }
        }
    }

    // ---- clock -----------------------------------------------------------

    LockClock {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.round(root.height * 0.09)
    }

    // ---- account, field, actions -----------------------------------------

    Column {
        id: centre

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.round(root.height * 0.46)
        width: Math.round(Math.min(root.width * 0.26, 340))
        spacing: Math.round(root.height * 0.018)

        transform: Translate { x: root.shakeOffset }

        // The account. More than one means a row to pick from; the greeter
        // hands over the last one that signed in, which is the right default.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(root.height * 0.012)
            visible: root.userCount > 1

            Repeater {
                model: typeof userModel !== "undefined" ? userModel : []

                delegate: Column {
                    spacing: 6
                    opacity: index === root.userIndex ? 1.0 : 0.45

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.round(root.height * 0.055)
                        height: width
                        radius: width / 2
                        color: Qt.rgba(1, 1, 1, 0.14)

                        Image {
                            anchors.fill: parent
                            source: root.userFace(userModel.get(index))
                            fillMode: Image.PreserveAspectCrop
                            visible: source != ""
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.displayName(userModel.get(index))
                        color: Qt.rgba(1, 1, 1, 0.85)
                        font.pixelSize: 13
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.userIndex = index
                            passwordField.forceActiveFocus()
                        }
                    }
                }
            }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            visible: root.userCount <= 1

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.round(root.height * 0.07)
                height: width
                radius: width / 2
                color: Qt.rgba(1, 1, 1, 0.14)

                Image {
                    anchors.fill: parent
                    source: root.userFace(root.currentUser)
                    fillMode: Image.PreserveAspectCrop
                    visible: source != ""
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.displayName(root.currentUser)
                color: Qt.rgba(1, 1, 1, 0.9)
                font.pixelSize: 15
                font.weight: Font.Medium
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.notification
            visible: text !== ""
            color: Qt.rgba(1, 0.78, 0.78, 0.95)
            font.pixelSize: 13
        }

        TextField {
            id: passwordField

            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width

            echoMode: TextInput.Password
            placeholderText: qsTr("密码")
            horizontalAlignment: TextInput.AlignHCenter
            placeholderTextColor: Qt.rgba(1, 1, 1, 0.48)
            selectionColor: Qt.rgba(1, 1, 1, 0.28)
            selectedTextColor: "white"
            color: "white"
            font.pixelSize: 16
            leftPadding: 18
            rightPadding: 18
            topPadding: 9
            bottomPadding: 9

            onAccepted: root.login()

            // The same glass the lock screen's field is made of, minus the
            // parts that only exist to survive a wallpaper: the lift that
            // keeps the pill off a dark picture, a body that is darker still,
            // and one lit edge along the top.
            background: Item {
                readonly property int cornerRadius: Math.round(height * 0.5)

                Rectangle {
                    anchors.fill: parent
                    radius: parent.cornerRadius
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.20) }
                        GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.12) }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: parent.cornerRadius
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: Qt.rgba(0.06, 0.07, 0.11, 0.32) }
                        GradientStop { position: 0.5; color: Qt.rgba(0.03, 0.04, 0.07, 0.26) }
                        GradientStop { position: 1.0; color: Qt.rgba(0.02, 0.03, 0.05, 0.40) }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: parent.cornerRadius
                    color: "transparent"
                    border.width: 1
                    border.color: root.rejecting
                        ? Qt.rgba(1, 0.42, 0.42, 0.55)
                        : Qt.rgba(1, 1, 1, passwordField.activeFocus ? 0.30 : 0.18)
                }

                Rectangle {
                    x: parent.cornerRadius
                    y: 2
                    width: Math.max(0, parent.width - parent.cornerRadius * 2)
                    height: 2
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.28) }
                        GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: Math.round(root.height * 0.035)

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("登录")
                color: Qt.rgba(1, 1, 1, 0.72)
                font.pixelSize: 14

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    onClicked: root.login()
                }
            }
        }
    }

    // ---- bottom: session and power ---------------------------------------

    Row {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: Math.round(root.height * 0.03)
        spacing: 10

        ComboBox {
            id: sessionBox

            width: Math.round(root.width * 0.16)
            model: typeof sessionModel !== "undefined" ? sessionModel : []
            textRole: "name"
            currentIndex: (typeof sessionModel !== "undefined"
                && typeof sessionModel.lastIndex === "number") ? sessionModel.lastIndex : 0

            background: Rectangle {
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.10)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.18)
            }

            contentItem: Text {
                leftPadding: 14
                rightPadding: 8
                verticalAlignment: Text.AlignVCenter
                text: sessionBox.displayText
                color: Qt.rgba(1, 1, 1, 0.82)
                font.pixelSize: 13
                elide: Text.ElideRight
            }
        }
    }

    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Math.round(root.height * 0.03)
        spacing: Math.round(root.height * 0.015)

        Text {
            text: qsTr("重启")
            color: Qt.rgba(1, 1, 1, 0.6)
            font.pixelSize: 13

            MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                onClicked: sddm.reboot()
            }
        }

        Text {
            text: qsTr("关机")
            color: Qt.rgba(1, 1, 1, 0.6)
            font.pixelSize: 13

            MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                onClicked: sddm.powerOff()
            }
        }
    }
}
