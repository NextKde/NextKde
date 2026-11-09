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
    signal backRequested()
    property bool useSystemFont: false
    property string systemFontFamily: ""
    property string statusText: ""
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

    Demo.LiquidActionButton {
        text: I18n.tr("Back to Theme")
        materialForm: true
        onClicked: page.backRequested()
    }
    Text {
        Layout.fillWidth: true
        text: I18n.tr("Choose the fonts used by the system and applications.")
        color: page.colors.secondaryText
        wrapMode: Text.Wrap
        font.pixelSize: 12
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
        FormRow {
            label: I18n.tr("Desktop follows system font")
            description: I18n.tr("Use the general font for the top bar, Dock and desktop controls. Desktop text sizes stay unchanged.")
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
        title: I18n.tr("System fonts")
        enabled: page.ready
        Repeater {
            model: page.fontRoles
            delegate: Demo.SettingsItem {
                id: fontRow
                required property var modelData
                readonly property font selectedFont: page.fonts ? page.fonts[modelData.key] : Qt.font({})
                title: modelData.label
                description: selectedFont.family + " · " + selectedFont.pointSize + " pt"
                titleColor: page.colors.primaryText
                descriptionColor: page.colors.secondaryText
                Text {
                    text: "Aa 字体"
                    font: fontRow.selectedFont
                    color: page.colors.primaryText
                    Layout.maximumWidth: 90
                    elide: Text.ElideRight
                }
                Demo.LiquidActionButton {
                    objectName: "choose-font-" + fontRow.modelData.key
                    text: I18n.tr("Choose…")
                    materialForm: true
                    implicitHeight: 24
                    enabled: page.ready && page.backend.fontEditable(fontRow.modelData.key)
                    onClicked: page.chooseFont(fontRow.modelData.key)
                }
            }
        }
        Demo.SettingsItem {
            title: I18n.tr("Adjust all fonts")
            titleColor: page.colors.primaryText
            Demo.LiquidActionButton {
                text: I18n.tr("Choose…")
                materialForm: true
                implicitHeight: 24
                enabled: page.ready && page.fontRoles.some(role => page.backend.fontEditable(role.key))
                onClicked: page.chooseFont("all")
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
            enabled: page.antiAliasing && page.rendering !== null && page.rendering.exclude
            RowLayout {
                SpinBox {
                    objectName: "font-exclude-from"
                    implicitWidth: 90
                    from: 0
                    to: page.rendering ? page.rendering.excludeTo : 99
                    value: page.rendering ? page.rendering.excludeFrom : 8
                    editable: true
                    enabled: page.editable("excludeFrom")
                    onValueModified: page.backend.setRendering("excludeFrom", value)
                }
                Text { text: I18n.tr("to"); color: page.colors.secondaryText }
                SpinBox {
                    objectName: "font-exclude-to"
                    implicitWidth: 90
                    from: page.rendering ? page.rendering.excludeFrom : 0
                    to: 999
                    value: page.rendering ? page.rendering.excludeTo : 15
                    editable: true
                    enabled: page.editable("excludeTo")
                    onValueModified: page.backend.setRendering("excludeTo", value)
                }
                Text { text: "pt"; color: page.colors.secondaryText }
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
            title: I18n.tr("Rendering preview")
            titleColor: page.colors.primaryText
            visible: page.ready && page.antiAliasing
            Image {
                source: page.ready ? "image://preview/" + page.backend.module.subPixelCurrentIndex
                    + "_" + page.backend.module.hintingCurrentIndex + ".png" : ""
                sourceSize: Qt.size(1, 1)
            }
        }
        FormRow {
            visible: Qt.platform.pluginName === "xcb"
            label: I18n.tr("Force font DPI")
            control: RowLayout {
                SpinBox {
                    from: 1
                    to: 999
                    value: page.rendering && page.rendering.dpi > 0 ? page.rendering.dpi : 96
                    editable: true
                    enabled: page.editable("dpi") && page.rendering.dpi > 0
                    onValueModified: page.backend.setRendering("dpi", value)
                }
                Controls.SettingsSwitch {
                    checked: page.rendering ? page.rendering.dpi > 0 : false
                    enabled: page.editable("dpi")
                    accentColor: page.colors.accent
                    onToggled: checked => page.backend.setRendering("dpi", checked ? 96 : 0)
                }
            }
        }
        Demo.SettingsItem {
            description: I18n.tr("Rendering changes may require restarting applications.")
            descriptionColor: page.colors.secondaryText
        }
    }

    Flow {
        Layout.fillWidth: true
        spacing: 8
        Demo.LiquidActionButton {
            text: I18n.tr("Restore defaults")
            materialForm: true
            enabled: page.ready
            onClicked: { page.backend.defaults(); page.statusText = ""; }
        }
        Demo.LiquidActionButton {
            objectName: "font-reset-button"
            text: I18n.tr("Reset")
            materialForm: true
            enabled: page.ready && page.backend.needsSave
            onClicked: { page.backend.reset(); page.statusText = ""; }
        }
        Demo.LiquidActionButton {
            objectName: "font-apply-button"
            text: I18n.tr("Apply")
            materialForm: true
            highlighted: true
            enabled: page.ready && page.backend.needsSave
            onClicked: {
                page.statusText = page.backend.apply() ? I18n.tr("Font settings applied.") : "";
                if (page.bridge) page.bridge.appearanceSnapshot();
            }
        }
    }
    Text {
        Layout.fillWidth: true
        visible: text.length > 0
        text: page.backend && page.backend.needsSave
            ? I18n.tr("You have unapplied font changes.") : page.statusText
        color: page.colors.secondaryText
        font.pixelSize: 12
        wrapMode: Text.Wrap
    }

    Dialogs.FontDialog {
        id: fontPicker
        property string category: "font"
        title: I18n.tr("Choose a font")
        onAccepted: {
            if (category === "all") allOptions.open();
            else page.backend.setFont(category, selectedFont);
            page.statusText = "";
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
