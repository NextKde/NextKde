// Headless harness: loads the shipped LockScreen.qml inside a sized container
// and stubs what kscreenlocker_greet injects. Verification only -- never part
// of the package.
//
// console.log is swallowed in this environment, so results come back through
// the process exit code plus a rendered PNG.
import QtQuick
import QtQuick.Window

Item {
    id: wrapper

    width: 1200
    height: 800

    property AuthenticatorStub authenticator: AuthenticatorStub {}
    property QtObject config: QtObject {}
    property WallpaperStub wallpaper: WallpaperStub {
        anchors.fill: parent
    }

    property int clearPasswordCount: 0

    // `Qt.exit()` does not unwind the script that called it, so a later call
    // overwrites the code and the happy path at the end of the run would turn
    // every failure into a pass. Recording the first failure and refusing to
    // exit zero afterwards is what makes the exit code mean anything.
    property bool failed: false

    function check(condition, code) {
        if (!condition && !wrapper.failed) {
            wrapper.failed = true
            Qt.exit(code)
        }
    }

    // Success has to be claimed explicitly for the same reason.
    function done() {
        if (!wrapper.failed)
            Qt.exit(0)
    }

    // Depth-first reach into the loaded theme, for the things that only exist
    // as rendered text.
    function findByObjectName(item, name) {
        if (!item)
            return null
        if (item.objectName === name)
            return item
        const kids = item.children || []
        for (let i = 0; i < kids.length; ++i) {
            const hit = wrapper.findByObjectName(kids[i], name)
            if (hit)
                return hit
        }
        return null
    }

    Loader {
        id: screen
        anchors.fill: parent
        // Always the shipped file, never a copy: the harness must test what
        // the greeter will load.
        source: "../../contents/lockscreen/LockScreen.qml"

        onStatusChanged: {
            if (status === Loader.Error)
                Qt.exit(90)
        }
    }

    // The session menu sits in its own file behind a Loader so that a Plasma
    // import the greeter cannot resolve takes down the menu and nothing else.
    // That arrangement is only worth having if the import does resolve, so it
    // is loaded here too: a broken one fails the run instead of quietly
    // costing the user the power button.
    Loader {
        id: sessionMenuProbe
        anchors.fill: parent
        source: "../../contents/lockscreen/SessionMenu.qml"

        onStatusChanged: {
            if (status === Loader.Error)
                Qt.exit(91)
        }
    }

    Connections {
        target: screen.item

        function onClearPassword() {
            wrapper.clearPasswordCount++
        }
    }

    // The theme asks to authenticate while it loads, and the greeter refuses
    // that: the grace period is still up. Everything below depends on the
    // theme asking again at a moment that counts.
    Timer {
        interval: 400
        running: true
        onTriggered: wrapper.check(wrapper.authenticator.refusedStartCount > 0, 101)
    }

    // The grace period ends. From here a start request is answered, which is
    // the state a user is in by the time they type anything.
    Timer {
        interval: 500
        running: true
        onTriggered: wrapper.authenticator.graceLocked = false
    }

    Timer {
        interval: 800
        running: true
        onTriggered: {
            try {
                const lock = screen.item
                if (lock === null)
                    Qt.exit(191)

                // Nothing is typed and nothing is blanked when the greeter
                // opens: `viewVisible` belongs to the greeter, so the theme
                // must leave it alone.
                wrapper.check(lock.entry === "", 102)
                wrapper.check(lock.viewVisible === false, 103)

                // The screen animates in, and no exit fade is running yet.
                // `reveal` is only ever driven by the entry animation, so a 0
                // here means it never started -- and a real lock screen that
                // never reveals itself is a black screen with a cursor.
                wrapper.check(lock.reveal > 0.9, 125)
                wrapper.check(lock.dismiss === 0, 126)

                const lyricsLoader = wrapper.findByObjectName(lock, "lockLyricsLoader")
                if (lyricsLoader === null || lyricsLoader.status !== Loader.Ready
                        || lyricsLoader.item === null) {
                    Qt.exit(136)
                } else {
                    // No KOS Music MPRIS service exists in this isolated run.
                    // The lyric bridge must load successfully and remain hidden.
                    wrapper.check(lyricsLoader.item.visible === false, 137)
                    wrapper.check(lyricsLoader.item.unwrap({value: "line"}) === "line", 138)
                    const argumentLike = {0: {value: "line"}, length: 1}
                    wrapper.check(lyricsLoader.item.unwrap(argumentLike) === "line", 139)
                }

                if (sessionMenuProbe.status !== Loader.Ready) {
                    Qt.exit(127)
                } else {
                    // Closed until asked for, and drivable from outside: the
                    // theme and this harness are its only two callers.
                    wrapper.check(sessionMenuProbe.item.open === false, 128)
                    sessionMenuProbe.item.open = true
                    wrapper.check(sessionMenuProbe.item.open === true, 129)
                    sessionMenuProbe.item.close()
                }

                // What the clock actually formatted to. `Qt.formatDate` has an
                // overload that takes a locale and then ignores the format
                // string, and a locale the session does not have renders an
                // English weekday -- both produce a date, just not this one,
                // and nothing in the properties above would show it.
                const dateText = wrapper.findByObjectName(lock, "clockDateText")
                const timeText = wrapper.findByObjectName(lock, "clockTimeText")
                if (dateText === null || timeText === null) {
                    Qt.exit(131)
                } else {
                    wrapper.check(/^星期[一二三四五六日]\s*\d{1,2}月\d{1,2}日$/.test(dateText.text), 132)
                    wrapper.check(!/\d{4}年/.test(dateText.text), 133)
                    wrapper.check(/^\d{2}:\d{2}$/.test(timeText.text), 134)
                }

                // Where the glass put the numerals, against where the Text
                // actually is. The canvas covers the time line grown by
                // `rimPad` on every side, so in its own -- ratio-scaled --
                // coordinates the Text's baseline has to land at
                // `(text.x + rimPad) * ratio`.
                //
                // This is the assertion that catches a wrong origin, and the
                // reason it is written as a comparison rather than as a look
                // at the render: at devicePixelRatio 1 every wrong formula
                // agrees with the right one, so a 1x preview of the clock
                // looks correct while every HiDPI screen draws it clipped.
                // run.sh runs this harness at 2x as well for exactly that.
                const clockItem = wrapper.findByObjectName(lock, "lockClock")
                const rimItem = wrapper.findByObjectName(lock, "clockTimeRim")
                const timeItem = wrapper.findByObjectName(lock, "clockTimeText")
                if (clockItem === null || rimItem === null || timeItem === null
                        || timeItem.parent === null) {
                    Qt.exit(135)
                } else {
                    const timeLineItem = timeItem.parent
                    const expectedX = (timeItem.x + clockItem.rimPad) * rimItem.ratio
                    const expectedY = (timeItem.y + timeItem.baselineOffset + clockItem.rimPad)
                        * rimItem.ratio
                    // 3, not 1: `rim.width` is rounded, so the box the canvas
                    // covers is up to half a logical pixel off nominal on each
                    // side, and at ratio 2 that is a device pixel per side.
                    // The failure this is here for was two hundred and forty.
                    wrapper.check(Math.abs(timeLineItem.paintOriginX - expectedX) <= 3, 136)
                    wrapper.check(Math.abs(timeLineItem.paintOriginY - expectedY) <= 3, 137)
                }

                lock.wake()

                // A password is an arbitrary string.
                const typed = "P@ss w0rd!"
                lock.entry = typed
                wrapper.check(lock.entry === typed, 104)

                lock.submit()
                // The load-time request was refused, so the theme has to have
                // identified the authenticators itself -- otherwise this
                // answer went into a conversation that was never running.
                wrapper.check(wrapper.authenticator.startCount > 0, 118)
                wrapper.check(wrapper.authenticator.droppedRespondCount === 0, 119)
                wrapper.check(wrapper.authenticator.lastResponded === typed, 105)
                wrapper.check(lock.entry === "", 106)

                // Enter on an empty field must not talk to PAM.
                wrapper.authenticator.lastResponded = ""
                lock.submit()
                wrapper.check(wrapper.authenticator.lastResponded === "", 107)

                // A rejected attempt clears the field and surfaces the message.
                lock.entry = "wrong"
                wrapper.authenticator.failed(0)
                wrapper.check(lock.entry === "", 109)
                wrapper.check(lock.notification.length > 0, 108)

                // The reveal toggle is the user's own choice, not a default.
                wrapper.check(lock.showPassword === false, 112)
                lock.showPassword = true
                wrapper.check(lock.showPassword === true, 113)
                lock.showPassword = false

                // Escape drops the text and tells the greeter to forget the
                // pending secret.
                lock.entry = "half-typed"
                lock.discard()
                wrapper.check(lock.entry === "", 110)
                wrapper.check(wrapper.clearPasswordCount > 0, 111)

                // The wallpaper takeover: the theme must have adopted the
                // greeter's item and found the still image inside it, because
                // that is the file it re-draws at display resolution. Without
                // this the background is whatever the package rendered.
                wrapper.check(lock.hasWallpaper, 115)
                wrapper.check(String(lock.wallpaperSource).endsWith("wallpaper-sample.png"), 116)
                wrapper.check(lock.wallpaperFillMode >= 0 && lock.wallpaperFillMode <= 6, 117)
            } catch (e) {
                Qt.exit(199)
            }
        }
    }

    // What the lock screen resolved for the wallpaper, burnt into the render:
    // the harness runs in a window nobody can attach to, so the preview is the
    // only channel that can report a value back.
    Text {
        anchors {
            top: parent.top
            left: parent.left
            margins: 8
        }

        z: 50
        color: "yellow"
        font.pixelSize: 13
        font.family: "monospace"

        text: {
            const lock = screen.item
            if (!lock)
                return "lock item not loaded"
            return "hasWallpaper=" + lock.hasWallpaper + "  fill=" + lock.wallpaperFillMode
                + "\nsource=[" + lock.wallpaperSource + "]"
                + "\nprobe=[" + lock.wallpaperProbe + "]"
        }
    }

    // State worth looking at: a password being retyped after a rejection.
    Timer {
        interval: 1600
        running: true
        onTriggered: {
            const lock = screen.item
            lock.wake()
            lock.entry = "hunter2"
        }
    }

    // Open the menu for the render: it is the one part of the screen there is
    // no other way to look at.
    Timer {
        interval: 2150
        running: true
        onTriggered: if (sessionMenuProbe.item)
            sessionMenuProbe.item.open = true
    }

    Timer {
        interval: 2200
        running: true
        onTriggered: wrapper.grabToImage(result => {
            // Next to this file, whatever the caller's cwd is.
            const url = Qt.resolvedUrl("lock.png").toString()
            const path = url.indexOf("file://") === 0
                ? decodeURIComponent(url.substring("file://".length))
                : url
            result.saveToFile(path)
        }, Qt.size(wrapper.width, wrapper.height))
    }

    // PAM messages are status, not a permanent record: they clear themselves.
    Timer {
        interval: 4400
        running: true
        onTriggered: {
            try {
                const lock = screen.item
                wrapper.check(lock.notification === "", 114)
                // A rejection ends the conversation, and nothing else starts a
                // new one. The theme has to queue it, or the next attempt --
                // the one with the correct password -- is dropped on the floor.
                wrapper.check(wrapper.authenticator.startCount >= 2, 120)
            } catch (e) {
                Qt.exit(199)
            }
        }
    }

    // The unlock path, left until last because it is the one that ends the run.
    // The theme must not agree to exit on the frame the secret is accepted:
    // the controls fade first, so the desktop is not swapped in behind a lock
    // screen that is still fully drawn.
    Timer {
        interval: 4700
        running: true
        onTriggered: wrapper.authenticator.succeeded()
    }

    Timer {
        interval: 4850
        running: true
        onTriggered: {
            try {
                const lock = screen.item
                wrapper.check(lock.dismiss > 0.1, 130)
                wrapper.done()
            } catch (e) {
                Qt.exit(199)
            }
        }
    }
}
