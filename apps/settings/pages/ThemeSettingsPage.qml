import Kos.Demo as Demo
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../../../shared/qml/controls" as LiquidControls
import "../../../shared/qml/foundation" as Foundation
import "../../../shared/qml/i18n"
import "../components" as Controls

ColumnLayout {
    id: themePage
    required property var colors
    property bool materialForm: false
    required property var glassStyles
    signal shellStyleObserved(string style)
    signal materialSeedObserved(string seed)

    Layout.fillWidth: true
    spacing: 12

    property var bridge: null
    property string shellStyle: "macos"
    // Material's colour source, mirrored from the Shell so the segmented
    // control reflects what is actually applied.
    property string materialColorScheme: "monet"
    // Name of the traditional swatch the accent resolved to, shown as
    // feedback so "中国传统色" is legible rather than abstract.
    property string materialAccentName: ""
    // Representative swatches per colour source, straight from the Shell
    // (materialColorSwatches on the snapshot). Each entry is
    // {id, colors: [#rrggbb, ...]}; empty until a wallpaper seed exists.
    property var colorSchemes: []
    property string errorText: ""
    // 界面语言持久值（auto / zh-CN / pt-BR / en），经 i18n-settings IPC 由 Shell
    // 持有与落盘；"auto" 的本地解析在 onI18nSnapshotChanged 里做。
    property string language: "auto"
    readonly property var styles: [
        {
            id: "macos",
            name: "macOS",
            feature: "LIQUID GLASS",
            description: I18n.tr("Floating Dock, translucent top bar and softer large-radius components"),
            accent: "#0a84ff"
        },
        {
            id: "material",
            name: "Material Design",
            feature: "MONET TONAL",
            description: I18n.tr("Tonal surfaces, state indicators and standardized hierarchy with motion"),
            accent: "#6750a4"
        }
    ]

    function isValidStyle(style) {
        return style === "windows12" || style === "macos" || style === "material";
    }

    function isValidMaterialColorScheme(scheme) {
        return scheme === "monet" || scheme === "chinese" || scheme === "japanese";
    }

    function schemeName(id) {
        return id === "chinese" ? I18n.tr("Chinese traditional colors") : (id === "japanese" ? I18n.tr("Japanese palettes") : I18n.tr("Monet colors"));
    }

    // One accent per source, so the selected card reads at a glance the way
    // the style gallery's cards do.
    function schemeAccent(id) {
        return id === "chinese" ? "#c3272b" : (id === "japanese" ? "#bc64a4" : "#6750a4");
    }

    function applyState(state) {
        if (!state || !isValidStyle(state.shellStyle))
            return;
        shellStyle = state.shellStyle;
        // The window palette follows the same style. ControlForm is NOT
        // assigned here: reading themePage.materialForm before this line would
        // hand the shared controls the previous style. Both
        // DisplaySettingsPage instances re-apply the form from their own
        // fresh isMaterialDesign, and selectStyle() calls them right after.
        themePage.shellStyleObserved(shellStyle);
        if (isValidMaterialColorScheme(state.materialColorScheme))
            materialColorScheme = state.materialColorScheme;
        materialAccentName = String(state.materialAccentName ?? "");
        // The Shell owns the scheme and sends previews; the page never
        // evaluates colours itself. The swatches cross the C++ bridge as a
        // JSON string (see the Shell side for why); parsing here keeps the
        // bridge free of nested-type conversion.
        let parsed = [];
        try {
            parsed = JSON.parse(state.materialColorSwatches || "[]");
        } catch (error) {
            parsed = [];
            console.warn("[Settings] colour swatches unreadable: " + error);
        }
        colorSchemes = parsed;
        // The accent the shell derived from the wallpaper is enough to
        // rebuild the same Material 3 roles in this window.
        themePage.materialSeedObserved(parsed.length > 0 && parsed[0].colors && parsed[0].colors.length > 0 ? String(parsed[0].colors[0]) : "");
        errorText = "";
    }

    function refresh() {
        if (!bridge) {
            errorText = I18n.tr("The Settings bridge has not been built");
            return;
        }
        bridge.appearanceSnapshot();
    }

    function selectStyle(style) {
        if (!bridge || !isValidStyle(style)) {
            errorText = bridge ? I18n.tr("Unknown theme shape") : I18n.tr("The Settings bridge has not been built");
            return;
        }
        bridge.updateShellStyle(style);
    }

    // Only the Material shell style reads the colour source; switching it
    // is still sent for every style so the stored preference survives a
    // detour through macOS or Windows 12.
    function selectMaterialColorScheme(scheme) {
        if (!bridge || !isValidMaterialColorScheme(scheme)) {
            errorText = bridge ? I18n.tr("Unknown palette source") : I18n.tr("The Settings bridge has not been built");
            return;
        }
        bridge.updateMaterialColorScheme(scheme);
    }

    function isValidLanguage(lang) {
        return lang === "zh-CN" || lang === "pt-BR" || lang === "en" || lang === "auto"
    }

    function setLanguage(lang) {
        if (!bridge || !isValidLanguage(lang)) {
            errorText = bridge ? I18n.tr("Unknown language") : I18n.tr("The Settings bridge has not been built");
            return;
        }
        bridge.updateLanguage(lang);
    }

    Connections {
        target: themePage.bridge
        enabled: themePage.bridge !== null
        function onAppearanceSnapshotChanged(state) {
            themePage.applyState(state);
            themeMaterialSettings.applyState(state);
            globalAppearanceSettings.applyState(state);
            if (themePage.bridge.lastError)
                themePage.errorText = I18n.tr(themePage.bridge.lastError);
        }
    }

    Connections {
        target: themePage.bridge
        enabled: themePage.bridge !== null
        function onI18nSnapshotChanged(state) {
            if (state && state.language !== undefined && state.language !== "") {
                themePage.language = String(state.language);
                // "auto" 只作为持久值：生效语言由 shell 解析后同步回来时
                // 已经是具体值；这里在本地也解析一份（同一实现），保证立即生效。
                I18n.language = themePage.language === "auto" ? I18n.systemDefault() : themePage.language;
            }
        }
    }

    Component.onCompleted: {
        refresh();
        if (bridge)
            bridge.i18nSnapshot();
    }

    // Existing appearance adapter retains preview/commit/cancel and confirmed state.
    DisplaySettingsPage {
        id: themeMaterialSettings
        visible: false
        colors: themePage.colors
        materialForm: themePage.materialForm
        bridge: themePage.bridge
        glassStyles: themePage.glassStyles
        suppressInitialRequest: true
        showSystemAppearance: false
        showGlassMaterial: false
        showIconAppearance: false
        onShellStyleObserved: style => themePage.shellStyleObserved(style)
    }

    Demo.SettingsGroup {
        title: I18n.tr("Interface shape")
        backgroundColor: colors.card
        Item {
            Layout.fillWidth: true
            implicitHeight: 158
            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12
                Repeater {
                    model: themePage.styles
                    AbstractButton {
                        id: choice
                        required property int index
                        required property var modelData
                        objectName: "settingsShapeChoice" + index
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.minimumWidth: 0
                        Layout.fillHeight: true
                        hoverEnabled: true
                        Accessible.name: modelData.name
                        Accessible.role: Accessible.RadioButton
                        Accessible.checked: themePage.shellStyle === modelData.id
                        onClicked: themePage.selectStyle(modelData.id)
                        background: Rectangle {
                            radius: 10
                            color: choice.hovered ? Demo.AppTheme.withAlpha(Demo.AppTheme.text, .025) : "transparent"
                            border.width: themePage.shellStyle === choice.modelData.id || choice.visualFocus ? 2 : 0
                            border.color: Demo.AppTheme.accent
                        }
                        contentItem: ColumnLayout {
                            spacing: 6
                            Demo.SettingsAppearancePreview {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 64
                                Layout.margins: 10
                                Layout.bottomMargin: 0
                                objectName: "settingsAppearancePreview" + choice.index
                                form: choice.modelData.id
                                windowTitle: I18n.tr("Settings")
                                settingTitle: I18n.tr("Appearance")
                            }
                            Text {
                                Layout.fillWidth: true
                                Layout.leftMargin: 12
                                Layout.bottomMargin: 10
                                text: choice.modelData.name
                                color: Demo.AppTheme.text
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
        Demo.SettingsItem {
            visible: themePage.shellStyle === "material"
            title: I18n.tr("Theme palette")
            description: themePage.materialAccentName ? I18n.tr("Current seed color: ") + themePage.materialAccentName : I18n.tr("Material You: derive the whole palette from the wallpaper hue")
            Controls.SettingsSelect {
                textRole: "label"
                colors: themePage.colors
                materialForm: themePage.materialForm
                model: ["monet", "chinese", "japanese"].map(id => ({
                            id: id,
                            label: themePage.schemeName(id)
                        }))
                currentIndex: ["monet", "chinese", "japanese"].indexOf(themePage.materialColorScheme)
                onSelectionChanged: index => themePage.selectMaterialColorScheme(model[index].id)
            }
        }
        Demo.SettingsItem {
            visible: themePage.shellStyle !== "material"
            title: I18n.tr("Material style")
            Controls.SettingsSelect {
                objectName: "themeMaterialStyleSelect"
                textRole: "label"
                colors: themePage.colors
                materialForm: themePage.materialForm
                model: themePage.glassStyles.options
                currentIndex: Math.max(0, themePage.glassStyles.indexOf(themeMaterialSettings.glassStyle))
                onSelectionChanged: index => themeMaterialSettings.setGlassStyle(index)
            }
        }
        Demo.SettingsItem {
            title: I18n.tr(themePage.shellStyle === "material" ? "Background blur" : "Blur strength")
            Text {
                text: themeMaterialSettings.percentage(themeMaterialSettings.blurStrength)
                color: colors.secondaryText
                font.pixelSize: 11
            }
            Controls.SettingsSlider {
                accentColor: colors.accent
                trackColor: colors.divider
                value: themeMaterialSettings.blurStrength
                onPreviewChanged: value => themeMaterialSettings.previewBlur(value)
                onCommitRequested: themeMaterialSettings.commitBlur()
                onCanceled: {
                    themeMaterialSettings.blurDirty = false;
                    themeMaterialSettings.refresh();
                }
            }
        }
        Demo.SettingsItem {
            visible: themePage.shellStyle !== "material"
            title: I18n.tr("Liquid strength")
            Text {
                text: themeMaterialSettings.percentage(themeMaterialSettings.liquidStrength)
                color: colors.secondaryText
                font.pixelSize: 11
            }
            Controls.SettingsSlider {
                accentColor: colors.accent
                trackColor: colors.divider
                value: themeMaterialSettings.liquidStrength
                onPreviewChanged: value => themeMaterialSettings.previewLiquid(value)
                onCommitRequested: themeMaterialSettings.commitLiquid()
                onCanceled: {
                    themeMaterialSettings.liquidDirty = false;
                    themeMaterialSettings.refresh();
                }
            }
        }
    }

    DisplaySettingsPage {
        id: globalAppearanceSettings
        colors: themePage.colors
        materialForm: themePage.materialForm
        bridge: themePage.bridge
        glassStyles: themePage.glassStyles
        suppressInitialRequest: true
        showSystemAppearance: true
        showGlassMaterial: false
        showIconAppearance: true
        showSpatialWallpaper: false
        onShellStyleObserved: style => themePage.shellStyleObserved(style)
    }
    WidgetAppearanceSection {
        colors: themePage.colors
        materialForm: themePage.materialForm
        bridge: themePage.bridge
        suppressInitialRequest: true
    }
    Demo.SettingsGroup {
        backgroundColor: colors.card
        Demo.SettingsItem {
            title: I18n.tr("Language")
            description: I18n.tr("Switch the interface language; applies live.")
            Controls.SettingsSelect {
                textRole: "label"
                colors: themePage.colors
                materialForm: themePage.materialForm
                model: [
                    { id: "auto", label: I18n.tr("Follow system") },
                    { id: "zh-CN", label: "简体中文" },
                    { id: "en", label: "English" },
                    { id: "pt-BR", label: "Português (Brasil)" }
                ]
                currentIndex: Math.max(0, model.findIndex(function(option) {
                    return option.id === themePage.language
                }))
                onSelectionChanged: function(index) {
                    themePage.setLanguage(model[index].id)
                }
            }
        }
    }
    Text {
        Layout.fillWidth: true
        visible: themePage.errorText.length > 0
        text: themePage.errorText
        color: "#ff453a"
        font.pixelSize: 10
        wrapMode: Text.Wrap
    }
}
