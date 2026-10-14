import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../shared/qml/controls" as LiquidControls

ColumnLayout {
    id: page
    required property var theme
    property var bridge: null
    property var state: ({})
    property bool pending: false
    property string errorText: ""
    property string appFilter: ""
    readonly property bool ready: state.ready === true && bridge !== null
    readonly property var applications: (state.sources || []).filter(source =>
        source.appName.toLowerCase().indexOf(appFilter.toLowerCase()) >= 0)
    spacing: 16
    function refresh() {
        if (!bridge || pending) return
        pending = true
        bridge.notificationSnapshot()
    }
    function setPreference(key, value) {
        if (!ready || pending) return
        pending = true
        bridge.setNotificationPreference(key, value)
    }
    Connections {
        target: page.bridge
        enabled: page.bridge !== null
        function onNotificationSnapshotChanged(snapshot) {
            page.pending = false
            if (snapshot.ready !== undefined) page.state = snapshot
            page.errorText = page.bridge.lastError || snapshot.saveError || ""
        }
    }
    Component.onCompleted: refresh()
    // Synchronize changes made by the Control Center and newly discovered apps.
    Timer { interval: 2500; running: page.visible && page.bridge !== null; repeat: true; onTriggered: page.refresh() }
    Text {
        Layout.fillWidth: true
        text: "通知中心默认显示最近三张消息卡片，展开后可浏览全部。长消息可点击展开。"
        color: page.theme.secondaryText
        wrapMode: Text.Wrap
        font.pixelSize: 13
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: preferences.implicitHeight
        radius: 18
        color: page.theme.card
        Column {
            id: preferences
            width: parent.width
            Repeater {
                model: [
                    {key: "doNotDisturbEnabled", title: "勿扰模式", detail: "暂停通知横幅，仍按历史设置保存消息"},
                    {key: "bannersEnabled", title: "显示通知横幅", detail: "新消息到达时显示弹出通知"},
                    {key: "historyEnabled", title: "保留通知历史", detail: "保存本次会话最近 50 条；关闭后停止保存新消息"},
                    {key: "showPreview", title: "显示消息内容预览", detail: "关闭后在通知中心和横幅中隐藏标题与正文"},
                    {key: "showNotificationBadges", title: "显示通知角标", detail: "在 Dock 应用图标上显示通知数字和提醒红点"}
                ]
                delegate: Item {
                    required property var modelData
                    required property int index
                    width: preferences.width
                    height: Math.max(76, descriptions.implicitHeight + 26)
                    Column {
                        id: descriptions
                        anchors { left: parent.left; right: toggle.left; verticalCenter: parent.verticalCenter; leftMargin: 18; rightMargin: 16 }
                        spacing: 5
                        Text { width: parent.width; text: modelData.title; color: page.theme.primaryText; font.pixelSize: 14; wrapMode: Text.Wrap }
                        Text { width: parent.width; text: modelData.detail; color: page.theme.secondaryText; font.pixelSize: 11; wrapMode: Text.Wrap }
                    }
                    LiquidControls.LiquidGlassSwitch {
                        id: toggle
                        objectName: "notification-" + modelData.key + "-switch"
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 18 }
                        checked: page.state[modelData.key] === true
                        enabled: page.ready && !page.pending
                        accentColor: page.theme.accent
                        trackColor: page.theme.divider
                        Accessible.name: modelData.title
                        onToggled: checked => page.setPreference(modelData.key, checked)
                    }
                    Rectangle { visible: index < 4; anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 18 }
                    height: 1; color: page.theme.separator }
                }
            }
        }
    }
    Text { text: "应用通知"; color: page.theme.primaryText; font { pixelSize: 16; weight: Font.DemiBold } }
    TextField {
        Layout.fillWidth: true
        placeholderText: "搜索已发送通知的应用"
        color: page.theme.primaryText
        onTextChanged: page.appFilter = text
        background: Rectangle { radius: 12; color: page.theme.card; border.width: parent.activeFocus ? 1 : 0; border.color: page.theme.accent }
        leftPadding: 16; rightPadding: 16; topPadding: 12; bottomPadding: 12
        Accessible.name: "搜索应用通知"
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: appRows.implicitHeight
        radius: 18
        color: page.theme.card
        Column {
            id: appRows
            width: parent.width
            Repeater {
                model: page.applications
                delegate: Item {
                    required property var modelData
                    required property int index
                    readonly property bool blocked: (page.state.blockedKeys || []).indexOf(modelData.key) >= 0
                    width: appRows.width
                    height: 70
                    Column {
                        anchors { left: parent.left; right: allowToggle.left; verticalCenter: parent.verticalCenter; leftMargin: 18; rightMargin: 16 }
                        spacing: 5
                        Text { width: parent.width; text: modelData.appName; textFormat: Text.PlainText; elide: Text.ElideRight; color: page.theme.primaryText; font.pixelSize: 14 }
                        Text { width: parent.width; text: parent.parent.blocked ? "已屏蔽新通知" : "允许通知"; color: page.theme.secondaryText; font.pixelSize: 11 }
                    }
                    LiquidControls.LiquidGlassSwitch {
                        id: allowToggle
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 18 }
                        checked: !parent.blocked
                        enabled: page.ready && !page.pending
                        accentColor: page.theme.accent
                        trackColor: page.theme.divider
                        Accessible.name: "允许 " + modelData.appName + " 的通知"
                        onToggled: checked => {
                            page.pending = true
                            page.bridge.setNotificationBlocked(modelData.key, !checked)
                        }
                    }
                    Rectangle { visible: index < page.applications.length - 1; anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 18 }
                    height: 1; color: page.theme.separator }
                }
            }
            Text {
                width: parent.width
                padding: 20
                visible: page.applications.length === 0
                text: page.appFilter ? "没有匹配的应用" : "收到通知后，应用会出现在这里"
                color: page.theme.secondaryText
                wrapMode: Text.Wrap
                font.pixelSize: 13
            }
        }
    }
    Text {
        Layout.fillWidth: true
        visible: !page.ready || page.errorText.length > 0
        text: page.errorText || (page.bridge ? "正在连接通知服务…" : "通知服务未连接")
        color: page.errorText ? "#ff453a" : page.theme.secondaryText
        wrapMode: Text.Wrap
        font.pixelSize: 12
    }
}
