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
    required property var glassStyles
    signal shellStyleObserved(string style)
    id: displayPage

    Layout.fillWidth: true
    spacing: 7

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
    property bool glassFollowsAppearanceMode: false
    property bool spatialWallpaperEnabled: false
    // 使用系统字体: the saved option, and the family it resolves to. The family
    // comes from the Shell because this window is not allowed to read
    // kdeglobals: a separate process with its own settings file, and the Shell
    // already watches that file.
    property bool useSystemFont: false
    property string systemFontFamily: ""
    property bool blurDirty: false
    property bool liquidDirty: false
    property string errorText: ""

    function percentage(value) {
        return Math.round(value * 100) + "%"
    }

    function applyState(state) {
        if (!state)
            return
        const rawBlur = state.globalBlurStrength !== undefined
            ? state.globalBlurStrength : state.blurStrength
        const rawLiquid = state.globalLiquidStrength !== undefined
            ? state.globalLiquidStrength : state.liquidStrength
        if (rawBlur === undefined || rawLiquid === undefined)
            return
        blurStrength = Math.max(0, Math.min(1, Number(rawBlur)))
        liquidStrength = Math.max(0, Math.min(1, Number(rawLiquid)))
        const styleIndex = glassStyles.indexOf(state.glassStyle)
        glassStyle = styleIndex >= 0 ? String(state.glassStyle) : "liquid"
        shellStyle = String(state.shellStyle || "macos")
        LiquidControls.ControlForm.materialForm = isMaterialDesign
                    // The window palette follows the same style.
        displayPage.shellStyleObserved(shellStyle)
        if (state.glassFollowsAppearanceMode !== undefined)
            glassFollowsAppearanceMode = !!state.glassFollowsAppearanceMode
        if (state.useSystemFont !== undefined)
            useSystemFont = !!state.useSystemFont
        // Only present on a Shell that knows the option; an older one leaves
        // the row naming no family instead of claiming the wrong one.
        if (state.systemFontFamily !== undefined)
            systemFontFamily = String(state.systemFontFamily || "")
        spatialWallpaperEnabled = !!state.spatialWallpaperEnabled
        blurDirty = false
        liquidDirty = false
        errorText = ""
    }

    // A composing page (ThemeSettingsPage embeds two instances) requests one
    // snapshot for everyone; each instance still applies the broadcast reply.
    property bool suppressInitialRequest: false

    function refresh() {
        if (!bridge) {
            errorText = I18n.tr("The Settings bridge has not been built")
            return
        }
        bridge.appearanceSnapshot()
    }

    Timer {
        id: liveBlurDebounce
        interval: 60
        repeat: false
        onTriggered: {
            if (displayPage.bridge && displayPage.blurDirty) {
                displayPage.bridge.updateGlobalBlurStrength(displayPage.blurStrength)
            }
        }
    }

    Timer {
        id: liveLiquidDebounce
        interval: 60
        repeat: false
        onTriggered: {
            if (displayPage.bridge && displayPage.liquidDirty) {
                displayPage.bridge.updateGlobalLiquidStrength(displayPage.liquidStrength)
            }
        }
    }

    function previewBlur(value) {
        const clamped = Math.max(0, Math.min(1, value))
        if (Math.abs(blurStrength - clamped) < 0.005)
            return
        blurStrength = clamped
        blurDirty = true
        liveBlurDebounce.restart()
    }

    function commitBlur() {
        liveBlurDebounce.stop()
        if (!blurDirty || !bridge)
            return
        blurDirty = false
        bridge.updateGlobalBlurStrength(blurStrength)
    }

    function previewLiquid(value) {
        const clamped = Math.max(0, Math.min(1, value))
        if (Math.abs(liquidStrength - clamped) < 0.005)
            return
        liquidStrength = clamped
        liquidDirty = true
        liveLiquidDebounce.restart()
    }

    function commitLiquid() {
        liveLiquidDebounce.stop()
        if (!liquidDirty || !bridge)
            return
        liquidDirty = false
        bridge.updateGlobalLiquidStrength(liquidStrength)
    }

    function setSystemAppearance(index) {
        if (!bridge) {
            errorText = I18n.tr("The Settings bridge has not been built")
            return
        }
        bridge.applySystemAppearance(index === 1)
    }

    function setGlassStyle(index) {
        if (!bridge)
            return
        const option = glassStyles.options[index]
        if (!option)
            return
        bridge.updateGlassStyle(option.id)
    }

    function saveGlassFollowsAppearanceMode(checked) {
        if (!bridge)
            return
        bridge.updateGlassFollowsAppearanceMode(checked)
    }

    function saveUseSystemFont(checked) {
        if (!bridge)
            return
        bridge.updateUseSystemFont(checked)
    }

    Connections {
        target: displayPage.bridge
        enabled: displayPage.bridge !== null
        function onAppearanceSnapshotChanged(state) {
            displayPage.applyState(state)
            if (displayPage.bridge.lastError)
                displayPage.errorText = I18n.tr(displayPage.bridge.lastError)
        }
        function onSystemAppearanceApplied(accepted) {
            if (accepted)
                displayPage.errorText = ""
            else if (displayPage.bridge.lastError)
                displayPage.errorText = I18n.tr(displayPage.bridge.lastError)
        }
    }

    Component.onCompleted: if (!suppressInitialRequest) refresh()

    Text {
        visible: displayPage.showSystemAppearance
        text: I18n.tr("System appearance").toUpperCase()
        color: colors.secondaryText
        font.pixelSize: 12
        font.weight: Font.DemiBold
        Layout.leftMargin: 13
    }

    Rectangle {
        visible: displayPage.showSystemAppearance
        Layout.fillWidth: true
        // The glass-follows-appearance row is a liquid-glass control and is
        // absent under Material, so the card collapses to just the
        // appearance-mode row instead of leaving a gap behind it.
        implicitHeight: displayPage.isMaterialDesign ? 54 : 109
        radius: 18
        color: colors.card

        Column {
            anchors.fill: parent

            Item {
                width: parent.width
                height: 54

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12

                    Controls.SettingIcon {
                        colors: displayPage.colors
                        materialForm: displayPage.materialForm
                        symbol: "◐"
                        tint: "#5ac8fa"
                    }
                    Text {
                        text: I18n.tr("Appearance mode")
                        color: colors.primaryText
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                    }
                    Item { Layout.fillWidth: true }
                    Controls.SettingsNavBar {
                        colors: displayPage.colors
                        materialForm: displayPage.materialForm
                        id: systemAppearanceNavBar
                        model: [
                            { id: "light", label: I18n.tr("Light") },
                            { id: "dark", label: I18n.tr("Dark") }
                        ]
                        currentIndex: colors.dark ? 1 : 0
                        onSelectionChanged: function(index) {
                            displayPage.setSystemAppearance(index)
                        }
                    }
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 53
                height: 1
                // Hidden together with the row below it: a separator with
                // no second row would draw a stray line under the mode
                // switch once the card collapses under Material.
                visible: !displayPage.isMaterialDesign
                color: colors.separator
            }

            Item {
                width: parent.width
                height: 54
                // Liquid glass only. Material has no liquid blur to follow
                // the appearance mode with, so the row is dropped rather
                // than shown disabled.
                visible: !displayPage.isMaterialDesign

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12

                    Controls.SettingIcon {
                        colors: displayPage.colors
                        materialForm: displayPage.materialForm
                        symbol: "◈"
                        tint: "#64d2ff"
                    }
                    Text {
                        text: I18n.tr("Liquid glass follows the appearance mode")
                        color: colors.primaryText
                        font.pixelSize: 14
                    }
                    Item { Layout.fillWidth: true }
                    LiquidControls.LiquidGlassSwitch {
                        id: glassFollowsAppearanceModeSwitch
                        width: 64
                        height: 25
                        checked: displayPage.glassFollowsAppearanceMode
                        // The shared controls carry the host's palette, so the
                        // Material form hands them the Material accent: their
                        // own default is the iPadOS blue this window was
                        // designed with.
                        accentColor: colors.accent
                        trackColor: colors.divider
                        onToggled: function(checked) {
                            displayPage.saveGlassFollowsAppearanceMode(checked)
                        }
                    }
                }
            }
        }
    }

    // ── 使用系统字体 ────────────────────────────────────────────────────────
    // The Shell names its designed families explicitly (SF Pro Display / Noto
    // Sans CJK SC) on ~110 Text items, so it ignores the KDE font unless this is
    // on. With it on every Shell surface -- Bar, Dock, launcher, desk widgets,
    // quick search, the menus -- draws with the family KDE is configured with,
    // which is what a user who installs their own font expects to see.
    //
    // Applications are not mentioned in this row because they do not need it:
    // they name no family and have always drawn with the platform font, so they
    // already follow KDE.
    //
    // The row never offers a file picker: the font is KDE's, chosen in System
    // Settings, and the Shell watches kdeglobals so a change there follows
    // without coming back to this page. The resolved family is shown instead,
    // so the option is never an abstract promise.
    Text {
        visible: displayPage.showSystemAppearance
        text: I18n.tr("Interface font").toUpperCase()
        color: colors.secondaryText
        font.pixelSize: 12
        font.weight: Font.DemiBold
        Layout.leftMargin: 13
        Layout.topMargin: 10
    }

    Rectangle {
        visible: displayPage.showSystemAppearance
        Layout.fillWidth: true
        implicitHeight: interfaceFontRow.implicitHeight + 24
        radius: 18
        color: colors.card

        RowLayout {
            id: interfaceFontRow
            anchors.fill: parent
            anchors.margins: 12
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 12

            Controls.SettingIcon {
                colors: displayPage.colors
                materialForm: displayPage.materialForm
                // "B" is the bold-glyph entry in VectorIcon's symbol table; "文"
                // is not registered there and would fall back to a gear.
                symbol: "B"
                tint: "#5e5ce6"
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                Text {
                    text: I18n.tr("Use the system font")
                    color: colors.primaryText
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                Text {
                    Layout.fillWidth: true
                    text: displayPage.useSystemFont
                        ? I18n.tr("Every part of the desktop draws with %1.").arg(
                            displayPage.systemFontFamily.length > 0
                                ? displayPage.systemFontFamily
                                : I18n.tr("the system font"))
                        : I18n.tr("The desktop uses its own font. Turn this on to draw every part of it with the font chosen in KDE System Settings.")
                    color: colors.secondaryText
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                }
            }

            LiquidControls.LiquidGlassSwitch {
                id: useSystemFontSwitch
                width: 64
                height: 25
                objectName: "use-system-font-switch"
                // The snapshot is the authority: this binding is never assigned
                // to, so the switch settles on whatever the Shell confirms. An
                // assignment here would destroy the binding for good (QML does
                // not restore it), and the switch would then keep showing a
                // value the Shell had already rejected -- the "needs several
                // clicks" failure.
                checked: displayPage.useSystemFont
                accentColor: colors.accent
                trackColor: colors.divider
                onToggled: function(checked) {
                    if (checked !== displayPage.useSystemFont)
                        displayPage.saveUseSystemFont(checked)
                }
            }
        }
    }

    Text {
        visible: displayPage.showSpatialWallpaper
        text: I18n.tr("Spatial wallpaper")
        color: colors.secondaryText
        font.pixelSize: 12
        font.weight: Font.DemiBold
        Layout.leftMargin: 13
        Layout.topMargin: 10
    }

    Rectangle {
        visible: displayPage.showSpatialWallpaper
        Layout.fillWidth: true
        implicitHeight: spatialWallpaperRow.implicitHeight + 20
        radius: 18
        color: colors.card

        RowLayout {
            id: spatialWallpaperRow
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            Controls.SettingIcon {
                colors: displayPage.colors
                materialForm: displayPage.materialForm
                symbol: "◉"
                tint: "#64d2ff"
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                Text {
                    text: I18n.tr("Enable spatial wallpaper parallax")
                    color: colors.primaryText
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                Text {
                    Layout.fillWidth: true
                    text: I18n.tr("The model runs locally only. First enablement downloads it and generates the depth cache on CPU; afterwards only wallpaper changes are reprocessed.")
                    color: colors.secondaryText
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                }
            }

            LiquidControls.LiquidGlassSwitch {
                id: spatialWallpaperSwitch
                width: 64
                height: 25
                checked: displayPage.spatialWallpaperEnabled
                accentColor: colors.accent
                trackColor: colors.divider
                onToggled: function(checked) {
                    if (displayPage.bridge)
                        displayPage.bridge.updateSpatialWallpaperEnabled(checked)
                    spatialWallpaperSwitch.checked =
                        displayPage.spatialWallpaperEnabled
                }
            }
        }
    }

    Text {
        visible: displayPage.showGlassMaterial
        text: (displayPage.isMaterialDesign ? I18n.tr("Background blur") : I18n.tr("Glass material")).toUpperCase()
        color: colors.secondaryText
        font.pixelSize: 12
        font.weight: Font.DemiBold
        Layout.leftMargin: 13
    }

    Rectangle {
        visible: displayPage.showGlassMaterial
        Layout.fillWidth: true
        implicitHeight: displayPage.isMaterialDesign ? 48 : 145
        radius: 18
        color: colors.card

        Column {
            anchors.fill: parent

            Item {
                width: parent.width
                height: 48
                visible: !displayPage.isMaterialDesign

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12
                    Controls.SettingIcon {
                        colors: displayPage.colors
                        materialForm: displayPage.materialForm
                        symbol: "◇"
                        tint: "#64d2ff"
                    }
                    Text {
                        text: I18n.tr("Material style")
                        color: colors.primaryText
                        font.pixelSize: 14
                    }
                    Item { Layout.fillWidth: true }
                    Controls.SettingsNavBar {
                        colors: displayPage.colors
                        materialForm: displayPage.materialForm
                        Layout.preferredWidth: 264
                        itemWidthOverride: 88
                        model: glassStyles.options
                        currentIndex: Math.max(0,
                            glassStyles.indexOf(displayPage.glassStyle))
                        onSelectionChanged: function(index) {
                            displayPage.setGlassStyle(index)
                        }
                    }
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 53
                height: 1
                visible: !displayPage.isMaterialDesign
                color: colors.separator
            }

            Item {
                width: parent.width
                height: 48

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12

                    Controls.SettingIcon {
                        colors: displayPage.colors
                        materialForm: displayPage.materialForm
                        symbol: "◌"
                        tint: "#5ac8fa"
                    }
                    Text {
                        text: I18n.tr("Blur strength")
                        color: colors.primaryText
                        font.pixelSize: 14
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: displayPage.percentage(displayPage.blurStrength)
                        color: colors.secondaryText
                        font.pixelSize: 12
                        Layout.preferredWidth: 38
                        horizontalAlignment: Text.AlignRight
                    }
                    LiquidControls.LiquidSlider {
                        // The shared controls carry the host's palette, so the
                        // Material form has to hand them the Material accent: their own
                        // default is the iPadOS blue this window was designed with.
                        accentColor: colors.accent
                        Layout.preferredWidth: 190
                        value: displayPage.blurStrength
                        trackColor: colors.divider
                        onPreviewChanged: function(position) {
                            displayPage.previewBlur(position)
                        }
                        onCanceled: { liveBlurDebounce.stop(); displayPage.blurDirty = false; displayPage.refresh() }
                        onCommitRequested: displayPage.commitBlur()
                    }
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 53
                height: 1
                visible: !displayPage.isMaterialDesign
                color: colors.separator
            }

            Item {
                width: parent.width
                height: 48
                visible: !displayPage.isMaterialDesign

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12

                    Controls.SettingIcon {
                        colors: displayPage.colors
                        materialForm: displayPage.materialForm
                        symbol: "≈"
                        tint: "#af52de"
                    }
                    Text {
                        text: I18n.tr("Liquid strength")
                        color: colors.primaryText
                        font.pixelSize: 14
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: displayPage.percentage(displayPage.liquidStrength)
                        color: colors.secondaryText
                        font.pixelSize: 12
                        Layout.preferredWidth: 38
                        horizontalAlignment: Text.AlignRight
                    }
                    LiquidControls.LiquidSlider {
                        // The shared controls carry the host's palette, so the
                        // Material form has to hand them the Material accent: their own
                        // default is the iPadOS blue this window was designed with.
                        accentColor: colors.accent
                        Layout.preferredWidth: 190
                        value: displayPage.liquidStrength
                        trackColor: colors.divider
                        onPreviewChanged: function(position) {
                            displayPage.previewLiquid(position)
                        }
                        onCanceled: { liveLiquidDebounce.stop(); displayPage.liquidDirty = false; displayPage.refresh() }
                        onCommitRequested: displayPage.commitLiquid()
                    }
                }
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
