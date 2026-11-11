// Shell feature-to-icon catalog. Edit this file to change a feature's icon.
// Values are names from shared/Icons/IconMap.js, compatibility aliases, or
// BundledIcons artwork keys. An empty value intentionally leaves a blank slot.
// Keep layout sizes in the caller; application artwork and user files stay external.

export const appArtwork = Object.freeze({
    "kos-calendar": "application.calendar",
    "kos-music": "application.music",
    "kos-weather": "application.weather",
});

// Paths are relative to BundledIcons.qml, next to this catalog.
export const artworkSources = Object.freeze({
    "app-launcher": "../../assets/applauncher.svg",
});

export const icons = Object.freeze({

    // action
    "action.activateWindow": "window-restore",
    "action.appearance": "theme-appearance",
    "action.back": "back",
    "action.check": "check",
    "action.close": "window-close",
    "action.controlCenter": "control-center",
    "action.copy": "edit-copy",
    "action.countdown": "countdown",
    "action.cpu": "cpu",
    "action.cut": "edit-cut",
    "action.edit": "document-new",
    "action.folder": "folder",
    "action.hibernate": "system-suspend",
    "action.iconSize": "arrange",
    "action.lock": "lock",
    "action.logout": "system-log-out",
    "action.minimize": "window-minimize",
    "action.newFile": "document-new",
    "action.newFolder": "folder-new",
    "action.open": "folder-open",
    "action.openWith": "open-with",
    "action.paste": "edit-paste",
    "action.pin": "pin",
    "action.powerOff": "power",
    "action.radio": "placeholder-dot",
    "action.radio.checked": "check",
    "action.reboot": "system-reboot",
    "action.refresh": "view-refresh",
    "action.remove": "edit-clear",
    "action.rename": "edit-rename",
    "action.reset": "reset-layout",
    "action.restart": "system-reboot",
    "action.screenshot": "screenshot",
    "action.settings": "preferences-system",
    "action.shutdown": "power",
    "action.sleep": "system-suspend",
    "action.sort": "sort-name",
    "action.submenu": "submenu",
    "action.suspend": "system-suspend",
    "action.switchUser": "system-switch-user",
    "action.temperature": "cpu-temperature",
    "action.unpin": "unpin",
    "action.visibility": "customize-appearance",

    // application artwork and generic fallback
    "application.calendar": "kos-calendar",
    "application.music": "kos-music",
    "application.weather": "kos-weather",
    "application.fallback": "application-x-executable",

    // audio
    "audio.application.audible": "speaker_2",
    "audio.application.muted": "speaker_slash",
    "audio.details": "chevron_right",
    "audio.deviceSelected": "checkmark",
    "audio.output.high": "speaker_3_fill",
    "audio.output.low": "speaker_1_fill",
    "audio.output.muted": "speaker_slash_fill",
    "audio.output.normal": "speaker_2_fill",
    "audio.output.silent": "speaker_fill",
    "audio.settings": "chevron_right",

    // bar
    "bar.collection.collapse": "chevron_right_2",
    "bar.collection.expand": "chevron_left_2",
    "bar.controlCenter": "control-center",
    "bar.menuOverflow": "chevron_right_2",
    "bar.notifications": "bell",
    "bar.settings": "status-settings",
    "bar.systemMenu": "nextkde",

    // battery
    "battery.charging": "bolt_fill",
    "battery.fill": "battery_fill",
    "battery.outline": "battery_0",

    // bluetooth
    "bluetooth.connected": "checkmark",
    "bluetooth.control": "bluetooth",
    "bluetooth.details": "chevron_right",
    "bluetooth.device": "bluetooth",
    "bluetooth.settings": "chevron_right",

    // brightness
    "brightness.details": "chevron_right",
    "brightness.level": "sun_max",
    "brightness.settings": "chevron_right",

    // clipboard
    "clipboard.image": "image-x-generic",
    "clipboard.text": "edit-paste",

    // controlCenter
    "controlCenter.appearance": "theme-appearance",
    "controlCenter.back": "chevron_left",
    "controlCenter.doNotDisturb": "moon_fill",
    "controlCenter.keepAwake": "keep-awake",
    "controlCenter.nightLight": "sun_haze_fill",
    "controlCenter.screenshot": "screenshot",
    "controlCenter.session": "power",
    "controlCenter.stageMode": "window",

    // desktop
    "desktop.file.code": "text-x-script",
    "desktop.file.folder": "folder",
    "desktop.file.image": "image-x-generic",
    "desktop.file.launcher": "application-x-executable",
    "desktop.file.pdf": "application-pdf",
    "desktop.file.text": "text-x-generic",
    "desktop.menu.addWidgets": "",
    "desktop.menu.appearance": "",
    "desktop.menu.arrange": "",
    "desktop.menu.arrangeByName": "",
    "desktop.menu.arrangeByType": "",
    "desktop.menu.arrangeModifiedNew": "",
    "desktop.menu.arrangeModifiedOld": "",
    "desktop.menu.color": "",
    "desktop.menu.copy": "edit-copy",
    "desktop.menu.cut": "edit-cut",
    "desktop.menu.editWidgets": "",
    "desktop.menu.emoji.frequent": "",
    "desktop.menu.emoji.life": "",
    "desktop.menu.emoji.study": "",
    "desktop.menu.emoji.symbols": "",
    "desktop.menu.iconSize": "",
    "desktop.menu.iconSpacing": "",
    "desktop.menu.lock": "",
    "desktop.menu.logout": "",
    "desktop.menu.newFile": "document-new",
    "desktop.menu.newFolder": "folder-new",
    "desktop.menu.open": "",
    "desktop.menu.openEntry": "",
    "desktop.menu.openWith": "",
    "desktop.menu.openWithMore": "",
    "desktop.menu.paste": "edit-paste",
    "desktop.menu.poweroff": "",
    "desktop.menu.reboot": "",
    "desktop.menu.removeCustom": "",
    "desktop.menu.rename": "",
    "desktop.menu.resetLayout": "",
    "desktop.menu.session": "",
    "desktop.menu.setColor": "",
    "desktop.menu.setEmoji": "",
    "desktop.menu.setIconSize": "",
    "desktop.menu.setIconSpacing": "",
    "desktop.menu.suspend": "",
    "desktop.menu.switch": "",
    "desktop.menu.toggleExtensions": "",
    "desktop.menu.trash": "user-trash",
    "desktop.timer": "countdown",
    "desktop.timer.close": "xmark",
    "desktop.timer.notification": "bell",
    "desktop.widget.activity": "chart_bar",
    "desktop.widget.add": "plus",
    "desktop.widget.calendar": "calendar",
    "desktop.widget.clock": "clock",
    "desktop.widget.music": "music_note_2",
    "desktop.widget.remove": "minus",
    "desktop.widget.resize": "arrow_up_left_arrow_down_right",
    "desktop.widget.system": "cpu",
    "desktop.widget.todo": "checkmark",
    "desktop.widget.weather": "sun_max",

    // dialog
    "dialog.help": "help",
    "dialog.trash": "user-trash",

    // dock
    "dock.launcher": "app-launcher",
    "dock.menu.activate": "",
    "dock.menu.close": "window-close",
    "dock.menu.close_all": "window-close",
    "dock.menu.launcher.bottom": "",
    "dock.menu.launcher.bottomWide": "",
    "dock.menu.launcher.center": "",
    "dock.menu.launcher.fullscreen": "",
    "dock.menu.launcher.settings": "preferences-system",
    "dock.menu.minimize": "",
    "dock.menu.new_window": "window-new",
    "dock.menu.open": "",
    "dock.menu.pin": "",
    "dock.menu.trash.empty": "user-trash",
    "dock.menu.trash.open": "",
    "dock.menu.unpin": "",
    "dock.preview.closeWindow": "xmark",
    "dock.preview.newWindow": "plus",
    "dock.widget.add": "plus",
    "dock.widget.clock": "clock",
    "dock.widget.metrics": "cpu",
    "dock.widget.music": "music_note_2",
    "dock.widget.remove": "minus",
    "dock.widget.weather": "sun_max",

    // feedback
    "feedback.success": "check",

    // launcher
    "launcher.back": "chevron_left",
    "launcher.clearSearch": "xmark",
    "launcher.closeEditor": "xmark",
    "launcher.folder.removeApp": "minus",
    "launcher.search": "search",

    // media
    "media.fallback": "music_note_2",
    "media.coverFallback": "default-cover",
    "media.lyrics": "media-lyrics",
    "media.next": "media-next",
    "media.pause": "media-pause",
    "media.play": "media-play",
    "media.previous": "media-previous",

    // menu
    "menu.back": "back",
    "menu.trailing.checked": "check",
    "menu.trailing.submenu": "submenu",

    // network
    "network.connected": "checkmark",
    "network.dialog.busy": "ellipsis",
    "network.dialog.cancel": "xmark",
    "network.dialog.connect": "checkmark",
    "network.dialog.wifi": "wifi",
    "network.ethernet": "status-ethernet",
    "network.secured": "lock_fill",
    "network.settings": "chevron_right",
    "network.wifi.details": "chevron_right",
    "network.wifi.disabled": "wifi_slash",
    "network.wifi.full": "wifi",
    "network.wifi.medium": "wifi_2",
    "network.wifi.strong": "wifi",
    "network.wifi.weak": "wifi_1",

    // notification
    "notification.clearAll": "xmark",
    "notification.details.collapse": "chevron_up",
    "notification.details.expand": "chevron_down",
    "notification.dismiss": "xmark",
    "notification.history.collapse": "chevron_up",
    "notification.history.expand": "chevron_down",
    "notification.remove": "xmark",
    "notification.sourceFallback": "bell",

    // overview
    "overview.closeWindow": "xmark",
    "overview.windowFallback": "window",

    // search
    "search.clearQuery": "xmark",
    "search.clipboard.remove": "xmark",
    "search.pin.pinned": "star_fill",
    "search.pin.unpinned": "star",
    "search.query": "search",
    "search.settings": "gear_alt",
    "search.showAll": "chevron_right",
    "search.view.grid": "square_grid_2x2",
    "search.view.list": "list_bullet",

    // session
    "session.lock": "lock",
    "session.suspend": "system-suspend",
    "session.switch": "system-switch-user",
    "session.logout": "system-log-out",
    "session.reboot": "system-reboot",
    "session.poweroff": "power",
    "session.back": "chevron_left",
    "session.warning": "exclamationmark_triangle",

    // system
    "system.clock": "time",
    "system.cpu": "cpu",
    "system.cpuTemperature": "cpu-temperature",
    "system.disk": "drive-harddisk",
    "system.memory": "memory",
    "system.temperature": "temperature",

    // temperature
    "temperature.close": "xmark",

    // traffic
    "traffic.action.close": "xmark",
    "traffic.action.down": "chevron_down",
    "traffic.action.reset": "arrow_counterclockwise",
    "traffic.action.up": "chevron_up",
    "traffic.monitor": "antenna_radiowaves_left_right",

    // wallpaper
    "wallpaper.apply": "check",
    "wallpaper.exit": "window-close",
    "wallpaper.folderDetails": "submenu",
    "wallpaper.mode.color": "color-picker",
    "wallpaper.mode.image": "image-x-generic",
    "wallpaper.mode.slideshow": "media-play",
    "wallpaper.mode.theme": "theme-appearance",
    "wallpaper.pause": "media-pause",
    "wallpaper.play": "media-play",
    "wallpaper.selectAll": "select-all",
    "wallpaper.selection": "check",
    "wallpaper.settings": "status-settings",
    "wallpaper.spatial": "spatial-wallpaper",
    "wallpaper.transition": "media-shuffle",

    // weather
    "weather.cloud": "weather-cloud",
    "weather.cloudWide": "weather-cloud-wide",
    "weather.lightning": "bolt_fill",
});

