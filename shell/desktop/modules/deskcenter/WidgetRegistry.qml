pragma Singleton
import QtQuick
import qs.desktop.modules.common
import "../../../shared/qml/i18n"

QtObject {
    id: registry
    function isPlugin(id) { return String(id).startsWith("plugin:") }
    function sizeSpan(size) {
        return size === "large" ? [2, 2] : size === "medium" ? [2, 1] : [1, 1]
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
    // Live values refresh every poll; gallery identity changes only when the
    // installed type list or instance membership changes, preserving focus.
    readonly property string instanceMembership: JSON.stringify(PluginWidgetService.instances.map(item =>
        ({pluginId: item.pluginId, widgetId: item.widgetId})))
    readonly property var catalog: {
        const members = JSON.parse(instanceMembership)
        const entries = builtins.map(item => Object.assign({}, item, {
            key: item.id, category: "builtin", categoryName: I18n.tr("Built-in"),
            pluginId: "", widgetId: item.id, multiInstance: false,
            present: !AppearanceConfigService.isDeskCenterWidgetHidden(item.id)
        }))
        for (const plugin of PluginWidgetService.plugins) {
            if (!plugin.enabled || plugin.status === "unavailable") continue
            for (const widget of (plugin.widgets || [])) {
                entries.push({key: plugin.id + "/" + widget.id, id: widget.id,
                    widgetId: widget.id, pluginId: plugin.id, name: widget.name,
                    description: widget.description, category: plugin.id,
                    categoryName: plugin.name, sizes: widget.sizes,
                    multiInstance: !!widget.multiInstance,
                    present: members.some(item => item.pluginId === plugin.id && item.widgetId === widget.id)})
            }
        }
        return entries
    }
    function title(id) {
        if (isPlugin(id)) return PluginWidgetService.instance(id)?.name || I18n.tr("Widget")
        for (const item of builtins) if (item.id === id) return item.name
        return I18n.tr("Widget")
    }
    function sizes(id) {
        return isPlugin(id) ? (PluginWidgetService.instance(id)?.sizes || []) : ["small", "medium", "large"]
    }
    function span(id) {
        return isPlugin(id) ? sizeSpan(PluginWidgetService.instance(id)?.size) : DeskCenterConfigService.spanFor(id)
    }
    function canConfigure(id) {
        return isPlugin(id) ? (PluginWidgetService.instance(id)?.settingsSchema?.length || 0) > 0
            : ["clock", "weather", "calendar", "todo", "music"].indexOf(id) >= 0
    }
    function remove(id) {
        if (isPlugin(id)) PluginWidgetService.remove(id, function(ok) {
            if (ok) DeskCenterConfigService.forgetWidget(id)
        })
        else AppearanceConfigService.setDeskCenterWidgetVisible(id, false)
    }
}
