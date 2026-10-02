import QtQuick
import QtQuick.Layouts
import "../../shared/qml/controls" as LiquidControls

ColumnLayout {
    id: page
    property var bridge: null
    property var colors
    property var resources: ({})
    property string errorText: ""
    readonly property bool compatible: !!bridge && typeof bridge.initializeSpatialService === "function"
    spacing: 16
    function refresh() { if(compatible) bridge.wallpaperSnapshot() }
    Component.onCompleted: { if(compatible) bridge.inspectSpatialService(); refresh() }
    Connections {
        target: page.bridge
        ignoreUnknownSignals: true
        function onWallpaperSnapshotChanged(state) {
            page.resources=state.spatialResources || ({})
            page.errorText=page.resources.error || ""
        }
    }
    Timer {interval:1000;running:page.visible && page.compatible;repeat:true;onTriggered:page.refresh()}
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: content.implicitHeight+32
        radius: 18
        color: page.colors.card
        ColumnLayout {
            id: content
            anchors {left:parent.left;right:parent.right;top:parent.top;margins:16}
            spacing: 12
            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    Layout.fillWidth: true
                    Text {text:"空间壁纸";color:page.colors.primaryText;font.pixelSize:15;font.weight:Font.DemiBold}
                    Text {
                        text: page.resources.busy
                            ? (page.resources.stage || "正在准备…")
                                + (Number(page.resources.progress) >= 0
                                    ? " · " + Math.round(Number(page.resources.progress) * 100) + "%" : "")
                            : page.resources.checking ? "正在检查资源…"
                            : page.resources.enabled ? "已开启" : "首次开启会下载所需资源"
                        color:page.colors.secondaryText;font.pixelSize:12
                    }
                }
                LiquidControls.LiquidGlassSwitch {
                    checked: !!page.resources.enabled
                    enabled: page.compatible && !page.resources.busy && !page.resources.checking
                    accentColor: page.colors.accent
                    trackColor: page.colors.divider
                    onToggled: function(checked) {
                        if(checked) page.bridge.initializeSpatialService()
                        else page.bridge.disableSpatialService()
                    }
                }
            }
            Text {
                text:"缓存 " + (Number(page.resources.generatedBytes || 0)/1073741824).toFixed(2) + " / 2 GB · 自动清理最旧内容"
                color:page.colors.secondaryText;font.pixelSize:12
            }
            Text {
                Layout.fillWidth: true
                visible:page.errorText.length>0
                text:page.errorText;wrapMode:Text.Wrap
                color:page.colors.secondaryText;font.pixelSize:12
            }
        }
    }
}