// Compatibility for callers of BundledIcons.roleName(role, state).
const legacyRoles = {
    "cpu|": "action.cpu",
    "temperature|": "action.temperature",
    "settings|": "action.settings",
    "controlCenter|": "action.controlCenter",
    "open|": "action.open",
    "edit|": "action.edit",
    "pin|": "action.pin",
    "unpin|": "action.unpin",
    "activateWindow|": "action.activateWindow",
    "minimize|": "action.minimize",
    "close|": "action.close",
    "copy|": "action.copy",
    "cut|": "action.cut",
    "paste|": "action.paste",
    "folder|": "action.folder",
    "newFile|": "action.newFile",
    "newFolder|": "action.newFolder",
    "refresh|": "action.refresh",
    "rename|": "action.rename",
    "openWith|": "action.openWith",
    "sort|": "action.sort",
    "iconSize|": "action.iconSize",
    "appearance|": "action.appearance",
    "visibility|": "action.visibility",
    "reset|": "action.reset",
    "back|": "action.back",
    "submenu|": "action.submenu",
    "check|": "action.check",
    "remove|": "action.remove",
    "lock|": "action.lock",
    "suspend|": "action.suspend",
    "sleep|": "action.sleep",
    "hibernate|": "action.hibernate",
    "reboot|": "action.reboot",
    "restart|": "action.restart",
    "powerOff|": "action.powerOff",
    "shutdown|": "action.shutdown",
    "switchUser|": "action.switchUser",
    "logout|": "action.logout",
    "screenshot|": "action.screenshot",
    "nightLight|": "controlCenter.nightLight",
    "doNotDisturb|": "controlCenter.doNotDisturb",
    "countdown|": "action.countdown",
    "radio|checked": "action.radio.checked",
    "radio|": "action.radio"
};

export function resolve(name) {
    const key = String(name || "");
    return Object.prototype.hasOwnProperty.call(icons, key) ? icons[key] : key;
}

export function roleName(role, state) {
    const key = String(role || "") + "|" + String(state || "");
    return resolve(legacyRoles[key] || role);
}

// Theme-only artwork follows the user's system theme, outside the icon font.
export function themeCandidates(role, state) {
        const key = String(role || "")
        const variant = String(state || "")
        switch (key) {
        case "desktop.file.folder": return ["folder"]
        case "desktop.file.image": return ["image-x-generic"]
        case "desktop.file.pdf": return ["application-pdf"]
        case "desktop.file.code": return ["text-x-script"]
        case "desktop.file.text": return ["text-x-generic"]
        case "desktop.file.launcher": return ["application-x-executable"]
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
            return variant === "full"
                ? ["user-trash-full", "user-trash-full-symbolic",
                    "user-trash", "user-trash-symbolic"]
                : ["user-trash", "user-trash-symbolic"]
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

export function networkCandidates(connectionType, deviceState, signalStrength, limited) {
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

