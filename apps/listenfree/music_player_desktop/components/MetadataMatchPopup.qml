pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as Basic

Basic.Popup {
    id: popup
    objectName: "metadataMatchPopup"
    property var controller: null
    property var track: ({})
    property int selectedIndex: -1
    property var selectedKeys: ["title", "artist", "album", "artwork"]
    readonly property var coverState: controller ? controller.metadataArtwork : ({})
    readonly property var results: controller ? controller.metadataCandidates : []
    readonly property var selected: selectedIndex >= 0 && selectedIndex < results.length ? results[selectedIndex] : ({})
    signal acceptedValues(var values)
    function search() {
        selectedIndex = -1
        candidates.contentY = 0
        if (controller) controller.searchMetadataMatches(track, query.text, source.currentIndex === 0 ? "wy" : "tx")
    }
    function match(song) {
        track = song
        const path = String(song.localPath || "").replace(/\\/g, "/")
        const filename = path.slice(path.lastIndexOf("/") + 1).replace(/\.[^.]+$/, "")
        query.text = filename || [song.title || "", song.artist || ""].filter(value => value).join(" ")
        open(); search()
    }
    function choose(index) {
        selectedIndex = index; selectedKeys = ["title", "artist", "album", "artwork"]
        if (controller) controller.previewMetadataArtwork(index)
    }
    function toggle(key, checked) {
        let keys = selectedKeys.filter(value => value !== key)
        if (checked) keys.push(key)
        selectedKeys = keys
    }
    readonly property var values: {
        const coverRevision = coverState
        return controller ? controller.metadataMatchValues(selectedIndex, selectedKeys) : ({})
    }
    parent: Basic.Overlay.overlay
    popupType: Basic.Popup.Item
    anchors.centerIn: parent
    width: Math.min(940, parent ? parent.width - 48 : 940)
    height: Math.min(690, parent ? parent.height - 48 : 690)
    padding: 24
    modal: true; focus: true
    closePolicy: Basic.Popup.CloseOnEscape | Basic.Popup.CloseOnPressOutside
    onOpened: AppTheme.presentPopup(popup)
    onClosed: {
        if (controller) controller.cancelMetadataMatch()
        selectedIndex = -1
        if (AppTheme.currentPopup === popup) AppTheme.currentPopup = null
    }
    background: Rectangle { radius: 24; color: AppTheme.darkMode ? "#252d36" : "#f7f8fb"; border.color: AppTheme.border }
    Basic.Overlay.modal: Rectangle { color: "#780e1520"; radius: AppTheme.windowCornerRadius }
    contentItem: Item {
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: mouse => mouse.accepted = true; onWheel: wheel => wheel.accepted = true }
        Text { text: qsTr("搜索基本信息"); color: AppTheme.textPrimary; font.family: AppTheme.fontFamily; font.pixelSize: 23; font.weight: Font.DemiBold }
        Text { y: 34; text: qsTr("选择歌曲版本，逐项预览后填入编辑器"); color: AppTheme.textSecondary; font.family: AppTheme.fontFamily; font.pixelSize: 11 }
        RoundIconButton { anchors.right: parent.right; diameter: 30; kind: "close"; transparentSurface: true; onClicked: popup.close() }
        Row {
            y: 64; width: parent.width; spacing: 10
            Basic.ComboBox {
                id: source
                objectName: "metadataMatchSource"
                width: 120; height: 38; model: [qsTr("网易云音乐"), qsTr("QQ 音乐")]
                font.family: AppTheme.fontFamily; font.pixelSize: 12
                palette.text: AppTheme.textPrimary; palette.buttonText: AppTheme.textPrimary
                palette.base: AppTheme.darkMode ? "#353e49" : "#e9edf3"
                background: Rectangle { radius: 12; color: AppTheme.darkMode ? "#353e49" : "#e9edf3"; border.color: AppTheme.border }
                onActivated: popup.search()
            }
            Basic.TextField {
                id: query
                objectName: "metadataMatchQuery"
                width: parent.width - 226; height: 38; leftPadding: 36; rightPadding: 12
                placeholderText: qsTr("歌曲名 / 艺术家 / 专辑"); selectByMouse: true
                color: AppTheme.textPrimary; placeholderTextColor: AppTheme.textMuted
                font.family: AppTheme.fontFamily; font.pixelSize: 13
                selectionColor: AppTheme.accent; selectedTextColor: "white"
                background: Rectangle { radius: 12; color: AppTheme.darkMode ? "#353e49" : "#e9edf3"; border.width: query.activeFocus ? 1 : 0; border.color: AppTheme.accent }
                IconGlyph { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; kind: "search"; glyphColor: AppTheme.textSecondary }
                onAccepted: popup.search()
            }
            UiButton { objectName: "metadataSearchButton"; width: 86; height: 38; label: qsTr("搜索"); onClicked: popup.search() }
        }
        Text { y: 120; text: qsTr("搜索结果") + (popup.results.length ? "  ·  " + popup.results.length : ""); color: AppTheme.textSecondary; font.family: AppTheme.fontFamily; font.pixelSize: 11 }
        ListView {
            id: candidates
            objectName: "metadataMatchCandidates"
            x: 0; y: 144; width: Math.round(parent.width * .43); height: parent.height - 203
            clip: true; spacing: 8; boundsBehavior: Flickable.StopAtBounds
            model: popup.results
            delegate: Rectangle {
                id: result
                required property var modelData
                required property int index
                readonly property bool selected: popup.selectedIndex === index
                width: candidates.width; height: 99; radius: 12
                color: selected ? (AppTheme.darkMode ? "#3b444e" : "#e6f2fc") : AppTheme.darkMode ? "#303945" : "white"
                border.color: selected ? AppTheme.accent : AppTheme.darkMode ? "#485361" : "#dce2ea"
                activeFocusOnTab: true
                Keys.onReturnPressed: popup.choose(index)
                Keys.onSpacePressed: popup.choose(index)
                Column {
                    x: 13; y: 12; width: parent.width - 26; spacing: 6
                    Text { width: parent.width; text: result.modelData.title; elide: Text.ElideRight; color: AppTheme.textPrimary; font.family: AppTheme.fontFamily; font.pixelSize: 14; font.weight: Font.DemiBold }
                    Text { width: parent.width; text: result.modelData.artist || qsTr("未提供艺术家"); elide: Text.ElideRight; color: AppTheme.textSecondary; font.family: AppTheme.fontFamily; font.pixelSize: 12 }
                    Text { width: parent.width; text: result.modelData.album || qsTr("未提供专辑"); elide: Text.ElideRight; color: AppTheme.textMuted; font.family: AppTheme.fontFamily; font.pixelSize: 11 }
                    Text { text: (result.modelData.duration || "") + qsTr("    相关度 ") + result.modelData.score + "%"; color: result.selected ? AppTheme.accent : AppTheme.textMuted; font.pixelSize: 10 }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: popup.choose(result.index) }
            }
            Basic.ScrollBar.vertical: Basic.ScrollBar { width: 0; visible: false; policy: Basic.ScrollBar.AlwaysOff }
            Text {
                anchors.centerIn: parent; width: parent.width - 28; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                visible: !popup.results.length
                text: popup.controller && popup.controller.metadataMatchBusy ? qsTr("正在搜索…") : popup.controller ? popup.controller.metadataMatchError : ""
                color: AppTheme.textSecondary; font.family: AppTheme.fontFamily; font.pixelSize: 13
            }
        }
        Column {
            x: candidates.width + 16; y: 120; width: parent.width - x; spacing: 8
            Text { text: qsTr("选择要填入的字段"); color: AppTheme.textSecondary; font.family: AppTheme.fontFamily; font.pixelSize: 11 }
            Repeater {
                model: [{key:"title", label:qsTr("歌曲名")}, {key:"artist", label:qsTr("艺术家")}, {key:"album", label:qsTr("专辑名")}]
                Rectangle {
                    id: field
                    required property var modelData
                    readonly property string newValue: popup.selected[modelData.key] || ""
                    readonly property bool available: newValue.trim().length > 0
                    width: parent.width; height: 72; radius: 12
                    color: AppTheme.darkMode ? "#303945" : "white"; border.color: AppTheme.border
                    Basic.CheckBox {
                        id: check
                        objectName: "metadataField_" + field.modelData.key
                        x: 10; y: 1; width: parent.width - 20; height: 28
                        enabled: field.available
                        checked: field.available && popup.selectedKeys.indexOf(field.modelData.key) >= 0
                        onClicked: popup.toggle(field.modelData.key, checked)
                        indicator: Rectangle { x: 3; y: 6; width: 16; height: 16; radius: 5; color: check.checked ? AppTheme.accent : "transparent"; border.color: check.checked ? AppTheme.accent : AppTheme.textMuted
                            Text { anchors.centerIn: parent; text: check.checked ? "✓" : ""; color: "white"; font.pixelSize: 12 }
                        }
                        contentItem: Text { leftPadding: 28; text: field.modelData.label; verticalAlignment: Text.AlignVCenter; color: AppTheme.textPrimary; font.family: AppTheme.fontFamily; font.pixelSize: 12; font.weight: Font.Medium }
                    }
                    Text { x: 15; y: 31; width: parent.width - 30; text: qsTr("当前   ") + (popup.track[field.modelData.key] || qsTr("未填写")); elide: Text.ElideRight; color: AppTheme.textMuted; font.family: AppTheme.fontFamily; font.pixelSize: 11 }
                    Text { x: 15; y: 50; width: parent.width - 30; text: qsTr("填入   ") + (field.available ? field.newValue : popup.selectedIndex < 0 ? qsTr("请选择左侧结果") : qsTr("来源未提供 · 保留当前值")); elide: Text.ElideRight; color: field.available ? AppTheme.textPrimary : AppTheme.textMuted; font.family: AppTheme.fontFamily; font.pixelSize: 11 }
                }
            }
            Rectangle {
                width: parent.width; height: 146; radius: 12
                color: AppTheme.darkMode ? "#303945" : "white"; border.color: AppTheme.border
                Basic.CheckBox {
                    id: coverCheck
                    objectName: "metadataField_artwork"
                    x: 10; y: 2; height: 28; width: parent.width - 20
                    enabled: !!popup.coverState.url
                    checked: enabled && popup.selectedKeys.indexOf("artwork") >= 0
                    onClicked: popup.toggle("artwork", checked)
                    indicator: Rectangle { x: 3; y: 6; width: 16; height: 16; radius: 5; color: coverCheck.checked ? AppTheme.accent : "transparent"; border.color: coverCheck.checked ? AppTheme.accent : AppTheme.textMuted
                        Text { anchors.centerIn: parent; text: coverCheck.checked ? "✓" : ""; color: "white"; font.pixelSize: 12 }
                    }
                    contentItem: Text { leftPadding: 28; text: qsTr("封面"); verticalAlignment: Text.AlignVCenter; color: AppTheme.textPrimary; font.family: AppTheme.fontFamily; font.pixelSize: 12; font.weight: Font.Medium }
                }
                CoverArt { x: 15; y: 36; width: 80; height: 80; source: popup.track.artwork || ""; cornerRadius: 8; showShadow: false }
                Text { x: 15; y: 122; text: qsTr("当前封面"); color: AppTheme.textMuted; font.pixelSize: 10 }
                IconGlyph { x: 110; y: 65; width: 18; height: 18; kind: "chevronRight"; glyphColor: AppTheme.textMuted }
                CoverArt { objectName: "metadataCoverPreview"; x: 144; y: 36; width: 80; height: 80; source: popup.coverState.url || ""; cornerRadius: 8; showShadow: false }
                Text { x: 144; y: 122; text: qsTr("匹配封面"); color: AppTheme.textMuted; font.pixelSize: 10 }
                Text {
                    x: 240; y: 42; width: parent.width - x - 14; wrapMode: Text.WordWrap
                    text: popup.coverState.busy ? qsTr("正在加载…") : popup.coverState.error || (popup.coverState.url ? popup.coverState.width + " × " + popup.coverState.height + qsTr("\n保存后嵌入音频") : qsTr("请选择左侧结果"))
                    color: AppTheme.textSecondary; font.family: AppTheme.fontFamily; font.pixelSize: 11; lineHeight: 1.4
                }
            }
            Text { width: parent.width; text: qsTr("年份、曲号等其他字段保持原值。填入后可继续编辑，点击「保存」才会写入文件。"); wrapMode: Text.WordWrap; color: AppTheme.textMuted; font.family: AppTheme.fontFamily; font.pixelSize: 11; lineHeight: 1.3 }
        }
        Row {
            anchors.right: parent.right; anchors.bottom: parent.bottom; spacing: 9
            UiButton { objectName: "metadataCancelButton"; height: 36; label: qsTr("取消"); onClicked: popup.close() }
            UiButton {
                objectName: "metadataFillButton"
                height: 36; label: qsTr("填入所选字段"); emphasized: true
                enabled: popup.selectedIndex >= 0 && Object.keys(popup.values).length > 0 && !(popup.coverState.busy && popup.selectedKeys.indexOf("artwork") >= 0)
                opacity: enabled ? 1 : .45
                onClicked: { popup.acceptedValues(popup.values); popup.close() }
            }
        }
    }
}
