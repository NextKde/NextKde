// No user names, prompts or responses are retained by the lifecycle model.
function next(state, event) {
    var transitions = {
        Idle: { begin: "Authenticating" },
        Authenticating: { prompt: "AwaitingPrompt", ready: "ReadyToLaunch", failure: "Idle", cancel: "Cancelling" },
        AwaitingPrompt: { message: "Authenticating", respond: "Authenticating", prompt: "AwaitingPrompt", failure: "Idle", cancel: "Cancelling" },
        Cancelling: { inactive: "Idle" },
        ReadyToLaunch: { exit: "Exiting", cancel: "Cancelling" },
        Exiting: { launch: "LaunchRequested", cancel: "Cancelling" },
        LaunchRequested: { acknowledged: "Terminated" },
        Terminated: {}
    };
    if (event === "fatal" || event === "timeout") return "Terminated";
    return (transitions[state] || {})[event] || state;
}
