import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import qs.desktop
import qs.desktop.modules.common
import "../../../Kos/Ui/foundation/WallpaperCatalog.js" as WallpaperCatalog
import "../../../Kos/Ui"
import "../../../Kos/Ui/wallpapers" as ThemeVisuals

// A small Shell-owned liquid control, activated by kos-settings through the
// wallpaper-settings IPC endpoint. The gallery omits text options and hints.
PanelWindow {
    id: stage

    property bool listExpanded: true
    // A hidden layer-shell surface can lose its native window and report a
    // zero size. Do not keep gallery delegates alive across that transition.
    readonly property bool previewContentReady: stage.visible
        && stage.width > 0 && stage.height > 0
    property real depthPointerX: 0
    property real depthPointerY: 0
    HoverHandler {
        enabled: SpatialWallpaperService.ready
        onPointChanged: {
            stage.depthPointerX = Math.max(-1, Math.min(1,
                (point.position.x / Math.max(1, stage.width) - 0.5) * 2))
            stage.depthPointerY = Math.max(-1, Math.min(1,
                (point.position.y / Math.max(1, stage.height) - 0.5) * 2))
        }
        onHoveredChanged: if (!hovered) {
            stage.depthPointerX = 0
            stage.depthPointerY = 0
        }
    }
    readonly property bool spatialPromptActive: spatialServiceDialog.requestedOpen
        || preparationOverlay.requestedOpen
        || SpatialWallpaperService.preparationRequested
        || SpatialWallpaperService.errorMessage.length > 0
    onSpatialPromptActiveChanged: if (spatialPromptActive) effectFeedback.dismiss()
    signal sideActionTriggered(string action)

    function cycleTransition() {
        const effects = WallpaperCatalog.transitions
        const index = effects.map(item => item.id).indexOf(WallpaperService.transition)
        const effect = effects[(index + 1) % effects.length]
        if (WallpaperService.setTransition(effect.id))
            effectFeedback.show("已切换动态效果为：" + effect.label, "media-shuffle")
    }

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.namespace: "kos-wallpaper-preview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: stage.screen === ScreenLifecycle.activeScreen
        && stage.visible && !stage.spatialPromptActive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    focusable: stage.screen === ScreenLifecycle.activeScreen && stage.visible && !stage.spatialPromptActive
    anchors { top: true; left: true; right: true; bottom: true }
    implicitWidth: screen?.width ?? 1920
    implicitHeight: screen?.height ?? 1080

    BackgroundEffect.blurRegion: (AppearanceTokens.surface.usesKwinBlur
        && WallpaperPreviewService.active)
        ? previewBlurUnion : null

    Region {
        id: previewBlurUnion
        regions: WallpaperPreviewService.active && !stage.spatialPromptActive
            ? (stage.listExpanded
                ? [surface.blurRegion, listToggle.blurRegion, backdropPanel.blurRegion, sidePill.blurRegion, effectFeedback.blurRegion]
                : [surface.blurRegion, listToggle.blurRegion, sidePill.blurRegion]) : []
    }

    Connections {
        target: WallpaperPreviewService
        function onActiveChanged() {
            if (WallpaperPreviewService.active) stage.listExpanded = true
            else effectFeedback.dismiss()
        }
    }

    LiquidGlassPanel {
        id: backdropPanel
        opacity: stage.listExpanded && !stage.spatialPromptActive ? 1 : 0
        visible: opacity > 0
        enabled: !stage.spatialPromptActive
        scale: 0.94 + 0.06 * opacity
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        x: (stage.width - width) / 2
        y: surface.y + surface.height + 12
        width: Math.max(0, Math.min(600, stage.width - 32))
        height: Math.max(0, Math.min(468, stage.height - y - 116, 32 + Math.ceil(Math.max(1,
            WallpaperPreviewService.images.length) / 3) * 120))
        z: 0
        radius: 28
        material: "regular"
        useKwinEffect: AppearanceTokens.surface.usesKwinBlur
        fallbackEnabled: AppearanceTokens.surface.paintInQml
        blurAnchor: backdropPanel
        scrimEnabled: AppearanceTokens.surface.usesBackdrop
        scrimLevel: "transparent"

        Item {
            id: wallpaperViewport
            anchors.fill: parent
            anchors.margins: 16
            clip: true

            GridView {
                id: wallpaperGrid
                anchors.fill: parent
                cellWidth: width / 3
                cellHeight: 120
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds
                model: stage.previewContentReady && width > 0 && height > 0
                    ? WallpaperPreviewService.images : []

                delegate: Item {
                    required property string modelData
                    required property int index
                    width: wallpaperGrid.cellWidth
                    height: wallpaperGrid.cellHeight

                    Image {
                        id: wallpaperThumbnail
                        anchors.fill: parent
                        anchors.margins: 8
                        readonly property string cachedSource: WallpaperPreviewService.thumbnailFor(modelData)
                        property bool cacheFailed: false
                        onCachedSourceChanged: cacheFailed = false
                        visible: WallpaperPreviewService.mode !== "theme"
                        source: WallpaperPreviewService.mode === "theme" ? "" : cachedSource && !cacheFailed ? cachedSource : modelData
                        sourceSize: cachedSource && !cacheFailed ? Qt.size(0, 0)
                            : Qt.size(Math.max(1, width), Math.max(1, height))
                        cache: true
                        onStatusChanged: {
                            if (status === Image.Error && cachedSource && !cacheFailed)
                                cacheFailed = true
                        }
                        fillMode: Image.PreserveAspectCrop
                        autoTransform: true
                        asynchronous: true
                        smooth: true
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: thumbnailMask
                        }
                    }
                    Loader {
                        anchors.fill: parent
                        anchors.margins: 8
                        active: stage.previewContentReady && width > 0 && height > 0
                            && WallpaperPreviewService.mode === "theme"
                        // Packs carry their own preview image; built-ins use
                        // the shared static plate.
                        sourceComponent: ThemePackService.pack(modelData.slice(6))?.preview
                            ? packPreview : builtinPreview
                    }
                    Component {
                        id: packPreview
                        Image {
                            source: ThemePackService.previewUrl(modelData.slice(6))
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            smooth: true
                        }
                    }
                    Component {
                        id: builtinPreview
                        ThemeVisuals.ThemeWallpaperThumbnail {
                            themeId: modelData.slice(6)
                        }
                    }
                    Text {
                        visible: WallpaperPreviewService.mode === "theme"
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 14
                        text: WallpaperCatalog.theme(modelData.slice(6))?.label
                            || ThemePackService.pack(modelData.slice(6))?.name || ""
                        color: "white"
                        font.pixelSize: 11
                    }
                    Rectangle {
                        id: thumbnailMask
                        anchors.fill: wallpaperThumbnail
                        radius: 10
                        visible: false
                        layer.enabled: true
                    }
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 8
                        color: "transparent"
                        radius: 10
                        border.width: (WallpaperPreviewService.mode === "slideshow"
                            ? WallpaperPreviewService.selectedImages.indexOf(modelData) >= 0
                            : WallpaperPreviewService.image === modelData) ? 2 : 0
                        border.color: "white"
                    }
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 14
                        width: 22; height: 22; radius: 11
                        visible: WallpaperPreviewService.mode === "slideshow"
                        color: WallpaperPreviewService.selectedImages.indexOf(modelData) >= 0 ? "#ffffff" : "#80000000"
                        BundledIcon {
                            anchors.centerIn: parent
                            name: "check"
                            size: 14
                            visible: WallpaperPreviewService.selectedImages.indexOf(modelData) >= 0
                            color: "#202020"
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: WallpaperPreviewService.select(index)
                    }
                }

                function syncToPreview() {
                    const index = WallpaperPreviewService.images.indexOf(
                        WallpaperPreviewService.image)
                    if (index >= 0)
                        positionViewAtIndex(index, GridView.Contain)
                }
                Component.onCompleted: Qt.callLater(syncToPreview)

                KosKineticScroll { flickable: wallpaperGrid }
            }

            Connections {
                target: WallpaperPreviewService
                function onImageChanged() { Qt.callLater(wallpaperGrid.syncToPreview) }
                function onImagesChanged() { Qt.callLater(wallpaperGrid.syncToPreview) }
            }
        }
    }

    // Independent icon actions below the gallery.
    LiquidGlassPanel {
        id: sidePill
        opacity: stage.spatialPromptActive ? 0 : 1
        visible: opacity > 0
        enabled: !stage.spatialPromptActive
        scale: 0.94 + 0.06 * opacity
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        z: 2
        x: backdropPanel.x + (backdropPanel.width - width) / 2
        y: stage.listExpanded ? backdropPanel.y + backdropPanel.height + 8
            : surface.y + surface.height + 12
        width: sideActions.count * 44 + 16
        height: 44
        radius: height / 2
        material: "regular"
        useKwinEffect: AppearanceTokens.surface.usesKwinBlur
        fallbackEnabled: AppearanceTokens.surface.paintInQml
        scrimEnabled: AppearanceTokens.surface.usesBackdrop
        scrimLevel: "transparent"
        blurAnchor: sidePill

        Row {
            anchors.centerIn: parent
            spacing: 4
            Repeater {
                id: sideActions
                model: (WallpaperPreviewService.mode === "image" ? [
                    { action: "spatial-wallpaper", icon: "spatial-wallpaper", label: "开启空间壁纸服务" }
                ] : WallpaperPreviewService.mode === "slideshow" ? [
                    { action: "select-all", icon: "select-all", label: "选择全部图片" },
                    { action: "play-pause", icon: WallpaperPreviewService.slideshowPlaying ? "media-pause" : "media-play",
                        label: WallpaperPreviewService.slideshowPlaying ? "暂停预览" : "播放预览" }
                ] : []).concat([
                    { action: "transition", icon: "media-shuffle", label: "切换效果" },
                    { action: "settings", icon: "status-settings", label: "设置" },
                    { action: "exit", icon: "window-close", label: "退出预览" },
                    { action: "apply", icon: "check", label: WallpaperPreviewService.mode === "slideshow"
                        ? "应用已选 " + WallpaperPreviewService.selectedImages.length + " 张" : "应用壁纸" }
                ])
                delegate: AbstractButton {
                    id: sideButton
                    required property var modelData
                    width: 40
                    height: 40
                    padding: 0
                    hoverEnabled: true
                    enabled: modelData.action === "apply"
                        ? WallpaperPreviewService.presented && !WallpaperPreviewService.pending
                            && (WallpaperPreviewService.mode !== "slideshow" || WallpaperPreviewService.selectedImages.length >= 2)
                        : modelData.action !== "play-pause"
                            || (WallpaperPreviewService.selectedImages.length >= 2 && !WallpaperPreviewService.pending)
                    opacity: enabled ? 1 : 0.4
                    text: modelData.action === "spatial-wallpaper"
                        ? (SpatialWallpaperService.preparationRequested ? "取消准备"
                            : SpatialWallpaperService.previewEnabled ? "关闭空间效果" : modelData.label)
                        : modelData.label
                    Accessible.name: modelData.action === "transition"
                        ? text + "：" + (WallpaperCatalog.transitions.find(item => item.id === WallpaperService.transition)?.label || "")
                        : text
                    background: Item {}
                    contentItem: Item {
                        BundledIcon {
                            anchors.centerIn: parent
                            name: sideButton.modelData.icon
                            size: 20
                            visible: sideButton.modelData.action !== "spatial-wallpaper"
                                || !SpatialWallpaperService.preparationRequested
                            color: sideButton.modelData.action === "spatial-wallpaper" && SpatialWallpaperService.previewEnabled
                                ? "#80caff" : sidePill.foregroundColor
                            opacity: sideButton.down ? 0.55 : sideButton.hovered ? 0.8 : 1
                        }
                        BusyIndicator {
                            anchors.centerIn: parent
                            width: 24; height: 24
                            visible: sideButton.modelData.action === "spatial-wallpaper" && SpatialWallpaperService.preparationRequested
                            running: visible
                        }
                    }
                    ToolTip.visible: hovered
                    ToolTip.text: text
                    onClicked: {
                        if (modelData.action === "spatial-wallpaper") {
                            if (SpatialWallpaperService.preparationRequested || SpatialWallpaperService.previewEnabled)
                                SpatialWallpaperService.cancelPreparation()
                            else {
                                stage.listExpanded = false
                                effectFeedback.dismiss()
                                if (!SpatialResourceService.enabled) spatialServiceDialog.open()
                                else SpatialWallpaperService.prepareForEnable()
                            }
                        }
                        else if (modelData.action === "select-all")
                            WallpaperPreviewService.selectAll()
                        else if (modelData.action === "play-pause")
                            WallpaperPreviewService.toggleSlideshow()
                        else if (modelData.action === "exit")
                            WallpaperPreviewService.finish(false)
                        else if (modelData.action === "apply")
                            WallpaperPreviewService.finish(true)
                        else if (modelData.action === "transition")
                            stage.cycleTransition()
                        else if (modelData.action === "settings") {
                            WallpaperPreviewService.finish(false)
                            DesktopAppLauncher.openSettings()
                        }
                        else
                            stage.sideActionTriggered(modelData.action)
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }
            }
        }
    }

    DesktopConfirmDialog {
        id: spatialServiceDialog
        targetScreen: stage.screen
        titleText: "空间壁纸服务未开启"
        bodyText: "开启后可生成空间效果。首次开启会下载所需资源。"
        confirmText: "开启服务"
        iconName: "spatial-wallpaper"
        destructive: false
        onAccepted: SpatialWallpaperService.prepareForEnable()
    }

    SpatialPreparationOverlay {
        id: preparationOverlay
        targetScreen: stage.screen
        presentationAllowed: stage.visible && stage.screen === ScreenLifecycle.activeScreen
    }

    ActionFeedbackToast {
        id: effectFeedback
        z: 3
        x: (stage.width - width) / 2
        y: sidePill.y + sidePill.height + 10
    }

    LiquidGlassPanel {
        id: surface
        opacity: stage.spatialPromptActive ? 0 : 1
        visible: opacity > 0
        enabled: !stage.spatialPromptActive
        scale: 0.94 + 0.06 * opacity
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        z: 1
        property real jellyStretch: 0
        property real lensExpansion: 0
        readonly property int selectedIndex: ["image", "color", "slideshow", "theme"].indexOf(WallpaperPreviewService.mode)
        readonly property real segmentWidth: (width - 16) / 4
        x: backdropPanel.x + (backdropPanel.width - width - 12 - listToggle.width) / 2
        y: 48
        width: Math.min(400, stage.width - 32)
        height: 64
        radius: height / 2
        material: "thick"
        scrimEnabled: true
        scrimLevel: "readable"
        scrimOpacity: 1.0
        blurOverrideEnabled: true
        blurStrength: 1.0
        fallbackEnabled: true
        blurAnchor: surface

        Rectangle {
            id: segmentTrack
            x: 6; y: 6
            width: parent.width - 12
            height: parent.height - 12
            radius: height / 2
            color: Qt.rgba(0.02, 0.04, 0.08, 0.22)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.10)
            Rectangle {
                id: lens
                x: surface.selectedIndex * surface.segmentWidth + 4
                y: 3
                width: surface.segmentWidth - 8
                height: parent.height - 6
                radius: height / 2
                scale: 1 + surface.jellyStretch * 0.20
                color: Qt.rgba(1, 1, 1, 0.10 + surface.lensExpansion * 0.13)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.18 + surface.lensExpansion * 0.20)
                Behavior on x { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            }
            Row {
                anchors.fill: parent
                z: 1
                Repeater {
                    model: ["图像", "色彩", "幻灯片", "主题"]
                    delegate: Item {
                        id: option
                        required property int index
                        required property string modelData
                        width: segmentTrack.width / 4
                        height: segmentTrack.height
                        readonly property color iconColor: surface.selectedIndex === index ? "#ffffffff" : "#ccffffff"
                        Column {
                            anchors.centerIn: parent
                            spacing: 1
                            BundledIcon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                size: 20
                                name: ["image-x-generic", "color-picker", "media-play", "theme-appearance"][option.index]
                                color: option.iconColor
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: option.modelData
                                color: option.iconColor
                                font.pixelSize: 11
                                font.weight: surface.selectedIndex === option.index ? Font.DemiBold : Font.Medium
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                WallpaperPreviewService.setMode(["image", "color", "slideshow", "theme"][option.index])
                                jellyAnimation.restart()
                            }
                        }
                    }
                }
            }
        }
        SequentialAnimation {
            id: jellyAnimation
            NumberAnimation { target: surface; property: "jellyStretch"; to: 0.34; duration: 55; easing.type: Easing.OutQuad }
            NumberAnimation { target: surface; property: "jellyStretch"; to: -0.12; duration: 65; easing.type: Easing.InOutQuad }
            NumberAnimation { target: surface; property: "jellyStretch"; to: 0.04; duration: 55; easing.type: Easing.OutQuad }
            NumberAnimation { target: surface; property: "jellyStretch"; to: 0; duration: 75; easing.type: Easing.OutCubic }
        }
        SequentialAnimation {
            id: lensAnimation
            NumberAnimation { target: surface; property: "lensExpansion"; to: 1; duration: 100; easing.type: Easing.OutCubic }
            NumberAnimation { target: surface; property: "lensExpansion"; to: 0; duration: 250; easing.type: Easing.OutQuint }
        }
        Connections {
            target: WallpaperPreviewService
            function onModeChanged() { lensAnimation.restart() }
        }
    }

    LiquidGlassPanel {
        id: listToggle
        opacity: stage.spatialPromptActive ? 0 : 1
        visible: opacity > 0
        enabled: !stage.spatialPromptActive
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        x: surface.x + surface.width + 12
        y: surface.y + (surface.height - height) / 2
        width: 52; height: 52
        radius: width / 2
        material: "thick"
        scrimEnabled: true
        scrimLevel: "readable"
        scrimOpacity: 1.0
        blurOverrideEnabled: true
        blurStrength: 1.0
        fallbackEnabled: true
        blurAnchor: listToggle
        scale: toggleArea.pressed ? 0.94 : toggleArea.containsMouse ? 1.04 : 1
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Rectangle {
            anchors.centerIn: parent
            width: 40; height: 40
            radius: width / 2
            color: Qt.rgba(0.02, 0.04, 0.08, toggleArea.containsMouse ? 0.30 : 0.22)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.12)
        }
        BundledIcon {
            anchors.centerIn: parent
            size: 18
            name: "submenu"
            color: "white"
            rotation: stage.listExpanded ? -90 : 90
            Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }
        MouseArea {
            id: toggleArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: stage.listExpanded = !stage.listExpanded
        }
    }

    contentItem.focus: stage.screen === ScreenLifecycle.activeScreen && stage.visible
    contentItem.Keys.enabled: !stage.spatialPromptActive
    contentItem.Keys.onEscapePressed: WallpaperPreviewService.finish(false)
    contentItem.Keys.onReturnPressed: WallpaperPreviewService.finish(true)
}
