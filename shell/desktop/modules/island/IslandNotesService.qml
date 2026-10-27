pragma Singleton
import QtQuick
import qs.desktop.modules.platform
import "../../../shared/qml/i18n"

// IslandNotesService — notes are Markdown files, not state entries.
//
// One .md per note in IslandConfigService.notesFolder, plus an index of what
// exists so the island can draw titles without opening every file. Content is
// read and written through the platform contract (file.read-text /
// file.write-text): the daemon owns path validation and directory creation,
// and QML is not allowed to touch the filesystem itself.
//
// The file format is the one Apple's备忘录 uses: the first line is the title,
// the rest is the body. One source of truth, so a note opened elsewhere still
// shows its title.
QtObject {
    id: service

    readonly property string folder: IslandConfigService.notesFolder
    readonly property var notes: IslandConfigService.notesIndex || []

    property string activeId: ""
    property string activeTitle: ""
    property string activeText: ""
    property string lastError: ""
    property bool busy: false

    // Bumped only when a note is *loaded*.
    //
    // Saving writes the text back into activeText, and the panel used to
    // reload the editor whenever that happened: assigning `text` to a TextEdit
    // while the user is typing moves the caret to the start and drops the undo
    // stack, so every 400ms of typing was undone. The load and the echo now
    // have separate signals.
    property int loadRevision: 0

    // Newest first. The card shows three of these; the panel shows all.
    readonly property var sorted: {
        const list = (notes || []).slice()
        list.sort(function(a, b) { return (b.updated || 0) - (a.updated || 0) })
        return list
    }
    readonly property var recent: sorted.slice(0, 3)

    function pathFor(id) {
        return service.folder + "/" + id + ".md"
    }

    function titleFrom(text) {
        const lines = String(text === undefined ? "" : text).split("\n")
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].replace(/^#+\s*/, "").trim()
            if (line.length > 0)
                return line.slice(0, 40)
        }
        return ""
    }

    function _commitIndex(list) {
        IslandConfigService.setNotesIndex(list)
    }

    function _upsert(id, title) {
        const list = (service.notes || []).slice()
        let found = false
        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].id === id) {
                list[i] = { id: id, title: title, updated: Date.now() }
                found = true
                break
            }
        }
        if (!found)
            list.push({ id: id, title: title, updated: Date.now() })
        service._commitIndex(list)
    }

    function createNote() {
        const id = "n" + Date.now()
        service.activeId = id
        service.activeTitle = I18n.tr("Untitled note")
        service.activeText = ""
        service._upsert(id, service.activeTitle)
        service._write()
        service.loadRevision += 1
    }

    function openNote(id) {
        if (!id)
            return
        service.activeId = id
        service.busy = true
        PlatformClient.request("file.read-text",
            { path: service.pathFor(id) },
            function(response) {
                service.busy = false
                const raw = (response && response.ok && response.result)
                    ? String(response.result.text || "") : ""
                // First line is the title, the rest is the body.
                const cut = raw.indexOf("\n")
                service.activeTitle = cut >= 0 ? raw.slice(0, cut) : raw
                service.activeText = cut >= 0 ? raw.slice(cut + 1) : ""
                service.lastError = ""
                service.loadRevision += 1
            })
    }

    function saveTitle(title) {
        service.activeTitle = String(title === undefined ? "" : title)
        if (service.activeId.length > 0)
            service._upsert(service.activeId, service.titleFrom(service.activeTitle))
        service._write()
    }

    function saveText(text) {
        service.activeText = String(text === undefined ? service.activeText : text)
        service._write()
    }

    function _write() {
        const id = service.activeId
        if (!id)
            return
        const payload = service.activeTitle + "\n" + service.activeText
        service.busy = true
        PlatformClient.request("file.write-text",
            { path: service.pathFor(id), text: payload, mkdir: true },
            function(response) {
                service.busy = false
                service.lastError = (response && response.ok)
                    ? "" : I18n.tr("Could not save the note")
            })
    }

    function deleteNote(id) {
        const list = (service.notes || []).filter(function(entry) {
            return entry && entry.id !== id
        })
        service._commitIndex(list)
        if (service.activeId === id) {
            service.activeId = ""
            service.activeTitle = ""
            service.activeText = ""
        }
    }

    function setFolder(path) {
        IslandConfigService.setNotesFolder(path)
    }
}
