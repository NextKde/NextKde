import "../../shared/qml/i18n"
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
                    Text {text:I18n.tr("Spatial wallpaper");color:page.colors.primaryText;font.pixelSize:15;font.weight:Font.DemiBold}
                    Text {
                        // A build made without KOS_BUILD_SPATIAL has no worker
                        // and therefore no spatial.resources capability; say so
                        // instead of offering a switch that cannot do anything.
                        text: page.resources.available === false ? I18n.tr("This build does not include the spatial wallpaper component")
                            : page.resources.busy
                            ? (page.resources.stage || I18n.tr("Preparing…"))
                                + (Number(page.resources.progress) >= 0
                                    ? " · " + Math.round(Number(page.resources.progress) * 100) + "%" : "")
                            : page.resources.checking ? I18n.tr("Checking resources…")
                            : page.resources.enabled ? I18n.tr("On") : I18n.tr("Required resources are downloaded on first enablement")
                        color:page.colors.secondaryText;font.pixelSize:12
                    }
                }
                LiquidControls.LiquidGlassSwitch {
                    id: spatialServiceSwitch
                    objectName: "spatialServiceSwitch"
                    checked: !!page.resources.enabled
                    enabled: page.compatible && page.resources.available !== false
                        && !page.resources.busy && !page.resources.checking
                    accentColor: page.colors.accent
                    trackColor: page.colors.divider
                    onToggled: function(checked) {
                        if(checked) page.bridge.initializeSpatialService()
                        else page.bridge.disableSpatialService()
                    }
                }
            }
            Text {
                text:I18n.tr("Cache: ") + (Number(page.resources.generatedBytes || 0)/1073741824).toFixed(2) + I18n.tr(" / 2 GB · oldest entries are pruned automatically")
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
