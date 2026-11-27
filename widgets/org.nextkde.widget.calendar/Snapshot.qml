import QtQml

QtObject {
    function getSnapshot(size) {
        return {
            status: "ready",
            available: true,
            ready: true,
            cached: false,
            today: "2026-11-26",
            errorMessage: "",
            todayEvents: [
                { id: "evt-1", title: "Product Review", time: "10:00", allDay: false },
                { id: "evt-2", title: "Design Sync", time: "14:30", allDay: false },
                { id: "evt-3", title: "Sprint Planning", time: "16:30", allDay: false }
            ],
            pendingTodos: []
        }
    }
}
