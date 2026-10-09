pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs

AlertDialog {
    id: dialog
    property var service: null
    property string operation: "export"
    property var selected: []
    property string error: ""
    function begin(mode) {
        if (!service) return
        operation = mode
        selected = service.categories.map(c => c.id)
        error = ""
        if (mode === "import") importPicker.open()
        else open = true
    }
    title: operation === "export" ? qsTr("导出设置") : operation === "import" ? qsTr("导入设置") : qsTr("恢复默认设置")
    message: error.length ? error : qsTr("选择设置分类。账号凭据、音乐文件、歌单和播放队列不在此操作范围内。")
    primaryLabel: operation === "export" ? qsTr("选择保存位置") : qsTr("确认应用")
    contentComponent: Component {
        Column {
            width: parent ? parent.width : 412
            spacing: 8
            Flow {
                width: parent.width; spacing: 8
                Repeater {
                    model: dialog.service ? dialog.service.categories : []
                    delegate: Row {
                        id: choice
                        required property var modelData
                        width: 128; spacing: 6
                        SettingsCheckBox {
                        checked: dialog.selected.indexOf(choice.modelData.id) >= 0
                        onToggled: {
                            const next=dialog.selected.slice()
                            const i=next.indexOf(choice.modelData.id)
                            if(i>=0)next.splice(i,1);else next.push(choice.modelData.id)
                            dialog.selected=next
                        }
                        }
                        Text { text: choice.modelData.name; color: AppTheme.textPrimary; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
            }
            Flickable {
                width: parent.width; height: dialog.operation === "import" ? 180 : 0
                visible: height > 0; clip: true; contentHeight: previewText.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                Text {
                    id: previewText; width: parent.width
                    text: dialog.service ? dialog.service.preview : ""
                    textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere
                    color: AppTheme.textSecondary; font.pixelSize: 12
                }
            }
        }
    }
    onRejected: open = false
    onAccepted: {
        if(!selected.length){error=qsTr("请至少选择一个分类。");return}
        if(operation==="export"){open=false;exportPicker.open()}
        else if(operation==="import" ? service.applyImport(selected) : service.resetDefaults(selected)) open=false
    }
    FileDialog {
        id: exportPicker
        title: qsTr("导出 ListenFree 设置")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "json"
        nameFilters: ["ListenFree Settings (*.json)"]
        onAccepted: dialog.service.exportFile(selectedFile, dialog.selected)
    }
    FileDialog {
        id: importPicker
        title: qsTr("导入 ListenFree 设置")
        nameFilters: ["ListenFree Settings (*.json)"]
        onAccepted: if(dialog.service.inspectFile(selectedFile)) dialog.open=true
    }
}
