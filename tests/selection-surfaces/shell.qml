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
    property real closedBlurSigma: -1
    property real launcherBlurSetting: -1
    AppLauncherWindow { id: launcher; outputAvailable: true }
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
                    launcher.applications = [
                        {id: "selection-a.desktop", name: "Alpha", icon: ""},
                        {id: "selection-b.desktop", name: "Beta", icon: ""}
                    ]
                    launcher.applicationsDirty = false
                    launcher.open = true
                } else if (phase === 1) {
                    if (!JSON.parse(launcher.inspectGlass()).settledOpen)
                        return
                    appHighlights = namedItems(launcher.contentItem, "launcher-app-selection-highlight")
                    check(appHighlights.length === 2, "shipping launcher creates two selection plates")
                    check(appHighlights.every(h => h.enabled), "settled launcher accepts app selection")
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
                    closedBlurSigma = JSON.parse(launcher.inspectGlass()).blurSigma
                    launcherBlurSetting = AppearanceConfigService.effectiveLauncherBlur
                    const rootPage = namedItems(launcher.contentItem, "launcher-root-content")[0]
                    check(rootPage && !rootPage.layer.enabled, "closed folders do not retain a root-page texture")
                    launcher.displayedFolder = {id: "folder-test", name: "Folder", apps: launcher.applications}
                    launcher.openFolder = launcher.displayedFolder
                    launcher.folderDialogOpen = true
                } else if (phase === 2) {
                    if (launcher.folderBlurProgress < 1)
                        return
                    const rootPage = namedItems(launcher.contentItem, "launcher-root-content")[0]
                    const folderPage = namedItems(launcher.contentItem, "launcher-folder-page")[0]
                    check(rootPage.layer.enabled, "opening a folder filters the root page")
                    check(folderPage && folderPage.parent === rootPage.parent && !folderPage.layer.enabled,
                        "folder contents remain outside the blurred root-page layer")
                    check(JSON.parse(launcher.inspectGlass()).blurSigma === Math.max(closedBlurSigma, 20),
                        "open folder increases backdrop blur without reducing stronger user settings")
                    folderHighlights = namedItems(launcher.contentItem, "launcher-folder-selection-highlight")
                    check(folderHighlights.length === 2, "folder apps use the shared selection plate")
                    launcher.folderEditMode = true
                    check(folderHighlights.every(h => !h.enabled), "folder editing suppresses selection")
                    launcher.folderEditMode = false
                    AppearanceConfigService.shellStyle = "material"
                } else if (phase === 3) {
                    check(launcher.glassSelectionEnabled && folderHighlights.every(h => h.enabled),
                        "Material folder apps use default glass selection")
                    AppearanceConfigService.shellStyle = "macos"
                    launcher.closeFolder()
                    check(launcher.displayedFolder !== null, "closing retains folder contents during the animation")
                    check(namedItems(launcher.contentItem, "launcher-root-content")[0].layer.enabled,
                        "closing retains the blurred layer until the folder transition completes")
                } else if (phase === 4) {
                    if (launcher.displayedFolder !== null || launcher.folderBlurProgress > 0)
                        return
                    check(!namedItems(launcher.contentItem, "launcher-root-content")[0].layer.enabled,
                        "closing releases the root-page texture")
                    check(JSON.parse(launcher.inspectGlass()).blurSigma === closedBlurSigma,
                        "closing restores the original backdrop blur")
                    check(AppearanceConfigService.effectiveLauncherBlur === launcherBlurSetting,
                        "folder transitions do not change the user's blur setting")
                    AppearanceConfigService.shellStyle = "windows12"
                } else if (phase === 5) {
                    check(appHighlights.every(h => h.enabled), "Windows uses default glass selection")
                    AppearanceConfigService.shellStyle = "material"
                } else if (phase === 6) {
                    check(appHighlights.every(h => h.enabled), "Material uses default glass selection")
                    AppearanceConfigService.shellStyle = "macos"
                } else if (phase === 7) {
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
