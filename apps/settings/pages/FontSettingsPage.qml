import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Dialogs as Dialogs
import Kos.Demo as Demo
import "../../../shared/qml/i18n"
import "../components" as Controls

ColumnLayout {
    id: page
    required property var colors
    property bool materialForm: false
    property var backend: null
    property var bridge: null
    property bool useSystemFont: false
    property string systemFontFamily: ""
    readonly property var fonts: backend && backend.available ? backend.fonts : null
    readonly property var rendering: backend && backend.available ? backend.rendering : null
    readonly property bool ready: fonts !== null && rendering !== null
    readonly property bool antiAliasing: rendering ? rendering.antiAliasing : false
    readonly property var fontRoles: [
        {key: "font", label: I18n.tr("General font")},
        {key: "fixed", label: I18n.tr("Fixed width font")},
        {key: "smallestReadableFont", label: I18n.tr("Small font")},
        {key: "toolBarFont", label: I18n.tr("Toolbar font")},
        {key: "menuFont", label: I18n.tr("Menu font")},
        {key: "activeFont", label: I18n.tr("Window title font")}
    ]
    Layout.fillWidth: true
    spacing: 12

    function applyState(state) {
        if (!state) return;
        useSystemFont = !!state.useSystemFont;
        systemFontFamily = String(state.systemFontFamily || "");
    }
    function refresh() {
        if (backend) backend.refresh();
        if (bridge) bridge.appearanceSnapshot();
    }
    function editable(setting) {
        return ready && backend.renderingEditable(setting);
    }
    function chooseFont(category) {
        fontPicker.category = category;
        fontPicker.selectedFont = fonts[category === "all" ? "font" : category];
        fontPicker.options = Dialogs.FontDialog.DontUseNativeDialog
            | (category === "fixed" ? Dialogs.FontDialog.MonospacedFonts : 0);
        fontPicker.open();
    }
    Component.onCompleted: refresh()
    Connections {
        target: page.bridge
        function onAppearanceSnapshotChanged(state) { page.applyState(state); }
    }
    Connections {
        target: Qt.application
        function onStateChanged() {
            if (Qt.application.state === Qt.ApplicationActive) page.refresh();
        }
    }

    // All input controls use the existing Settings components. The KDE backend
    // holds unsaved values even if this loader is released during navigation.
    component FormRow: Demo.SettingsItem {
        id: row
        property alias label: row.title
        property alias control: control.sourceComponent
        titleColor: page.colors.primaryText
        descriptionColor: page.colors.secondaryText
        Loader { id: control }
    }
    component Section: Demo.SettingsGroup {
        backgroundColor: page.colors.card
        titleColor: page.colors.primaryText
    }
    Text {
        Layout.fillWidth: true
        visible: !page.ready || (page.backend && page.backend.error.length > 0)
        text: page.backend && page.backend.error.length > 0
            ? I18n.tr(page.backend.error) : I18n.tr("Font settings are unavailable.")
        color: page.colors.secondaryText
        wrapMode: Text.Wrap
    }

    Section {
        enabled: page.ready
        Repeater {
            model: page.fontRoles
            delegate: Demo.SettingsItem {
                id: fontRow
                required property var modelData
                objectName: "choose-font-" + modelData.key
                readonly property font selectedFont: page.fonts ? page.fonts[modelData.key] : Qt.font({pointSize: 10})
                title: modelData.label
                enabled: page.ready && page.backend.fontEditable(modelData.key)
                Accessible.description: selectedFont.family + ", " + selectedFont.pointSize + " pt"
                minimumRowHeight: 36
                allowStacking: false
                titleColor: page.colors.primaryText
                activeFocusOnTab: enabled
                Accessible.role: Accessible.Button
                Accessible.onPressAction: page.chooseFont(modelData.key)
                Keys.onReturnPressed: page.chooseFont(modelData.key)
                Keys.onEnterPressed: page.chooseFont(modelData.key)
                Keys.onSpacePressed: page.chooseFont(modelData.key)
                property Item pointer: MouseArea {
                    parent: fontRow
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.chooseFont(fontRow.modelData.key)
                }
                Text {
                    text: fontRow.selectedFont.family
                    font.family: fontRow.selectedFont.family
                    font.pixelSize: 12
                    color: page.colors.secondaryText
                    Layout.maximumWidth: Math.min(280, fontRow.availableWidth * 0.45)
                    elide: Text.ElideRight
                }
                Text {
                    text: fontRow.selectedFont.pointSize + " pt"
                    font.pixelSize: 12
                    color: page.colors.secondaryText
                }
                Demo.VectorIcon {
                    name: "chevron"
                    rotation: -90
                    size: 14
                    color: page.colors.secondaryText
                }
            }
        }
        Demo.SettingsItem {
            id: allFontsRow
            objectName: "adjust-all-fonts"
            title: I18n.tr("Adjust all fonts")
            enabled: page.ready && page.fontRoles.some(role => page.backend.fontEditable(role.key))
            minimumRowHeight: 36
            titleColor: page.colors.primaryText
            activeFocusOnTab: enabled
            Accessible.role: Accessible.Button
            Accessible.onPressAction: page.chooseFont("all")
            Keys.onReturnPressed: page.chooseFont("all")
            Keys.onEnterPressed: page.chooseFont("all")
            Keys.onSpacePressed: page.chooseFont("all")
            property Item pointer: MouseArea {
                parent: allFontsRow
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: page.chooseFont("all")
            }
            Demo.VectorIcon {
                name: "chevron"
                rotation: -90
                size: 14
                color: page.colors.secondaryText
            }
        }
    }

    Section {
        FormRow {
            label: I18n.tr("Desktop follows system font")
            control: Controls.SettingsSwitch {
                objectName: "use-system-font-switch"
                enabled: page.bridge !== null
                checked: page.useSystemFont
                accentColor: page.colors.accent
                onToggled: checked => {
                    if (checked !== page.useSystemFont)
                        page.bridge.updateUseSystemFont(checked);
                }
            }
        }
    }

    Section {
        title: I18n.tr("Font rendering")
        enabled: page.ready
        FormRow {
            label: I18n.tr("Anti-aliasing")
            control: Controls.SettingsSwitch {
                objectName: "font-antialiasing-switch"
                checked: page.antiAliasing
                enabled: page.editable("antiAliasing")
                accentColor: page.colors.accent
                onToggled: checked => page.backend.setRendering("antiAliasing", checked)
            }
        }
        FormRow {
            label: I18n.tr("Exclude a size range from anti-aliasing")
            control: Controls.SettingsSwitch {
                checked: page.rendering ? page.rendering.exclude : false
                enabled: page.antiAliasing && page.editable("exclude")
                accentColor: page.colors.accent
                onToggled: checked => page.backend.setRendering("exclude", checked)
            }
        }
        Demo.SettingsItem {
            title: I18n.tr("Excluded size range")
            titleColor: page.colors.primaryText
            visible: page.antiAliasing && page.rendering !== null && page.rendering.exclude
            RowLayout {
                Demo.SettingsTextField {
                    objectName: "font-exclude-from"
                    implicitWidth: 48
                    filled: true
                    horizontalAlignment: TextInput.AlignHCenter
                    text: page.rendering ? String(page.rendering.excludeFrom) : "8"
                    validator: IntValidator { bottom: 0; top: page.rendering ? page.rendering.excludeTo : 999 }
                    inputMethodHints: Qt.ImhDigitsOnly
                    enabled: page.editable("excludeFrom")
                    onTextEdited: if (acceptableInput) page.backend.setRendering("excludeFrom", Number(text))
                }
                Text { text: "–"; color: page.colors.secondaryText; font.pixelSize: 12 }
                Demo.SettingsTextField {
                    objectName: "font-exclude-to"
                    implicitWidth: 48
                    filled: true
                    horizontalAlignment: TextInput.AlignHCenter
                    text: page.rendering ? String(page.rendering.excludeTo) : "15"
                    validator: IntValidator { bottom: page.rendering ? page.rendering.excludeFrom : 0; top: 999 }
                    inputMethodHints: Qt.ImhDigitsOnly
                    enabled: page.editable("excludeTo")
                    onTextEdited: if (acceptableInput) page.backend.setRendering("excludeTo", Number(text))
                }
                Text { text: "pt"; color: page.colors.secondaryText; font.pixelSize: 12 }
            }
        }
        FormRow {
            label: I18n.tr("Sub-pixel rendering")
            control: Controls.SettingsSelect {
                objectName: "font-subpixel-select"
                colors: page.colors
                model: page.ready ? page.backend.subPixelOptions : []
                currentIndex: page.ready ? page.backend.module.subPixelCurrentIndex : 0
                enabled: page.antiAliasing && page.editable("subPixel")
                onSelectionChanged: index => page.backend.setSubPixel(index)
            }
        }
        FormRow {
            label: I18n.tr("Hinting")
            control: Controls.SettingsSelect {
                objectName: "font-hinting-select"
                colors: page.colors
                model: page.ready ? page.backend.hintingOptions : []
                currentIndex: page.ready ? page.backend.module.hintingCurrentIndex : 0
                enabled: page.antiAliasing && page.editable("hinting")
                onSelectionChanged: index => page.backend.setHinting(index)
            }
        }
        Demo.SettingsItem {
            id: renderingPreviewRow
            title: I18n.tr("Rendering preview")
            titleColor: page.colors.primaryText
            visible: page.ready && page.antiAliasing && page.backend.previewAvailable
            Image {
                id: renderingPreview
                objectName: "font-rendering-preview"
                // Newer Plasma includes DPR in the provider ID; older releases
                // ignore that third field. Older providers also need a focused
                // window, so never request an image while the page is hidden.
                Binding {
                    target: renderingPreview
                    property: "source"
                    when: page.ready && page.antiAliasing && page.backend.previewAvailable && page.Window.active
                    value: page.ready ? "image://preview/" + page.backend.module.subPixelCurrentIndex
                        + "_" + page.backend.module.hintingCurrentIndex + "_" + Screen.devicePixelRatio : ""
                    restoreMode: Binding.RestoreNone
                }
                Layout.preferredWidth: implicitWidth / Screen.devicePixelRatio
                Layout.preferredHeight: implicitHeight / Screen.devicePixelRatio
                Layout.maximumWidth: renderingPreviewRow.availableWidth
                fillMode: Image.PreserveAspectFit
            }
        }
        Demo.SettingsItem {
            visible: page.ready && page.antiAliasing && !page.backend.previewAvailable
            description: I18n.tr("Rendering preview requires XWayland or X11.")
            descriptionColor: page.colors.secondaryText
        }
        FormRow {
            objectName: "font-dpi-row"
            visible: page.ready && page.backend.dpiAvailable && Qt.platform.pluginName === "xcb"
            label: I18n.tr("Force font DPI")
            control: RowLayout {
                Demo.SettingsTextField {
                    implicitWidth: 48
                    filled: true
                    horizontalAlignment: TextInput.AlignHCenter
                    text: page.rendering && page.rendering.dpi > 0 ? String(page.rendering.dpi) : "96"
                    validator: IntValidator { bottom: 1; top: 999 }
                    inputMethodHints: Qt.ImhDigitsOnly
                    enabled: page.editable("dpi") && page.rendering.dpi > 0
                    onTextEdited: if (acceptableInput) page.backend.setRendering("dpi", Number(text))
                }
                Controls.SettingsSwitch {
                    checked: page.rendering ? page.rendering.dpi > 0 : false
                    enabled: page.editable("dpi")
                    accentColor: page.colors.accent
                    onToggled: checked => page.backend.setRendering("dpi", checked ? 96 : 0)
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        text: I18n.tr("Rendering changes may require restarting applications.")
        color: page.colors.secondaryText
        font.pixelSize: 11
        wrapMode: Text.Wrap
    }
    Dialogs.FontDialog {
        id: fontPicker
        objectName: "font-picker"
        property string category: "font"
        title: I18n.tr("Choose a font")
        onAccepted: {
            if (category === "all") allOptions.open();
            else page.backend.setFont(category, selectedFont);
        }
    }
    Demo.LiquidDialog {
        id: allOptions
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(360, parent ? parent.width - 32 : 360)
        title: I18n.tr("Adjust all fonts")
        standardButtons: Dialog.Ok | Dialog.Cancel
        contentItem: ColumnLayout {
            CheckBox { id: applyFamily; text: I18n.tr("Font family"); checked: true }
            CheckBox { id: applyStyle; text: I18n.tr("Font style"); checked: true }
            CheckBox { id: applySize; text: I18n.tr("Font size"); checked: true }
            Text {
                Layout.fillWidth: true
                text: I18n.tr("Fixed-width text keeps a monospaced family. Small text stays smaller.")
                color: page.colors.secondaryText
                wrapMode: Text.Wrap
            }
        }
        onAccepted: page.backend.adjustAllFonts(fontPicker.selectedFont,
            applyFamily.checked, applyStyle.checked, applySize.checked)
    }
}
