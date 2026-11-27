import QtQml

QtObject {
    function getSnapshot(size) {
        return {
            status: "ready",
            time24h: "09:41",
            time12h: "9:41 AM",
            isoDate: "2026-11-26",
            hours: 9,
            minutes: 41,
            seconds: 24,
            weekday: 4,
            utcOffsetMinutes: 480
        }
    }
}
