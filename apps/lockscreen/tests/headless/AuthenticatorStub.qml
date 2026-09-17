// Stands in for the object kscreenlocker_greet injects as `authenticator`.
// Verification only.
//
// It reproduces the parts of PamAuthenticators that decide whether a password
// can reach PAM at all, because that is where this theme can fail with no
// visible symptom. Two behaviours matter:
//
//   - startAuthenticating() is refused outright while the greeter's grace
//     period holds, so a theme that only asks once, at load time, is asking at
//     the one moment it will be turned down (PamAuthenticators returns early
//     on `state == Authenticating || graceLocked`, silently);
//   - respond() is forwarded unconditionally by the real object, so an answer
//     handed to a conversation that is not running disappears. The real one
//     cannot report that; the stub counts it instead, which is what turns
//     "the correct password does nothing" into a failing assertion.
import QtQml

QtObject {
    signal failed(int kind)
    signal succeeded()

    property string infoMessage: ""
    property string errorMessage: ""
    property string promptForSecret: ""
    property bool hadPrompt: false

    // Mirrors PamAuthenticators::AuthenticatorsState.
    readonly property int idle: 0
    readonly property int authenticating: 1

    property int state: 0

    // Raised while the greeter is settling the lock; start requests are
    // refused for as long as it holds.
    property bool graceLocked: true

    property int startCount: 0
    property int refusedStartCount: 0

    // Only a running conversation fills this in.
    property string lastResponded: ""
    property int droppedRespondCount: 0

    // A conversation ends with the attempt that ran it, and the real object
    // returns to Idle there -- that is what lets the *next* start request be
    // answered instead of being refused by the state check above.
    onFailed: state = idle

    function startAuthenticating() {
        if (state === authenticating || graceLocked) {
            refusedStartCount++
            return
        }
        state = authenticating
        startCount++
    }

    function respond(secret) {
        if (state !== authenticating) {
            droppedRespondCount++
            return
        }
        lastResponded = secret
    }
}
