/*
    SPDX-FileCopyrightText: 2026 KOS
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtTest
import "../../contents/lockscreen" as LockScreen

Item {
    id: scene
    width: 1200
    height: 800

    property AuthenticatorStub authenticator: AuthenticatorStub {}
    property QtObject config: QtObject {}
    property var wallpaper: null

    Component {
        id: controllerComponent
        LockScreen.WakeAuthentication { backend: scene.authenticator }
    }

    Component {
        id: channelComponent
        QtObject {
            property bool busy: false
            property int starts: 0
            function tryUnlock() {
                starts++
                busy = true
            }
        }
    }

    Loader {
        id: screen
        anchors.fill: parent
        active: false
        source: "../../contents/lockscreen/LockScreen.qml"
    }

    TestCase {
        name: "LockScreenWake"
        when: windowShown

        property var controller
        property var channel

        function init() {
            authenticator.state = authenticator.idle
            authenticator.graceLocked = true
            authenticator.startCount = 0
            authenticator.refusedStartCount = 0
            authenticator.lastResponded = ""
            authenticator.droppedRespondCount = 0
            controller = createTemporaryObject(controllerComponent, scene)
            channel = createTemporaryObject(channelComponent, scene)
        }

        function cleanup() {
            screen.active = false
            wait(0)
        }

        function loadScreen() {
            screen.active = true
            tryCompare(screen, "status", Loader.Ready)
            verify(authenticator.refusedStartCount > 0)
            authenticator.graceLocked = false
            const field = findChild(screen.item, "passwordField")
            verify(field !== null)
            field.forceActiveFocus()
            tryCompare(field, "activeFocus", true)
            tryCompare(screen.item, "reveal", 1)
            waitForRendering(field)
            return field
        }

        function test_keyStartsWithoutPasswordSubmission() {
            loadScreen()
            keyClick(Qt.Key_Shift)
            tryCompare(authenticator, "startCount", 1)
            compare(screen.item.entry, "")
            compare(authenticator.lastResponded, "")
            compare(authenticator.droppedRespondCount, 0)
        }

        function test_clickOnPasswordFieldStartsAuthentication() {
            const field = loadScreen()
            mouseClick(field, field.width / 2, field.height / 2)
            tryCompare(authenticator, "startCount", 1)
            compare(authenticator.lastResponded, "")
        }

        function test_typingAndSubmitPreservePassword() {
            loadScreen()
            keyClick(Qt.Key_A)
            keyClick(Qt.Key_B)
            keyClick(Qt.Key_C)
            compare(screen.item.entry, "abc")
            tryCompare(authenticator, "startCount", 1)
            keyClick(Qt.Key_Return)
            compare(authenticator.lastResponded, "abc")
            compare(authenticator.droppedRespondCount, 0)
            compare(screen.item.entry, "")
            wait(100)
            compare(authenticator.startCount, 1)
        }

        function test_escapeDoesNotStartAuthentication() {
            loadScreen()
            screen.item.entry = "partial"
            keyClick(Qt.Key_Escape)
            compare(screen.item.entry, "")
            wait(100)
            compare(authenticator.startCount, 0)
        }

        function test_keyRetriesTimedOutChannelWithoutResettingPassword() {
            loadScreen()
            authenticator.state = authenticator.authenticating
            screen.item.entry = "partial password"
            authenticator.failed(2, channel)
            keyClick(Qt.Key_Shift)
            tryCompare(channel, "starts", 1)
            compare(authenticator.startCount, 0)
            compare(screen.item.entry, "partial password")
            keyClick(Qt.Key_Shift)
            wait(100)
            compare(channel.starts, 1)
        }

        function test_retryHonorsPamDelayAndDoesNotPoll() {
            authenticator.state = authenticator.authenticating
            authenticator.loginFailedDelayStarted(2, channel, 350000)
            authenticator.failed(2, channel)
            for (let i = 0; i < 20; ++i)
                controller.request()
            wait(150)
            compare(channel.starts, 0)
            tryCompare(channel, "starts", 1)
            channel.busy = false
            authenticator.failed(2, channel)
            wait(150)
            compare(channel.starts, 1)
            controller.request()
            tryCompare(channel, "starts", 2)
        }

        function test_idleGroupHonorsPamDelay() {
            authenticator.graceLocked = false
            authenticator.loginFailedDelayStarted(0, null, 350000)
            controller.request()
            wait(150)
            compare(authenticator.startCount, 0)
            tryCompare(authenticator, "startCount", 1)
        }

        function test_runningChannelIsNotRetried() {
            authenticator.state = authenticator.authenticating
            channel.busy = true
            authenticator.failed(2, channel)
            controller.request()
            wait(100)
            compare(channel.starts, 0)
        }

        function test_passwordRejectionDelayBlocksActivity() {
            authenticator.graceLocked = false
            controller.blocked = true
            controller.request()
            wait(100)
            compare(authenticator.startCount, 0)
        }

        function test_successCancelsPendingWake() {
            authenticator.graceLocked = false
            controller.request()
            authenticator.succeeded()
            wait(100)
            controller.request()
            wait(100)
            compare(authenticator.startCount, 0)
        }
    }
}
