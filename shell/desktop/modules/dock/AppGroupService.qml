pragma Singleton
import QtQuick

// AppGroupService — derives application groups from the runtime window model.
// It is intentionally not persisted: groups are rebuilt from pinnedAppIds and
// current windows, making it reusable by Dock, Alt+Tab, and future workspace UI.

QtObject {
    id: svc

    property var groups: []
    property int revision: 0

    property Connections _windowConnections: Connections {
        target: WindowService
        function onRevisionChanged() { svc.rebuild() }
    }

    property Connections _configConnections: Connections {
        target: ConfigService
        function onPinnedAppIdsChanged() { svc.rebuild() }
    }

    function rebuild() {
        const result = [];
        const byId = ({});
        const ids = ConfigService.pinnedAppIds || [];

        function addGroup(desktopId, pinned) {
            const identity = AppIdentityService.resolve(desktopId);
            const group = {
                desktopId: identity.desktopId,
                name: identity.name,
                iconSource: identity.iconSource,
                pinned: pinned,
                windows: [],
                activeWindow: null,
                pinnedVisible: pinned,
            };
            byId[identity.normalizedId] = group;
            result.push(group);
            return group;
        }

        for (let i = 0; i < ids.length; i++)
            addGroup(ids[i], true);

        for (let i = 0; i < WindowService.records.length; i++) {
            const record = WindowService.records[i];
            const key = record.identity.normalizedId;
            const group = byId[key] ?? addGroup(record.identity.desktopId, false);
            group.windows.push(record);
            if (record.toplevel.activated)
                group.activeWindow = record;
        }

        // The current Dock presentation hides a pinned launcher while its app
        // has windows. Other consumers may choose a macOS/KDE grouped view.
        for (let i = 0; i < result.length; i++)
            result[i].pinnedVisible = result[i].pinned && result[i].windows.length === 0;

        svc.groups = result;
        svc.revision++;
    }

    Component.onCompleted: rebuild()
}
