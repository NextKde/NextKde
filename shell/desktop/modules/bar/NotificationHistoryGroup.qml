import QtQuick
import Quickshell.Widgets

Item {
    id: group
    required property string sourceKey
    required property string appName
    required property string desktopEntry
    required property string appIcon
    required property string itemsJson
    required property bool expanded
    required property int itemCount
    property color ink: "white"
    property bool dark: true
    property var coordinator: null
    property bool exiting: false
    property bool registeredExit: false
    property real frozenHeight: 0
    property var painted: ({sourceKey: sourceKey, appName: appName, appIcon: appIcon, desktopEntry: desktopEntry,
        expanded: expanded, count: itemCount})
    readonly property var memberKeys: JSON.parse(itemsJson).map(item => item.historyKey)
    property var leadingItem: null
    readonly property real latestHeight: leadingItem?.height ?? 112
    readonly property int headerHeight: painted.expanded && painted.count > 1 ? 32 : 0
    readonly property int backHeight: !painted.expanded && painted.count > 1 ? Math.min(2, painted.count - 1) * 6 : 0
    readonly property real cardsHeight: painted.expanded ? members.contentHeight : latestHeight
    height: exiting ? frozenHeight : headerHeight + cardsHeight + backHeight
    enabled: !exiting
    signal toggleRequested(string source, bool expanded)
    signal removeRequested(int key)
    signal clearRequested(var keys)

    Behavior on height {
        enabled: !group.exiting
        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
    }
    ListModel { id: memberModel }
    function reconcileMembers() {
        if (exiting) return
        const desired = JSON.parse(itemsJson)
        const selected = new Set(desired.map(item => item.historyKey))
        for (let i = memberModel.count - 1; i >= 0; --i)
            if (!selected.has(memberModel.get(i).historyKey)) memberModel.remove(i)
        for (let i = 0; i < desired.length; ++i) {
            let found = -1
            for (let j = i; j < memberModel.count; ++j)
                if (memberModel.get(j).historyKey === desired[i].historyKey) { found = j; break }
            if (found < 0) memberModel.insert(i, desired[i])
            else {
                if (found !== i) memberModel.move(found, i, 1)
                memberModel.set(i, desired[i])
            }
        }
    }
    onItemsJsonChanged: reconcileMembers()
    Component.onCompleted: reconcileMembers()
    ListView.onRemove: {
        // Detach display fields from disappearing roles and freeze geometry.
        painted = {sourceKey: sourceKey, appName: appName, appIcon: appIcon, desktopEntry: desktopEntry,
            expanded: expanded, count: itemCount}
        frozenHeight = height
        exiting = true
        if (coordinator && coordinator.historyGroupVisible(group)) {
            coordinator.beginHistoryExit()
            registeredExit = true
            ListView.delayRemove = true
            exitMotion.start()
        }
    }
    function releaseExit() {
        if (registeredExit && coordinator) coordinator.endHistoryExit()
        registeredExit = false
    }
    Component.onDestruction: releaseExit()
    SequentialAnimation {
        id: exitMotion
        PauseAnimation { duration: group.coordinator?.historyExitDelay(group.painted.sourceKey) ?? 0 }
        ParallelAnimation {
            NumberAnimation { target: group; property: "x"; to: 18; duration: 170; easing.type: Easing.InCubic }
            NumberAnimation { target: group; property: "opacity"; to: 0; duration: 170; easing.type: Easing.InCubic }
        }
        onFinished: {
            group.releaseExit()
            group.ListView.delayRemove = false
        }
    }
    NotificationSourceIcon {
        visible: group.headerHeight > 0
        anchors { left: parent.left; top: parent.top; leftMargin: 2; topMargin: 5 }
        width: 16; height: 16
        appIcon: group.painted.appIcon
        desktopEntry: group.painted.desktopEntry
        ink: group.ink
    }
    Text {
        visible: group.headerHeight > 0
        anchors { left: parent.left; top: parent.top; leftMargin: 24; topMargin: 5 }
        width: parent.width - (group.painted.count > 1 ? 116 : 30)
        text: group.painted.appName
        textFormat: Text.PlainText
        color: group.ink
        opacity: 0.72
        elide: Text.ElideRight
        font { pixelSize: 11; weight: Font.DemiBold }
    }
    Text {
        visible: group.headerHeight > 0
        anchors { right: clearButton.left; top: parent.top; rightMargin: 12; topMargin: 5 }
        text: "收起"
        color: group.ink
        opacity: 0.7
        font.pixelSize: 11
        MouseArea {
            anchors.fill: parent; anchors.margins: -5
            cursorShape: Qt.PointingHandCursor
            onClicked: group.toggleRequested(group.painted.sourceKey, !group.painted.expanded)
        }
    }
    Text {
        id: clearButton
        visible: group.headerHeight > 0
        anchors { right: parent.right; top: parent.top; rightMargin: 6; topMargin: 5 }
        text: "清除"
        color: group.ink
        opacity: 0.55
        font.pixelSize: 11
        MouseArea {
            anchors.fill: parent; anchors.margins: -5
            cursorShape: Qt.PointingHandCursor
            onClicked: group.clearRequested(group.memberKeys.slice())
        }
    }
    // Back cards have no paint above the leading card's bottom edge. This
    // geometric occlusion prevents every rear border from crossing content,
    // even while the front material retains slight translucency.
    Item {
        x: 0; y: group.headerHeight + group.latestHeight
        width: group.width
        height: group.backHeight
        clip: true
        Repeater {
            model: group.backHeight / 6
            delegate: Rectangle {
                required property int index
                z: -index
                x: (index + 1) * 6
                y: -group.latestHeight + (index + 1) * 6
                width: group.width - x * 2
                height: group.latestHeight
                radius: 13
                color: group.dark ? (index === 0 ? "#42464b" : "#3a3e43")
                    : (index === 0 ? "#d5d6d8" : "#c6c8ca")
                border.width: 1
                border.color: group.dark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.09)
            }
        }
    }
    ListView {
        id: members
        x: 0; y: group.headerHeight
        width: parent.width
        // Clip follows the one animated group height, so members reveal
        // gradually instead of painting over the neighbouring group at once.
        height: Math.max(0, group.height - group.headerHeight - group.backHeight)
        clip: true
        interactive: false
        spacing: 6
        model: memberModel
        // Instantiate the clipped members so expansion has a settled height.
        cacheBuffer: 5000
        displaced: Transition { NumberAnimation { property: "y"; duration: 200; easing.type: Easing.OutCubic } }
        add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 } }
        delegate: NotificationHistoryEntry {
            id: entryDelegate
            required property int index
            onIndexChanged: if (index === 0 && !exiting) group.leadingItem = entryDelegate
            Component.onCompleted: if (index === 0) group.leadingItem = entryDelegate
            Component.onDestruction: if (group.leadingItem === entryDelegate) group.leadingItem = null
            appName: group.painted.appName
            appIcon: group.painted.appIcon
            desktopEntry: group.painted.desktopEntry
            additionalCount: index === 0 && !group.painted.expanded ? group.painted.count - 1 : 0
            width: members.width
            ink: group.ink
            dark: group.dark
            coordinator: group.coordinator
            groupExiting: group.exiting
            onRemoveRequested: key => group.removeRequested(key)
        }
    }
    MouseArea {
        // Only the collapsed content surface expands; its separate remove
        // control remains reachable above this passive tap area.
        visible: !group.painted.expanded && group.painted.count > 1
        x: 0; y: group.headerHeight
        width: group.width - 36
        height: group.cardsHeight
        cursorShape: Qt.PointingHandCursor
        onClicked: group.toggleRequested(group.painted.sourceKey, true)
    }
}
