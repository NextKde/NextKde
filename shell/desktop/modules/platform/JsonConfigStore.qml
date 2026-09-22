pragma Singleton

import QtQuick
import Quickshell

// Shared persistence for the shell's small JSON state files.
//
// Every *ConfigService used to spawn a shell for mkdir/write/rename.
// The platform daemon now owns those paths through the bounded state.read /
// state.write ops: a canonicalized path confined to the
// $XDG_STATE_HOME/quickshell root, a 1 MiB payload cap, and an atomic
// QSaveFile commit, so a crash still cannot leave a half-written config.
//
// Callers keep passing their existing absolute paths (Quickshell.stateDir +
// "/<component>/<file>"); the payload carries the root-relative form because
// that is what the contract documents, and the daemon resolves both to the
// same file — so configs written by the old shell writers are read back
// without any migration.
QtObject {
    id: store

    // $XDG_STATE_HOME/quickshell — the daemon's state root. Quickshell.stateDir
    // resolves to <root>/<shell id>, so the root is its parent directory.
    readonly property string stateRoot: {
        const dir = String(Quickshell.stateDir).replace(/\/+$/, "")
        return dir.slice(0, dir.lastIndexOf("/"))
    }

    // The daemon accepts a root-relative dir or an absolute path under the
    // root; prefer the relative form so the payload stays small and mirrors
    // the documented contract.
    function _relativeDir(dir) {
        const path = String(dir).replace(/\/+$/, "")
        const prefix = stateRoot + "/"
        return path.indexOf(prefix) === 0 ? path.slice(prefix.length) : path
    }

    // onDone(data, exists): a missing file is reported as exists=false with an
    // empty data string — "no persisted state yet", same as the first run.
    // A transport or daemon failure lands here too (with a console.warn), so
    // callers keep a single "fall back to defaults" path.
    function read(dir, file, onDone) {
        PlatformClient.request("state.read",
            { dir: _relativeDir(dir), file: String(file) },
            function(response) {
                const result = response?.ok ? (response.result || ({})) : ({})
                if (!response?.ok)
                    console.warn("[JsonConfigStore] read failed: "
                        + (response?.error?.message || "platform unavailable"))
                onDone(result.exists ? String(result.data ?? "") : "",
                       result.exists === true)
            })
    }

    // onDone(ok): optional. Failures are already warned here, so most writers
    // do not need it; it exists for callers that must chain a second op on a
    // committed file (see LockScreenFeedService).
    function write(dir, file, data, onDone) {
        PlatformClient.request("state.write",
            { dir: _relativeDir(dir), file: String(file), data: String(data) },
            function(response) {
                const ok = !!response?.ok
                if (!ok)
                    console.warn("[JsonConfigStore] write failed: "
                        + (response?.error?.message || "platform unavailable"))
                if (onDone)
                    onDone(ok)
            })
    }

    function readPath(path, onDone) {
        const split = String(path).lastIndexOf("/")
        read(String(path).slice(0, split), String(path).slice(split + 1), onDone)
    }

    function writePath(path, data, onDone) {
        const split = String(path).lastIndexOf("/")
        write(String(path).slice(0, split), String(path).slice(split + 1),
              data, onDone)
    }
}
