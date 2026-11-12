/*
    SPDX-FileCopyrightText: 2026 KOS
    SPDX-License-Identifier: GPL-2.0-or-later
*/
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import org.kde.plasma.private.keyboardindicator as KeyboardIndicator

// Loaded by kscreenlocker_greet, never by Quickshell. Authentication, the
// session lock and display lifecycle remain owned by KDE. Optional effects,
// media and notifications must never prevent this input surface from loading.
Item {
    id: root
    property bool viewVisible: false
    property string notification
    signal clearPassword()
    signal notificationRepeated()
    onClearPassword: {
        root.cancelSubmission()
        root.entry = ""
        root.showPassword = false
    }

    property alias entry: inputField.text
    property bool showPassword: false
    property bool passwordPromptReady: false
    property bool submissionPending: false
    property bool responseInFlight: false
    readonly property bool backendPasswordDelay: typeof authenticator.inPasswordDelay === "boolean"
        ? authenticator.inPasswordDelay : authenticator.pamTimeout === true
    onBackendPasswordDelayChanged: {
        if (!root.backendPasswordDelay && root.submissionPending) Qt.callLater(root.resumeSubmission)
    }
    property real shakeOffset: 0
    property bool rejecting: false
    property real reveal: 0
    property real dismiss: 0
    property date now: new Date()
    property bool debug: false
    readonly property real unit: Math.max(0.65, Math.min(height / 1200, width / 720))
    readonly property bool softwareRendering: GraphicsInfo.api === GraphicsInfo.Software
    readonly property bool capsLockOn: capsLockState.locked
    readonly property bool menuOpen: !!sessionMenu.item && sessionMenu.item.open
    readonly property bool mediaEnabled: typeof config === "undefined" || !config || config.showMediaControls !== false
    readonly property bool notificationsEnabled: typeof config !== "undefined" && !!config && config.kosShowNotifications === true
    readonly property string userName: typeof kscreenlocker_userName === "string" ? kscreenlocker_userName : ""
    readonly property string userAvatar: typeof kscreenlocker_userImage === "string" && kscreenlocker_userImage !== ""
        ? "file://" + kscreenlocker_userImage.split("/").map(encodeURIComponent).join("/") : ""
    readonly property var glassTexture: glassSource.item ? glassSource.item.texture : null

    Timer {
        interval: 1000; running: root.Window.window ? root.Window.window.visible : true
        repeat: true; triggeredOnStart: true
        onTriggered: root.now = new Date()
    }
    Timer {
        id: idleTimer
        interval: 30000
        onTriggered: root.discard()
    }
    Timer {
        id: pendingSubmissionTimer
        objectName: "pendingSubmissionTimer"
        interval: 10000
        onTriggered: {
            if (!root.submissionPending) return
            root.cancelSubmission()
            // Keep the field, but expire the intent: never replay a secret much
            // later after a hung/unavailable authenticator starts working again.
            root.notification = qsTr("认证尚未就绪，请重试")
            notificationTimer.restart()
        }
    }
    Timer { id: notificationTimer; interval: 3000; onTriggered: root.notification = "" }
    // Preserve PAM's rejection grace period and WakeAuthentication's per-channel
    // retry state. No background polling of fingerprint/camera authenticators.
    Timer {
        id: graceLockTimer
        interval: 3000
        onTriggered: {
            root.cancelSubmission()
            root.entry = ""
            if (!root.backendPasswordDelay) authenticator.startAuthenticating()
        }
    }
    WakeAuthentication { id: wakeAuthentication; backend: authenticator; blocked: graceLockTimer.running || root.backendPasswordDelay }
    function wake() {
        idleTimer.restart()
        if (!root.menuOpen) inputField.forceActiveFocus()
        wakeAuthentication.request()
    }
    function cancelSubmission() {
        root.submissionPending = false
        root.responseInFlight = false
        pendingSubmissionTimer.stop()
    }
    function flushSubmission() {
        if (!root.submissionPending || !root.passwordPromptReady || root.backendPasswordDelay
            || graceLockTimer.running || wakeAuthentication.unlocked || authenticator.busy === true) return
        const secret = root.entry
        root.cancelSubmission()
        root.passwordPromptReady = false
        root.responseInFlight = true
        root.entry = ""
        authenticator.respond(secret)
    }
    function resumeSubmission() {
        if (!root.submissionPending || root.backendPasswordDelay || graceLockTimer.running) return
        if (root.passwordPromptReady) root.flushSubmission()
        else if (authenticator.busy !== true) authenticator.startAuthenticating()
    }
    function acceptSecretPrompt() {
        if (authenticator.state !== 1 || graceLockTimer.running || wakeAuthentication.unlocked
            || String(authenticator.promptForSecret || "").length === 0) return
        root.passwordPromptReady = true
        root.responseInFlight = false
        root.flushSubmission()
    }
    function submit() {
        if (root.entry.length === 0 || graceLockTimer.running || root.submissionPending || root.responseInFlight) return
        root.submissionPending = true
        root.showPassword = false
        pendingSubmissionTimer.restart()
        root.wake()
        // A prompt already observed on a previous event-loop turn is safe to
        // answer. Otherwise retain the field and wait, rather than dropping it.
        if (root.passwordPromptReady) root.flushSubmission()
        else Qt.callLater(root.resumeSubmission)
    }
    function discard() {
        root.cancelSubmission()
        root.entry = ""
        root.showPassword = false
        root.clearPassword()
    }
    NumberAnimation on reveal { from: 0; to: 1; duration: 650; easing.type: Easing.OutQuint }
    NumberAnimation { id: dismissAnimation; target: root; property: "dismiss"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
    Timer { id: unlockExitTimer; interval: 260; onTriggered: Qt.quit() }
    SequentialAnimation {
        id: rejectAnimation
        NumberAnimation { target: root; property: "shakeOffset"; to: -14; duration: 55; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "shakeOffset"; to: 11; duration: 55; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeOffset"; to: -8; duration: 50; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeOffset"; to: 5; duration: 45; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeOffset"; to: 0; duration: 40; easing.type: Easing.OutQuad }
        ScriptAction { script: root.rejecting = false }
    }
    Connections {
        target: authenticator
        ignoreUnknownSignals: true
        function onFailed(kind) {
            if (kind !== 0) return
            root.cancelSubmission()
            root.passwordPromptReady = false
            root.entry = ""
            root.showPassword = false
            root.notification = qsTr("密码错误")
            notificationTimer.restart()
            graceLockTimer.restart()
            root.rejecting = true
            rejectAnimation.restart()
            inputField.forceActiveFocus()
        }
        function onSucceeded() {
            root.cancelSubmission()
            root.passwordPromptReady = false
            root.entry = ""
            root.showPassword = false
            dismissAnimation.start()
            unlockExitTimer.restart()
        }
        function onBusyChanged() { Qt.callLater(root.flushSubmission) }
        function onAuthenticatorChanged() {
            root.discard()
            root.passwordPromptReady = false
        }
        function onInfoMessageChanged() {
            if (authenticator.infoMessage.length > 0) { root.notification = authenticator.infoMessage; notificationTimer.restart() }
        }
        function onErrorMessageChanged() {
            if (authenticator.errorMessage.length > 0) { root.notification = authenticator.errorMessage; notificationTimer.restart() }
        }
        function onPromptForSecretChanged() {
            root.showPassword = false
            inputField.forceActiveFocus()
            // KDE emits this signal before assigning m_pendingPrompt. Responding
            // inside the signal handler would still lose the first password.
            Qt.callLater(root.acceptSecretPrompt)
        }
    }
    Component.onCompleted: {
        if (wallpaper) {
            root.hasWallpaper = true
            wallpaper.parent = backdrop
            wallpaper.anchors.fill = backdrop
            wallpaper.z = -1
        }
        root.syncWallpaperSource()
        // The greeter reparents its wallpaper after setSource() returns. Re-adopt
        // it after that step so video/unknown providers also stay in our scene.
        Qt.callLater(root.syncWallpaperSource)
        if (String(authenticator.promptForSecret || "").length > 0) Qt.callLater(root.acceptSecretPrompt)
        else if (authenticator.busy !== true && !root.backendPasswordDelay) authenticator.startAuthenticating()
        inputField.forceActiveFocus()
        idleTimer.start()
    }
    Component.onDestruction: root.entry = ""
    Shortcut { sequence: "Escape"; enabled: !root.menuOpen; onActivated: root.discard() }
    KeyboardIndicator.KeyState { id: capsLockState; key: Qt.Key_CapsLock }

    // The greeter's TransientImage may have decoded at logical rather than
    // physical size. Keep the existing resolved-file takeover for HiDPI; leave
    // video/unknown providers alone instead of guessing a wallpaper path.
    property bool hasWallpaper: false
    property url wallpaperSource: ""
    property int wallpaperFillMode: Image.PreserveAspectCrop
    property string wallpaperProbe: ""
    readonly property var stillImageExtensions: [".jpg", ".jpeg", ".png", ".webp", ".jxl", ".bmp", ".avif", ".tif", ".tiff"]
    function fillModeValue(value) {
        return typeof value === "number" && value >= Image.Stretch && value <= Image.Pad ? value : Image.PreserveAspectCrop
    }
    function looksLikeStillImage(item) {
        if (!item || item.source === undefined || item.source === null || item.fillMode === undefined) return false
        const url = String(item.source)
        if (url.length === 0 || (url.charAt(0) !== "/" && url.indexOf("://") < 0)) return false
        const lower = url.toLowerCase()
        return root.stillImageExtensions.some(extension => lower.endsWith(extension))
    }
    function findWallpaperImage(item, depth) {
        if (!item || depth > 6) return null
        if (root.looksLikeStillImage(item)) return item
        const kids = item.children
        for (let i = 0; kids && i < kids.length; i++) {
            const hit = root.findWallpaperImage(kids[i], depth + 1)
            if (hit) return hit
        }
        return null
    }
    function syncWallpaperSource() {
        if (!wallpaper) return
        root.hasWallpaper = true
        if (wallpaper.parent !== backdrop) {
            wallpaper.parent = backdrop
            wallpaper.anchors.fill = backdrop
            wallpaper.z = -1
        }
        const image = root.findWallpaperImage(wallpaper, 0)
        root.wallpaperProbe = image ? String(image.source) : "(no still image found)"
        if (!image) { root.wallpaperSource = ""; return }
        root.wallpaperFillMode = root.fillModeValue(image.fillMode)
        const url = String(image.source)
        if (url !== String(root.wallpaperSource)) root.wallpaperSource = url
    }
    Timer { interval: 5000; running: true; repeat: true; onTriggered: root.syncWallpaperSource() }

    Item {
        id: backgroundScene
        anchors.fill: parent
        z: -2
        Item {
            id: backdrop
            objectName: "lockWallpaperBackdrop"
            anchors.fill: parent
            Rectangle { anchors.fill: parent; color: "#17232e"; z: -2 }
            Image {
                id: sharpWallpaper
                objectName: "lockWallpaper"
                anchors.fill: parent
                visible: status === Image.Ready
                source: root.wallpaperSource
                sourceSize: Qt.size(Math.round(width * Screen.devicePixelRatio), Math.round(height * Screen.devicePixelRatio))
                fillMode: root.wallpaperFillMode
                smooth: true; asynchronous: true
            }
        }
        Loader {
            anchors.fill: parent
            active: !root.softwareRendering
            source: "LockBackdropEffect.qml"
            onLoaded: item.backdrop = backdrop
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: "#38000000" }
                GradientStop { position: 0.45; color: "#12000000" }
                GradientStop { position: 1; color: "#55000000" }
            }
        }
    }
    Loader {
        id: glassSource
        anchors.fill: parent
        active: !root.softwareRendering
        source: "LockGlassSource.qml"
        onLoaded: item.backdrop = backgroundScene
        visible: false
    }
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: root.wake()
    }
    MacLockClock {
        id: clock
        objectName: "lockClock"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: root.height * 0.075
        unit: root.unit
        availableWidth: root.width - 40
        now: root.now
        opacity: Math.max(0, root.reveal - root.dismiss)
    }

    // The screenshot's compact player sits above the account, not below the
    // clock. Optional data imports are isolated from the authentication item.
    Loader {
        id: lyricsLoader
        objectName: "lockLyricsLoader"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: bottomStack.top
        anchors.bottomMargin: 26 * root.unit
        width: Math.min(372 * root.unit, root.width - 32)
        height: item ? item.implicitHeight : 0
        active: root.mediaEnabled
        source: "LockLyrics.qml"
        opacity: Math.max(0, root.reveal - root.dismiss)
        onLoaded: {
            item.unit = Qt.binding(() => root.unit)
            item.fontFamily = clock.fontFamily
            item.glassTexture = Qt.binding(() => root.glassTexture)
            item.glassFrame = backgroundScene
        }
    }
    Column {
        id: bottomStack
        objectName: "lockAccount"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.max(24, 72 * root.unit)
        spacing: 10 * root.unit
        width: Math.min(236 * root.unit, root.width - 48)
        opacity: Math.max(0, root.reveal - root.dismiss)
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 70 * root.unit; height: width
            LockGlass { anchors.fill: parent; radius: width / 2; texture: root.glassTexture; frame: backgroundScene; tint: 0.12 }
            Text {
                anchors.centerIn: parent
                text: root.userName.length ? root.userName.charAt(0).toUpperCase() : "●"
                textFormat: Text.PlainText
                color: "#deffffff"; font.pixelSize: 32 * root.unit
                font.family: clock.fontFamily
            }
            Loader {
                anchors.fill: parent
                active: !root.softwareRendering && root.userAvatar !== ""
                source: "LockAvatar.qml"
                onLoaded: item.source = root.userAvatar
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.userName
            textFormat: Text.PlainText
            visible: text.length > 0
            color: "#deffffff"; font.pixelSize: Math.max(12, 15 * root.unit)
            font.family: clock.fontFamily; font.weight: Font.Medium
        }
        TextField {
            id: inputField
            objectName: "passwordField"
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            height: Math.max(30, 36 * root.unit)
            transform: Translate { x: root.shakeOffset }
            echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
            readOnly: root.submissionPending || root.responseInFlight
            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
            placeholderText: qsTr("输入密码")
            color: "white"; placeholderTextColor: "#99ffffff"
            selectionColor: "#55ffffff"; selectedTextColor: "white"
            font.pixelSize: Math.max(12, 14 * root.unit)
            font.family: clock.fontFamily
            leftPadding: 16 * root.unit; rightPadding: 38 * root.unit
            topPadding: 0; bottomPadding: 0
            selectByMouse: true
            Accessible.name: qsTr("解锁密码")
            background: LockGlass {
                texture: root.glassTexture; frame: backgroundScene
                radius: height / 2; thickness: 18; tint: 0.19
                Rectangle {
                    anchors.fill: parent; radius: height / 2
                    color: "transparent"; border.width: 1
                    border.color: root.rejecting ? "#eeff8888" : inputField.activeFocus ? "#44ffffff" : "transparent"
                }
            }
            ToolButton {
                objectName: "lockSubmitButton"
                anchors.right: parent.right; anchors.rightMargin: 3
                anchors.verticalCenter: parent.verticalCenter
                width: parent.height - 6; height: width
                visible: root.entry.length > 0
                enabled: !graceLockTimer.running && !root.submissionPending && !root.responseInFlight
                Accessible.name: qsTr("解锁")
                contentItem: Text { text: "→"; color: "white"; font.pixelSize: 18; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: width / 2; color: parent.hovered ? "#44ffffff" : "#22ffffff" }
                onClicked: root.submit()
            }
            Keys.onPressed: event => {
                if (event.key !== Qt.Key_Escape && !event.isAutoRepeat) root.wake()
                event.accepted = false
            }
            TapHandler { onPressedChanged: if (pressed) wakeAuthentication.request() }
            onTextEdited: root.wake()
            onAccepted: root.submit()
        }
        Text {
            objectName: "lockHint"
            width: parent.width + 80 * root.unit
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            text: root.notification || (root.submissionPending || root.responseInFlight ? qsTr("正在验证…")
                : root.capsLockOn ? qsTr("已开启大写锁定") : qsTr("输入密码以解锁"))
            textFormat: Text.PlainText
            color: root.rejecting ? "#ffffb7b7" : "#aaffffff"
            font.pixelSize: Math.max(10, 12 * root.unit)
            wrapMode: Text.WordWrap
        }
    }
    Loader {
        id: notificationsLoader
        objectName: "lockNotificationsLoader"
        anchors.right: parent.right
        anchors.rightMargin: 18 * root.unit
        anchors.top: parent.top
        anchors.topMargin: 48 * root.unit
        width: Math.min(340 * root.unit, root.width * 0.30)
        // Narrow displays prioritize the password/clock, never cover them.
        active: root.notificationsEnabled && root.width >= 1000
        source: "LockNotifications.qml"
        opacity: Math.max(0, root.reveal - root.dismiss)
        onLoaded: {
            item.unit = Qt.binding(() => root.unit)
            item.fontFamily = clock.fontFamily
            item.glassTexture = Qt.binding(() => root.glassTexture)
            item.glassFrame = backgroundScene
        }
    }
    Loader {
        id: sessionMenu
        anchors.fill: parent
        active: root.dismiss === 0
        source: "SessionMenu.qml"
        opacity: Math.max(0, root.reveal - root.dismiss)
    }
    Rectangle {
        anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 10
        visible: root.debug; z: 100
        width: report.implicitWidth + 20; height: report.implicitHeight + 16
        radius: 8; color: "#bb000000"
        Text {
            id: report
            anchors.centerIn: parent; color: "white"; font.pixelSize: 12
            text: "KOS lock • " + root.width + "×" + root.height + " @ " + Screen.devicePixelRatio
                + "\n" + root.wallpaperProbe + "\n" + (root.softwareRendering ? "software fallback" : "GPU glass")
        }
    }
}
