pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: panel
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onWheel: wheel => wheel.accepted = true
    }

    property bool darkMode: AppTheme.darkMode || Qt.application.arguments.indexOf("--dark") >= 0
    property string title: qsTr("播放队列")
    property var rows: []
    property var sourceModel: null
    property int backendRevision: 0
    property bool fullScreenPresentation: false
    property int currentIndex: sourceModel && sourceModel.currentIndex !== undefined
                               ? sourceModel.currentIndex : -1

    readonly property int trackCount: sourceModel !== null ? backendList.count
                                                            : (rows ? rows.length : 0)

    signal playRequested(int index, var track)
    signal removeRequested(int index)
    signal moveRequested(int from, int to)
    signal trackCommandRequested(string command, var track, int rowIndex)
    signal clearRequested
    signal locateCurrentRequested
    signal closeRequested

    Component.onCompleted: {
        if (panel.darkMode && !AppTheme.darkMode)
            AppTheme.darkMode = true
    }

    implicitWidth: 360
    implicitHeight: 640

    function formatDuration(value) {
        if (typeof value !== "number")
            return String(value || "--:--")
        const seconds = Math.max(0, Math.floor(value >= 1000 ? value / 1000 : value))
        return Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0")
    }

    function backendRow(index, revision) {
        return sourceModel ? sourceModel.rowMap(index) : ({})
    }

    Connections {
        target: panel.sourceModel
        ignoreUnknownSignals: true
        function onDataChanged() { panel.backendRevision++ }
    }

    function openRowMenu(rowItem, pointX, pointY, rowIndex, track) {
        const point = rowItem.mapToItem(panel, pointX, pointY)
        rowMenu.openAt(point.x, point.y, { rowIndex: rowIndex, track: track })
    }

    function locateCurrentRow() {
        if (currentIndex < 0 || currentIndex >= trackCount)
            return
        const list = sourceModel !== null ? backendList : mockList
        list.positionViewAtIndex(currentIndex, ListView.Center)
        locateCurrentRequested()
    }

    component HeaderPill: Rectangle {
        id: pill

        required property string label
        property bool accent: false
        signal clicked

        height: 30
        radius: 15
        color: !enabled
               ? (panel.darkMode ? "#24303938" : "#70eef0f1")
               : accent
                 ? (pillHover.hovered ? Qt.lighter(AppTheme.accent, 1.08) : AppTheme.accent)
                 : pillHover.hovered ? AppTheme.controlHover : AppTheme.control
        border.width: 1
        border.color: accent && enabled ? "#34ffffff" : AppTheme.border
        opacity: enabled ? 1 : .45
        scale: pillTap.pressed ? .96 : 1

        Behavior on color { ColorAnimation { duration: AppTheme.duration(100) } }
        Behavior on scale { NumberAnimation { duration: AppTheme.duration(90); easing.type: Easing.OutCubic } }

        Text {
            anchors.centerIn: parent
            text: pill.label
            color: pill.accent && pill.enabled ? "white" : AppTheme.textPrimary
            font.family: AppTheme.fontFamily
            font.pixelSize: 11
            font.weight: Font.Medium
        }

        HoverHandler { id: pillHover; enabled: pill.enabled }
        TapHandler {
            id: pillTap
            enabled: pill.enabled
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: pill.clicked()
        }
    }

    GlassSurface {
        anchors.fill: parent
        cornerRadius: panel.fullScreenPresentation ? 0 : 20
        tint: AppTheme.floatingSurface
        edgeColor: AppTheme.border
        shadowOpacity: panel.fullScreenPresentation ? .16 : .24
    }

    Item {
        id: header
        x: panel.fullScreenPresentation ? 24 : 20
        y: panel.fullScreenPresentation ? 20 : 14
        width: parent.width - x * 2
        height: panel.fullScreenPresentation ? 48 : 50

        Text {
            id: titleLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: panel.title
            color: AppTheme.textPrimary
            font.family: AppTheme.fontFamily
            font.pixelSize: 20
            font.weight: Font.DemiBold
        }

        Text {
            anchors.left: titleLabel.right
            anchors.leftMargin: 9
            anchors.baseline: titleLabel.baseline
            text: panel.trackCount + qsTr(" 首")
            color: AppTheme.textSecondary
            font.family: AppTheme.fontFamily
            font.pixelSize: 12
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7

            HeaderPill {
                width: 80
                label: qsTr("清空列表")
                enabled: panel.trackCount > 0
                onClicked: panel.clearRequested()
            }

            HeaderPill {
                width: 106
                label: qsTr("定位当前歌曲")
                accent: true
                enabled: panel.currentIndex >= 0 && panel.currentIndex < panel.trackCount
                onClicked: panel.locateCurrentRow()
            }
        }
    }

    Rectangle {
        x: panel.fullScreenPresentation ? 24 : 20
        y: panel.fullScreenPresentation ? 78 : 65
        width: parent.width - x * 2
        height: 1
        color: AppTheme.divider
    }

    component QueueRow: SongRow {
        id: queueRow
        required property ListView ownerList
        property real lastDragOffset: 0
        width: ownerList.width
        current: panel.currentIndex === rowIndex
        showRemove: true
        removeObjectName: "queueRemove" + rowIndex
        z: dragHandler.active ? 20 : 1
        transform: Translate { y: dragHandler.active ? dragHandler.activeTranslation.y : 0 }
        onSelectedRequested: panel.playRequested(rowIndex,track)
        onActivated: panel.playRequested(rowIndex,track)
        onCommandRequested: command => {
            if (command === "remove_queue") panel.removeRequested(rowIndex)
            else panel.trackCommandRequested(command,track,rowIndex)
        }
        onContextRequested: (mx,my) => panel.openRowMenu(queueRow,mx,my,rowIndex,track)
        DragHandler {
            id: dragHandler
            target: null
            xAxis.enabled: false

            onActiveTranslationChanged: {
                if (active)
                    queueRow.lastDragOffset = activeTranslation.y
            }
            onActiveChanged: {
                if (active)
                    return
                const completedOffset = queueRow.lastDragOffset
                queueRow.lastDragOffset = 0
                if (Math.abs(completedOffset) < 8)
                    return
                const targetY = queueRow.y + queueRow.height / 2 + completedOffset
                let targetIndex = queueRow.ownerList.indexAt(8, targetY)
                if (targetIndex < 0)
                    targetIndex = targetY < 0 ? 0 : panel.trackCount - 1
                targetIndex = Math.max(0, Math.min(panel.trackCount - 1, targetIndex))
                if (targetIndex !== queueRow.rowIndex)
                    panel.moveRequested(queueRow.rowIndex, targetIndex)
            }
        }

    }

    ListView {
        id: mockList
        visible: panel.sourceModel === null
        x: panel.fullScreenPresentation ? 16 : 12
        y: panel.fullScreenPresentation ? 88 : 74
        width: parent.width - x * 2
        height: parent.height - y - (panel.fullScreenPresentation ? 18 : 12)
        clip: true
        spacing: 3
        boundsBehavior: Flickable.StopAtBounds
        model: panel.rows || []

        delegate: QueueRow {
            required property int index
            required property var modelData
            rowIndex: index
            track: modelData
            ownerList: mockList
        }
    }

    ListView {
        id: backendList
        visible: panel.sourceModel !== null
        x: panel.fullScreenPresentation ? 16 : 12
        y: panel.fullScreenPresentation ? 88 : 74
        width: parent.width - x * 2
        height: parent.height - y - (panel.fullScreenPresentation ? 18 : 12)
        clip: true
        spacing: 3
        boundsBehavior: Flickable.StopAtBounds
        model: panel.sourceModel

        delegate: QueueRow {
            required property int index
            rowIndex: index
            ownerList: backendList
            track: panel.backendRow(index, panel.backendRevision)
        }
    }

    Text {
        visible: panel.trackCount === 0
        anchors.centerIn: parent
        text: qsTr("播放队列为空")
        color: AppTheme.textSecondary
        font.family: AppTheme.fontFamily
        font.pixelSize: 13
    }

    ContextMenu {
        id: rowMenu
        anchors.fill: parent
        z: 100
        darkMode: panel.darkMode
        menuWidth: 172
        actions: [
            { label: qsTr("从队列移除"), command: "remove", destructive: true }
        ]
        onCommandTriggered: function(command, contextData) {
            if (command === "remove" && contextData)
                panel.removeRequested(contextData.rowIndex)
        }
    }
}
