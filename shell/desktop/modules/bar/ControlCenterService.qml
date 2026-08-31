pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Shared adapter for the first real Control Centre controls. Presentation
// components read this state only; system writes remain explicit methods here.
QtObject {
    id: service

    property bool audioAvailable: false
    property int volumePercent: 0
    property bool audioMuted: false
    property bool volumeChangeInProgress: false
    // Display brightness through the sysfs backlight class; writes go through
    // logind's SetBrightness so the session owner never needs /sys write
    // access. `brightnessAvailable` stays false when no backlight exists.
    property bool brightnessAvailable: false
    property int brightnessPercent: 0
    property bool brightnessChangeInProgress: false
    property string brightnessBacklightName: ""
    property bool bluetoothAvailable: false
    property bool bluetoothPowered: false
    property bool bluetoothChangeInProgress: false
    // Known devices are supplied as normalized { address, name, paired,
    // connected } objects so every future Bluetooth surface shares one parser.
    property var bluetoothDevices: []
    property bool bluetoothDevicesRefreshInProgress: false
    property bool bluetoothDeviceChangeInProgress: false
    property string bluetoothChangingAddress: ""
    // This is consumed by NotificationCenter. Keep the policy state in the
    // control service so future notification surfaces have one shared source.
    property bool doNotDisturbEnabled: false
    // Notification history: snapshots of dismissed/expired notifications,
    // populated by NotificationGroupService. Lives here (not in
    // NotificationGroupService) so the ControlCenter panel -- which already
    // binds this singleton -- can read it without a cross-module reference.
    property ListModel notificationHistory: ListModel {}
    property int notificationHistoryMax: 50
    // The history grouped by app for the session-history view. A JS array (not
    // a ListModel) because each group carries an `items` array; the panel
    // binds ListView to this and renders each group's rows with a nested
    // Repeater. Rebuilt on every history mutation via _historyConnections.
    property var historyGroups: []
    property int historyRevision: 0

    function rebuildHistoryGroups() {
        const groups = []
        const groupIndex = ({})
        const history = notificationHistory
        for (let i = 0; i < history.count; i++) {
            const row = history.get(i)
            const key = row.appName || "其他"
            let group = groupIndex[key]
            if (group === undefined) {
                group = groups.length
                groupIndex[key] = group
                groups.push({ appName: key, appIcon: row.appIcon, items: [] })
            }
            groups[group].items.push({
                notifId: row.notifId,
                summary: row.summary,
                body: row.body,
                timestamp: row.timestamp
            })
        }
        historyGroups = groups
        historyRevision++
    }

    // Remove a single history entry (used by each grouped row's close button).
    function removeHistoryById(notifId) {
        const history = notificationHistory
        for (let i = 0; i < history.count; i++) {
            if (history.get(i).notifId === notifId) {
                history.remove(i)
                return
            }
        }
    }

    property Connections _historyConnections: Connections {
        target: service.notificationHistory
        function onRowsInserted() { service.rebuildHistoryGroups() }
        function onRowsRemoved() { service.rebuildHistoryGroups() }
        function onRowsMoved() { service.rebuildHistoryGroups() }
        function onModelReset() { service.rebuildHistoryGroups() }
    }
    property bool screenshotInProgress: false
    property bool sessionActionInProgress: false
    property alias logoutInProgress: service.sessionActionInProgress
    property string lastSessionError: ""
    property string currentUserName: Quickshell.env("USER") || "用户"
    property bool canSuspend: true
    property bool canHibernate: false
    // The control center panel is owned by BarWindow, so a global shortcut
    // cannot toggle it directly. BarWindow listens for this request; the
    // service stays the intent channel (same pattern as AppActionService).
    signal toggleRequested()
    property var _refreshProcess: null

    function refresh() {
        if (_refreshProcess)
            return
        const proc = processFactory.createObject(service, {
            command: ["sh", "-c",
                "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null; "
                    + "printf '\\036'; bluetoothctl show 2>/dev/null; "
                    + "printf '\\036'; "
                    + "kde_cur=$(qdbus6 org.kde.Solid.PowerManagement /org/kde/Solid/PowerManagement/Actions/BrightnessControl org.kde.Solid.PowerManagement.Actions.BrightnessControl.brightness 2>/dev/null); "
                    + "kde_max=$(qdbus6 org.kde.Solid.PowerManagement /org/kde/Solid/PowerManagement/Actions/BrightnessControl org.kde.Solid.PowerManagement.Actions.BrightnessControl.brightnessMax 2>/dev/null); "
                    + "if [ -n \"$kde_max\" ] && [ \"$kde_max\" -gt 0 ] 2>/dev/null; then "
                    + "  printf 'kde|%s|%s' \"$kde_cur\" \"$kde_max\"; "
                    + "else "
                    + "  for d in /sys/class/backlight/*; do [ -r \"$d/max_brightness\" ] || continue; "
                    + "    name=${d##*/}; current=$(cat \"$d/brightness\" 2>/dev/null); max=$(cat \"$d/max_brightness\" 2>/dev/null); "
                    + "    case \"$max\" in ''|*[!0-9]*|[0]*) ;; *) printf '%s|%s|%s' \"$name\" \"$current\" \"$max\"; break;; esac; done; "
                    + "fi",
                "control-center-refresh"]
        })
        _refreshProcess = proc
        proc.exited.connect(function(code) {
            if (service._refreshProcess === proc)
                service._refreshProcess = null
            const parts = (proc.stdout?.text ?? "").split("\u001e")
            const volumeMatch = (parts[0] || "").match(/Volume:\s*([0-9.]+)/)
            service.audioAvailable = volumeMatch !== null
            if (volumeMatch)
                service.volumePercent = Math.round(Math.max(0,
                    Math.min(100, Number(volumeMatch[1]) * 100)))
            service.audioMuted = (parts[0] || "").indexOf("[MUTED]") >= 0
            const poweredMatch = (parts[1] || "").match(/Powered:\s*(yes|no)/i)
            service.bluetoothAvailable = poweredMatch !== null
            if (poweredMatch)
                service.bluetoothPowered = poweredMatch[1].toLowerCase() === "yes"
            const backlight = (parts[2] || "").trim()
            if (backlight) {
                const fields = backlight.split("|")
                const current = Number(fields[1])
                const maximum = Number(fields[2])
                service.brightnessAvailable = fields.length === 3
                    && Number.isFinite(current) && Number.isFinite(maximum) && maximum > 0
                if (service.brightnessAvailable) {
                    service.brightnessBacklightName = fields[0]
                    service.brightnessPercent = Math.round(
                        Math.max(0, Math.min(100, current / maximum * 100)))
                }
            } else {
                service.brightnessAvailable = false
                service.brightnessBacklightName = ""
                service.brightnessPercent = 0
            }
            proc.destroy()
        })
        proc.running = true
    }

    // Brightness changes prioritize KDE's PowerDevil/ScreenBrightness D-Bus
    // interfaces (supporting internal screens and external DDC/CI monitors),
    // and fall back to logind SetBrightness for sysfs backlights.
    function setBrightness(percent) {
        const value = Math.round(Math.max(0, Math.min(100, Number(percent) || 0)))
        if (!brightnessAvailable || brightnessChangeInProgress)
            return false
        brightnessChangeInProgress = true
        const proc = processFactory.createObject(service, {
            command: ["sh", "-c",
                "target=$1; name=$2; "
                    + "kde_max=$(qdbus6 org.kde.Solid.PowerManagement /org/kde/Solid/PowerManagement/Actions/BrightnessControl org.kde.Solid.PowerManagement.Actions.BrightnessControl.brightnessMax 2>/dev/null); "
                    + "if [ -n \"$kde_max\" ] && [ \"$kde_max\" -gt 0 ] 2>/dev/null; then "
                    + "  val=$(( (target * kde_max + 50) / 100 )); "
                    + "  qdbus6 org.kde.Solid.PowerManagement /org/kde/Solid/PowerManagement/Actions/BrightnessControl org.kde.Solid.PowerManagement.Actions.BrightnessControl.setBrightness \"$val\" 2>/dev/null; "
                    + "  displays=$(qdbus6 org.kde.ScreenBrightness /org/kde/ScreenBrightness org.kde.ScreenBrightness.DisplaysDBusNames 2>/dev/null); "
                    + "  for d in $displays; do "
                    + "    p=\"/org/kde/ScreenBrightness/${d#/org/kde/ScreenBrightness/}\"; p=\"/org/kde/ScreenBrightness/${p#/}\"; "
                    + "    d_max=$(qdbus6 org.kde.ScreenBrightness \"$p\" org.kde.ScreenBrightness.Display.MaxBrightness 2>/dev/null); "
                    + "    if [ -n \"$d_max\" ] && [ \"$d_max\" -gt 0 ] 2>/dev/null; then "
                    + "      d_val=$(( (target * d_max + 50) / 100 )); "
                    + "      qdbus6 org.kde.ScreenBrightness \"$p\" org.kde.ScreenBrightness.Display.SetBrightness \"$d_val\" 0 2>/dev/null || true; "
                    + "    fi; "
                    + "  done; "
                    + "  exit 0; "
                    + "fi; "
                    + "if [ -n \"$name\" ] && [ \"$name\" != \"kde\" ]; then "
                    + "  max=$(cat \"/sys/class/backlight/$name/max_brightness\" 2>/dev/null); "
                    + "  case \"$max\" in ''|*[!0-9]*|[0]*) exit 1;; esac; "
                    + "  val=$(( (target * max + 50) / 100 )); "
                    + "  qdbus6 --system org.freedesktop.login1 /org/freedesktop/login1/session/auto org.freedesktop.login1.Session.SetBrightness backlight \"$name\" \"$val\"; "
                    + "fi",
                "control-center-brightness", String(value), brightnessBacklightName]
        })
        proc.exited.connect(function(writeCode) {
            service.brightnessChangeInProgress = false
            if (writeCode === 0)
                service.brightnessPercent = value
            service.refresh()
            proc.destroy()
        })
        proc.running = true
        return true
    }

    function setVolume(percent) {
        const value = Math.round(Math.max(0, Math.min(100, Number(percent) || 0)))
        if (!audioAvailable || volumeChangeInProgress)
            return false
        volumeChangeInProgress = true
        const proc = processFactory.createObject(service, {
            command: ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", String(value / 100)]
        })
        proc.exited.connect(function(code) {
            service.volumeChangeInProgress = false
            if (code === 0)
                service.volumePercent = value
            service.refresh()
            proc.destroy()
        })
        proc.running = true
        return true
    }

    // Mute is intentionally a separate operation from setting volume to 0.
    // That preserves the user's chosen volume and mirrors normal desktop
    // control-centre behaviour when the button is tapped a second time.
    function setMuted(muted) {
        const desired = Boolean(muted)
        if (!audioAvailable || volumeChangeInProgress || desired === audioMuted)
            return false
        volumeChangeInProgress = true
        const proc = processFactory.createObject(service, {
            command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", desired ? "1" : "0"]
        })
        proc.exited.connect(function(code) {
            service.volumeChangeInProgress = false
            if (code === 0)
                service.audioMuted = desired
            service.refresh()
            proc.destroy()
        })
        proc.running = true
        return true
    }

    function setBluetoothEnabled(enabled) {
        const desired = Boolean(enabled)
        if (!bluetoothAvailable || bluetoothChangeInProgress || desired === bluetoothPowered)
            return false
        bluetoothChangeInProgress = true
        const proc = processFactory.createObject(service, {
            command: ["bluetoothctl", "power", desired ? "on" : "off"]
        })
        proc.exited.connect(function(code) {
            service.bluetoothChangeInProgress = false
            if (code === 0)
                service.bluetoothPowered = desired
            service.refresh()
            service.refreshBluetoothDevices()
            proc.destroy()
        })
        proc.running = true
        return true
    }

    function _parseBluetoothDevices(allOutput, connectedOutput, pairedOutput) {
        function parseBlock(output) {
            const devices = []
            const lines = String(output || "").split("\n")
            for (let i = 0; i < lines.length; i++) {
                const match = lines[i].match(/^Device\s+([0-9A-F:]{17})\s+(.+)$/i)
                if (match)
                    devices.push({ address: match[1].toUpperCase(), name: match[2].trim() })
            }
            return devices
        }
        const connected = parseBlock(connectedOutput)
        const paired = parseBlock(pairedOutput)
        const connectedAddresses = connected.map(device => device.address)
        const pairedAddresses = paired.map(device => device.address)
        const source = parseBlock(allOutput).concat(paired)
        const seen = {}
        const normalized = []
        for (let i = 0; i < source.length; i++) {
            const device = source[i]
            if (seen[device.address])
                continue
            seen[device.address] = true
            normalized.push({
                address: device.address,
                name: device.name || device.address,
                paired: pairedAddresses.indexOf(device.address) >= 0,
                connected: connectedAddresses.indexOf(device.address) >= 0
            })
        }
        normalized.sort((left, right) => Number(right.connected) - Number(left.connected)
            || Number(right.paired) - Number(left.paired) || left.name.localeCompare(right.name))
        return normalized
    }

    function refreshBluetoothDevices() {
        if (bluetoothDevicesRefreshInProgress || !bluetoothPowered)
            return
        bluetoothDevicesRefreshInProgress = true
        const proc = processFactory.createObject(service, {
            command: ["sh", "-c", "bluetoothctl devices; printf '\\036'; bluetoothctl devices Connected; printf '\\036'; bluetoothctl devices Paired"]
        })
        proc.exited.connect(function() {
            const parts = (proc.stdout?.text ?? "").split("\u001e")
            service.bluetoothDevices = service._parseBluetoothDevices(parts[0], parts[1], parts[2])
            service.bluetoothDevicesRefreshInProgress = false
            proc.destroy()
        })
        proc.running = true
    }

    function setBluetoothDeviceConnected(device, connected) {
        if (!device || !device.address || bluetoothDeviceChangeInProgress)
            return false
        bluetoothDeviceChangeInProgress = true
        bluetoothChangingAddress = device.address
        const proc = processFactory.createObject(service, {
            command: ["bluetoothctl", connected ? "connect" : "disconnect", device.address]
        })
        proc.exited.connect(function() {
            service.bluetoothDeviceChangeInProgress = false
            service.bluetoothChangingAddress = ""
            service.refreshBluetoothDevices()
            proc.destroy()
        })
        proc.running = true
        return true
    }

    // Launches an interactive region screenshot tool. Probes for feature-rich
    // third-party screenshot utilities (mark-shot, flameshot, ksnip) first and
    // gracefully falls back to KDE's built-in Spectacle for general users.
    function captureInteractiveScreenshot() {
        if (screenshotInProgress)
            return false
        screenshotInProgress = true
        const proc = processFactory.createObject(service, {
            command: ["sh", "-c",
                "if command -v mark-shot >/dev/null 2>&1; then "
                + "exec mark-shot --capture; "
                + "elif command -v markshot >/dev/null 2>&1; then "
                + "exec markshot --capture; "
                + "elif command -v flameshot >/dev/null 2>&1; then "
                + "exec flameshot gui; "
                + "elif command -v ksnip >/dev/null 2>&1; then "
                + "exec ksnip -r; "
                + "elif command -v spectacle >/dev/null 2>&1; then "
                + "exec spectacle -r; "
                + "elif command -v grimblast >/dev/null 2>&1; then "
                + "exec grimblast copy area; "
                + "fi"
            ]
        })
        proc.exited.connect(function() {
            service.screenshotInProgress = false
            proc.destroy()
        })
        proc.running = true
        return true
    }

    function lockSession() {
        if (sessionActionInProgress)
            return false
        sessionActionInProgress = true
        lastSessionError = ""
        const proc = processFactory.createObject(service, {
            command: ["sh", "-c", "loginctl lock-session 2>/dev/null || qdbus6 org.freedesktop.ScreenSaver /ScreenSaver org.freedesktop.ScreenSaver.Lock 2>/dev/null"]
        })
        proc.exited.connect(function(code) {
            service.sessionActionInProgress = false
            if (code !== 0) {
                service.lastSessionError = "锁屏失败"
            }
            proc.destroy()
        })
        proc.running = true
        return true
    }

    function suspendSystem() {
        if (sessionActionInProgress)
            return false
        sessionActionInProgress = true
        lastSessionError = ""
        const proc = processFactory.createObject(service, {
            command: ["sh", "-c", "systemctl suspend 2>/dev/null || loginctl suspend 2>/dev/null || qdbus6 org.freedesktop.PowerManagement /org/freedesktop/PowerManagement org.freedesktop.PowerManagement.Suspend 2>/dev/null"]
        })
        proc.exited.connect(function(code) {
            service.sessionActionInProgress = false
            if (code !== 0) {
                service.lastSessionError = "睡眠操作失败"
            }
            proc.destroy()
        })
        proc.running = true
        return true
    }

    function hibernateSystem() {
        if (sessionActionInProgress)
            return false
        sessionActionInProgress = true
        lastSessionError = ""
        const proc = processFactory.createObject(service, {
            command: ["sh", "-c", "systemctl hibernate 2>/dev/null || loginctl hibernate 2>/dev/null || qdbus6 org.freedesktop.PowerManagement /org/freedesktop/PowerManagement org.freedesktop.PowerManagement.Hibernate 2>/dev/null"]
        })
        proc.exited.connect(function(code) {
            service.sessionActionInProgress = false
            if (code !== 0) {
                service.lastSessionError = "休眠操作失败"
            }
            proc.destroy()
        })
        proc.running = true
        return true
    }

    function rebootSystem() {
        if (sessionActionInProgress)
            return false
        sessionActionInProgress = true
        lastSessionError = ""
        const proc = processFactory.createObject(service, {
            command: ["sh", "-c", "qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logoutAndReboot 2>/dev/null || systemctl reboot 2>/dev/null || loginctl reboot 2>/dev/null"]
        })
        proc.exited.connect(function(code) {
            service.sessionActionInProgress = false
            if (code !== 0) {
                service.lastSessionError = "重启操作失败"
            }
            proc.destroy()
        })
        proc.running = true
        return true
    }

    function powerOffSystem() {
        if (sessionActionInProgress)
            return false
        sessionActionInProgress = true
        lastSessionError = ""
        const proc = processFactory.createObject(service, {
            command: ["sh", "-c", "qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logoutAndShutdown 2>/dev/null || systemctl poweroff 2>/dev/null || loginctl poweroff 2>/dev/null"]
        })
        proc.exited.connect(function(code) {
            service.sessionActionInProgress = false
            if (code !== 0) {
                service.lastSessionError = "关机操作失败"
            }
            proc.destroy()
        })
        proc.running = true
        return true
    }

    function switchUser() {
        if (sessionActionInProgress)
            return false
        sessionActionInProgress = true
        lastSessionError = ""
        const proc = processFactory.createObject(service, {
            command: ["sh", "-c", "dm-tool switch-to-greeter 2>/dev/null || ( [ -n \"$XDG_SEAT_PATH\" ] && qdbus6 --system org.freedesktop.DisplayManager \"$XDG_SEAT_PATH\" org.freedesktop.DisplayManager.Seat.SwitchToGreeter 2>/dev/null ) || qdbus6 --system org.freedesktop.DisplayManager /org/freedesktop/DisplayManager/Seat0 org.freedesktop.DisplayManager.Seat.SwitchToGreeter 2>/dev/null || loginctl lock-session \"${XDG_SESSION_ID:-self}\" 2>/dev/null || qdbus6 org.freedesktop.ScreenSaver /ScreenSaver Lock 2>/dev/null"]
        })
        proc.exited.connect(function(code) {
            service.sessionActionInProgress = false
            if (code !== 0) {
                service.lastSessionError = "切换用户失败"
            }
            proc.destroy()
        })
        proc.running = true
        return true
    }

    // Terminating the current session via KDE Shutdown D-Bus or logind
    function logoutCurrentSession() {
        if (sessionActionInProgress)
            return false
        sessionActionInProgress = true
        lastSessionError = ""
        const proc = processFactory.createObject(service, {
            command: ["sh", "-c", "qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logout 2>/dev/null || loginctl terminate-session \"$XDG_SESSION_ID\" 2>/dev/null"]
        })
        proc.exited.connect(function(code) {
            service.sessionActionInProgress = false
            if (code !== 0) {
                service.lastSessionError = "注销失败"
            }
            proc.destroy()
        })
        proc.running = true
        return true
    }

    property bool themeChangeInProgress: false

    function toggleDarkMode() {
        if (themeChangeInProgress)
            return false
        themeChangeInProgress = true
        const pyScript = "import subprocess\n"
            + "def get_cfg(f, g, k):\n"
            + "    res = subprocess.run(['kreadconfig6', '--file', f, '--group', g, '--key', k], capture_output=True, text=True)\n"
            + "    return res.stdout.strip()\n"
            + "curr_lnf = get_cfg('kdeglobals', 'KDE', 'LookAndFeelPackage')\n"
            + "curr_scheme = get_cfg('kdeglobals', 'General', 'ColorScheme')\n"
            + "lnfs_proc = subprocess.run(['plasma-apply-lookandfeel', '-l'], capture_output=True, text=True)\n"
            + "installed = [l.strip() for l in lnfs_proc.stdout.splitlines() if l.strip()]\n"
            + "is_dark = '-d' in curr_lnf.lower() or 'dark' in curr_lnf.lower() or 'dark' in curr_scheme.lower()\n"
            + "target_dark = not is_dark\n"
            + "def find_partner(theme, to_dark):\n"
            + "    if not theme: return None\n"
            + "    cands = []\n"
            + "    if to_dark:\n"
            + "        if theme.endswith('-w'): cands.append(theme[:-2] + '-d')\n"
            + "        if theme.endswith('_w'): cands.append(theme[:-2] + '_d')\n"
            + "        if theme.endswith('Light'): cands.append(theme[:-5] + 'Dark')\n"
            + "        if theme.endswith('-Light'): cands.append(theme[:-6] + '-Dark')\n"
            + "        if theme.endswith('_Light'): cands.append(theme[:-6] + '_Dark')\n"
            + "        if 'light' in theme.lower(): cands.append(theme.replace('light', 'dark').replace('Light', 'Dark'))\n"
            + "        if theme.endswith('.desktop'):\n"
            + "            base = theme[:-8]\n"
            + "            cands.extend([base + 'dark.desktop', base + '-dark.desktop', base + 'Dark.desktop'])\n"
            + "        cands.extend([theme + '-Dark', theme + 'Dark', theme + '-d'])\n"
            + "    else:\n"
            + "        if theme.endswith('-d'): cands.append(theme[:-2] + '-w')\n"
            + "        if theme.endswith('_d'): cands.append(theme[:-2] + '_w')\n"
            + "        if theme.endswith('Dark'): cands.extend([theme[:-4] + 'Light', theme[:-4]])\n"
            + "        if theme.endswith('-Dark'): cands.extend([theme[:-5] + '-Light', theme[:-5]])\n"
            + "        if theme.endswith('_Dark'): cands.extend([theme[:-5] + '_Light', theme[:-5]])\n"
            + "        if 'dark' in theme.lower(): cands.append(theme.replace('dark', 'light').replace('Dark', 'Light'))\n"
            + "        if theme.endswith('dark.desktop'): cands.extend([theme[:-12] + '.desktop', theme[:-12] + 'light.desktop'])\n"
            + "    for c in cands:\n"
            + "        for inst in installed:\n"
            + "            if c.lower() == inst.lower(): return inst\n"
            + "    return None\n"
            + "target_lnf = find_partner(curr_lnf, target_dark)\n"
            + "if not target_lnf:\n"
            + "    fallbacks = ['org.kde.breezedark.desktop', 'org.fedoraproject.fedoradark.desktop'] if target_dark else ['org.kde.breeze.desktop', 'org.fedoraproject.fedoralight.desktop', 'org.fedoraproject.fedora.desktop']\n"
            + "    for fb in fallbacks:\n"
            + "        if fb in installed: target_lnf = fb; break\n"
            + "if target_lnf:\n"
            + "    subprocess.run(['plasma-apply-lookandfeel', '-a', target_lnf])\n"
            + "if curr_scheme:\n"
            + "    target_scheme = ''\n"
            + "    if target_dark:\n"
            + "        if curr_scheme.endswith('Light'): target_scheme = curr_scheme[:-5] + 'Dark'\n"
            + "        elif 'Dark' not in curr_scheme: target_scheme = curr_scheme + 'Dark'\n"
            + "    else:\n"
            + "        if curr_scheme.endswith('Dark'): target_scheme = curr_scheme[:-4] + 'Light'\n"
            + "        elif 'Dark' in curr_scheme: target_scheme = curr_scheme.replace('Dark', 'Light')\n"
            + "    if target_scheme:\n"
            + "        subprocess.run(['plasma-apply-colorscheme', target_scheme])\n"
            + "subprocess.run(['qdbus6', 'org.kde.KWin', '/KWin', 'reconfigure'])\n"

        const proc = processFactory.createObject(service, {
            command: ["python3", "-c", pyScript]
        })
        proc.exited.connect(function() {
            service.themeChangeInProgress = false
            proc.destroy()
        })
        proc.running = true
        return true
    }

    function toggleDoNotDisturb() {
        doNotDisturbEnabled = !doNotDisturbEnabled
        return doNotDisturbEnabled
    }

    property Component processFactory: Component {
        Process {
            stdout: StdioCollector {}
            stderr: StdioCollector {}
        }
    }
    property Timer refreshTimer: Timer {
        interval: 3000; repeat: true; running: true
        onTriggered: service.refresh()
    }
    Component.onCompleted: refresh()
}
