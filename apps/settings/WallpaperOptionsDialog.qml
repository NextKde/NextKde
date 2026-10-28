import "components" as SettingsControls
import Kos.Demo as Demo
import "../../shared/qml/i18n"
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
        Demo.SettingsGroup {
            backgroundColor: dialog.colors.card
            WallpaperSettingsRow {

                colors: dialog.colors
                label: I18n.tr("Fill mode")
                separator: true
                SettingsControls.SettingsSelect {
                    colors: dialog.colors
                    implicitHeight: 24
                    Layout.preferredHeight: 24
                    objectName: "wallpaperFitMenu"
                    accentColor: dialog.colors.accent
                    model: [I18n.tr("Fill the screen"), I18n.tr("Show in full"), I18n.tr("Stretch"), I18n.tr("Centered")]
                    currentIndex: Math.max(0, ["crop", "fit", "stretch", "center"].indexOf(dialog.fitMode))
                    onActivated: function (index) {
                        dialog.fitChosen(["crop", "fit", "stretch", "center"][index]);
                    }
                }
            }
            WallpaperSettingsRow {

                colors: dialog.colors
                label: I18n.tr("Switch effect")
                separator: true
                SettingsControls.SettingsSelect {
                    colors: dialog.colors
                    implicitHeight: 24
                    Layout.preferredHeight: 24
                    objectName: "wallpaperTransitionMenu"
                    accentColor: dialog.colors.accent
                    model: WallpaperCatalog.transitions.map(item => Object.assign({}, item, {
                            label: I18n.tr(item.label)
                        }))
                    textRole: "label"
                    currentIndex: Math.max(0, WallpaperCatalog.transitions.map(item => item.id).indexOf(dialog.transition))
                    onActivated: function (index) {
                        dialog.transitionChosen(WallpaperCatalog.transitions[index].id);
                    }
                }
            }
            WallpaperSettingsRow {
                description: dialog.takeoverAvailable ? I18n.tr("Restores the Plasma wallpaper when KOS wallpaper is turned off. Enabling spatial wallpaper pauses auto-switching.") : I18n.tr("The current platform service version does not support wallpaper takeover; please update first.")

                colors: dialog.colors
                label: I18n.tr("KOS draws the wallpaper")
                SettingsControls.SettingsSwitch {
                    id: toggle
                    enabled: dialog.takeoverAvailable && !dialog.takeoverPending
                    checked: dialog.takeoverEnabled
                    accentColor: dialog.colors.accent
                    trackColor: dialog.colors.divider
                    onToggled: function (checked) {
                        dialog.takeoverChosen(checked);
                        toggle.checked = Qt.binding(() => dialog.takeoverEnabled);
                    }
                }
            }
        }
    }
}
