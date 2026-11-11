import QtQuick
import Quickshell
import Quickshell.Io
import qs.desktop.modules.switcher
import qs.desktop.modules.dock

ShellRoot {
    readonly property int windowCount: WindowService.windowCount
    SwitcherWindow { id: overlay }
    IpcHandler {
        target: "switcher-test"
        function snapshot(): string {
            return JSON.stringify({ config: SwitcherService.snapshot(), open: SwitcherService.open,
                mapped: overlay.visible, width: overlay.width, height: overlay.height,
                content: overlay.contentItem.children.map(item => ({
                    width: item.width, height: item.height, visible: item.visible,
                    progress: item.revealProgress, pending: item.entrancePending,
                    mapped: item.mapped
                })),
                screen: overlay.screen ? overlay.screen.name : "",
                windows: SwitcherService.windows, selected: SwitcherService.selectedHandle,
                records: WindowService.records.map(row => ({ windowId: row.windowId,
                    handleId: row.handleId, title: row.title })), active: WindowService.kwinActiveId })
        }
        function enable(value: bool): string {
            SwitcherService.setEnabled(value)
            return JSON.stringify(SwitcherService.snapshot())
        }
    }
}
