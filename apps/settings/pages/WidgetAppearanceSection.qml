import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../../../shared/qml/controls" as LiquidControls
import "../../../shared/qml/foundation" as Foundation
import "../../../shared/qml/i18n"
import "../components" as Controls

ColumnLayout {
    required property var colors
    property bool materialForm: false
    id: widgetAppearance
    Layout.fillWidth: true
    spacing: 7
    property var bridge: null
    property string style: "color"
    property bool loaded: false

    Connections {
        target: widgetAppearance.bridge
        function onAppearanceSnapshotChanged(state) {
            if (!state || (state.widgetStyle !== "color" && state.widgetStyle !== "glass"))
                return
            widgetAppearance.style = state.widgetStyle
            widgetAppearance.loaded = true
        }
    }
    // ThemeSettingsPage requests the snapshot once for all embedded sections.
    property bool suppressInitialRequest: false

    Component.onCompleted: {
        if (bridge && !suppressInitialRequest)
            bridge.appearanceSnapshot()
    }

    Text {
        text: I18n.tr("Widget appearance")
        color: colors.secondaryText
        font.pixelSize: 12
        font.weight: Font.DemiBold
        Layout.leftMargin: 13
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 58
        radius: 18
        color: colors.card
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 12
            Controls.SettingIcon {
                colors: widgetAppearance.colors
                materialForm: widgetAppearance.materialForm
                symbol: "▦"
                tint: "#5ac8fa"
            }
            Text { text: I18n.tr("Card style"); color: colors.primaryText; font.pixelSize: 15; font.weight: Font.DemiBold }
            Item { Layout.fillWidth: true }
            Controls.SettingsNavBar {
                colors: widgetAppearance.colors
                materialForm: widgetAppearance.materialForm
                objectName: "widget-style-picker"
                model: [{ id: "color", label: I18n.tr("Colorful cards") }, { id: "glass", label: I18n.tr("Glass") }]
                itemWidthOverride: 78
                currentIndex: widgetAppearance.style === "glass" ? 1 : 0
                disabled: !widgetAppearance.loaded || widgetAppearance.materialForm
                onSelectionChanged: function(index) {
                    // LiquidNavBar.select() assigns currentIndex. Restore
                    // the binding so failures and later snapshots still
                    // show the confirmed Shell value.
                    currentIndex = Qt.binding(function() {
                        return widgetAppearance.style === "glass" ? 1 : 0
                    })
                    if (widgetAppearance.bridge)
                        widgetAppearance.bridge.updateWidgetStyle(index === 1 ? "glass" : "color")
                }
            }
        }
    }
    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 13
        Layout.rightMargin: 13
        text: widgetAppearance.materialForm
            ? I18n.tr("Material Design uses theme-colored cards; other themes can pick colorful cards or glass separately.")
            : I18n.tr("Glass effects follow the material settings in the theme. This option does not change app icon colors.")
        wrapMode: Text.Wrap
        color: colors.secondaryText
        font.pixelSize: 12
    }
    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 13
        text: widgetAppearance.bridge ? widgetAppearance.bridge.lastError : ""
        visible: text.length > 0
        wrapMode: Text.Wrap
        color: "#ff453a"
        font.pixelSize: 12
    }
}
