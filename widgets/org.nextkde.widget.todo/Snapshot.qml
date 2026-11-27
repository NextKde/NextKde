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
            todayEvents: [],
            pendingTodos: [
                { id: "todo-1", title: "Send weekly design notes", due: "2026-11-25", completed: false },
                { id: "todo-2", title: "Review desktop widget PR", due: "2026-11-26", completed: false },
                { id: "todo-3", title: "Update release checklist", due: "2026-11-26", completed: false },
                { id: "todo-4", title: "Prepare Q4 roadmap slides", due: "2026-11-27", completed: false },
                { id: "todo-5", title: "Sync package icons", due: "2026-11-28", completed: false },
                { id: "todo-6", title: "Archive old sprint notes", due: "2026-11-30", completed: false }
            ]
        }
    }
}
