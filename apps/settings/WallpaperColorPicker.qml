import Kos.Demo as Demo
import "components" as SettingsControls
import "../../shared/qml/i18n"
import "../../shared/qml/controls" as SharedControls
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../shared/qml/controls" as LiquidControls
import "../../shared/qml/foundation/WallpaperCatalog.js" as WallpaperCatalog

Dialog {
    id: picker
    property var colors: ({
            card: "#283545",
            primaryText: "white",
            secondaryText: "#aeb8c5",
            accent: "#70A0F5"
        })
    property color selectedColor: "#70A0F5"
    property int selectedTab: 0
    property string errorMessage: ""
    signal colorApplied(color value)
    signal eyedropperRequested
    property bool eyedropperAvailable: false
    objectName: "customWallpaperColorDialog"
    modal: true
    anchors.centerIn: Overlay.overlay
    width: Math.min(450, parent ? parent.width - 32 : 450)
    padding: 20
    standardButtons: Dialog.NoButton
    background: Rectangle {
        radius: 26
        color: picker.colors.card
    }
    function setRgb(channel, value) {
        selectedColor = Qt.rgba(channel === 0 ? value : selectedColor.r, channel === 1 ? value : selectedColor.g, channel === 2 ? value : selectedColor.b, 1);
    }
    function gridColor(index) {
        const row = Math.floor(index / 12), col = index % 12;
        if (row === 0)
            return Qt.rgba(1 - col / 11, 1 - col / 11, 1 - col / 11, 1);
        const hues = [0.54, 0.61, 0.71, 0.79, 0.91, 0.015, 0.065, 0.105, 0.135, 0.17, 0.21, 0.28];
        return Qt.hsva(hues[col], row > 5 ? Math.max(0.12, 1 - (row - 5) * 0.22) : 0.93, row > 5 ? 1 : 0.18 + row * 0.15, 1);
    }
    contentItem: ColumnLayout {
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            Demo.LiquidActionButton {
                materialForm: true
                implicitHeight: 24
                cornerRadius: 6
                objectName: "wallpaperEyedropper"
                visible: picker.eyedropperAvailable
                text: I18n.tr("Pick color")
                Accessible.name: I18n.tr("Pick color from screen")
                onClicked: picker.eyedropperRequested()
            }
            Label {
                text: I18n.tr("Color")
                color: picker.colors.primaryText
                font.pixelSize: 18
                font.weight: Font.DemiBold
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }
            Demo.LiquidActionButton {
                materialForm: true
                implicitHeight: 24
                cornerRadius: 6
                contentItem: SharedControls.VectorIcon {
                    name: "close"
                    size: 20
                    color: picker.colors.primaryText
                }
                Accessible.name: I18n.tr("Close")
                onClicked: picker.close()
            }
        }
        SettingsControls.SettingsSelect {
            textRole: "label"

            colors: picker.colors
            currentIndex: picker.selectedTab
            model: [I18n.tr("Grid"), I18n.tr("Spectrum"), I18n.tr("Slider")].map(label => ({
                        label: label
                    }))
            onSelectionChanged: function (index) {
                picker.selectedTab = index;
            }
        }
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: picker.selectedTab === 2 ? 152 : 290
            Grid {
                visible: picker.selectedTab === 0
                anchors.fill: parent
                columns: 12
                rows: 10
                Repeater {
                    model: 120
                    Rectangle {
                        required property int index
                        width: parent.width / 12
                        height: parent.height / 10
                        color: picker.gridColor(index)
                        border.width: picker.selectedColor.toString() === color.toString() ? 2 : 0
                        border.color: picker.colors.primaryText
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: picker.selectedColor = parent.color
                        }
                    }
                }
            }
            Canvas {
                id: spectrum
                visible: picker.selectedTab === 1
                anchors.fill: parent
                onVisibleChanged: if (visible)
                    requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    for (let x = 0; x < 72; x++)
                        for (let y = 0; y < 48; y++) {
                            ctx.fillStyle = Qt.hsla(x / 71, 1, 1 - y / 47, 1).toString();
                            ctx.fillRect(x * width / 72, y * height / 48, Math.ceil(width / 72), Math.ceil(height / 48));
                        }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.CrossCursor
                    function pick(mouse) {
                        picker.selectedColor = Qt.hsla(Math.max(0, Math.min(1, mouse.x / width)), 1, 1 - Math.max(0, Math.min(1, mouse.y / height)), 1);
                    }
                    onPressed: function (mouse) {
                        pick(mouse);
                    }
                    onPositionChanged: function (mouse) {
                        if (pressed)
                            pick(mouse);
                    }
                }
                Rectangle {
                    width: 14
                    height: 14
                    radius: 7
                    color: "transparent"
                    border.width: 2
                    border.color: "white"
                    x: Math.max(0, picker.selectedColor.hslHue) * parent.width - width / 2
                    y: (1 - picker.selectedColor.hslLightness) * parent.height - height / 2
                }
            }
            Demo.SettingsGroup {
                visible: picker.selectedTab === 2
                anchors.fill: parent
                backgroundColor: picker.colors.card
                Repeater {
                    model: [I18n.tr("Red"), I18n.tr("Green"), I18n.tr("Blue")]
                    delegate: Demo.SettingsItem {
                        required property int index
                        required property string modelData
                        title: modelData
                        Text {
                            text: Math.round([picker.selectedColor.r, picker.selectedColor.g, picker.selectedColor.b][index] * 255)
                            color: picker.colors.secondaryText
                            font.pixelSize: 12
                        }
                        LiquidControls.ColorRampSlider {
                            Layout.preferredWidth: 170
                            Layout.preferredHeight: 24
                            thumbDiameter: 14
                            trackHeight: 4
                            value: [picker.selectedColor.r, picker.selectedColor.g, picker.selectedColor.b][index]
                            thumbColor: picker.selectedColor
                            rampColors: Array.from({
                                length: 7
                            }, (_, i) => Qt.rgba(index === 0 ? i / 6 : picker.selectedColor.r, index === 1 ? i / 6 : picker.selectedColor.g, index === 2 ? i / 6 : picker.selectedColor.b, 1))
                            onPreviewChanged: function (value) {
                                picker.setRgb(index, value);
                            }
                            onCommitRequested: function (value) {
                                picker.setRgb(index, value);
                            }
                        }
                    }
                }
                Demo.SettingsItem {
                    Demo.LiquidTextField {
                        implicitWidth: 170
                        implicitHeight: 24
                        materialForm: true
                        Layout.preferredWidth: 170

                        text: picker.selectedColor.toString().toUpperCase()
                        placeholderText: "#RRGGBB"
                        maximumLength: 7
                        onEditingFinished: {
                            if (/^#[0-9a-fA-F]{6}$/.test(text))
                                picker.selectedColor = text;
                            else
                                text = picker.selectedColor.toString().toUpperCase();
                        }
                    }
                }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Qt.rgba(0.5, 0.5, 0.5, 0.2)
        }
        RowLayout {
            Layout.fillWidth: true
            Rectangle {
                width: 68
                height: 68
                radius: 18
                color: picker.selectedColor
            }
            Grid {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                columns: 5
                columnSpacing: 14
                rowSpacing: 12
                Repeater {
                    model: ["#000000", "#006AFF", "#35C759", "#FFCC00", "#FF453A", "#FF9500", "#3D238E", "#FF8954", "#AB7100", "#FFDA47"]
                    Rectangle {
                        required property string modelData
                        width: 30
                        height: 30
                        radius: 15
                        color: modelData
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: picker.selectedColor = parent.color
                        }
                    }
                }
            }
        }
        Label {
            Layout.fillWidth: true
            text: picker.errorMessage
            visible: text.length > 0
            wrapMode: Text.Wrap
            color: "#e66f73"
        }
        RowLayout {
            Layout.alignment: Qt.AlignRight
            Demo.LiquidActionButton {
                materialForm: true
                implicitHeight: 24
                cornerRadius: 6
                text: I18n.tr("Cancel")
                onClicked: picker.close()
            }
            Demo.LiquidActionButton {
                materialForm: true
                implicitHeight: 24
                cornerRadius: 6
                text: I18n.tr("Use this color")
                onClicked: picker.colorApplied(picker.selectedColor)
            }
        }
    }
}
