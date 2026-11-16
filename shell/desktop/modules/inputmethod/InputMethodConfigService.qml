pragma Singleton
import QtQuick
import Quickshell
import qs.desktop.modules.platform

// Presentation preferences belong to NextKde state, never Fcitx config.
QtObject {
    id: service
    readonly property string configPath: Quickshell.stateDir + "/inputmethod/presentation.json"
    property bool ready: false
    property string saveError: ""
    property var preferences: defaults()
    readonly property int fontSize: preferences.fontSize
    readonly property string layout: preferences.layout
    readonly property string material: preferences.material
    readonly property bool showAnnotations: preferences.showAnnotations
    readonly property bool highContrast: preferences.highContrast
    readonly property bool reduceMotion: preferences.reduceMotion

    function defaults() {
        return {fontSize: 15, layout: "engine", material: "liquid", showAnnotations: true,
            highContrast: false, reduceMotion: false}
    }

    function valid(key, value) {
        if (key === "fontSize")
            return typeof value === "number" && Number.isInteger(value) && value >= 12 && value <= 24
        if (key === "layout")
            return ["engine", "adaptive", "horizontal", "vertical"].indexOf(value) >= 0
        if (key === "material")
            return ["liquid", "frosted"].indexOf(value) >= 0
        return ["showAnnotations", "highContrast", "reduceMotion"].indexOf(key) >= 0
            && typeof value === "boolean"
    }

    function snapshot() {
        return Object.assign({ready: ready, saveError: saveError}, preferences)
    }

    function update(patch) {
        if (!ready || !patch || typeof patch !== "object" || Array.isArray(patch)) return false
        const keys = Object.keys(patch)
        if (keys.some(key => !valid(key, patch[key]))) return false
        const next = Object.assign({}, preferences, patch)
        if (JSON.stringify(next) === JSON.stringify(preferences)) return true
        preferences = next
        saveError = ""
        saveTimer.restart()
        return true
    }

    property Timer saveTimer: Timer {
        interval: 250
        onTriggered: {
            JsonConfigStore.writePath(service.configPath,
                JSON.stringify(Object.assign({version: 1}, service.preferences)), function(ok) {
                    service.saveError = ok ? "" : "Could not save candidate appearance"
                })
        }
    }

    Component.onCompleted: JsonConfigStore.readPath(configPath, function(data, exists) {
        const next = service.defaults()
        if (exists) {
            try {
                const saved = JSON.parse(data)
                for (const key of Object.keys(next))
                    if (service.valid(key, saved[key])) next[key] = saved[key]
            } catch (error) {
                console.warn("[InputMethodConfig] Invalid presentation preferences: " + error)
            }
        }
        service.preferences = next
        service.ready = true
    })
}
