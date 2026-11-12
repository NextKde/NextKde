import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Kos.Demo as Demo
import Kos.Icons as Symbols
import "../components" as Controls
import "../../../shared/qml/i18n"

ColumnLayout {
    id: page
    objectName: "lockScreenSettingsPage"
    required property var colors
    property var backend: null
    property bool materialForm: false
    readonly property var snapshot: backend ? backend.state : ({})
    property var images: []
    property int thumbnailRevision: 0
    property bool galleryExpanded: false
    property date previewDate: new Date()
    spacing: 12

    function imageUrl(path) {
        return path ? (path.indexOf("file:") === 0 ? path : "file://" + path) : "";
    }
    function reload() {
        if (!backend) return;
        backend.refresh();
        images = backend.wallpaperImages();
    }
    Component.onCompleted: reload()
    Connections {
        target: page.backend
        function onThumbnailReady() { page.thumbnailRevision++; }
    }
    Connections {
        target: Qt.application
        function onStateChanged() {
            if (Qt.application.state === Qt.ApplicationActive) page.reload();
        }
    }

    // A picture, not a greeter: no auth context, notification subscription or
    // ScreenSaver request is constructed by previewing or opening this page.
    Rectangle {
        id: preview
        objectName: "lockScreenStaticPreview"
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(300, width * 0.57)
        radius: 14
        color: page.colors.card
        clip: true
        Image {
            anchors.fill: parent
            source: page.imageUrl(page.snapshot.wallpaper || "")
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 1200
            asynchronous: true
        }
        Rectangle { anchors.fill: parent; color: "#50000000" }
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: preview.height * 0.13
            spacing: 0
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.fmt(page.previewDate, I18n.tr("dddd, MMMM d"))
                color: "white"
                font.pixelSize: 15
                font.weight: Font.Medium
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatTime(page.previewDate, "hh:mm")
                color: "white"
                font.pixelSize: Math.min(68, preview.height * 0.25)
                font.weight: Font.DemiBold
            }
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 23
            width: 132
            height: 38
            radius: 19
            color: "#45ffffff"
            Row {
                anchors.centerIn: parent
                spacing: 9
                Symbols.Icon { name: "person"; size: 20; color: "white" }
                Text { text: I18n.tr("Your account"); color: "white"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
            }
        }
    }
    Text {
        Layout.fillWidth: true
        text: I18n.tr("Static preview only. Your session will not be locked.")
        color: page.colors.secondaryText
        font.pixelSize: 11
        wrapMode: Text.Wrap
    }

    Demo.SettingsGroup {
        title: I18n.tr("Lock screen style")
        backgroundColor: page.colors.card
        Demo.SettingsItem {
            title: I18n.tr("Theme")
            description: I18n.tr("Changing the lock screen does not change your desktop.")
            Controls.SettingsSelect {
                objectName: "lockScreenThemeSelect"
                colors: page.colors
                materialForm: page.materialForm
                model: [I18n.tr("System default"), I18n.tr("KOS (MacLock style)")]
                currentIndex: page.snapshot.active ? 1 : 0
                enabled: !!page.backend && page.snapshot.canChangeTheme === true
                onActivated: function(index) { page.backend.setTheme(index === 1 ? "kos" : "system"); }
            }
        }
        Demo.SettingsItem {
            title: I18n.tr("KOS resources")
            description: page.snapshot.active ? I18n.tr("Active")
                : page.snapshot.installed ? I18n.tr("Installed, not active")
                : page.snapshot.available ? I18n.tr("Available") : I18n.tr("Unavailable")
        }
    }
    Text {
        objectName: "lockScreenError"
        visible: text.length > 0
        Layout.fillWidth: true
        text: page.snapshot.error ? I18n.tr(page.snapshot.error) : ""
        color: page.colors.secondaryText
        font.pixelSize: 12
        wrapMode: Text.Wrap
    }

    Demo.SettingsGroup {
        title: I18n.tr("Lock screen wallpaper")
        backgroundColor: page.colors.card
        Demo.SettingsItem {
            title: I18n.tr("Choose an image")
            description: I18n.tr("Only the lock screen wallpaper changes. Your desktop stays the same.")
            Controls.SettingsTextButton {
                objectName: "lockScreenChooseFile"
                label: I18n.tr("Choose file…")
                colors: page.colors
                enabled: !!page.backend
                onClicked: wallpaperFile.open()
            }
        }
    }
    GridLayout {
        Layout.fillWidth: true
        columns: page.width >= 540 ? 4 : 3
        columnSpacing: 10
        rowSpacing: 10
        Repeater {
            model: page.galleryExpanded ? page.images : Array.prototype.slice.call(page.images, 0, 12)
            delegate: Button {
                id: tile
                required property string modelData
                objectName: "lockScreenWallpaperTile"
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(74, width * 0.6)
                Accessible.name: I18n.tr("Use lock screen wallpaper") + " " + modelData.split("/").pop()
                onClicked: page.backend.setWallpaper(modelData)
                background: Rectangle {
                    radius: 10
                    color: page.colors.card
                    border.width: tile.activeFocus || page.imageUrl(tile.modelData) === page.snapshot.wallpaper ? 2 : 0
                    border.color: page.colors.accent
                }
                contentItem: Image {
                    source: {
                        const revision = page.thumbnailRevision;
                        return page.backend ? page.backend.wallpaperThumbnail(tile.modelData, 360, 216) : "";
                    }
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
            }
        }
    }
    Controls.SettingsTextButton {
        visible: !page.galleryExpanded && page.images.length > 12
        label: I18n.tr("Show all wallpapers")
        colors: page.colors
        onClicked: page.galleryExpanded = true
    }

    Demo.SettingsGroup {
        title: I18n.tr("While locked")
        backgroundColor: page.colors.card
        Demo.SettingsItem {
            title: I18n.tr("Media controls")
            description: I18n.tr("Control playback from the lock screen")
            Controls.SettingsSwitch {
                objectName: "lockScreenMediaSwitch"
                materialForm: page.materialForm
                checked: page.snapshot.showMediaControls !== false
                enabled: !!page.backend
                onToggled: function(checked) { page.backend.setShowMediaControls(checked); }
            }
        }
        Demo.SettingsItem {
            title: I18n.tr("Show notifications")
            description: I18n.tr("Lock screen notifications show app names only, never message content.")
            Controls.SettingsSwitch {
                objectName: "lockScreenNotificationsSwitch"
                materialForm: page.materialForm
                checked: page.snapshot.kosShowNotifications === true
                enabled: !!page.backend && page.snapshot.active === true
                onToggled: function(checked) { page.backend.setShowNotifications(checked); }
            }
        }
        Demo.SettingsItem {
            title: I18n.tr("Lock this session")
            description: I18n.tr("You will need to unlock to return to your desktop.")
            Controls.SettingsTextButton {
                objectName: "lockScreenLockNow"
                label: I18n.tr("Lock now")
                colors: page.colors
                enabled: !!page.backend
                onClicked: page.backend.lockNow()
            }
        }
    }
    FileDialog {
        id: wallpaperFile
        title: I18n.tr("Choose lock screen wallpaper")
        nameFilters: [I18n.tr("Images (*.png *.jpg *.jpeg *.webp *.avif *.bmp)")]
        onAccepted: page.backend.setWallpaper(selectedFile.toString())
    }
}
