// Verification only: mirrors the PAM prompt/response boundary, not real auth.
// Starting a conversation is asynchronous and does not make respond() valid.
// KDE 6.8 emits promptForSecretChanged before storing its pending D-Bus reply;
// a consumer must defer a response from that signal until the stack unwinds.
import QtQml

QtObject {
    id: backend
    signal failed(int kind, var channel)
    signal succeeded()
    signal loginFailedDelayStarted(int kind, var channel, int usecDelay)

    property string infoMessage: ""
    property string errorMessage: ""
    property string promptForSecret: ""
    property bool hadPrompt: false
    property bool busy: false
    property bool inPasswordDelay: false
    property bool workerReady: true
    // -1 delivers synchronously, >= 0 models asynchronous worker startup.
    property int promptDelay: -1
    property bool pendingPrompt: false

    readonly property int idle: 0
    readonly property int authenticating: 1
    property int state: 0
    property bool graceLocked: true
    property int startCount: 0
    property int refusedStartCount: 0
    property string lastResponded: ""
    property int responseCount: 0
    property int droppedRespondCount: 0

    property Timer promptTimer: Timer {
        onTriggered: backend.deliverPrompt()
    }

    onFailed: (kind, channel) => {
        if (kind === 0) {
            promptTimer.stop()
            state = idle
            busy = false
            pendingPrompt = false
            // Real PAM retains its last prompt text after consuming the reply.
        }
    }

    function deliverPrompt() {
        busy = false
        hadPrompt = true
        if (promptForSecret === "Password:") promptForSecretChanged()
        else promptForSecret = "Password:"
        // Intentionally AFTER the notification, like promptInternal().
        pendingPrompt = true
    }

    function startAuthenticating() {
        if (graceLocked || inPasswordDelay || busy || pendingPrompt) {
            refusedStartCount++
            return
        }
        // The group can report Authenticating even when worker startup failed.
        state = authenticating
        if (!workerReady) { refusedStartCount++; return }
        busy = true
        startCount++
        if (promptDelay < 0) deliverPrompt()
        else {
            promptTimer.interval = promptDelay
            promptTimer.start()
        }
    }

    function respond(secret) {
        if (!pendingPrompt) { droppedRespondCount++; return }
        pendingPrompt = false
        lastResponded = secret
        responseCount++
        // busy and the old prompt text are not a readiness indicator after send.
    }
}
