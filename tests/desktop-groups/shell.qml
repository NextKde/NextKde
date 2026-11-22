import QtQuick
import Quickshell
import qs.desktop.modules.deskcenter
import "shared/qml/i18n"

ShellRoot {
    id: test

    Item {
        id: host
        width: 400
        height: 560

        property var fixtures: [
            { path: "/groups/App.desktop", name: "App.desktop", title: "App",
                kind: "launcher", icon: "applications-internet" },
            { path: "/groups/photo.png", name: "photo.png", kind: "image" },
            { path: "/groups/wall.jpg", name: "wall.jpg", kind: "image" },
            { path: "/groups/Projects", name: "Projects", kind: "folder" },
            { path: "/groups/notes.txt", name: "notes.txt", kind: "text" },
            { path: "/groups/report.pdf", name: "report.pdf", kind: "pdf" }
        ]

        DesktopGroupsContent {
            id: view
            objectName: "groups-content-test"
            entries: host.fixtures
            initialCategory: "shortcuts"
            onCategorySelected: function(category) {
                test.categorySignals++
            }
        }
    }

    property int stage: 0
    property int categorySignals: 0

    function check(ok, message) {
        if (!ok)
            throw new Error(message)
    }

    Timer {
        interval: 120
        running: true
        repeat: true
        onTriggered: {
            try {
                if (stage === 0) {
                    check(view.visible, "grouped content is visible")
                    check(view.groups.length === 4, "all four preset groups appear")
                    check(view.groups.map(group => group.category).join(",")
                        === "shortcuts,pictures,folders,files", "preset order")
                    check(view.totalCount === 6, "total count")
                    check(view.countFor("shortcuts") === 1, "shortcut count")
                    check(view.countFor("pictures") === 2, "picture count")
                    check(view.countFor("folders") === 1, "folder count")
                    check(view.countFor("files") === 2, "catch-all count")
                    check(view.selectedCategory === "shortcuts", "initial tab")
                    check(view.contentCount === 1, "initial content")

                    DesktopFilesService.setGroupSelectedCategory("pictures")
                    check(DesktopFilesService.layout.groupSelectedCategory
                        === "pictures", "selected tab persists")
                    DesktopFilesService.setGroupSelectedCategory("bogus")
                    check(DesktopFilesService.layout.groupSelectedCategory
                        === "pictures", "invalid tab rejected")

                    check(view.selectCategory("pictures"), "pictures tab selectable")
                    check(view.selectedCategory === "pictures", "pictures selected")
                    check(view.contentCount === 2, "pictures content")
                    view.searchQuery = "photo"
                    check(view.contentCount === 1, "search filters item names")
                    view.searchQuery = "zzz"
                    check(view.contentCount === 0, "search can return no results")
                    view.searchQuery = "photo"
                    view.openSearch()
                    check(view.searchOpen, "search bubble opens")
                    view.closeSearch()
                    check(!view.searchOpen && view.searchQuery === "photo"
                        && view.contentCount === 1,
                        "closing the bubble keeps the active filter")
                    view.openSearch()
                    view.editing = true
                    check(!view.searchOpen, "entering widget edit mode closes search")
                    view.editing = false
                    view.searchQuery = ""
                    check(view.contentCount === 2,
                        "manually clearing the query restores content")

                    // Display parity with the normal icon field.
                    view.showExtensions = false
                    check(view.displayName({ name: "notes.txt", kind: "text" })
                        === "notes", "extension hiding reaches member labels")
                    check(view.displayName({ name: "Projects", kind: "folder" })
                        === "Projects", "folders keep their name")
                    view.showExtensions = true
                    check(view.displayName({ name: "notes.txt", kind: "text" })
                        === "notes.txt", "extensions show when enabled")
                    view.folderCustomizations = {
                        "/groups/Projects": { color: "#FF6B6B", emoji: "⭐" }
                    }
                    check(view.customFor({ path: "/groups/Projects" }).emoji === "⭐",
                        "folder customization reaches the icon")
                    view.folderCustomizations = ({})

                    // Inline rename commits through the shared desktop callback
                    // and only closes the editor on success.
                    let renamed = null
                    view.renameCallback = function(entry, name) {
                        renamed = { entry: entry, name: name }
                        return name === "notes-2.txt"
                    }
                    view.beginRename("/groups/notes.txt")
                    check(view.renamingPath === "/groups/notes.txt",
                        "rename starts on the requested member")
                    check(view.commitRename({ path: "/groups/notes.txt" }, "bad/name")
                        === false, "failed rename keeps the editor")
                    check(view.renamingPath === "/groups/notes.txt",
                        "failed rename keeps editing")
                    check(view.commitRename({ path: "/groups/notes.txt" },
                        "notes-2.txt") === true,
                        "rename commits through the shared callback")
                    check(renamed && renamed.name === "notes-2.txt",
                        "callback got the new name")
                    check(view.renamingPath === "",
                        "successful rename closes the editor")
                    view.renameCallback = null

                    // Member artwork and grid metrics follow the desktop's
                    // Small/Medium/Large icon size setting.
                    check(view.iconSize === 56, "default member icon size")
                    check(view.cellHeight === 102, "default member cell height")
                    check(view.columnWidth === 92, "default member column width")
                    check(view.labelFontSize === 11, "default label size")
                    view.iconSize = 72
                    check(view.cellHeight === 118 && view.columnWidth === 108
                        && view.labelFontSize === 14
                        && view.labelFontWeight === Font.Bold,
                        "large icons scale the member grid")
                    view.iconSize = 40
                    check(view.cellHeight === 86 && view.columnWidth === 76
                        && view.labelFontSize === 9
                        && view.labelFontWeight === Font.Medium,
                        "small icons scale the member grid")
                    view.iconSize = 56

                    // Single selection mirrors the normal desktop's filled
                    // highlight and clears when the visible type changes.
                    view.selectOnly("/groups/photo.png")
                    check(view.isSelected("/groups/photo.png"),
                        "single click selects a member")
                    check(!view.isSelected("/groups/wall.jpg"),
                        "only one member is selected")
                    check(view.selectCategory("shortcuts"),
                        "switch type for the selection check")
                    check(!view.isSelected("/groups/photo.png"),
                        "changing type clears the selection")
                    stage++
                    return
                }
                // Snapshot change: pictures disappears, files grows, and the
                // selected picture tab falls back to a non-empty one.
                host.fixtures = host.fixtures.filter(entry =>
                    entry.kind !== "image").concat([
                    { path: "/groups/archive.zip", name: "archive.zip",
                        kind: "file" }
                ])
                check(view.groups.map(group => group.category).join(",")
                    === "shortcuts,folders,files", "empty category removed")
                check(view.countFor("files") === 3, "catch-all follows snapshot")
                check(view.selectedCategory === "shortcuts",
                    "selection falls back from an empty tab")
                check(view.contentCount === 1, "fallback content")
                check(!view.selectCategory("pictures"),
                    "empty tab is not selectable")
                console.log("DESKTOP_GROUPS_RUNTIME_PASS")
                Qt.quit()
            } catch (error) {
                console.log("FAIL " + error)
                Qt.quit()
            }
        }
    }
}
