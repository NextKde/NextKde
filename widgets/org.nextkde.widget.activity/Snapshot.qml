import QtQml

QtObject {
    function getSnapshot(size) {
        const days = []
        const pattern = [
            0, 7200, 14400, 18900, 23400, 9600, 3600,
            19800, 25200, 21600, 16200, 27000, 10800, 5400,
            22500, 24300, 18000, 12600, 26100, 7200, 0,
            20700, 27900, 23400, 15300, 19800, 9000, 5400,
            24000, 21600, 17100, 25200, 22500, 10800, 3600,
            18900, 27000, 24300, 14400, 21600, 11700, 7200,
            25200, 20700, 19800, 26100, 23400, 9600, 5400,
            18000, 24300, 27000, 21600, 16200, 10800, 6300,
            23400, 25200, 18900, 20520
        ]
        const baseMs = Date.UTC(2026, 10, 26)
        for (let i = 0; i < 60; ++i) {
            const d = new Date(baseMs - (59 - i) * 86400000)
            const y = d.getUTCFullYear()
            const m = d.getUTCMonth() + 1
            const day = d.getUTCDate()
            const key = y + "-" + (m < 10 ? "0" : "") + m + "-" + (day < 10 ? "0" : "") + day
            days.push({ key: key, seconds: pattern[i] })
        }
        return {
            status: "ready",
            todayKey: "2026-11-26",
            todayUptimeSeconds: 20520,
            recentUptimeDays: days,
            todayApps: [
                { id: "code", name: "VS Code", icon: "", seconds: 8420 },
                { id: "firefox", name: "Firefox", icon: "", seconds: 5280 },
                { id: "konsole", name: "Konsole", icon: "", seconds: 3180 },
                { id: "dolphin", name: "Dolphin", icon: "", seconds: 1620 },
                { id: "obsidian", name: "Obsidian", icon: "", seconds: 1260 },
                { id: "spotify", name: "Music", icon: "", seconds: 760 },
                { id: "kate", name: "Kate", icon: "", seconds: 480 },
                { id: "systemsettings", name: "Settings", icon: "", seconds: 300 }
            ]
        }
    }
}
