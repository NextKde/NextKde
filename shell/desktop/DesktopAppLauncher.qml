pragma Singleton
import QtQuick
import Quickshell

// Starts standalone Qt Quick applications without importing their UI into, or
// tying their lifetime to, the Shell process.
QtObject {
    id: launcher

    readonly property string settingsBinary:
        Quickshell.shellDir + "/../apps/settings/build/kos-settings"

    function openSettings() {
        Quickshell.execDetached([
            "sh", "-c",
            // Settings talks back to its Shell over Quickshell IPC. Preserve
            // the active Shell directory so a source-tree session opens a
            // Settings window connected to that same session rather than the
            // installed `kos` configuration. Candidates are deliberately
            // limited to the one canonical in-tree artifact plus the
            // installed copy: a second build tree would drift and open a
            // Settings build that does not match the running Shell.
            "export KOS_SHELL_DIR=\"$2\"; "
            + "if [ -x \"$1\" ]; then exec \"$1\"; fi; "
            + "if command -v kos-settings >/dev/null 2>&1; then exec kos-settings; fi; "
            + "if [ -x \"$HOME/.local/bin/kos-settings\" ]; then exec \"$HOME/.local/bin/kos-settings\"; fi; "
            + "echo 'kos-settings is not built; run ./tools/kosctl build' >&2; exit 1",
            "kos-settings-launch",
            launcher.settingsBinary,
            Quickshell.shellDir
        ])
    }
}
