pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

KosDialog {
    id: root
    objectName: "kosSettingsDialog"

    property var settings: null
    property bool inWindowMaterials: false
    property bool inWindowSamplingAvailable: false
    property Component toolTipBackground: null
    readonly property bool localGlassActive: inWindowMaterials && inWindowSamplingAvailable
        && settings && settings.materialMode !== "solid" && !settings.reduceTransparency
    readonly property real displayedOpacity: !settings ? 1 : inWindowMaterials
        ? (localGlassActive ? settings.materialOpacity : 1) : settings.effectiveMaterialOpacity

    component MaterialTip: ToolTip {
        id: tip
        popupType: Popup.Item
        delay: 500
        timeout: 5000
        padding: 8
        margins: 8
        x: parent ? (parent.width - width) / 2 : 0
        y: parent ? parent.height + 6 : 0
        contentItem: Label { text: tip.text; color: AppTheme.text; font.pixelSize: 12 }
        background: Loader { sourceComponent: root.toolTipBackground }
    }

    property string applicationName: qsTr("Application")
    readonly property var accentChoices: [
        { key: "system", label: qsTr("System accent"), color: AppTheme.systemAccent },
        { key: "blue", label: qsTr("Blue"), color: AppTheme.defaultAccentSeed },
        { key: "purple", label: qsTr("Purple"), color: AppTheme.purpleAccentSeed },
        { key: "green", label: qsTr("Green"), color: AppTheme.greenAccentSeed },
        { key: "orange", label: qsTr("Orange"), color: AppTheme.orangeAccentSeed }
    ]

    parent: Overlay.overlay
    title: qsTr("%1 Settings").arg(applicationName)
    anchors.centerIn: parent
    width: Math.min(580, parent ? parent.width - 40 : 580)
    height: Math.min(650, parent ? parent.height - 40 : 650)
    popupType: Popup.Item
    modal: true
    focus: true
    padding: 0
    closePolicy: Popup.CloseOnEscape

    function appearanceIndex() {
        if (!settings || settings.appearanceMode === "system") return 0
        return settings.appearanceMode === "light" ? 1 : 2
    }

    function materialIndex() {
        if (!settings || settings.materialMode === "auto") return 0
        return settings.materialMode === "glass" ? 1 : 2
    }

    Shortcut {
        sequences: [StandardKey.Preferences]
        onActivated: root.open()
    }

    Overlay.modal: Rectangle {
        radius: AppTheme.modernDesign && root.ApplicationWindow.window ? root.ApplicationWindow.window.windowCornerRadius || 0 : 0
        color: AppTheme.withAlpha(AppTheme.blackSeed, AppTheme.dark ? 0.42 : 0.24)
    }

    background: Rectangle {
        radius: AppTheme.largeRadius
        color: root.inWindowMaterials
            ? (AppTheme.dark ? "#2C2C2E" : "#F7F7F9") : AppTheme.cardSurface
        border.width: 1
        border.color: AppTheme.border

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.width: 1
            border.color: AppTheme.withAlpha(AppTheme.whiteSeed,
                                             AppTheme.dark ? 0.06 : 0.58)
        }
    }

    header: Item {
        implicitHeight: 72

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 24
            anchors.rightMargin: 18
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: 11
                color: AppTheme.withAlpha(AppTheme.accent,
                                          AppTheme.dark ? 0.22 : 0.14)

                Label {
                    anchors.centerIn: parent
                    text: "⚙"
                    color: AppTheme.accent
                    font.pixelSize: 20
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Label {
                    text: qsTr("%1 Settings").arg(root.applicationName)
                    color: AppTheme.text
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                }
                Label {
                    text: qsTr("Appearance is shared across KOS applications")
                    color: AppTheme.mutedText
                    font.pixelSize: 11
                }
            }

            KosToolButton {
                id: closeSettings
                objectName: "settingsClose"
                text: "×"
                font.pixelSize: 18
                Accessible.name: qsTr("Close settings")
                ToolTip.visible: !root.toolTipBackground && hovered
                ToolTip.text: Accessible.name
                MaterialTip {
                    objectName: "settingsCloseTip"
                    visible: root.toolTipBackground !== null && closeSettings.hovered && !closeSettings.pressed
                    text: closeSettings.Accessible.name
                }
                onClicked: root.close()
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: AppTheme.border
        }
    }

    contentItem: ScrollView {
        id: scroller
        Accessible.name: root.title
        clip: true
        leftPadding: 22
        rightPadding: 22
        topPadding: 18
        bottomPadding: 18
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            width: scroller.availableWidth
            spacing: 14

            Label {
                text: qsTr("APPEARANCE")
                color: AppTheme.mutedText
                font.pixelSize: 11
                font.weight: Font.DemiBold
                Layout.leftMargin: 4
            }

            KosCard {
                Layout.fillWidth: true

                contentItem: ColumnLayout {
                    spacing: 16

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 18

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 2
                            Label { text: qsTr("Color scheme"); color: AppTheme.text }
                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: qsTr("Follow KDE or choose a fixed appearance")
                                color: AppTheme.mutedText
                                font.pixelSize: 11
                            }
                        }

                        LiquidSegmentedControl {
                            materialForm: root.inWindowMaterials || ControlForm.materialForm
                            focusColor: root.inWindowMaterials ? AppTheme.focusRing : AppTheme.accent
                            backgroundColor: root.inWindowMaterials
                                ? (AppTheme.dark ? "#3A3A3C" : "#EDEDF0") : AppTheme.button
                            selectionColor: root.inWindowMaterials
                                ? (AppTheme.dark ? "#636368" : "#FFFFFF") : AppTheme.cardHover
                            Layout.preferredWidth: 230
                            objectName: "settingsAppearanceSelector"
                            labels: [qsTr("System"), qsTr("Light"), qsTr("Dark")]
                            currentIndex: root.appearanceIndex()
                            onSelectionRequested: function(index) {
                                if (root.settings)
                                    root.settings.appearanceMode = ["system", "light", "dark"][index]
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: AppTheme.border
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 18

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 2
                            Label { text: root.inWindowMaterials ? qsTr("Liquid material") : qsTr("Window material"); color: AppTheme.text }
                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: root.inWindowMaterials ? qsTr("Applies to controls and floating panels")
                                    : root.settings && root.settings.nativeBlurAvailable
                                    ? qsTr("KWin native blur is available")
                                    : qsTr("Uses a readable solid fallback when blur is unavailable")
                                color: !root.inWindowMaterials && root.settings && root.settings.nativeBlurAvailable
                                    ? AppTheme.positive : AppTheme.mutedText
                                font.pixelSize: 11
                            }
                        }

                        LiquidSegmentedControl {
                            materialForm: root.inWindowMaterials || ControlForm.materialForm
                            focusColor: root.inWindowMaterials ? AppTheme.focusRing : AppTheme.accent
                            backgroundColor: root.inWindowMaterials
                                ? (AppTheme.dark ? "#3A3A3C" : "#EDEDF0") : AppTheme.button
                            selectionColor: root.inWindowMaterials
                                ? (AppTheme.dark ? "#636368" : "#FFFFFF") : AppTheme.cardHover
                            Layout.preferredWidth: 230
                            objectName: "settingsMaterialSelector"
                            labels: [qsTr("Auto"), qsTr("Glass"), qsTr("Solid")]
                            currentIndex: root.materialIndex()
                            onSelectionRequested: function(index) {
                                if (root.settings)
                                    root.settings.materialMode = ["auto", "glass", "solid"][index]
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: AppTheme.border
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 2
                            Label { text: qsTr("Material opacity"); color: AppTheme.text }
                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: root.inWindowMaterials ? qsTr("Higher values make liquid surfaces more opaque")
                                    : qsTr("Higher values improve contrast over detailed wallpapers")
                                color: AppTheme.mutedText
                                font.pixelSize: 11
                            }
                        }

                        KosSlider {
                            objectName: "settingsMaterialOpacity"
                            Layout.preferredWidth: 190
                            from: root.inWindowMaterials || (root.settings && root.settings.nativeBlurAvailable)
                                ? 0.72 : 0.93
                            to: 0.98
                            stepSize: 0.01
                            enabled: root.inWindowMaterials ? root.localGlassActive
                                : root.settings && root.settings.glassActive && !root.settings.reduceTransparency
                            value: root.displayedOpacity
                            Accessible.name: qsTr("Material opacity")
                            onMoved: if (root.settings)
                                root.settings.materialOpacity = value
                        }

                        Label {
                            Layout.preferredWidth: 38
                            text: Math.round(root.displayedOpacity * 100) + "%"
                            color: AppTheme.mutedText
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            }

            Label {
                text: qsTr("ACCENT COLOR")
                color: AppTheme.mutedText
                font.pixelSize: 11
                font.weight: Font.DemiBold
                Layout.leftMargin: 4
            }

            KosCard {
                Layout.fillWidth: true

                contentItem: RowLayout {
                    spacing: 13

                    ButtonGroup { id: accentGroup }

                    Repeater {
                        model: root.accentChoices

                        delegate: AbstractButton {
                            id: accentButton
                            required property var modelData
                            Layout.preferredWidth: 38
                            Layout.preferredHeight: 38
                            checkable: true
                            ButtonGroup.group: accentGroup
                            checked: root.settings
                                && root.settings.accentName === modelData.key
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: modelData.label
                            Accessible.checked: checked
                            ToolTip.visible: !root.toolTipBackground && hovered
                            ToolTip.text: modelData.label
                            MaterialTip {
                                visible: root.toolTipBackground !== null && accentButton.hovered && !accentButton.pressed
                                text: accentButton.modelData.label
                            }
                            onClicked: if (root.settings)
                                root.settings.accentName = modelData.key

                            contentItem: Label {
                                text: accentButton.checked ? "✓" : ""
                                color: AppTheme.contrastRatio(
                                           accentButton.modelData.color,
                                           AppTheme.blackSeed)
                                       >= AppTheme.contrastRatio(
                                           accentButton.modelData.color,
                                           AppTheme.whiteSeed)
                                    ? AppTheme.blackSeed : AppTheme.whiteSeed
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                font.weight: Font.Bold
                            }

                            background: Rectangle {
                                radius: 12
                                color: accentButton.modelData.color
                                border.width: accentButton.activeFocus ? 3 : 1
                                border.color: accentButton.activeFocus
                                    ? AppTheme.text : AppTheme.withAlpha(AppTheme.whiteSeed, 0.44)
                                scale: accentButton.down ? 0.94 : 1
                                Behavior on scale {
                                    NumberAnimation { duration: AppTheme.motionFast }
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Label {
                        text: qsTr("Applied instantly")
                        color: AppTheme.mutedText
                        font.pixelSize: 11
                    }
                }
            }

            Label {
                text: qsTr("ACCESSIBILITY")
                color: AppTheme.mutedText
                font.pixelSize: 11
                font.weight: Font.DemiBold
                Layout.leftMargin: 4
            }

            KosCard {
                Layout.fillWidth: true

                contentItem: ColumnLayout {
                    spacing: 14

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 2
                            Label { text: qsTr("Reduce transparency"); color: AppTheme.text }
                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: qsTr("Use fully opaque surfaces for maximum readability")
                                color: AppTheme.mutedText
                                font.pixelSize: 11
                            }
                        }
                        KosSwitch {
                            checked: root.settings
                                ? root.settings.reduceTransparency : false
                            accessibleName: qsTr("Reduce transparency")
                            onToggled: function(checked) {
                                if (root.settings)
                                    root.settings.reduceTransparency = checked
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: AppTheme.border
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 2
                            Label { text: qsTr("Reduce motion"); color: AppTheme.text }
                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: qsTr("Disable decorative color and movement transitions")
                                color: AppTheme.mutedText
                                font.pixelSize: 11
                            }
                        }
                        KosSwitch {
                            checked: root.settings ? root.settings.reduceMotion : false
                            accessibleName: qsTr("Reduce motion")
                            onToggled: function(checked) {
                                if (root.settings)
                                    root.settings.reduceMotion = checked
                            }
                        }
                    }
                }
            }
        }
    }

    footer: Item {
        implicitHeight: 68

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: AppTheme.border
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 22
            anchors.rightMargin: 22

            KosButton {
                text: qsTr("Restore Defaults")
                onClicked: if (root.settings)
                    root.settings.resetAppearance()
            }
            Item { Layout.fillWidth: true }
            KosButton {
                text: qsTr("Done")
                highlighted: true
                onClicked: root.close()
            }
        }
    }
}
