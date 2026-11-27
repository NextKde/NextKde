pragma Singleton
import QtQuick
import "WidgetLayout.mjs" as WidgetLayout
import qs.desktop.modules.common
import "../../../shared/qml/i18n"

QtObject {
    id: registry
    function sizeSpan(size) {
        return WidgetLayout.namedGallerySpan(size)
    }
    readonly property var builtins: [
        {id: "clock", name: I18n.tr("Clock"), description: I18n.tr("Keep an eye on the time and your timer."), sizes: ["small", "medium", "large"]},
        {id: "weather", name: I18n.tr("Weather"), description: I18n.tr("Current conditions and the forecast at a glance."), sizes: ["small", "medium", "large"]},
        {id: "calendar", name: I18n.tr("Calendar"), description: I18n.tr("Your month and today's events."), sizes: ["small", "medium", "large"]},
        {id: "todo", name: I18n.tr("To-Do"), description: I18n.tr("Keep your next reminders close by."), sizes: ["small", "medium", "large"]},
        {id: "system", name: I18n.tr("System"), description: I18n.tr("Memory, storage and system status."), sizes: ["small", "medium", "large"]},
        {id: "activity", name: I18n.tr("Activity"), description: I18n.tr("See how you spend time on your desktop."), sizes: ["small", "medium", "large"]},
        {id: "music", name: I18n.tr("Music"), description: I18n.tr("Playback controls and your current track."), sizes: ["small", "medium", "large"]}
    ]
    readonly property var catalog: builtins.map(item => Object.assign({}, item, {
        key: item.id, category: "builtin", categoryName: I18n.tr("Built-in"),
        present: !AppearanceConfigService.isDeskCenterWidgetHidden(item.id)
    }))
    // Under the in-process, user-audited trust model (WidgetGalleryPreviewPlan
    // R2), any valid package indexed from `$XDG_DATA_HOME/kos/widgets/` with
    // verified `Widget.qml` and `Snapshot.qml` entry paths is dynamically
    // executable — no hardcoded allowlist.
    function canExecute(entryOrId) {
        if (!entryOrId || typeof entryOrId !== "object") return false
        return entryOrId.available === true
            && String(entryOrId.widgetEntry ?? "").length > 0
            && String(entryOrId.snapshotEntry ?? "").length > 0
    }
    // Every widget package declares exactly one design family in metadata.json:
    // "material" or "macos". Material shell style shows/runs only "material"
    // packages; macOS shell style shows/runs only "macos" packages. Other-style
    // instances stay parked on disk until the user switches back.
    readonly property string activePackageStyle: AppearanceTokens.isMaterial ? "material" : "macos"
    function matchesActiveStyle(entry) {
        return String(entry?.style ?? "") === activePackageStyle
    }
    function title(id) {
        for (const item of builtins) if (item.id === id) return item.name
        return I18n.tr("Widget")
    }
    function sizes(id) {
        return ["small", "medium", "large"]
    }
    function span(id) {
        return DeskCenterConfigService.spanFor(id)
    }
    function canConfigure(id) {
        return ["clock", "weather", "calendar", "todo", "music"].indexOf(id) >= 0
    }
    function remove(id) {
        AppearanceConfigService.setDeskCenterWidgetVisible(id, false)
    }
}

