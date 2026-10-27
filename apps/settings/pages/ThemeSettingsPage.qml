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
    signal materialSeedObserved(string seed)
    id: themePage

    Layout.fillWidth: true
    spacing: 10

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
        return style === "windows12" || style === "macos"
            || style === "material"
    }

    function isValidMaterialColorScheme(scheme) {
        return scheme === "monet" || scheme === "chinese"
            || scheme === "japanese"
    }

    function schemeName(id) {
        return id === "chinese" ? I18n.tr("Chinese traditional colors")
            : (id === "japanese" ? I18n.tr("Japanese palettes") : I18n.tr("Monet colors"))
    }

    // One accent per source, so the selected card reads at a glance the way
    // the style gallery's cards do.
    function schemeAccent(id) {
        return id === "chinese" ? "#c3272b"
            : (id === "japanese" ? "#bc64a4" : "#6750a4")
    }

    function applyState(state) {
        if (!state || !isValidStyle(state.shellStyle))
            return
        shellStyle = state.shellStyle
        // The window palette follows the same style. ControlForm is NOT
        // assigned here: reading themePage.materialForm before this line would
        // hand the shared controls the previous style. Both
        // DisplaySettingsPage instances re-apply the form from their own
        // fresh isMaterialDesign, and selectStyle() calls them right after.
        themePage.shellStyleObserved(shellStyle)
        if (isValidMaterialColorScheme(state.materialColorScheme))
            materialColorScheme = state.materialColorScheme
        materialAccentName = String(state.materialAccentName ?? "")
        // The Shell owns the scheme and sends previews; the page never
        // evaluates colours itself. The swatches cross the C++ bridge as a
        // JSON string (see the Shell side for why); parsing here keeps the
        // bridge free of nested-type conversion.
        let parsed = []
        try {
            parsed = JSON.parse(state.materialColorSwatches || "[]")
        } catch (error) {
            parsed = []
            console.warn("[Settings] colour swatches unreadable: " + error)
        }
        colorSchemes = parsed
        // The accent the shell derived from the wallpaper is enough to
        // rebuild the same Material 3 roles in this window.
        themePage.materialSeedObserved(parsed.length > 0 && parsed[0].colors
            && parsed[0].colors.length > 0 ? String(parsed[0].colors[0]) : "")
        errorText = ""
    }

    function refresh() {
        if (!bridge) {
            errorText = I18n.tr("The Settings bridge has not been built")
            return
        }
        bridge.appearanceSnapshot()
    }

    function selectStyle(style) {
        if (!bridge || !isValidStyle(style)) {
            errorText = bridge ? I18n.tr("Unknown theme shape") : I18n.tr("The Settings bridge has not been built")
            return
        }
        bridge.updateShellStyle(style)
    }

    // Only the Material shell style reads the colour source; switching it
    // is still sent for every style so the stored preference survives a
    // detour through macOS or Windows 12.
    function selectMaterialColorScheme(scheme) {
        if (!bridge || !isValidMaterialColorScheme(scheme)) {
            errorText = bridge ? I18n.tr("Unknown palette source") : I18n.tr("The Settings bridge has not been built")
            return
        }
        bridge.updateMaterialColorScheme(scheme)
    }

    function isValidLanguage(lang) {
        return lang === "zh-CN" || lang === "pt-BR" || lang === "en" || lang === "auto"
    }

    function setLanguage(lang) {
        if (!bridge || !isValidLanguage(lang)) {
            errorText = bridge ? I18n.tr("Unknown language") : I18n.tr("The Settings bridge has not been built")
            return
        }
        bridge.updateLanguage(lang)
    }

    Connections {
        target: themePage.bridge
        enabled: themePage.bridge !== null
        function onAppearanceSnapshotChanged(state) {
            themePage.applyState(state)
            themeMaterialSettings.applyState(state)
            globalAppearanceSettings.applyState(state)
            if (themePage.bridge.lastError)
                themePage.errorText = I18n.tr(themePage.bridge.lastError)
        }
    }

    Connections {
        target: themePage.bridge
        enabled: themePage.bridge !== null
        function onI18nSnapshotChanged(state) {
            if (state && state.language !== undefined
                    && state.language !== "") {
                themePage.language = String(state.language)
                // "auto" 只作为持久值：生效语言由 shell 解析后同步回来时
                // 已经是具体值；这里在本地也解析一份（同一实现），保证立即生效。
                I18n.language = themePage.language === "auto"
                    ? I18n.systemDefault() : themePage.language
            }
        }
    }

    Component.onCompleted: {
        refresh()
        if (bridge)
            bridge.i18nSnapshot()
    }

    Text {
        text: I18n.tr("Interface shape").toUpperCase()
        color: colors.secondaryText
        font.pixelSize: 12
        font.weight: Font.DemiBold
        Layout.leftMargin: 13
    }

    Rectangle {
        Layout.fillWidth: true
        // The card is as tall as its contents: the style gallery, the
        // divider, the Material colour-source control (only present while
        // Material is selected) and the embedded appearance controls. Under
        // Material that controls block is much shorter, so a fixed 550
        // would leave a dead band below it.
        implicitHeight: 16 + styleGallery.height + 13 + 1 + 10
            + (themeColorSchemeCard.visible
                ? themeColorSchemeCard.implicitHeight + 10 : 0)
            + themeMaterialSettings.implicitHeight + 16
        Layout.preferredHeight: implicitHeight
        radius: 26
        color: colors.dark ? "#000000" : "#ffffff"
        border.width: 1
        border.color: colors.floatingBorder
        clip: true

        Flickable {
            id: styleGallery
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 16
            height: 310
            contentWidth: styleGalleryRow.width
            contentHeight: styleGalleryRow.height
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Row {
                id: styleGalleryRow
                width: childrenRect.width
                height: 310
                spacing: 14

                Repeater {
                    model: themePage.styles

                    delegate: Rectangle {
                        id: styleCard
                        required property var modelData

                        // Only implemented styles are shown for now, so
                        // both cards should be complete rather than look
                        // accidentally clipped.
                        width: Math.max(300,
                            (styleGallery.width - styleGalleryRow.spacing) / 2)
                        height: styleGalleryRow.height
                        radius: 22
                        color: colors.dark
                            ? (themePage.shellStyle === modelData.id
                                ? "#34343a" : "#262629")
                            : Qt.rgba(0, 0, 0, themePage.shellStyle === modelData.id ? 0.085 : 0.045)
                        border.width: themePage.shellStyle === modelData.id ? 2 : 1
                        border.color: themePage.shellStyle === modelData.id
                            ? modelData.accent : colors.floatingBorder

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 13
                            spacing: 10

                            Rectangle {
                                id: stylePreview
                                Layout.fillWidth: true
                                Layout.preferredHeight: 166
                                radius: 16
                                clip: true
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop {
                                        position: 0
                                        color: styleCard.modelData.id === "material"
                                            ? "#d8c8f0" : (styleCard.modelData.id === "macos" ? "#789cc6" : "#b9d8ef")
                                    }
                                    GradientStop {
                                        position: 1
                                        color: styleCard.modelData.id === "material"
                                            ? "#a8d5c6" : (styleCard.modelData.id === "macos" ? "#b786bd" : "#9ba9c3")
                                    }
                                }

                                Rectangle {
                                    x: 18; y: 32
                                    width: parent.width * 0.46
                                    height: 76
                                    radius: styleCard.modelData.id === "material" ? 22 : 10
                                    color: styleCard.modelData.id === "material"
                                        ? Qt.rgba(0.96, 0.91, 1, 0.70) : Qt.rgba(1, 1, 1, 0.44)
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.48)

                                    Rectangle {
                                        x: 12; y: 13; width: parent.width * 0.58; height: 7
                                        radius: 4; color: Qt.rgba(0.18, 0.20, 0.28, 0.35)
                                    }
                                    Rectangle {
                                        x: 12; y: 28; width: parent.width * 0.76; height: 5
                                        radius: 3; color: Qt.rgba(0.18, 0.20, 0.28, 0.18)
                                    }
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    height: 22
                                    color: Qt.rgba(1, 1, 1,
                                        styleCard.modelData.id === "macos" ? 0.34 : 0.16)
                                    visible: styleCard.modelData.id !== "windows12"

                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 9
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 4
                                        Repeater {
                                            model: 3
                                            Rectangle {
                                                width: 6; height: 6; radius: 3
                                                color: index === 0 ? "#ff665d"
                                                    : (index === 1 ? "#ffbd45" : "#28c941")
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 18
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 45
                                    width: 42; height: 42; radius: 21
                                    visible: styleCard.modelData.id === "material"
                                    color: "#72558f"
                                    Text { anchors.centerIn: parent; text: "+"; color: "white"; font.pixelSize: 25 }
                                }

                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: styleCard.modelData.id === "macos" ? 10 : 0
                                    width: styleCard.modelData.id === "windows12"
                                        ? parent.width : (styleCard.modelData.id === "macos" ? 206 : 222)
                                    height: styleCard.modelData.id === "windows12" ? 34 : 42
                                    radius: styleCard.modelData.id === "windows12"
                                        ? 0 : (styleCard.modelData.id === "macos" ? 16 : 21)
                                    color: styleCard.modelData.id === "material"
                                        ? Qt.rgba(0.92, 0.84, 1, 0.88)
                                        : Qt.rgba(0.92, 0.96, 1, styleCard.modelData.id === "macos" ? 0.47 : 0.76)
                                    border.width: styleCard.modelData.id === "macos" ? 1 : 0
                                    border.color: Qt.rgba(1, 1, 1, 0.80)

                                    Rectangle {
                                        visible: styleCard.modelData.id === "macos"
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: 2
                                        height: 8
                                        radius: 7
                                        color: Qt.rgba(1, 1, 1, 0.32)
                                    }

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: styleCard.modelData.id === "material" ? 21 : 9
                                        Repeater {
                                            model: styleCard.modelData.id === "macos" ? 6 : 5
                                            Rectangle {
                                                width: styleCard.modelData.id === "macos" ? 24 : 16
                                                height: width
                                                radius: styleCard.modelData.id === "macos" ? 7 : width / 2
                                                color: index === 0 ? styleCard.modelData.accent
                                                    : (index % 3 === 1 ? "#f49e5c"
                                                    : (index % 3 === 2 ? "#70b98c" : "#8b83ca"))
                                                border.width: styleCard.modelData.id === "macos" ? 1 : 0
                                                border.color: Qt.rgba(1, 1, 1, 0.55)
                                            }
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text {
                                        text: styleCard.modelData.feature
                                        color: styleCard.modelData.accent
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0.8
                                    }
                                    Text {
                                        text: styleCard.modelData.name
                                        color: colors.primaryText
                                        font.pixelSize: 18
                                        font.weight: Font.Bold
                                    }
                                }

                                Rectangle {
                                    visible: themePage.shellStyle === styleCard.modelData.id
                                    Layout.preferredWidth: 46
                                    Layout.preferredHeight: 22
                                    radius: 11
                                    color: Qt.rgba(0.04, 0.52, 1, 0.16)
                                    Text {
                                        anchors.centerIn: parent
                                        text: I18n.tr("Now")
                                        color: styleCard.modelData.accent
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: styleCard.modelData.description
                                color: colors.secondaryText
                                font.pixelSize: 12
                                wrapMode: Text.Wrap
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: themePage.selectStyle(styleCard.modelData.id)
                        }
                    }
                }
            }

            // 横向画廊：滚轮顺着惯性滑动（竖向滚轮在没有可竖向滚动的内容时
            // 会落到唯一可滚的轴上）。
            Foundation.KosKineticScroll { flickable: styleGallery }
        }

        Rectangle {
            id: themeMaterialDivider
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: styleGallery.bottom
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            anchors.topMargin: 13
            height: 1
            color: colors.dark ? Qt.rgba(1, 1, 1, 0.18)
                              : Qt.rgba(0, 0, 0, 0.12)
        }

        // Material's colour source. Only shown while the Material card is
        // selected: the choice has no effect on the glass styles, and a
        // control that does nothing is worse than an absent one.
        Rectangle {
            id: themeColorSchemeCard
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: themeMaterialDivider.bottom
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.topMargin: 10
            // Tall enough for the tile row below: the header column (39),
            // the 10px gap and the 74px tiles, plus the 14px margins.
            // The old 136 cut 3px off that and squeezed the tiles.
            implicitHeight: 152
            visible: themePage.shellStyle === "material"
            radius: 18
            color: colors.card

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 11

                    Controls.SettingIcon {
                        colors: themePage.colors
                        materialForm: themePage.materialForm
                        symbol: "◐"
                        tint: "#8d6e63"
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: I18n.tr("Theme palette")
                            color: colors.primaryText
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: {
                                if (themePage.materialColorScheme === "monet")
                                    return I18n.tr("Material You: derive the whole palette from the wallpaper hue")
                                if (themePage.materialAccentName)
                                    return I18n.tr("Current seed color: ") + themePage.materialAccentName
                                return I18n.tr("No traditional color close enough to the wallpaper seed; fell back to Monet")
                            }
                            color: colors.secondaryText
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                }

                // Each source is drawn from the Shell's own preview colours,
                // so the cards show what this wallpaper actually becomes
                // rather than three labels. The big top swatch is the
                // accent — the colour a user recognises as theirs — and the
                // strip below it carries the companions and both surfaces.
                // Never leave the block blank: an empty swatch list means the
                // Shell has no wallpaper seed yet, which is a state worth
                // naming rather than rendering as nothing.
                Text {
                    Layout.fillWidth: true
                    visible: themePage.colorSchemes.length === 0
                    text: I18n.tr("Waiting for wallpaper color extraction; three swatches will appear here")
                    color: colors.secondaryText
                    font.pixelSize: 11
                }

                RowLayout {
                    Layout.fillWidth: true
                    // 7 + accent 24 + 5 + strip 10 + 5 + label 16 + 7. At 62
                    // the label had no room and hung 8px out of the tile.
                    Layout.preferredHeight: 74
                    visible: themePage.colorSchemes.length > 0
                    spacing: 10

                    Repeater {
                        model: themePage.colorSchemes

                        delegate: Rectangle {
                            id: schemeTile
                            required property var modelData
                            readonly property bool chosen:
                                themePage.materialColorScheme === modelData.id
                            readonly property var swatches: modelData.colors

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            // A selected tile is a filled container in the
                            // tonal form, not an outlined one; the iPadOS form
                            // keeps the wash and the scheme's own accent rim.
                            radius: themePage.materialForm ? 16 : 12
                            color: schemeTile.chosen
                                ? colors.selectedContainer
                                : (colors.dark ? Qt.rgba(1, 1, 1, 0.05)
                                              : Qt.rgba(0, 0, 0, 0.025))
                            border.width: themePage.materialForm
                                ? 0 : (schemeTile.chosen ? 2 : 1)
                            border.color: schemeTile.chosen
                                ? themePage.schemeAccent(schemeTile.modelData.id)
                                : colors.floatingBorder

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 7
                                spacing: 5

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 24
                                    radius: themePage.materialForm ? 8 : 6
                                    color: schemeTile.swatches.length > 0
                                        ? schemeTile.swatches[0] : "transparent"
                                }

                                Row {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 10
                                    spacing: 2

                                    Repeater {
                                        model: schemeTile.swatches.slice(1)

                                        delegate: Rectangle {
                                            required property var modelData
                                            width: Math.max(2,
                                                (parent.width - 8) / 5)
                                            height: parent.height
                                            radius: 3
                                            color: modelData
                                        }
                                    }
                                }

                                // A leading radio is the loudest cue the tile
                                // has: the container tint alone read as noise
                                // next to three coloured swatches. Kept at
                                // 14px so it stays inside the label's own
                                // 16px line box -- the card height above is
                                // sized around that line and cannot grow.
                                RowLayout {
                                    Layout.alignment: Qt.AlignHCenter
                                    spacing: 6

                                    Rectangle {
                                        id: schemeRadio
                                        implicitWidth: 14
                                        implicitHeight: 14
                                        Layout.alignment: Qt.AlignVCenter
                                        radius: width / 2
                                        color: "transparent"
                                        border.width: 1.5
                                        border.color: schemeTile.chosen
                                            ? colors.accent : colors.secondaryText

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 6
                                            height: 6
                                            radius: 3
                                            visible: schemeTile.chosen
                                            color: schemeRadio.border.color
                                        }
                                    }

                                    Text {
                                        text: themePage.schemeName(
                                            schemeTile.modelData.id)
                                        color: schemeTile.chosen
                                            ? colors.primaryText : colors.secondaryText
                                        font.pixelSize: 11
                                        font.weight: schemeTile.chosen
                                            ? Font.DemiBold : Font.Normal
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: themePage.selectMaterialColorScheme(
                                    schemeTile.modelData.id)
                            }
                        }
                    }
                }
            }
        }

        DisplaySettingsPage {
            colors: themePage.colors
            materialForm: themePage.materialForm
            bridge: themePage.bridge
            glassStyles: themePage.glassStyles
            onShellStyleObserved: style => themePage.shellStyleObserved(style)
            id: themeMaterialSettings
            suppressInitialRequest: true
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: themeColorSchemeCard.visible
                ? themeColorSchemeCard.bottom : themeMaterialDivider.bottom
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.topMargin: 10
            showSystemAppearance: false
            showGlassMaterial: true
            showIconAppearance: false
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 12
    }

    // Appearance controls belong to the selected colors. Keep the global
    // blur control available for every shell style, including Material.
    DisplaySettingsPage {
        colors: themePage.colors
        materialForm: themePage.materialForm
        bridge: themePage.bridge
        glassStyles: themePage.glassStyles
        onShellStyleObserved: style => themePage.shellStyleObserved(style)
        id: globalAppearanceSettings
        suppressInitialRequest: true
        Layout.fillWidth: true
        showSystemAppearance: true
        showGlassMaterial: false
        showIconAppearance: true
        showSpatialWallpaper: false
    }

    WidgetAppearanceSection {
        colors: themePage.colors
        materialForm: themePage.materialForm
        bridge: themePage.bridge
        suppressInitialRequest: true
        Layout.topMargin: 12
        Layout.bottomMargin: 12
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 64
        Layout.preferredHeight: implicitHeight
        radius: 26
        color: colors.dark ? "#000000" : "#ffffff"
        border.width: 1
        border.color: colors.floatingBorder

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 12
            Controls.SettingIcon {
                colors: themePage.colors
                materialForm: themePage.materialForm
                symbol: "文"
                tint: "#0a84ff"
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: I18n.tr("Language")
                    color: colors.primaryText
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                Text {
                    text: I18n.tr("Switch the interface language; applies live.")
                    color: colors.secondaryText
                    font.pixelSize: 11
                }
            }
            Controls.SettingsNavBar {
                colors: themePage.colors
                materialForm: themePage.materialForm
                Layout.preferredHeight: 30
                size: "tiny"
                barHeight: 30
                itemWidthOverride: 72
                // 语言选项固定显示各自语言的写法，不参与翻译；
                // 「跟随系统」是模式名，随界面语言翻译。
                model: [
                    { id: "auto", label: I18n.tr("Follow system") },
                    { id: "zh-CN", label: "简体中文" },
                    { id: "en", label: "English" },
                    { id: "pt-BR", label: "Português" }
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
        Layout.leftMargin: 13
        Layout.rightMargin: 13
        visible: themePage.errorText.length > 0
        text: themePage.errorText
        color: "#ff453a"
        font.pixelSize: 12
        wrapMode: Text.Wrap
    }
}
