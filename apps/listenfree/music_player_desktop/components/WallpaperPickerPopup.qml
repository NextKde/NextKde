pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as Basic
import QtQuick.Dialogs

Basic.Popup {
    id: popup
    objectName: "backgroundWallpaperPicker"
    property var service: typeof backendWallpaperLibrary !== "undefined" ? backendWallpaperLibrary : null
    property var settingsStore: null
    property url selectedProject: ""
    property url extraFolder: ""
    property string errorText: ""
    readonly property var filteredItems: {
        if (!visible || !service) return []
        const query = search.text.trim().toLocaleLowerCase()
        return service.items.filter(item => !query || item.title.toLocaleLowerCase().indexOf(query) >= 0)
    }
    signal wallpaperSelected(url project)
    signal folderSelected(url folder)
    function refresh() {
        errorText = ""
        if (service) service.scan(extraFolder)
    }
    function choose(project) {
        if (!settingsStore) return
        const result = settingsStore.resolveBackground(project, true)
        if (result.error) { errorText = result.error; return }
        wallpaperSelected(project)
        close()
    }
    parent: Basic.Overlay.overlay
    popupType: Basic.Popup.Item
    anchors.centerIn: parent
    width: Math.min(760, parent ? parent.width - 40 : 760)
    height: Math.min(610, parent ? parent.height - 40 : 610)
    padding: 24
    modal: true
    focus: true
    closePolicy: Basic.Popup.CloseOnEscape | Basic.Popup.CloseOnPressOutside
    onOpened: { search.text = ""; AppTheme.presentPopup(popup); refresh() }
    onClosed: {
        if (service) service.cancel()
        if (AppTheme.currentPopup === popup) AppTheme.currentPopup = null
    }
    background: Rectangle { radius: 24; color: AppTheme.darkMode ? "#252b34" : "#fcfcfe"; border.color: AppTheme.border }
    Basic.Overlay.modal: Rectangle { color: "#55000000"; radius: AppTheme.windowCornerRadius }
    FolderDialog {
        id: folderPicker
        title: qsTr("选择 Steam 库或壁纸目录")
        onAccepted: {
            popup.folderSelected(selectedFolder)
            popup.errorText = ""
            if (popup.service) popup.service.scan(selectedFolder)
        }
    }
    contentItem: Item {
        Text { text: qsTr("选择视频壁纸"); color: AppTheme.textPrimary; font.pixelSize: 22; font.weight: Font.DemiBold }
        RoundIconButton { anchors.right: parent.right; diameter: 28; kind: "close"; transparentSurface: true; onClicked: popup.close() }
        Text {
            y: 36; width: parent.width
            text: popup.errorText || (popup.service ? popup.service.summary : qsTr("壁纸目录服务不可用。"))
            color: popup.errorText ? "#d65a5a" : AppTheme.textSecondary
            font.pixelSize: 12; wrapMode: Text.Wrap
        }
        Basic.TextField {
            id: search
            objectName: "wallpaperSearch"
            x: 0; y: 78; width: parent.width; height: 34
            placeholderText: qsTr("搜索壁纸名称")
            color: AppTheme.textPrimary
            placeholderTextColor: AppTheme.textSecondary
            selectByMouse: true
            background: Rectangle { radius: 10; color: AppTheme.cardStrong; border.color: AppTheme.border }
        }
        GridView {
            id: grid
            objectName: "wallpaperGrid"
            anchors.left: parent.left; anchors.right: parent.right
            anchors.top: search.bottom; anchors.topMargin: 14
            anchors.bottom: footer.top; anchors.bottomMargin: 12
            cellWidth: width / Math.max(1, Math.floor(width / 210))
            cellHeight: 165
            clip: true
            cacheBuffer: 0
            model: popup.filteredItems
            Basic.ScrollBar.vertical: Basic.ScrollBar {}
            delegate: Item {
                id: card
                required property var modelData
                width: grid.cellWidth; height: grid.cellHeight
                Rectangle {
                    anchors.fill: parent; anchors.margins: 5
                    radius: 12
                    color: hit.containsMouse ? AppTheme.cardStrong : "transparent"
                    border.width: String(popup.selectedProject) === String(card.modelData.project) ? 2 : 1
                    border.color: String(popup.selectedProject) === String(card.modelData.project) ? AppTheme.accent : AppTheme.border
                    Rectangle {
                        x: 7; y: 7; width: parent.width - 14; height: 110
                        color: AppTheme.cardStrong; radius: 7; clip: true
                        Text { anchors.centerIn: parent; text: qsTr("视频壁纸"); color: AppTheme.textSecondary; font.pixelSize: 13 }
                        Image {
                            anchors.fill: parent
                            source: card.modelData.preview
                            sourceSize: Qt.size(320, 180)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                        }
                    }
                    Text {
                        x: 10; y: 123; width: parent.width - 20
                        text: card.modelData.title
                        textFormat: Text.PlainText
                        color: AppTheme.textPrimary; font.pixelSize: 13
                        elide: Text.ElideRight
                    }
                    MouseArea {
                        id: hit
                        objectName: "wallpaperCard"
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: popup.choose(card.modelData.project)
                        Basic.ToolTip.visible: containsMouse
                        Basic.ToolTip.delay: 700
                        Basic.ToolTip.text: card.modelData.title + "\n" + card.modelData.directory
                    }
                }
            }
            Text {
                anchors.centerIn: parent; width: parent.width - 30
                visible: grid.count === 0
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                color: AppTheme.textSecondary; font.pixelSize: 14
                text: popup.service && popup.service.busy ? qsTr("正在读取壁纸列表…")
                    : search.text.trim() ? qsTr("没有匹配的壁纸。") : qsTr("这里会显示已下载的视频壁纸。\n可点击下方“指定目录”查找其他位置。")
            }
        }
        Item {
            id: footer
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            height: 54
            Text {
                width: parent.width - buttons.width - 18
                anchors.verticalCenter: parent.verticalCenter
                text: popup.service && popup.service.directories.length ? popup.service.directories.join("\n") : qsTr("自动识别 Steam 的多个库目录")
                color: AppTheme.textSecondary; font.pixelSize: 11
                textFormat: Text.PlainText; elide: Text.ElideMiddle; maximumLineCount: 2
            }
            Row {
                id: buttons
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                UiButton { label: qsTr("指定目录"); onClicked: folderPicker.open() }
                UiButton { label: qsTr("刷新"); enabled: !popup.service || !popup.service.busy; onClicked: popup.refresh() }
            }
        }
    }
}
