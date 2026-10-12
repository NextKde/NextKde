import QtQuick
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd
import "qml/Lifecycle.js" as Lifecycle
import "qml" as Greeter

ShellRoot {
    id: root
    property string phase: "Idle"
    readonly property bool reducedMotion: Quickshell.env("KOS_GREETER_REDUCED_MOTION") === "1"
    readonly property int exitDuration: reducedMotion ? 1 : Math.max(180, Math.min(280, Number(Quickshell.env("KOS_GREETER_EXIT_MS")) || 220))
    property bool exitFrameArmed: false
    property int exitFramesRemaining: 0
    property bool backendRecovery: false
    property bool responseSent: false
    function mark(event) { console.info("KOS_GREETER_VISUAL " + event + " " + Date.now()); }
    function exitComplete() {
        if (phase !== "Exiting") return;
        mark("ExitComplete");
        // Arm on the next event-loop turn, then request a new pure-background frame.
        Qt.callLater(function() {
            if (root.phase !== "Exiting") return;
            root.exitFramesRemaining = 2; root.exitFrameArmed = true;
            if (visual.Window.window) visual.Window.window.update();
        });
    }
    function frameSubmitted() {
        if (!exitFrameArmed || phase !== "Exiting" || visual.opacity !== 0 || shade.opacity !== 0) return;
        if (!startupReady && !startupFallback) return;
        // Drain any swap already queued by the render thread before arming.
        // Its completion precedes this explicit request for another zero-UI frame.
        if (--exitFramesRemaining > 0) {
            mark("ExitFrameDrain");
            if (visual.Window.window) visual.Window.window.update();
            return;
        }
        exitFrameArmed = false;
        if (Greetd.state !== GreetdState.ReadyToLaunch) { recoverBackend(); return; }
        mark("FrameSubmitted"); step("launch"); mark("LaunchRequested");
        watchdog.interval = 10000; watchdog.restart();
        Greetd.launch(sessionCommand, [], false);
    }
    function recoverBackend() {
        wipe(); exitAnimation.stop(); exitFrameArmed = false;
        backendRecovery = true; notice = "会话启动失败，正在重建认证；请重新登录";
        phase = "Cancelling"; watchdog.interval = 5000; watchdog.restart();
        Greetd.cancelSession();
    }
    property string notice: Greetd.available ? "" : "登录服务未连接"
    property string feedback: ""
    property bool echoResponse: false
    property bool promptError: false
    property var accounts: []
    property var selectedUid: null
    property bool choosingUser: true
    property bool returningToList: false
    property bool accountsReady: false
    property bool startupComplete: false
    property bool startupFallback: false
    readonly property bool startupReady: accountsReady && wallpaperSource.ready && primaryWallpaper.resourceSettled &&
        (Quickshell.env("QT_QPA_PLATFORM") === "offscreen" ||
         (wallpaperWindows.item && activeScreen && wallpaperWindows.item.settledScreens[activeScreen.name] === true))
    onStartupReadyChanged: if (startupReady) startupComplete = true
    Component.onCompleted: if (startupReady) startupComplete = true

    Greeter.WallpaperSource { id: wallpaperSource; uid: root.selectedUid; frozen: ["ReadyToLaunch", "Exiting", "LaunchRequested"].includes(root.phase) }
    Loader {
        id: wallpaperWindows
        active: Quickshell.env("QT_QPA_PLATFORM") !== "offscreen"
        source: "qml/WallpaperWindows.qml"
        onLoaded: {
            item.state = Qt.binding(function() { return wallpaperSource.state; });
            item.sourceReady = Qt.binding(function() { return root.accountsReady && wallpaperSource.ready; });
        }
    }
    Timer {
        interval: 7000; running: !root.startupComplete
        onTriggered: {
            root.startupFallback = true; root.startupComplete = true;
            console.info("KOS_WALLPAPER_STARTUP_FALLBACK");
        }
    }
    property var outputState: null
    readonly property var activeScreen: chooseScreen()
    function chooseScreen() {
        let screens = Quickshell.screens;
        if (outputState && outputState.status !== "inventory-unavailable") {
            if (outputState.primary) {
                for (let screen of screens) if (screen.name === outputState.primary) return screen;
            }
            for (let output of outputState.outputs || []) {
                for (let screen of screens) if (screen.name === output.connector) return screen;
            }
            return null;
        }
        // Qt's enabled output list is the fallback when KScreen is unavailable.
        for (let screen of screens) if (screen.width > 32 && screen.height > 32) return screen;
        return null;
    }
    function restoreFocus() {
        Qt.callLater(function() {
            if (root.phase === "AwaitingPrompt") response.forceActiveFocus();
            else root.focusIdentity();
        });
    }
    Process {
        id: outputController
        command: ["/usr/bin/python3", Quickshell.shellDir + "/companion/display.py", "--watch"].concat(
            Quickshell.env("KOS_GREETER_OUTPUT_APPLY") === "1" ? ["--apply"] : [])
        running: Quickshell.env("QT_QPA_PLATFORM") !== "offscreen"
        onExited: (exitCode, exitStatus) => { root.outputState = null; }
        stdout: SplitParser {
            onRead: data => {
                try { root.outputState = JSON.parse(data); } catch (_) {}
            }
        }
    }
    onActiveScreenChanged: restoreFocus()

    function focusIdentity() {
        Qt.callLater(function() {
            if (root.choosingUser) otherUserButton.forceActiveFocus();
            else if (root.phase === "AwaitingPrompt" || root.selectedUid !== null) response.forceActiveFocus();
            else username.forceActiveFocus();
        });
    }
    function selectUser(account) {
        if (phase !== "Idle") return;
        wipe(); selectedUid = account ? account.uid : null;
        username.text = account ? account.username : "";
        choosingUser = false; feedback = ""; promptError = false; notice = "";
        focusIdentity();
        if (account) submit();
    }
    function backToList() {
        wipe();
        if (phase === "Idle") { choosingUser = true; selectedUid = null; username.text = ""; focusIdentity(); }
        else { returningToList = true; cancel(); }
    }
    Process {
        id: accountReader
        command: ["/usr/bin/python3", Quickshell.shellDir + "/companion/accounts.py"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.accounts = JSON.parse(text); if (root.accounts.length === 1 && root.phase === "Idle" && root.choosingUser) root.selectUser(root.accounts[0]); } catch (_) { root.accounts = []; }
                root.accountsReady = true;
            }
        }
    }
    Timer { id: accountTimeout; interval: 10000; running: true; onTriggered: { accountReader.running = false; root.accountsReady = true; } }
    // Fixed allowlist, checked against the installed desktop entry by the wrapper.
    readonly property var sessionCommand: [Quickshell.shellDir + "/bin/kos-user-session"]

    function step(event) {
        let previous = phase;
        phase = Lifecycle.next(phase, event);
        if (phase !== previous) console.info("KOS_GREETER_STATE " + phase);
    }
    function wallpaperPosition(field) {
        // mapToItem does not establish dependencies for ancestor transforms.
        // Explicitly observe layout and ScrollView's Flickable content offsets.
        let layout = field.x + field.y + field.width + field.height +
            formViewport.x + formViewport.y + formViewport.width + formViewport.height +
            form.width + form.implicitHeight + primaryWallpaper.width + primaryWallpaper.height;
        let flick = formViewport.contentItem;
        let scrolling = flick ? (flick.contentX || 0) + (flick.contentY || 0) : 0;
        return field.mapToItem(primaryWallpaper, 0, 0);
    }
    function wipe() { response.text = ""; }
    function terminate() {
        wipe(); watchdog.stop(); exitAnimation.stop(); exitFrameArmed = false;
        step("fatal"); Qt.quit();
    }
    function cancel() {
        if (!["Authenticating", "AwaitingPrompt", "ReadyToLaunch", "Exiting"].includes(phase)) return;
        wipe(); exitAnimation.stop(); exitFrameArmed = false; step("cancel");
        watchdog.interval = 60000; watchdog.restart(); Greetd.cancelSession();
    }
    function submit() {
        if (!Greetd.available) return;
        if (phase === "Idle" && !choosingUser && username.text.trim().length > 0) {
            wipe(); responseSent = false; promptError = false; notice = "认证中"; step("begin"); watchdog.interval = 60000; watchdog.restart();
            Greetd.createSession(username.text.trim());
        } else if (phase === "AwaitingPrompt") {
            responseSent = true; feedback = ""; step("respond"); watchdog.restart();
            // No application-level cache; clear the field immediately after IPC serialization.
            Greetd.respond(response.text); wipe();
        }
    }
    Connections {
        target: Greetd
        function onAvailableChanged() {
            if (Greetd.available && root.phase === "Idle" && !root.choosingUser && root.selectedUid !== null) authenticationRestart.restart();
        }
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (!["Authenticating", "AwaitingPrompt"].includes(root.phase)) return;
            root.wipe(); root.notice = message; root.promptError = error; watchdog.restart();
            if (responseRequired) {
                root.echoResponse = echoResponse; root.step("prompt"); response.forceActiveFocus();
            } else { root.step("message"); }
        }
        function onAuthFailure(message) {
            if (root.phase === "Cancelling") return;
            if (!["Authenticating", "AwaitingPrompt"].includes(root.phase)) {
                if (root.phase === "LaunchRequested") root.recoverBackend();
                else root.terminate();
                return;
            }
            root.wipe(); watchdog.stop(); root.step("failure"); root.feedback = root.responseSent ? "认证失败，请重新输入" : "无法开始认证，请按回车重试";
            if (root.responseSent) authenticationRestart.restart();
        }
        function onStateChanged() {
            if (root.phase === "Cancelling" && Greetd.state === GreetdState.Inactive) {
                watchdog.stop(); root.step("inactive"); root.feedback = root.backendRecovery ? "会话启动失败，请重试" : ""; root.notice = ""; root.backendRecovery = false;
                if (root.returningToList) { root.returningToList = false; root.backToList(); }
                else authenticationRestart.restart();
            }
        }
        function onError(error) {
            root.wipe(); exitAnimation.stop(); root.exitFrameArmed = false;
            root.phase = "Terminated"; root.notice = "登录连接异常；即将退出并由登录宿主重建会话";
            watchdog.stop(); diagnosticExit.restart();
        }
        function onReadyToLaunch() {
            if (root.phase !== "Authenticating") return;
            root.wipe(); root.step("ready"); root.step("exit"); root.mark("ExitStarted"); exitAnimation.restart(); watchdog.interval = 5000; watchdog.restart();
        }
        function onLaunched() {
            if (root.phase !== "LaunchRequested") return;
            root.wipe(); watchdog.stop(); root.step("acknowledged"); Qt.quit();
        }
    }
    Timer {
        id: watchdog
        interval: 60000
        onTriggered: root.terminate()
    }
    Timer {
        id: authenticationRestart; interval: 80; repeat: true
        property int attempts: 0
        onRunningChanged: if (running) attempts = 0
        onTriggered: {
            if (root.phase !== "Idle" || root.choosingUser) { stop(); return; }
            if (++attempts > 60) { stop(); root.terminate(); return; }
            if (Greetd.state === GreetdState.Inactive) { stop(); root.submit(); }
        }
    }
    Timer { id: diagnosticExit; interval: 1800; onTriggered: Qt.quit() }
    ParallelAnimation {
        id: exitAnimation
        NumberAnimation { target: visual; property: "opacity"; to: 0; duration: root.exitDuration; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shade; property: "opacity"; to: 0; duration: root.exitDuration; easing.type: Easing.InOutQuad }
        onFinished: root.exitComplete()
    }
    onPhaseChanged: {
        if (!["Exiting", "LaunchRequested"].includes(phase)) {
            exitAnimation.stop(); exitFrameArmed = false; visual.opacity = 1; shade.opacity = 0.16;
        }
    }
    Timer {
        id: windowRecovery
        interval: 2500
        onTriggered: {
            if (root.activeScreen !== null && !window.backingWindowVisible) root.terminate();
        }
    }
    FloatingWindow {
        id: window
        // Start with the output geometry, before the fullscreen configure arrives.
        implicitWidth: screen ? screen.width : 900
        implicitHeight: screen ? screen.height : 600
        screen: root.activeScreen
        fullscreen: Quickshell.env("QT_QPA_PLATFORM") !== "offscreen"
        visible: root.activeScreen !== null && root.startupComplete
        onScreenChanged: root.restoreFocus()
        color: "transparent"
        title: "KOS 登录"
        onClosed: windowRecovery.restart()
        Item {
            id: composition; anchors.fill: parent
        Greeter.WallpaperHost {
            id: primaryWallpaper
            pixelRatio: window.screen ? window.screen.devicePixelRatio : 1
            anchors.fill: parent
            // Paint and sample the same local static composition. This avoids
            // relying on a separate hidden backdrop for the glass texture;
            // the sample contains only wallpaper, never UI or credentials.
            visible: true
            source: wallpaperSource.state.source
            fitMode: wallpaperSource.state.fit
        }
        Connections {
            target: visual.Window.window
            function onFrameSwapped() { root.frameSubmitted(); }
        }
        Rectangle { id: shade; anchors.fill: parent; color: "black"; opacity: 0.16 }
        Item {
            id: visual
            anchors.fill: parent
            enabled: !["ReadyToLaunch", "Exiting", "LaunchRequested", "Terminated", "Cancelling"].includes(root.phase)
            Keys.onEscapePressed: event => {
                if (!["ReadyToLaunch", "Exiting", "LaunchRequested", "Terminated", "Cancelling"].includes(root.phase)) root.backToList();
            }
            property date now: new Date()
            Timer { interval: 1000; running: true; repeat: true; onTriggered: visual.now = new Date() }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.108 - height / 2
                text: Qt.formatDate(visual.now, "M月d日") + "  " + ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"][visual.now.getDay()]
                color: "white"; font.pixelSize: Math.max(14, Math.min(28, parent.height * 0.025))
                style: Text.Raised; styleColor: "#55000000"
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.187 - height / 2
                text: Qt.formatTime(visual.now, "hh:mm")
                color: "#e6ffffff"; font.pixelSize: Math.max(40, Math.min(160, parent.height * 0.145))
                font.weight: Font.Medium
                // Plain text is the deterministic material fallback; no shader dependency.
                style: Text.Raised; styleColor: "#55000000"
            }
        ScrollView {
            id: formViewport
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.max(16, Math.min(parent.height * 0.79, parent.height - height - 16))
            width: Math.max(0, Math.min(340, parent.width - 32))
            height: Math.max(0, Math.min(form.implicitHeight, parent.height * 0.55, parent.height - 32))
            contentWidth: availableWidth
            contentHeight: form.implicitHeight
            clip: true
        Column {
            id: form
            spacing: 12; width: formViewport.availableWidth
            Rectangle {
                visible: !root.choosingUser && root.selectedUid !== null
                width: 72; height: 72; radius: 36
                color: "#566c80"; border.color: "#60ffffff"; border.width: 1
                anchors.horizontalCenter: parent.horizontalCenter
                readonly property var account: root.accounts.find(a => a.uid === root.selectedUid)
                Image { id: selectedAvatar; anchors.fill: parent; source: parent.account ? parent.account.avatar : ""; fillMode: Image.PreserveAspectFit }
                Item {
                    anchors.fill: parent; visible: selectedAvatar.status !== Image.Ready
                    Rectangle { width: 20; height: 20; radius: 10; anchors.horizontalCenter: parent.horizontalCenter; y: 15; color: "#edf2f6" }
                    Rectangle { width: 38; height: 22; radius: 12; anchors.horizontalCenter: parent.horizontalCenter; y: 39; color: "#edf2f6" }
                }
            }
            Label {
                visible: !root.choosingUser && root.selectedUid !== null
                text: { let a = root.accounts.find(a => a.uid === root.selectedUid); return a ? a.displayName : ""; }
                textFormat: Text.PlainText; color: "white"; font.pixelSize: 17; font.weight: Font.Medium
                width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
            }
            ScrollView {
                width: parent.width; height: Math.min(230, userList.implicitHeight); visible: root.choosingUser
                clip: true
                Column {
                    id: userList; width: form.width; spacing: 10
                    Repeater {
                        model: root.accounts
                        Button {
                            required property var modelData
                            width: form.width; height: 56
                            text: modelData.displayName
                            Accessible.name: modelData.displayName + "，登录名 " + modelData.username
                            enabled: root.phase === "Idle"; onClicked: root.selectUser(modelData)
                            background: Rectangle { radius: 16; color: parent.hovered ? "#30ffffff" : "#12000000" }
                            contentItem: Row {
                                spacing: 14
                                Rectangle {
                                    width: 40; height: 40; radius: 20; color: "#566c80"
                                    Image { id: icon; anchors.fill: parent; source: modelData.avatar; fillMode: Image.PreserveAspectFit }
                                    Label { anchors.centerIn: parent; text: "●"; visible: icon.status !== Image.Ready; color: "white" }
                                }
                                Label { height: 40; verticalAlignment: Text.AlignVCenter; text: modelData.displayName; textFormat: Text.PlainText; font.pixelSize: 16; color: "white"; width: Math.max(0, form.width - 68); elide: Text.ElideRight }
                            }
                        }
                    }
                    Button {
                        id: otherUserButton; text: "其他用户"; width: parent.width; height: 36
                        enabled: root.phase === "Idle"; onClicked: root.selectUser(null)
                        background: Item {}
                        contentItem: Text { text: parent.text; color: "#e6ffffff"; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    }
                }
            }
            TextField {
                id: username; width: Math.min(250, parent.width); height: 40; anchors.horizontalCenter: parent.horizontalCenter
                maximumLength: 256; placeholderText: "登录名"; color: "white"; placeholderTextColor: "#d9ffffff"
                font.pixelSize: 14; padding: 12; horizontalAlignment: TextInput.AlignHCenter
                background: Greeter.GlassFieldBackground {
                    backdrop: primaryWallpaper; focused: username.activeFocus
                    sampleOrigin: root.wallpaperPosition(username)
                }
                visible: !root.choosingUser && root.selectedUid === null
                Accessible.name: "登录名"; enabled: root.phase === "Idle" && Greetd.available
                onAccepted: root.submit()
            }
            TextField {
                id: response; width: Math.min(250, parent.width); height: 40; anchors.horizontalCenter: parent.horizontalCenter
                maximumLength: 4096; color: "white"; placeholderTextColor: "#d9ffffff"
                font.pixelSize: 14; leftPadding: 16; rightPadding: 16; horizontalAlignment: TextInput.AlignHCenter
                property string promptLabel: root.phase === "AwaitingPrompt" ? (root.echoResponse ? root.notice : (/password|密码/i.test(root.notice) ? "密码" : root.notice)) : (root.phase === "Authenticating" ? "正在验证…" : "密码")
                placeholderText: ""
                background: Greeter.GlassFieldBackground {
                    backdrop: primaryWallpaper; focused: response.activeFocus
                    sampleOrigin: root.wallpaperPosition(response)
                    Text { anchors.fill: parent; text: response.promptLabel; visible: response.text.length === 0; color: "#d9ffffff"; font.pixelSize: 14; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; leftPadding: 16; rightPadding: 16 }
                }
                visible: !root.choosingUser && (root.selectedUid !== null || root.phase !== "Idle")
                enabled: Greetd.available && (root.phase === "AwaitingPrompt" || (root.phase === "Idle" && !root.choosingUser))
                Accessible.name: root.notice || "密码"
                echoMode: root.echoResponse ? TextInput.Normal : TextInput.Password
                inputMethodHints: root.echoResponse ? Qt.ImhNone : Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                onAccepted: root.submit()
            }
            Greeter.LoadingSpinner {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: ["Authenticating", "ReadyToLaunch", "Exiting", "LaunchRequested"].includes(root.phase)
                reducedMotion: root.reducedMotion
            }
            Label {
                text: root.feedback || (root.promptError || root.phase === "Terminated" || (!Greetd.available && !root.choosingUser) ? root.notice : (root.phase === "Authenticating" && root.notice !== "认证中" ? root.notice : ""))
                visible: text.length > 0; Accessible.name: text
                color: root.feedback || root.promptError ? "#ffcfad" : "#e6ffffff"
                width: parent.width; horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap; textFormat: Text.PlainText; font.pixelSize: 13
            }
            Button {
                visible: !root.choosingUser && (root.accounts.length > 1 || root.selectedUid === null)
                width: parent.width; height: 28; text: "切换用户"
                enabled: !["ReadyToLaunch", "Exiting", "LaunchRequested", "Terminated", "Cancelling"].includes(root.phase)
                onClicked: root.backToList()
                background: Item {}
                contentItem: Text { text: parent.text; color: "#ccffffff"; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            }
        }
        }
        }
        }
    }
}
