import QtQuick

// This delegate owns its exit. No ListView remove transition or height
// animation competes with delayRemove; neighbours move after its release.
Item {
    id: entry
    required property int historyKey
    required property string summary
    required property string body
    required property real timestamp
    property string appName: ""
    property string appIcon: ""
    property string desktopEntry: ""
    property int additionalCount: 0
    property real clockNow: Date.now()
    property color ink: "white"
    property bool dark: true
    property var coordinator: null
    property bool groupExiting: false
    property bool exiting: false
    property bool registeredExit: false
    property real frozenHeight: 0
    property var painted: ({key: historyKey, summary: summary, body: body,
        timestamp: timestamp, appName: appName, appIcon: appIcon,
        desktopEntry: desktopEntry, additionalCount: additionalCount})
    signal removeRequested(int key)
    height: exiting ? frozenHeight : content.implicitHeight + 48
        + (painted.additionalCount > 0 ? 25 : 0)
    enabled: !exiting && !groupExiting
    ListView.onRemove: {
        painted = {key: historyKey, summary: summary, body: body,
            timestamp: timestamp, appName: appName, appIcon: appIcon,
            desktopEntry: desktopEntry, additionalCount: additionalCount}
        frozenHeight = height
        exiting = true
        if (coordinator && !groupExiting) {
            coordinator.beginHistoryExit()
            registeredExit = true
        }
        if (!groupExiting) {
            ListView.delayRemove = true
            exitMotion.start()
        }
    }
    function releaseExit() {
        if (registeredExit && coordinator) coordinator.endHistoryExit()
        registeredExit = false
    }
    Component.onDestruction: releaseExit()
    ParallelAnimation {
        id: exitMotion
        NumberAnimation { target: entry; property: "x"; to: 18; duration: 170; easing.type: Easing.InCubic }
        NumberAnimation { target: entry; property: "opacity"; to: 0; duration: 170; easing.type: Easing.InCubic }
        onFinished: {
            entry.releaseExit()
            entry.ListView.delayRemove = false
        }
    }
    Rectangle {
        anchors.fill: parent
        radius: 13
        color: entry.dark ? Qt.rgba(0.27, 0.29, 0.32, 0.88) : Qt.rgba(0.94, 0.94, 0.95, 0.9)
        border.width: 1
        border.color: entry.dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.07)
    }
    Timer {
        interval: 60000
        repeat: true
        running: entry.visible && !entry.exiting
        onTriggered: entry.clockNow = Date.now()
    }
    function timeLabel() {
        if (!painted.timestamp) return ""
        const minutes = Math.max(0, Math.floor((clockNow - painted.timestamp) / 60000))
        if (minutes === 0) return "刚刚"
        if (minutes < 60) return minutes + " 分钟前"
        if (minutes < 1440) return Math.floor(minutes / 60) + " 小时前"
        return Math.floor(minutes / 1440) + " 天前"
    }
    NotificationSourceIcon {
        x: 12; y: 12
        width: 16; height: 16
        appIcon: entry.painted.appIcon
        desktopEntry: entry.painted.desktopEntry
        ink: entry.ink
    }
    Text {
        x: 34; y: 13
        width: Math.max(0, timeText.x - x - 8)
        text: entry.painted.appName
        textFormat: Text.PlainText
        color: entry.ink
        opacity: 0.7
        elide: Text.ElideRight
        font { pixelSize: 10; weight: Font.DemiBold }
    }
    Text {
        id: timeText
        anchors { right: parent.right; top: parent.top; rightMargin: 33; topMargin: 13 }
        text: entry.timeLabel()
        color: entry.ink
        opacity: 0.48
        font.pixelSize: 9
    }
    Column {
        id: content
        anchors { left: parent.left; top: parent.top; leftMargin: 12; topMargin: 36 }
        width: parent.width - 24
        spacing: 4
        Text {
            width: parent.width
            text: entry.painted.summary || "通知"
            textFormat: Text.PlainText
            color: entry.ink
            elide: Text.ElideRight
            font { pixelSize: 13; weight: Font.DemiBold }
            style: entry.dark ? Text.Outline : Text.Normal
            styleColor: Qt.rgba(0, 0, 0, 0.25)
        }
        Text {
            width: parent.width
            visible: text.length > 0
            text: entry.painted.body
            textFormat: Text.PlainText
            color: entry.ink
            opacity: 0.72
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            font.pixelSize: 12
            style: entry.dark ? Text.Outline : Text.Normal
            styleColor: Qt.rgba(0, 0, 0, 0.25)
        }
    }
    Text {
        anchors { left: parent.left; bottom: parent.bottom; leftMargin: 12; bottomMargin: 11 }
        visible: entry.painted.additionalCount > 0
        text: "还有 " + entry.painted.additionalCount + " 条通知"
        color: entry.ink
        opacity: 0.6
        font.pixelSize: 11
    }
    Text {
        anchors { right: parent.right; top: parent.top; rightMargin: 10; topMargin: 9 }
        text: "×"
        color: entry.ink
        opacity: removeMouse.containsMouse ? 1 : 0.5
        font.pixelSize: 18
        MouseArea {
            id: removeMouse
            anchors.fill: parent; anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: entry.removeRequested(entry.painted.key)
        }
    }
}
