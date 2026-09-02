pragma Singleton
import QtQuick
import Quickshell

// Starts standalone Qt Quick applications without importing their UI into, or
// tying their lifetime to, the Shell process.
QtObject {
    id: launcher

    readonly property string settingsEntrypoint:
        Quickshell.shellDir + "/../apps/settings/main.qml"
    readonly property string settingsBinary:
        Quickshell.shellDir + "/../apps/settings/build/kos-settings"

    function openSettings() {
        Quickshell.execDetached([
            "sh", "-c",
            "if [ -x \"$1\" ]; then exec \"$1\"; fi; "
            + "if [ -x \"$2\" ]; then exec \"$2\"; fi; "
            + "if command -v kos-settings >/dev/null 2>&1; then exec kos-settings; fi; "
            + "if [ -x \"$HOME/.local/bin/kos-settings\" ]; then exec \"$HOME/.local/bin/kos-settings\"; fi; "
            + "if command -v qml6 >/dev/null 2>&1; then exec qml6 \"$3\"; fi",
            "kos-settings-launch",
            launcher.settingsBinary,
            Quickshell.shellDir + "/../.build/apps/settings/kos-settings",
            launcher.settingsEntrypoint
        ])
    }
}
