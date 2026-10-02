/*
    SPDX-FileCopyrightText: 2026 KOS
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// User activity may arrive after the load-time start was refused, or after a
// noninteractive PAM conversation timed out while the password prompt stayed
// alive. Retry only in response to activity; never keep a camera polling.
Item {
    id: root

    required property var backend
    property bool blocked: false
    property bool unlocked: false
    property var channels: []

    function channelState(channel) {
        for (const state of channels) {
            if (state.channel === channel)
                return state
        }
        const state = {channel: channel, failed: false, retryAfter: 0}
        channels.push(state)
        return state
    }

    function request() {
        if (unlocked || blocked || activityTimer.running)
            return
        // Coalesce key/pointer events from one wake without consuming them.
        activityTimer.interval = 50
        activityTimer.start()
    }

    function authenticate() {
        if (unlocked || blocked)
            return
        const now = Date.now()
        let wait = 0
        // PamAuthenticators::Authenticating is 1. Starting the whole group in
        // that state is a no-op in Plasma 6.7, even if one channel has failed.
        if (backend.state !== 1) {
            for (const state of channels)
                wait = Math.max(wait, state.retryAfter - now)
            if (wait <= 0) {
                for (const state of channels)
                    state.failed = false
                backend.startAuthenticating()
                return
            }
        } else {
            for (const state of channels) {
                const channel = state.channel
                if (!state.failed || !channel || channel.busy)
                    continue
                const remaining = state.retryAfter - now
                if (remaining > 0) {
                    wait = wait > 0 ? Math.min(wait, remaining) : remaining
                    continue
                }
                // Leave the password conversation and its pending secret alone.
                state.failed = false
                channel.tryUnlock()
            }
        }
        if (wait > 0) {
            // Complete this user-requested wake after PAM's own delay. A later
            // failure only records state; it cannot schedule another attempt.
            activityTimer.interval = Math.ceil(wait) + 1
            activityTimer.start()
        }
    }

    Timer {
        id: activityTimer
        onTriggered: root.authenticate()
    }

    Connections {
        target: root.backend

        function onFailed(kind, channel) {
            if (kind !== 0 && channel)
                root.channelState(channel).failed = true
        }

        function onLoginFailedDelayStarted(kind, channel, usecDelay) {
            root.channelState(channel).retryAfter = Date.now() + Math.ceil(usecDelay / 1000)
        }

        function onSucceeded() {
            root.unlocked = true
            activityTimer.stop()
            root.channels = []
        }
    }
}
