import QtQml

// UI-shell seam for the future C++/Qt application facade.
// This object intentionally contains no persistence, network, audio, or file I/O.
QtObject {
    id: facade

    signal navigateRequested(string route)
    signal playbackCommandRequested(string command)
    signal settingChanged(string key, var value)
    signal queueCommandRequested(string command, var payload)
    signal accountCookieSaveRequested(string provider, string cookie)
    signal accountLogoutRequested(string provider)
    signal accountCookieTestResult(string provider, bool success, string accountName)

    function navigate(route) {
        navigateRequested(route);
    }

    function requestPlayback(command) {
        playbackCommandRequested(command);
    }

    function setSetting(key, value) {
        settingChanged(key, value);
    }

    function requestQueue(command, payload) {
        queueCommandRequested(command, payload);
    }

    // Dedicated transient channel: callers must not log or persist the cookie
    // as a normal setting. The backend owns validation and credential storage.
    function requestAccountCookieSave(provider, cookie) {
        accountCookieSaveRequested(provider, cookie);
    }

    function requestAccountLogout(provider) {
        accountLogoutRequested(provider);
    }

    function reportAccountCookieTestResult(provider, success, accountName) {
        accountCookieTestResult(provider, success, accountName);
    }
}
