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
    id: displayPage
    required property var colors
    property bool materialForm: false
    required property var glassStyles
    signal shellStyleObserved(string style)

    Layout.fillWidth: true
    spacing: 12

    property bool showSystemAppearance: true
    property bool showGlassMaterial: true
    property bool showIconAppearance: true
    property bool showSpatialWallpaper: false

    property var bridge: null
    property real blurStrength: 0.42
    property real liquidStrength: 1.0
    property string glassStyle: "liquid"
    property string shellStyle: "macos"
    readonly property bool isMaterialDesign: shellStyle === "material"
    readonly property bool narrowLayout: width < 430
    property bool glassFollowsAppearanceMode: false
    property bool spatialWallpaperEnabled: false
    property bool blurDirty: false
    property bool liquidDirty: false
    property string errorText: ""

    function percentage(value) {
        return Math.round(value * 100) + "%";
    }

    function applyState(state) {
        if (!state)
            return;
        const rawBlur = state.globalBlurStrength !== undefined ? state.globalBlurStrength : state.blurStrength;
        const rawLiquid = state.globalLiquidStrength !== undefined ? state.globalLiquidStrength : state.liquidStrength;
        if (rawBlur === undefined || rawLiquid === undefined)
            return;
        blurStrength = Math.max(0, Math.min(1, Number(rawBlur)));
        liquidStrength = Math.max(0, Math.min(1, Number(rawLiquid)));
        const styleIndex = glassStyles.indexOf(state.glassStyle);
        glassStyle = styleIndex >= 0 ? String(state.glassStyle) : "liquid";
        shellStyle = String(state.shellStyle || "macos");
        LiquidControls.ControlForm.materialForm = isMaterialDesign;
        // The window palette follows the same style.
        displayPage.shellStyleObserved(shellStyle);
        if (state.glassFollowsAppearanceMode !== undefined)
            glassFollowsAppearanceMode = !!state.glassFollowsAppearanceMode;
        spatialWallpaperEnabled = !!state.spatialWallpaperEnabled;
        blurDirty = false;
        liquidDirty = false;
        errorText = "";
    }

    // A composing page (ThemeSettingsPage embeds two instances) requests one
    // snapshot for everyone; each instance still applies the broadcast reply.
    property bool suppressInitialRequest: false

    function refresh() {
        if (!bridge) {
            errorText = I18n.tr("The Settings bridge has not been built");
            return;
        }
        bridge.appearanceSnapshot();
    }

    Timer {
        id: liveBlurDebounce
        interval: 60
        repeat: false
        onTriggered: {
            if (displayPage.bridge && displayPage.blurDirty) {
                displayPage.bridge.updateGlobalBlurStrength(displayPage.blurStrength);
            }
        }
    }

    Timer {
        id: liveLiquidDebounce
        interval: 60
        repeat: false
        onTriggered: {
            if (displayPage.bridge && displayPage.liquidDirty) {
                displayPage.bridge.updateGlobalLiquidStrength(displayPage.liquidStrength);
            }
        }
    }

    function previewBlur(value) {
        const clamped = Math.max(0, Math.min(1, value));
        if (Math.abs(blurStrength - clamped) < 0.005)
            return;
        blurStrength = clamped;
        blurDirty = true;
        liveBlurDebounce.restart();
    }

    function commitBlur() {
        liveBlurDebounce.stop();
        if (!blurDirty || !bridge)
            return;
        blurDirty = false;
        bridge.updateGlobalBlurStrength(blurStrength);
    }

    function previewLiquid(value) {
        const clamped = Math.max(0, Math.min(1, value));
        if (Math.abs(liquidStrength - clamped) < 0.005)
            return;
        liquidStrength = clamped;
        liquidDirty = true;
        liveLiquidDebounce.restart();
    }

    function commitLiquid() {
        liveLiquidDebounce.stop();
        if (!liquidDirty || !bridge)
            return;
        liquidDirty = false;
        bridge.updateGlobalLiquidStrength(liquidStrength);
    }

    function setSystemAppearance(index) {
        if (!bridge) {
            errorText = I18n.tr("The Settings bridge has not been built");
            return;
        }
        bridge.applySystemAppearance(index === 1);
    }

    function setGlassStyle(index) {
        if (!bridge)
            return;
        const option = glassStyles.options[index];
        if (!option)
            return;
        bridge.updateGlassStyle(option.id);
    }

    function saveGlassFollowsAppearanceMode(checked) {
        if (!bridge)
            return;
        bridge.updateGlassFollowsAppearanceMode(checked);
    }

    Connections {
        target: displayPage.bridge
        enabled: displayPage.bridge !== null
        function onAppearanceSnapshotChanged(state) {
            displayPage.applyState(state);
            if (displayPage.bridge.lastError)
                displayPage.errorText = I18n.tr(displayPage.bridge.lastError);
        }
        function onSystemAppearanceApplied(accepted) {
            if (accepted)
                displayPage.errorText = "";
            else if (displayPage.bridge.lastError)
                displayPage.errorText = I18n.tr(displayPage.bridge.lastError);
        }
    }

    Component.onCompleted: if (!suppressInitialRequest)
        refresh()

    Demo.SettingsGroup {
        visible: displayPage.showSystemAppearance
        title: I18n.tr("System appearance")
        backgroundColor: colors.card

        Demo.SettingsItem {
            title: I18n.tr("Appearance mode")

            Controls.SettingsNavBar {
                id: systemAppearanceNavBar
                colors: displayPage.colors
                materialForm: displayPage.materialForm
                model: [
                    {
                        id: "light",
                        label: I18n.tr("Light")
                    },
                    {
                        id: "dark",
                        label: I18n.tr("Dark")
                    }
                ]
                currentIndex: colors.dark ? 1 : 0
                onSelectionChanged: function (index) {
                    displayPage.setSystemAppearance(index);
                }
            }
        }

        Demo.SettingsItem {
            visible: !displayPage.isMaterialDesign
            title: I18n.tr("Liquid glass follows the appearance mode")

            Controls.SettingsSwitch {
                id: glassFollowsAppearanceModeSwitch
                checked: displayPage.glassFollowsAppearanceMode
                // The shared controls carry the host's palette, so the
                // Material form hands them the Material accent: their
                // own default is the iPadOS blue this window was
                // designed with.
                accentColor: colors.accent
                trackColor: colors.divider
                onToggled: function (checked) {
                    displayPage.saveGlassFollowsAppearanceMode(checked);
                }
            }
        }
    }

    Demo.SettingsGroup {
        visible: displayPage.showSpatialWallpaper
        title: I18n.tr("Spatial wallpaper")
        backgroundColor: colors.card

        Demo.SettingsItem {
            visible: displayPage.showSpatialWallpaper
            title: I18n.tr("Enable spatial wallpaper parallax")
            description: I18n.tr("The model runs locally only. First enablement downloads it and generates the depth cache on CPU; afterwards only wallpaper changes are reprocessed.")

            Controls.SettingsSwitch {
                id: spatialWallpaperSwitch
                checked: displayPage.spatialWallpaperEnabled
                accentColor: colors.accent
                trackColor: colors.divider
                onToggled: function (checked) {
                    if (displayPage.bridge)
                        displayPage.bridge.updateSpatialWallpaperEnabled(checked);
                    spatialWallpaperSwitch.checked = displayPage.spatialWallpaperEnabled;
                }
            }
        }
    }

    Demo.SettingsGroup {
        visible: displayPage.showGlassMaterial
        title: (displayPage.isMaterialDesign ? I18n.tr("Background blur") : I18n.tr("Glass material"))
        backgroundColor: colors.card

        Demo.SettingsItem {
            visible: !displayPage.isMaterialDesign
            title: I18n.tr("Material style")

            Controls.SettingsSelect {
                objectName: "displayMaterialStyleSelect"
                textRole: "label"
                colors: displayPage.colors
                materialForm: displayPage.materialForm

                model: glassStyles.options
                currentIndex: Math.max(0, glassStyles.indexOf(displayPage.glassStyle))
                onSelectionChanged: function (index) {
                    displayPage.setGlassStyle(index);
                }
            }
        }

        Demo.SettingsItem {
            title: I18n.tr("Blur strength")

            Text {
                text: displayPage.percentage(displayPage.blurStrength)
                color: colors.secondaryText
                font.pixelSize: 12
                horizontalAlignment: Text.AlignRight
            }
            Controls.SettingsSlider {
                // The shared controls carry the host's palette, so the
                // Material form has to hand them the Material accent: their own
                // default is the iPadOS blue this window was designed with.
                accentColor: colors.accent
                value: displayPage.blurStrength
                trackColor: colors.divider
                onPreviewChanged: function (position) {
                    displayPage.previewBlur(position);
                }
                onCanceled: {
                    liveBlurDebounce.stop();
                    displayPage.blurDirty = false;
                    displayPage.refresh();
                }
                onCommitRequested: displayPage.commitBlur()
            }
        }

        Demo.SettingsItem {
            visible: !displayPage.isMaterialDesign
            title: I18n.tr("Liquid strength")

            Text {
                text: displayPage.percentage(displayPage.liquidStrength)
                color: colors.secondaryText
                font.pixelSize: 12
                horizontalAlignment: Text.AlignRight
            }
            Controls.SettingsSlider {
                // The shared controls carry the host's palette, so the
                // Material form has to hand them the Material accent: their own
                // default is the iPadOS blue this window was designed with.
                accentColor: colors.accent
                value: displayPage.liquidStrength
                trackColor: colors.divider
                onPreviewChanged: function (position) {
                    displayPage.previewLiquid(position);
                }
                onCanceled: {
                    liveLiquidDebounce.stop();
                    displayPage.liquidDirty = false;
                    displayPage.refresh();
                }
                onCommitRequested: displayPage.commitLiquid()
            }
        }
    }

    IconAppearanceSection {
        colors: displayPage.colors
        materialForm: displayPage.materialForm
        visible: displayPage.showIconAppearance
        bridge: displayPage.bridge
        // The composing page's single snapshot covers this instance too,
        // including the hidden one (showIconAppearance: false still creates it).
        suppressInitialRequest: true
    }

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 13
        Layout.rightMargin: 13
        visible: displayPage.errorText.length > 0
        text: displayPage.errorText
        color: "#ff453a"
        font.pixelSize: 12
        wrapMode: Text.Wrap
    }
}
