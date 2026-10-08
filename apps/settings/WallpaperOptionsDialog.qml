import QtQuick
import "../../shared/qml/foundation/WallpaperCatalog.js" as WallpaperCatalog
import QtQuick.Controls
import QtQuick.Layouts
import "../../shared/qml/controls" as LiquidControls

Dialog {
    id: dialog
    property var colors
    property string fitMode: "crop"
    property string transition: "cinematic"
    property bool takeoverEnabled: false
    property bool takeoverAvailable: false
    property bool takeoverPending: false
    signal fitChosen(string mode)
    signal transitionChosen(string style)
    signal takeoverChosen(bool enabled)
    title: I18n.tr("Wallpaper options")
    background: Rectangle {
        radius: 22
        color: dialog.colors.dark ? "#ed25282e" : "#f8f9fbfd"
        border.color: dialog.colors.dark ? "#62ffffff" : "#aaffffff"
        border.width: 1
    }
    header: Text {
        text: dialog.title
        color: dialog.colors.primaryText
        font.pixelSize: 16
        font.weight: Font.DemiBold
        leftPadding: 18
        topPadding: 17
        bottomPadding: 12
    }
    modal: true
    width: 420
    anchors.centerIn: Overlay.overlay
    footer: Item {
        implicitHeight: 48
        WallpaperTextButton {
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            label: I18n.tr("Done")
            colors: dialog.colors
            emphasized: true
            onClicked: dialog.close()
        }
    }
    contentItem: ColumnLayout {
        spacing: 8
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: rows.implicitHeight
            radius: 18
            color: dialog.colors.card
            Column {
                id: rows
                width: parent.width
                WallpaperSettingsRow {
                    width: parent.width
                    colors: dialog.colors
                    label: I18n.tr("Fill mode")
                    separator: true
                    LiquidControls.LiquidSelect {
                        objectName: "wallpaperFitMenu"
                        accentColor: dialog.colors.accent
                        model: [I18n.tr("Fill the screen"), I18n.tr("Show in full"), I18n.tr("Stretch"), I18n.tr("Centered")]
                        currentIndex: Math.max(0, ["crop", "fit", "stretch", "center"].indexOf(dialog.fitMode))
                        onActivated: function(index) {
                            dialog.fitChosen(["crop", "fit", "stretch", "center"][index])
                        }
                    }
                }
                WallpaperSettingsRow {
                    width: parent.width
                    colors: dialog.colors
                    label: I18n.tr("Switch effect")
                    separator: true
                    LiquidControls.LiquidSelect {
                        objectName: "wallpaperTransitionMenu"
                        accentColor: dialog.colors.accent
                        model: WallpaperCatalog.transitions
                        textRole: "label"
                        currentIndex: Math.max(0, WallpaperCatalog.transitions.map(item => item.id).indexOf(dialog.transition))
                        onActivated: function(index) {
                            dialog.transitionChosen(WallpaperCatalog.transitions[index].id)
                        }
                    }
                }
                WallpaperSettingsRow {
                    width: parent.width
                    colors: dialog.colors
                    label: I18n.tr("KOS draws the wallpaper")
                    LiquidControls.LiquidGlassSwitch {
                        id: toggle
                        enabled: dialog.takeoverAvailable && !dialog.takeoverPending
                        checked: dialog.takeoverEnabled
                        accentColor: dialog.colors.accent
                        trackColor: dialog.colors.divider
                        onToggled: function(checked) {
                            dialog.takeoverChosen(checked)
                            toggle.checked = Qt.binding(() => dialog.takeoverEnabled)
                        }
                    }
                }
            }
        }
        Text {
            Layout.fillWidth: true
            text: dialog.takeoverAvailable
                ? I18n.tr("Restores the Plasma wallpaper when KOS wallpaper is turned off. Enabling spatial wallpaper pauses auto-switching.")
                : I18n.tr("The current platform service version does not support wallpaper takeover; please update first.")
            color: dialog.colors.secondaryText
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }
    }
}
