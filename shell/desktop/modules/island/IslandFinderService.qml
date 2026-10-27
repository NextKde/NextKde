pragma Singleton
import QtQuick
import qs.desktop.modules.platform

// IslandFinderService — file search for the island.
//
// Islet searches with `fd` and `fzf`. This shell may not run external
// commands from its UI, so the walk and the fuzzy match live in the data
// service (kos-data-service, files.go) and this adapter only holds the query
// and the results.
//
// The index is a snapshot of the home directory, rebuilt in the background
// every ten minutes; a search answers from the last build, and the first one
// triggers a build if there is none yet.
QtObject {
    id: service

    property string query: ""
    property var results: []
    property int indexed: 0
    property bool ready: false
    property bool searching: false
    property string errorMessage: ""

    // Typing must not produce one request per keystroke, but the delay has
    // to stay under the length of a word: the panel feels dead at 400ms.
    property int debounceMs: 120

    Timer {
        id: debounce
        interval: service.debounceMs
        onTriggered: service.run()
    }

    function setQuery(text) {
        query = String(text || "")
        debounce.restart()
    }

    function clear() {
        query = ""
        results = []
        indexed = 0
    }

    function run() {
        if (query.length === 0 && results.length > 0)
            return
        searching = true
        DataClient.request("files.search", { query: query, limit: 24 },
            function(response) {
                service.searching = false
                if (!response || !response.ok) {
                    service.errorMessage = response && response.error
                        ? String(response.error.message || "") : ""
                    return
                }
                service.errorMessage = ""
                const result = response.result || {}
                service.results = result.results || []
                service.indexed = Number(result.indexed || 0)
                service.ready = Boolean(result.ready)
            })
    }

    // Where did a shelved file go? The shelf keeps a reference, so the file
    // can be moved or renamed behind its back. The data service answers from
    // its index: the original path first, then the same name elsewhere.
    function resolve(path, name, callback) {
        DataClient.request("files.resolve", { path: path, name: name },
            function(response) {
                if (!response || !response.ok) {
                    callback(path, false)
                    return
                }
                const result = response.result || {}
                callback(String(result.path || path), Boolean(result.found))
            })
    }

    function refresh() {
        DataClient.request("files.refresh", {}, function() {})
        // The rebuild is asynchronous; ask again shortly so the list fills in.
        debounce.interval = 600
        debounce.restart()
        debounce.interval = service.debounceMs
    }
}
