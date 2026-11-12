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
            authenticator.promptTimer.stop()
            authenticator.state = authenticator.idle
            authenticator.graceLocked = true
            authenticator.promptForSecret = ""
            authenticator.pendingPrompt = false
            authenticator.busy = false
            authenticator.inPasswordDelay = false
            authenticator.workerReady = true
            authenticator.promptDelay = -1
            authenticator.responseCount = 0
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

        function test_firstSubmissionWaitsForPrompt_data() {
            return [{tag: "enter", method: "enter"}, {tag: "arrow", method: "arrow"}]
        }

        function test_firstSubmissionWaitsForPrompt(data) {
            const field = loadScreen()
            authenticator.promptDelay = 250
            keyClick(Qt.Key_A)
            if (data.method === "enter") keyClick(Qt.Key_Return)
            else {
                const button = findChild(screen.item, "lockSubmitButton")
                verify(button !== null)
                mouseClick(button, button.width / 2, button.height / 2)
            }
            wait(100)
            compare(authenticator.lastResponded, "")
            compare(authenticator.droppedRespondCount, 0)
            compare(screen.item.entry, "a")
            tryCompare(authenticator, "lastResponded", "a")
            compare(authenticator.responseCount, 1)
            compare(screen.item.entry, "")
            wait(150)
            compare(authenticator.responseCount, 1)
        }

        function test_readyPromptSubmissionDoesNotRestartAuthentication() {
            loadScreen()
            keyClick(Qt.Key_A)
            tryCompare(authenticator, "pendingPrompt", true)
            wait(0)
            const refused = authenticator.refusedStartCount
            keyClick(Qt.Key_Return)
            tryCompare(authenticator, "lastResponded", "a")
            compare(authenticator.refusedStartCount, refused)
            compare(authenticator.responseCount, 1)
        }

        function test_cancelBeforePromptDoesNotReplayPassword() {
            const field = loadScreen()
            authenticator.promptDelay = 250
            keyClick(Qt.Key_A)
            keyClick(Qt.Key_Return)
            tryCompare(authenticator, "busy", true)
            keyClick(Qt.Key_Escape)
            compare(screen.item.entry, "")
            wait(400)
            compare(authenticator.responseCount, 0)
            compare(authenticator.droppedRespondCount, 0)
            compare(screen.item.submissionPending, false)
            // The existing prompt remains usable after cancelling the intent.
            keyClick(Qt.Key_B)
            keyClick(Qt.Key_Return)
            tryCompare(authenticator, "lastResponded", "b")
            compare(authenticator.responseCount, 1)
        }

        function test_repeatedSubmitDoesNotSendTwice() {
            const field = loadScreen()
            authenticator.promptDelay = 250
            keyClick(Qt.Key_A)
            keyClick(Qt.Key_Return)
            keyClick(Qt.Key_Return)
            screen.item.submit()
            tryCompare(authenticator, "lastResponded", "a")
            compare(authenticator.responseCount, 1)
            compare(authenticator.startCount, 1)
            keyClick(Qt.Key_Return)
            wait(150)
            compare(authenticator.responseCount, 1)
        }

        function test_submissionHonorsBackendPasswordDelay() {
            loadScreen()
            authenticator.inPasswordDelay = true
            keyClick(Qt.Key_A)
            keyClick(Qt.Key_Return)
            wait(150)
            compare(authenticator.startCount, 0)
            compare(authenticator.responseCount, 0)
            compare(screen.item.entry, "a")
            authenticator.inPasswordDelay = false
            tryCompare(authenticator, "lastResponded", "a")
            compare(authenticator.responseCount, 1)
        }

        function test_pendingSubmissionDoesNotPollAuthenticators() {
            loadScreen()
            authenticator.workerReady = false
            keyClick(Qt.Key_A)
            keyClick(Qt.Key_Return)
            wait(150)
            const starts = authenticator.refusedStartCount
            compare(authenticator.responseCount, 0)
            compare(authenticator.droppedRespondCount, 0)
            compare(screen.item.entry, "a")
            wait(350)
            compare(authenticator.refusedStartCount, starts)
            keyClick(Qt.Key_Escape)
        }

        function test_expiredSubmissionKeepsFieldWithoutLateReplay() {
            loadScreen()
            authenticator.promptDelay = 300
            const timer = findChild(screen.item, "pendingSubmissionTimer")
            verify(timer !== null)
            timer.interval = 80
            keyClick(Qt.Key_A)
            keyClick(Qt.Key_Return)
            wait(180)
            compare(screen.item.submissionPending, false)
            compare(screen.item.entry, "a")
            compare(authenticator.responseCount, 0)
            tryCompare(authenticator, "pendingPrompt", true)
            wait(0)
            compare(authenticator.responseCount, 0)
            keyClick(Qt.Key_Return)
            tryCompare(authenticator, "lastResponded", "a")
        }

        function test_externalClearCancelsPendingSubmission() {
            loadScreen()
            authenticator.promptDelay = 250
            keyClick(Qt.Key_A)
            keyClick(Qt.Key_Return)
            screen.item.clearPassword()
            compare(screen.item.entry, "")
            wait(400)
            compare(authenticator.responseCount, 0)
            compare(screen.item.submissionPending, false)
        }

        function test_deferredSubmissionPreservesArbitraryCharacters() {
            loadScreen()
            authenticator.promptDelay = 80
            const secret = "P@ss 空格☃ !"
            screen.item.entry = secret
            screen.item.submit()
            tryCompare(authenticator, "lastResponded", secret)
            compare(authenticator.responseCount, 1)
            compare(authenticator.droppedRespondCount, 0)
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
