/*
    SPDX-FileCopyrightText: 2026 KOS

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Window
import QtQuick.Controls
import org.kde.plasma.private.keyboardindicator as KeyboardIndicator

// iPadOS-flavoured lock screen skin.
//
// This file is loaded by kscreenlocker_greet -- not by Quickshell -- so the
// only things available to it are plain QtQuick plus the objects the greeter
// injects: `authenticator` (the PAM conversation), `wallpaper` (the Plasma
// wallpaper item), `config`, and the kscreenlocker_* globals. Nothing from
// Kos.Ui can be imported here.
//
// The greeter looks for three magic members on this root object:
//
//   property bool viewVisible
//       True while the greeter is showing the view, false while it has
//       blanked it. The greeter owns this property -- upstream's theme only
//       ever reads it -- so this theme reads it too and never writes it.
//   signal clearPassword()
//       Asks the greeter to forget a pending secret.
//   signal notificationRepeated()
//       Signals that the greeter sent the same message twice.
//
// `notification` is not required by the greeter; it is kept because that is
// where a theme is expected to accumulate PAM messages before showing them.
Item {
    id: root

    // ---- kscreenlocker contract ------------------------------------------

    property bool viewVisible: false
    property string notification
    signal clearPassword()
    signal notificationRepeated()

    // ---- input state -----------------------------------------------------

    // The password field is the only way in. An account password is an
    // arbitrary string -- letters, digits, punctuation, spaces -- so anything
    // that only offers digits would lock part of the user base out. The alias
    // is the whole state machine: the field's text *is* `entry`.
    property alias entry: inputField.text
    property bool showPassword: false

    // Set while the field is shaking off a rejected attempt.
    property real shakeOffset: 0

    // Set for the length of the rejection animation, so the ring around the
    // field can turn red: the shake alone reads as a rendering glitch.
    property bool rejecting: false

    // 0 on the first frame, 1 once the screen has settled. The clock animates
    // its own copy of the same curve and the controls below use this one, so
    // the screen arrives as a single movement instead of as a set of widgets
    // switching on one by one.
    property real reveal: 0

    // 0 while locked, 1 once the password has been accepted and the screen is
    // fading out to the desktop. Both layers subtract it, so the entry
    // animation and the exit animation never fight over `opacity`.
    property real dismiss: 0

    property date now: new Date()

    readonly property bool capsLockOn: capsLockState.locked

    // Who is being unlocked. kscreenlocker injects both of these; the guards
    // are not defensive decoration -- a bare reference to a context property
    // the greeter did not provide is a ReferenceError inside a binding, and
    // this is the one window the user cannot get around. The headless harness
    // does not inject them either, so this is also what lets the preview run.
    //
    // `kscreenlocker_userImage` is a *path*, not a URL: it has to be prefixed
    // and encoded segment by segment, which is what upstream's own theme does
    // with it. Empty when the greeter has no face for this account.
    readonly property string userName: typeof kscreenlocker_userName === "string"
        ? kscreenlocker_userName : ""
    readonly property string userAvatar: typeof kscreenlocker_userImage === "string"
        && kscreenlocker_userImage !== ""
        ? "file://" + kscreenlocker_userImage.split("/").map(encodeURIComponent).join("/")
        : ""
    // Set to true to paint a readout of the injected objects over the lock
    // screen. There is no other way to see what the greeter actually handed
    // over -- the theme runs in a process nobody can attach to -- so this is
    // the diagnostic for "the wallpaper looks wrong".
    property bool debug: false

    Timer {
        id: clockTimer
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    // Half-typed passwords should not sit in memory (or on screen) forever.
    // The session stays locked either way; only the text is dropped.
    Timer {
        id: idleTimer
        interval: 30000
        onTriggered: {
            root.entry = ""
            root.clearPassword()
        }
    }

    // PAM messages ("密码错误", hints) are status, not a permanent record.
    Timer {
        id: notificationTimer
        interval: 3000
        onTriggered: root.notification = ""
    }

    // A rejected attempt ends the PAM conversation, and nothing else starts a
    // new one -- so a second try would have its answer delivered into that dead
    // session and the screen would never open again. That is what a user sees
    // as "the correct password does nothing". Upstream restarts the
    // authenticators after the same delay; so does this theme.
    Timer {
        id: graceLockTimer
        interval: 3000
        onTriggered: {
            root.entry = ""
            authenticator.startAuthenticating()
        }
    }

    function wake() {
        idleTimer.restart()
        inputField.forceActiveFocus()
    }

    function submit() {
        if (root.entry.length === 0)
            return
        wake()
        // Identifying the authenticators is what makes the answer below land
        // in a live PAM conversation. `startAuthenticating()` is idempotent
        // while one is already running (it returns early on the authenticating
        // state), and without it `respond()` posts the password into a
        // conversation that does not exist -- the call is forwarded
        // unconditionally, so a dead session swallows the secret and the
        // screen simply never opens. The call in Component.onCompleted is not
        // enough on its own: the greeter holds a grace period after the lock
        // engages and refuses to start authenticating during it, which lands
        // exactly on a theme that only ever asks once at load.
        authenticator.startAuthenticating()
        authenticator.respond(root.entry)
        root.entry = ""
    }

    // Escape: drop what was typed and ask the greeter to forget a pending
    // secret. It does not unlock anything and does not blank the screen.
    function discard() {
        root.entry = ""
        root.clearPassword()
    }

    NumberAnimation on reveal {
        from: 0
        to: 1
        duration: 620
        easing.type: Easing.OutCubic
    }

    // Started from onSucceeded. The greeter takes the screen down as soon as
    // the theme agrees to it, so the fade has to be short; the timer below is
    // what keeps `Qt.quit()` from cutting it off on its first frame.
    NumberAnimation {
        id: dismissAnimation

        target: root
        property: "dismiss"
        from: 0
        to: 1
        duration: 200
        easing.type: Easing.OutCubic
    }

    Timer {
        id: unlockExitTimer
        interval: 260
        onTriggered: Qt.quit()
    }

    // A wrong password: swings that decay, rather than three even ones. The
    // decay is what makes it read as a spring that was struck instead of as
    // the whole screen sliding sideways.
    SequentialAnimation {
        id: rejectAnimation

        NumberAnimation {
            target: root
            property: "shakeOffset"
            to: -14
            duration: 55
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: root
            property: "shakeOffset"
            to: 11
            duration: 55
            easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            target: root
            property: "shakeOffset"
            to: -8
            duration: 50
            easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            target: root
            property: "shakeOffset"
            to: 5
            duration: 45
            easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            target: root
            property: "shakeOffset"
            to: 0
            duration: 40
            easing.type: Easing.OutQuad
        }
        ScriptAction {
            script: root.rejecting = false
        }
    }

    Connections {
        target: authenticator

        function onFailed(kind) {
            // Any kind other than zero comes from a non-interactive
            // authenticator (fingerprint, smartcard) and has its own UI.
            if (kind !== 0)
                return
            // PAM keeps the rejected answer on its side; the field must not.
            root.entry = ""
            root.notification = qsTr("密码错误")
            notificationTimer.restart()
            // The conversation is over. Queue the next one, or the following
            // attempt has nothing to be delivered to.
            graceLockTimer.restart()
            root.rejecting = true
            rejectAnimation.restart()
            inputField.forceActiveFocus()
        }

        function onSucceeded() {
            // The greeter owns the unlock, and exiting is how the theme agrees
            // to it -- but not on the same frame the secret is accepted. The
            // controls fade first so the desktop is not swapped in behind a
            // lock screen that is still fully drawn; unlockExitTimer is what
            // gives that fade its two hundred milliseconds.
            dismissAnimation.start()
            unlockExitTimer.restart()
        }

        function onInfoMessageChanged() {
            if (authenticator.infoMessage.length > 0) {
                root.notification = authenticator.infoMessage
                notificationTimer.restart()
            }
        }

        function onErrorMessageChanged() {
            if (authenticator.errorMessage.length > 0) {
                root.notification = authenticator.errorMessage
                notificationTimer.restart()
            }
        }

        // A secret prompt arrives for every password attempt, including the
        // first one. Upstream uses it to re-focus the field and to drop the
        // cleartext reveal, which is exactly what a lock screen should do.
        function onPromptForSecretChanged() {
            root.showPassword = false
            inputField.forceActiveFocus()
        }
    }

    // Ask PAM for the first prompt before the user does anything: an empty
    // screen that only reacts after a key press feels broken when the account
    // has no password at all (those are unlocked by the greeter directly).
    //
    // The greeter hands the wallpaper in as a property we do not declare, so
    // it can be neither grouped-anchored (`wallpaper { ... }` parses as a new
    // type) nor relied on to be laid out already. Adopting it here -- moving
    // it into `backdrop` and pinning it full-bleed -- makes its position ours
    // to own, and it stays where it was put instead of where the greeter put
    // it.
    Component.onCompleted: {
        if (wallpaper) {
            root.hasWallpaper = true
            wallpaper.parent = backdrop
            wallpaper.anchors.fill = backdrop
            // Explicit, so the theme's own copy cannot end up underneath it
            // whatever z the package gives its root.
            wallpaper.z = -1
        }
        // After adopting it, not before: the package builds its own image once
        // it knows how big it is.
        root.syncWallpaperSource()
        authenticator.startAuthenticating()
        inputField.forceActiveFocus()
    }

    // The field has to hold the keyboard: a lock screen where the first key
    // press goes nowhere is worse than an ugly one. This only re-grabs focus
    // inside our own window, so it cannot fight the greeter.
    Timer {
        interval: 1500
        running: true
        repeat: true
        onTriggered: if (!inputField.activeFocus)
            inputField.forceActiveFocus()
    }

    Shortcut {
        sequence: "Escape"
        // The session menu claims Escape while it is open. Without this guard
        // both shortcuts fire, so closing the menu would also throw away
        // whatever had been typed into the field behind it.
        enabled: !(sessionMenu.item && sessionMenu.item.open)
        onActivated: root.discard()
    }

    // Real caps-lock state, straight from the keyboard layouts. Same module
    // upstream's theme uses. Passwords have letters, so this matters here
    // more than it does in a digits-only UI.
    KeyboardIndicator.KeyState {
        id: capsLockState
        key: Qt.Key_CapsLock
    }

    // ---- background ------------------------------------------------------

    // True once the greeter's wallpaper has been adopted into `backdrop`.
    // The fallback floor below is invisible when it has, because the picture
    // is now the surface.
    property bool hasWallpaper: false

    // The file the wallpaper package resolved for itself, and how it asked to
    // be cropped. Empty when the walk below found nothing usable (animated or
    // video wallpapers), in which case the package's own item is what shows.
    property url wallpaperSource: ""
    property int wallpaperFillMode: Image.PreserveAspectCrop

    // What the walk found, for the debug readout.
    property string wallpaperProbe: ""

    readonly property var stillImageExtensions: [".jpg", ".jpeg", ".png", ".webp", ".jxl", ".bmp", ".avif", ".tif", ".tiff"]

    // Wallpaper::FillMode and Image::FillMode happen to share their order, so
    // the package's own choice can be handed straight to our Image.
    function fillModeValue(value) {
        return (typeof value === "number" && value >= Image.Stretch && value <= Image.Pad)
            ? value
            : Image.PreserveAspectCrop
    }

    function looksLikeStillImage(item) {
        if (!item || item.source === undefined || item.source === null || item.fillMode === undefined)
            return false
        const url = String(item.source)
        if (url.length === 0)
            return false
        // A relative URL is resolved against the file that wrote it, which is
        // the package, not us -- re-using it here would load the wrong path (or
        // nothing). Every wallpaper backend hands over an absolute URL or an
        // image provider, so anything else is left to the package to draw.
        if (url.charAt(0) !== "/" && url.indexOf("://") < 0)
            return false
        const lower = url.toLowerCase()
        for (let i = 0; i < root.stillImageExtensions.length; ++i) {
            if (lower.endsWith(root.stillImageExtensions[i]))
                return true
        }
        return false
    }

    // Depth-first hunt for the image the wallpaper package loaded. The package
    // resolves wallpaper names ("Horos"), dark/light fragments and the rest
    // for us, so reading what it ended up with beats parsing its config: we
    // need the resolved file, not the setting.
    function findWallpaperImage(item, depth) {
        if (!item || depth > 6)
            return null
        if (root.looksLikeStillImage(item))
            return item
        const kids = item.children
        for (let i = 0; kids && i < kids.length; ++i) {
            const hit = root.findWallpaperImage(kids[i], depth + 1)
            if (hit)
                return hit
        }
        return null
    }

    function syncWallpaperSource() {
        if (!wallpaper)
            return
        const image = root.findWallpaperImage(wallpaper, 0)
        root.wallpaperProbe = image ? String(image.source) : "(no still image found)"
        if (!image) {
            root.wallpaperSource = ""
            return
        }
        root.wallpaperFillMode = root.fillModeValue(image.fillMode)
        const url = String(image.source)
        if (url !== String(root.wallpaperSource))
            root.wallpaperSource = url
    }

    // The walk has to be retried: the package builds its image after we adopt
    // it, and a slideshow swaps the file underneath us.
    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: root.syncWallpaperSource()
    }

    // Full-bleed holder for the background. The greeter's wallpaper item is
    // adopted into it at runtime -- `wallpaper` is injected, not declared here,
    // so it has to be moved into the scene rather than anchored in place -- and
    // the theme's own copy of the picture is declared inside it, on top. It
    // sits at the very back, so the scrim above always has it underneath.
    //
    // There is no blur on any of it, and that was tried: the only way to blur
    // a wallpaper here without a shader is to render it into a small texture
    // and scale it back up, and at any downscale soft enough to read as a blur
    // the result is a grid of bilinear blocks -- a mosaic, not glass. A real
    // Gaussian is MultiEffect, which is a shader and therefore invisible under
    // a software renderer. So the picture stays sharp and the scrim below does
    // the separating.
    Item {
        id: backdrop
        anchors.fill: parent
        z: -2

        // A native-resolution copy of the wallpaper, drawn by plain QtQuick.
        //
        // The package behind `wallpaper` is a C++ `TransientImage` whose
        // texture is built from whatever geometry the item had when it loaded
        // -- geometry this theme only takes over afterwards. On a HiDPI
        // display (this project's panel is 3840x2160 at scale 2) that texture
        // can end up at the logical size, and a 1920x1080 picture stretched
        // over a 3840x2160 panel is exactly what "the wallpaper became a very
        // low resolution image" means. Nothing can recover those pixels:
        // grabbing the item, playing with `layer`, or nudging the package into
        // re-decoding all end up sampling the same undersized texture.
        //
        // So the pixels are not the package's to give. `sourceSize` makes
        // QtQuick decode the file itself at the pixels this screen actually has
        // -- the one thing a plain Image is guaranteed to get right -- and it
        // is drawn over the package's own copy. If the walk finds nothing, the
        // picture simply stays whatever the greeter handed over.
        Image {
            id: sharpWallpaper

            anchors.fill: parent
            z: 1

            visible: root.wallpaperSource != ""
            source: root.wallpaperSource
            sourceSize: Qt.size(Math.round(width * Screen.devicePixelRatio),
                                Math.round(height * Screen.devicePixelRatio))
            fillMode: root.wallpaperFillMode
            smooth: true
            asynchronous: true
        }
    }

    // Fallback floor, only visible when the greeter had no wallpaper to offer.
    Rectangle {
        anchors.fill: parent
        color: "#101014"
        visible: !root.hasWallpaper
        z: -1
    }

    // Full-screen scrim. It covers the whole picture rather than just the
    // bottom, so the wallpaper reads as one toned-down field behind everything
    // instead of as a clear top half joined to a dark bottom half.
    //
    // It is a gradient and not a flat fill for two reasons: the light in this
    // design falls from above, so the foot of the picture is the part that
    // should be furthest from the viewer; and with no blur to lean on, the
    // password field still has to be readable over whatever wallpaper the user
    // happens to have, which is what the lower third is carrying.
    Rectangle {
        id: scrim

        anchors.fill: parent

        // Exposed because this is the one number that has to be re-judged
        // against a real wallpaper: 0.22/0.30/0.55 is set for a mid-tone
        // picture, and a very light or very dark one wants it moved.
        property real topAlpha: 0.22
        property real midAlpha: 0.30
        property real footAlpha: 0.55

        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, scrim.topAlpha) }
            GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, scrim.midAlpha) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, scrim.footAlpha) }
        }
    }

    LockClock {
        id: clock
        objectName: "lockClock"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.round(root.height * 0.075)
        now: root.now
        // Shared with the controls below, so the clock and the field leave the
        // screen together.
        dismiss: root.dismiss
    }

    // The widget rail: weather, the month, a dial, stacked down the left edge
    // like the reference lock screen. It is anchored to the screen rather than
    // to the field, because it is a rail of reports that runs the height of
    // the picture, not part of the group the user is aiming at.
    //
    // Loaded, like everything else here that can fail on its own.
    Loader {
        id: widgetsLoader

        // Under the clock: the clock is what is being looked at, and these are
        // the reports that go with it. Centred on it rather than pinned to an
        // edge, so the group reads as one thing with the time above it.
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: clock.bottom
        anchors.topMargin: Math.round(root.height * 0.045)
        source: "LockWidgets.qml"

        opacity: Math.max(0, root.reveal - root.dismiss)
    }

    // ---- bottom: message, password field, status -------------------------

    Column {
        id: bottomStack

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        // Near the foot of the screen rather than a twelfth of the way up it:
        // the clock owns the top, and everything the user has to aim at -- the
        // name, the field, the hints -- belongs in one group at the bottom.
        // What is left below it is the edge of the screen and nothing else.
        anchors.bottomMargin: Math.round(root.height * 0.055)
        spacing: Math.round(root.height * 0.014)
        // Narrow enough to read as an iOS field: the real one is a good deal
        // narrower than the text it accepts. It was 0.30/420 for one revision
        // and that was the wrong direction -- the field is not the subject of
        // this screen, the clock is, and a wide slab of glass under it fought
        // with the numerals for the eye. 0.26/340 is back to roughly where it
        // started; what changed is the glass, not the footprint.
        width: Math.round(Math.min(root.width * 0.26, 340))

        // Rises into place behind the clock, and leaves with it.
        opacity: Math.max(0, root.reveal - root.dismiss)
        transform: Translate {
            y: (1 - root.reveal) * Math.round(root.height * 0.018)
        }

        // The face, when there is one. Loaded from its own file because its
        // mask is a shader, and a shader import that does not resolve must not
        // be able to take the password field down with it.
        Loader {
            id: avatarLoader

            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.round(root.height * 0.07)
            height: width
            active: root.userAvatar !== ""
            source: "LockAvatar.qml"

            opacity: Math.max(0, root.reveal - root.dismiss)
            onLoaded: item.source = root.userAvatar
        }

        // The account being unlocked: on the way to the field the eye passes
        // the name, which is the order that reads as an address to a person
        // rather than as a prompt. Hidden when the greeter handed nothing over
        // -- an empty line here would just be a gap.
        Text {
            id: nameText

            anchors.horizontalCenter: parent.horizontalCenter
            text: root.userName
            visible: text.length > 0
            color: Qt.rgba(1, 1, 1, 0.88)
            font.pixelSize: 15
            font.weight: Font.Medium
        }

        Text {
            id: messageText

            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.notification
            visible: text.length > 0
            color: root.rejecting
                ? Qt.rgba(1, 0.78, 0.78, 0.95)
                : Qt.rgba(1, 1, 1, 0.9)
            font.pixelSize: 14
            wrapMode: Text.WordWrap

            Behavior on color {
                ColorAnimation {
                    duration: 160
                }
            }
        }

        TextField {
            id: inputField

            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width

            // A transform rather than `x`, because the field is anchored.
            transform: Translate {
                x: root.shakeOffset
            }

            echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
            placeholderText: qsTr("输入密码")
            horizontalAlignment: TextInput.AlignHCenter
            selectByMouse: true

            color: "white"
            placeholderTextColor: Qt.rgba(1, 1, 1, 0.48)
            selectionColor: Qt.rgba(1, 1, 1, 0.28)
            selectedTextColor: "white"
            font.pixelSize: 16

            leftPadding: 18
            rightPadding: 18
            topPadding: 9
            bottomPadding: 9

            // The same glass as the clock, in its smoked variant.
            //
            // One recipe, three parts, and every one of them is translucent --
            // that is the whole difference between a pane of glass and a chip
            // pasted onto the picture:
            //
            //   1. a body that is dark but not opaque, so the wallpaper is
            //      still inside the field
            //   2. a sheen across the top of the body, the light the glass
            //      catches
            //   3. a crown: one bright hairline just inside the top edge, and
            //      its bounce along the inside of the foot
            //
            // There is no outline. This field had one for several revisions --
            // a gradient ring, lit at the crown and fading to nothing at the
            // foot, which is the right way to draw an edge if an edge is what
            // is wanted. It is not: an outline is exactly what makes the pane
            // read as a control laid on top of the picture rather than as a
            // piece of it, and at this size and translucency the glass is
            // perfectly findable without one. The only thing the edge was
            // still carrying was the rejected-password state, so that stays --
            // and only while it is true.
            //
            // Focus is the crown catching a little more light, for the same
            // reason: the field should acknowledge the keyboard without
            // growing a border.
            //
            // The shape is a capsule: the radius is half the height, so the
            // two ends are semicircles. Anything less leaves a straight run of
            // edge at the corners and reads as a rounded box.
            //
            // Plain QtQuick only: the greeter has neither the KWin glass effect
            // nor Kos.Ui, and everything here is a flat fill or a gradient, so
            // it also draws under the software backend.
            background: Item {
                id: pane

                // Half the height, not a fraction of it: at 0.5 the two ends
                // are semicircles and the field is a capsule. Anything less
                // leaves a straight run of edge at the corners, which is what
                // made the pane read as a rounded box rather than as a pill.
                readonly property int cornerRadius: Math.round(pane.height * 0.5)

                // How hard the glass is lit, and this is carrying more weight
                // than a highlight usually does: the body is dark and the
                // wallpaper under it now sits behind a full-screen scrim, so on
                // a dark picture -- a black one especially -- the pane has
                // almost nothing of its own to be seen by. What is left is the
                // light it catches. A real pane of smoked glass on a dark
                // background reads exactly this way: a shape drawn by its top
                // and bottom edges, with the middle gone.
                //
                // It is the crown that moves on focus and not an outline,
                // because an outline is what made every earlier revision of
                // this field read as a sticker rather than as a pane.
                readonly property real crownAlpha: inputField.activeFocus ? 0.40 : 0.28
                readonly property real bounceAlpha: 0.16

                // The shadow, drawn first so it steps out from under the pane:
                // four dark copies, each a little further down, a little wider
                // and a little fainter than the last. Flat fills instead of a
                // blur -- a blur is the one effect this environment has already
                // been caught faking. Four steps rather than three, and each
                // one fainter, so the stack reads as depth rather than as a
                // ledge.
                Repeater {
                    model: [
                        { y: 1, grow: 0, alpha: 0.12 },
                        { y: 2, grow: 0, alpha: 0.095 },
                        { y: 3, grow: 1, alpha: 0.070 },
                        { y: 5, grow: 1, alpha: 0.050 },
                        { y: 7, grow: 2, alpha: 0.034 },
                        { y: 10, grow: 3, alpha: 0.022 }
                    ]

                    delegate: Rectangle {
                        x: 0
                        y: modelData.y
                        width: parent.width
                        height: parent.height
                        radius: pane.cornerRadius + modelData.grow
                        color: Qt.rgba(0, 0, 0, modelData.alpha)
                    }
                }

                // The one edge the pane still has, and only while it means
                // something: a rejected password. Invisible the rest of the
                // time. A rejection is also the one moment the field has to be
                // unmistakable, and a red hairline is cheap, unambiguous, and
                // gone three seconds later with the message.
                Rectangle {
                    anchors.fill: parent
                    radius: pane.cornerRadius
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(1, 0.42, 0.42, 0.55)
                    visible: root.rejecting
                }

                // 0. The lift, under the dark body. The body is black glass,
                // and black glass on a black wallpaper is visible only by its
                // edges -- which is exactly what the last revision was, and it
                // was not enough. This white wash is what the pane is lit
                // against: on a dark picture it is the difference between the
                // pill and the void around it, and on a light one the dark body
                // on top nearly cancels it out, so it costs nothing there.
                Rectangle {
                    anchors.fill: parent
                    radius: pane.cornerRadius
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.20) }
                        GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.12) }
                    }
                }

                // 1. The body: black, but never opaque, and heavier at the foot
                // so the pane sits into the wallpaper rather than on it. It
                // fills the pane exactly -- the one-pixel inset it used to
                // carry was there to leave room for the border, and with the
                // border gone it only left a hairline of undarkened wallpaper
                // round the outside of the glass.
                Rectangle {
                    anchors.fill: parent
                    radius: pane.cornerRadius
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: Qt.rgba(0.06, 0.07, 0.11, 0.32) }
                        GradientStop { position: 0.50; color: Qt.rgba(0.03, 0.04, 0.07, 0.26) }
                        GradientStop { position: 1.0; color: Qt.rgba(0.02, 0.03, 0.05, 0.40) }
                    }
                }

                // 2. The sheen across the top of the body.
                Rectangle {
                    anchors.fill: parent
                    radius: pane.cornerRadius
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.14) }
                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.04) }
                        GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                    }
                }

                // 2b. The same light again, along the inside of the bottom
                // edge: what the pane picks up off the wallpaper behind it,
                // fainter than the crown because it has bounced once to get
                // there. Together with the crown this is the pair of lines that
                // draws the pane on a dark picture -- without either of them
                // the foot of the glass is a hard cut on light wallpapers and
                // nothing at all on dark ones.
                Rectangle {
                    x: Math.round(pane.cornerRadius * 0.9)
                    y: pane.height - 3
                    width: Math.max(0, pane.width - Math.round(pane.cornerRadius * 1.8))
                    height: 2
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, pane.bounceAlpha) }
                        GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                    }
                }

                // 3. The crown, inset so it reads as the lit inside edge of the
                // glass and not as another outline, and faded at both ends
                // because it is a reflection, not a box.
                Rectangle {
                    // Spans the straight run between the two ends -- on a
                    // capsule the corners curve away from under a line that
                    // starts any further in, and the highlight would appear to
                    // float clear of the edge it belongs to.
                    x: pane.cornerRadius
                    y: 2
                    width: Math.max(0, pane.width - pane.cornerRadius * 2)
                    // Two pixels, not one: at 1px this is a hairline that a 2x
                    // panel renders as a single device pixel, which is not
                    // enough to hold a shape on a black wallpaper.
                    height: 2
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, pane.crownAlpha) }
                        GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                    }
                }
            }

            onTextEdited: idleTimer.restart()
            onAccepted: root.submit()
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("已开启大写锁定")
            visible: root.capsLockOn && inputField.activeFocus
            color: Qt.rgba(1, 1, 1, 0.9)
            font.pixelSize: 14
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.showPassword ? qsTr("隐藏密码") : qsTr("显示密码")
            color: Qt.rgba(1, 1, 1, 0.68)
            font.pixelSize: 14

            MouseArea {
                anchors.fill: parent
                anchors.margins: -10
                onClicked: {
                    root.showPassword = !root.showPassword
                    root.wake()
                }
            }
        }
    }

    // ---- session actions: the way out of the session ----------------------

    // The two empty circles iPadOS keeps in its bottom corners are gone. There
    // is no flashlight and no camera on a desktop, and a control that does
    // nothing is exactly what makes a skin read as a copy of something else.
    // The slot that does matter on a computer is the way out of it, so that is
    // what the top-right corner holds now.
    //
    // Loaded rather than declared, deliberately. `SessionMenu.qml` imports
    // `org.kde.plasma.private.sessions`, and an import that fails to resolve
    // inside the greeter takes down the whole file that declared it. Behind a
    // Loader the blast radius is the menu: the password field, which is the
    // only way back into the session, keeps working either way.
    Loader {
        id: sessionMenu

        // Fills the screen rather than sitting in the corner. The menu has to
        // be dismissible by clicking anywhere, so the loaded item owns the
        // whole surface and puts its own button in the corner.
        anchors.fill: parent

        // There is nothing to offer a session that is already fading out.
        active: root.dismiss === 0
        source: "SessionMenu.qml"

        opacity: Math.max(0, root.reveal - root.dismiss)
    }

    // There is no home bar. A desktop has no gesture to hint at, and a bar
    // that does nothing is exactly the kind of borrowed furniture that makes
    // a skin read as a copy of something else.

    // ---- diagnostics -----------------------------------------------------

    // Shown only when `debug` is flipped on. Plain text and plain rectangles,
    // so it renders even where shaders do not, and it exists because there is
    // no other way to see what the greeter handed over: lock the screen with
    // debug on, read the numbers off the panel, unlock.
    Rectangle {
        anchors {
            top: parent.top
            left: parent.left
            margins: Math.round(parent.height * 0.015)
        }

        visible: root.debug
        z: 100

        width: report.width + 20
        height: report.height + 16
        radius: 8
        color: Qt.rgba(0, 0, 0, 0.72)

        Text {
            id: report

            anchors.centerIn: parent
            color: "white"
            font.pixelSize: 12
            font.family: "monospace"
            text: root.report()
        }
    }

    function report() {
        const w = wallpaper
        const layer = w && w.layer ? w.layer : null
        return [
            "screen    " + Screen.width + "x" + Screen.height
                + "  dpr " + Screen.devicePixelRatio,
            "root      " + Math.round(root.width) + "x" + Math.round(root.height),
            "wallpaper " + (w
                ? Math.round(w.width) + "x" + Math.round(w.height)
                    + "  implicit " + Math.round(w.implicitWidth) + "x" + Math.round(w.implicitHeight)
                : "null"),
            "layer     " + (layer
                ? layer.enabled + "  texture " + Math.round(layer.textureSize.width)
                    + "x" + Math.round(layer.textureSize.height)
                : "-"),
            "found     " + root.wallpaperProbe,
            "ours      " + root.wallpaperSource,
            "decoding  " + Math.round(root.width * Screen.devicePixelRatio) + "x"
                + Math.round(root.height * Screen.devicePixelRatio)
                + "  fill " + root.wallpaperFillMode,
            "image     " + sharpWallpaper.status + "  " + sharpWallpaper.progress
        ].join("\n")
    }

    // ---- input -----------------------------------------------------------

    // Kept for the pointer only: the field owns the keyboard. Anything typed
    // reaches the field directly, and Escape is a window shortcut.
    MouseArea {
        id: interaction
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.ArrowCursor

        // Declared before the field, so the field and the buttons above sit on
        // top of this and keep their own clicks.
        z: -1

        onClicked: root.wake()
        onPositionChanged: root.wake()
    }
}
