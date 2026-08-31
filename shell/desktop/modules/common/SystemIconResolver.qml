pragma Singleton

import QtQuick
import Quickshell

// Semantic icon contract for shell chrome and menus.
//
// Consumers ask for a role instead of embedding a Font Awesome glyph, an SVG
// path, or a theme-specific filename. Candidate names follow the freedesktop /
// KDE naming conventions and are resolved by the active system icon theme.
// IconThemeReloadService reloads the shell when that theme changes, so no
// component needs to watch kdeglobals independently.
QtObject {
    id: resolver

    function candidates(role, state) {
        const key = String(role || "")
        const variant = String(state || "")
        switch (key) {
        case "cpu":
            return ["cpu-symbolic", "cpu", "preferences-devices-cpu"]
        case "temperature":
            return ["temperature-symbolic", "sensors-temperature-symbolic",
                "temperature-normal", "weather-temperature"]
        case "settings":
            return ["preferences-system-symbolic", "preferences-system", "systemsettings"]
        case "controlCenter":
            return ["view-media-equalizer", "adjustlevels", "preferences-system"]
        case "open":
            return ["document-open-symbolic", "document-open", "folder-open"]
        case "edit":
            return ["document-edit-symbolic", "document-edit", "edit"]
        case "pin":
            return ["window-pin-symbolic", "window-pin", "pin"]
        case "unpin":
            return ["window-unpin-symbolic", "window-unpin", "window-pin", "pin"]
        case "activateWindow":
            return ["window-restore-symbolic", "window-restore", "window"]
        case "minimize":
            return ["window-minimize-symbolic", "window-minimize"]
        case "close":
            return ["window-close-symbolic", "window-close"]
        case "copy":
            return ["edit-copy-symbolic", "edit-copy"]
        case "cut":
            return ["edit-cut-symbolic", "edit-cut"]
        case "paste":
            return ["edit-paste-symbolic", "edit-paste"]
        case "trash":
            return ["user-trash-symbolic", "user-trash"]
        case "folder":
            return ["folder-symbolic", "folder"]
        case "newFile":
            return ["document-new-symbolic", "document-new"]
        case "newFolder":
            return ["folder-new-symbolic", "folder-new"]
        case "refresh":
            return ["view-refresh-symbolic", "view-refresh"]
        case "rename":
            return ["edit-rename-symbolic", "edit-rename"]
        case "openWith":
            return ["system-run-symbolic", "system-run", "application-x-executable"]
        case "sort":
            return ["view-sort-symbolic", "view-sort"]
        case "iconSize":
            return ["view-list-icons-symbolic", "view-list-icons"]
        case "appearance":
            return ["preferences-desktop-theme-symbolic", "preferences-desktop-theme"]
        case "visibility":
            return ["view-visible-symbolic", "view-visible"]
        case "reset":
            return ["edit-undo-symbolic", "edit-undo"]
        case "back":
            return ["go-previous-symbolic", "go-previous"]
        case "submenu":
            return ["go-next-symbolic", "go-next"]
        case "check":
            return ["checkmark-symbolic", "dialog-ok-symbolic", "dialog-ok"]
        case "remove":
            return ["list-remove-symbolic", "list-remove"]
        case "radio":
            return variant === "checked"
                ? ["radio-checked-symbolic", "radio-checked"]
                : ["radio-symbolic", "radio"]
        case "lock":
            return ["system-lock-screen-symbolic", "system-lock-screen", "lock-symbolic", "lock"]
        case "suspend":
        case "sleep":
            return ["system-suspend-symbolic", "system-suspend", "system-suspend-hibernate", "sleep"]
        case "hibernate":
            return ["system-suspend-hibernate-symbolic", "system-suspend-hibernate", "system-hibernate"]
        case "reboot":
        case "restart":
            return ["system-reboot-symbolic", "system-reboot", "system-restart-symbolic", "system-restart"]
        case "powerOff":
        case "shutdown":
            return ["system-shutdown-symbolic", "system-shutdown", "system-log-out-symbolic", "system-log-out"]
        case "switchUser":
            return ["system-switch-user-symbolic", "system-switch-user", "user-switch-symbolic", "user-switch", "user-identity", "system-users"]
        case "logout":
            return ["system-log-out-symbolic", "system-log-out", "application-exit"]
        default:
            // A caller may pass a standard icon name as its role while a new
            // semantic role is being introduced. It still goes through the
            // system resolver and never becomes a filesystem dependency.
            return key ? [key] : []
        }
    }

    function networkCandidates(connectionType, deviceState, signalStrength, limited) {
        const medium = String(connectionType || "")
        const state = String(deviceState || "")
        if (medium === "ethernet") {
            if (state === "connecting")
                return ["network-wired-acquiring-symbolic", "network-wired-acquiring"]
            if (state !== "connected")
                return ["network-wired-offline-symbolic", "network-wired-unavailable"]
            if (limited)
                return ["network-wired-no-route-symbolic", "network-wired-activated-limited"]
            return ["network-wired-symbolic", "network-wired-activated", "network-wired"]
        }
        if (medium !== "wifi")
            return ["network-error-symbolic", "network-unavailable"]
        if (state === "connecting")
            return ["network-wireless-acquiring-symbolic", "network-wireless-acquiring"]
        if (state !== "connected")
            return ["network-wireless-offline-symbolic", "network-wireless-disconnected"]

        const strength = Math.max(0, Math.min(100, Number(signalStrength) || 0))
        const level = strength < 20 ? 0 : strength < 40 ? 20
            : strength < 60 ? 40 : strength < 80 ? 60
            : strength < 95 ? 80 : 100
        if (limited)
            return ["network-wireless-no-route-symbolic",
                "network-wireless-" + level + "-limited",
                "network-wireless-symbolic"]
        return ["network-wireless-" + level,
            "network-wireless-symbolic", "network-wireless"]
    }

    function nameFromCandidates(candidateNames, fallbackName) {
        const values = typeof candidateNames === "string"
            ? [candidateNames] : (candidateNames || [])
        for (let index = 0; index < values.length; ++index) {
            const name = String(values[index] || "").trim()
            if (name && Quickshell.hasThemeIcon(name))
                return name
        }
        const fallback = String(fallbackName || "image-missing").trim()
        return fallback && Quickshell.hasThemeIcon(fallback) ? fallback : ""
    }

    function sourceFromCandidates(candidateNames, fallbackName) {
        const name = nameFromCandidates(candidateNames, fallbackName)
        return name ? (Quickshell.iconPath(name, true) || "") : ""
    }

    function name(role, state) {
        return nameFromCandidates(candidates(role, state), "image-missing")
    }

    function source(role, state) {
        return sourceFromCandidates(candidates(role, state), "image-missing")
    }
}
