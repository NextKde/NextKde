import QtQuick
import Quickshell
import qs.desktop.modules.common
import qs.desktop.modules.bar
import qs.desktop.modules.applauncher

ShellRoot {
    id: test
    property int phase: 0
    property var appHighlights: []
    property var folderHighlights: []
    AppLauncherWindow { id: launcher; outputAvailable: false }
    ControlCenterPanel { id: center }
    function check(value, message) {
        if (!value) throw new Error(message)
    }
    function namedItems(item, name) {
        let result = []
        if (!item) return result
        if (item.objectName === name) result.push(item)
        const children = item.children || []
        for (let i = 0; i < children.length; ++i)
            result = result.concat(namedItems(children[i], name))
        return result
    }
    Timer {
        interval: 200
        repeat: true
        running: true
        onTriggered: {
            try {
                if (phase === 0) {
                    AppearanceConfigService.shellStyle = "macos"
                    AppLauncherConfigService.rootItems = []
                    AppLauncherService.dockWidth = 600
                    AppLauncherService.dockHeight = 60
                    launcher.open = true
                    launcher.applications = [
                        {id: "selection-a.desktop", name: "Alpha", icon: ""},
                        {id: "selection-b.desktop", name: "Beta", icon: ""}
                    ]
                    launcher.applicationsDirty = false
                } else if (phase === 1) {
                    appHighlights = namedItems(launcher.contentItem, "launcher-app-selection-highlight")
                    check(appHighlights.length === 2, "shipping launcher creates two selection plates")
                    check(appHighlights.every(h => !h.selected), "opening launcher must not preselect first app")
                    launcher.keyboardSelectionActive = true
                    launcher.selectedIndex = 1
                    check(appHighlights.filter(h => h.selected).length === 1, "keyboard selects exactly one app")
                    check(appHighlights[1].selected, "keyboard selection follows index")
                    const width = appHighlights[1].parent.width
                    launcher.editMode = true
                    check(appHighlights.every(h => !h.enabled), "editing suppresses app selection")
                    launcher.editMode = false
                    launcher.folderMergeTargetKey = launcher._itemKey(launcher.filteredApplications[1])
                    check(!appHighlights[1].enabled, "merge target keeps its blue indication")
                    launcher.folderMergeTargetKey = ""
                    check(appHighlights[1].parent.width === width, "selection must not alter tile layout")
                    launcher.displayedFolder = {id: "folder-test", name: "Folder", apps: launcher.applications}
                    launcher.openFolder = launcher.displayedFolder
                    launcher.folderDialogOpen = true
                } else if (phase === 2) {
                    folderHighlights = namedItems(launcher.contentItem, "launcher-folder-selection-highlight")
                    check(folderHighlights.length === 2, "folder apps use the shared selection plate")
                    launcher.folderEditMode = true
                    check(folderHighlights.every(h => !h.enabled), "folder editing suppresses selection")
                    launcher.folderEditMode = false
                    AppearanceConfigService.shellStyle = "material"
                    check(appHighlights.every(h => !h.enabled), "Material keeps legacy app highlighting")
                    check(folderHighlights.every(h => !h.enabled), "Material keeps legacy folder highlighting")
                    AppearanceConfigService.shellStyle = "windows12"
                    check(appHighlights.every(h => !h.enabled), "Windows keeps legacy app highlighting")
                    AppearanceConfigService.shellStyle = "macos"
                    check(appHighlights[1].selected, "keyboard selection survives style changes")
                    const controls = namedItems(center.contentItem, "control-center-selection-highlight")
                    check(controls.length >= 10, "shipping control center wires main cards and navigation")
                    check(controls.every(h => h.pointer !== null), "card highlights observe existing input handlers")
                    console.log("SELECTION_SURFACES_PASS")
                    Qt.quit()
                }
                phase++
            } catch (error) {
                console.log("FAIL " + error)
                Qt.quit()
            }
        }
    }
    Timer { interval: 6000; running: true; onTriggered: { console.log("FAIL timeout"); Qt.quit() } }
}
