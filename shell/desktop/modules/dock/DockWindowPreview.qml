import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import qs.desktop.modules.common

// Multi-window thumbnail preview popup with macOS-style window cards.
PopupWindow {
    id: preview

    property Item anchorItem: null
    property string appId: ""
    property string windowId: ""
    property string title: ""
    property var windows: []
    property real revealProgress: 0.0
    property bool closing: false

    // Exposed to the owning DockIcon so it can bridge pointer movement across
    // the gap between two separate Wayland popup surfaces.
    // HoverHandler on background tracks pointer presence across ALL child controls without occlusion.
    property bool pointerInside: backgroundHover.hovered || previewRootMouse.containsMouse

    signal activateRequested()

    readonly property var effectiveWindows: {
        WindowService.revision
        if (preview.windows && preview.windows.length > 0)
            return preview.windows
        if (preview.appId)
            return WindowService.windowsForApp(preview.appId)
        if (preview.windowId) {
            const win = WindowService.windowById(preview.windowId)
            return win ? [win] : []
        }
        return []
    }

    readonly property int windowCount: effectiveWindows.length
    readonly property real cardWidth: 220
    readonly property real cardHeight: 160
    readonly property real rowPadding: 8
    readonly property real rowSpacing: 8

    readonly property real calculatedWidth: rowPadding * 2
        + (windowCount > 0
           ? windowCount * cardWidth + (windowCount - 1) * rowSpacing
           : 0)

    readonly property real maxAllowedWidth: {
        const screenW = anchorItem?.targetScreen?.width ?? Quickshell.screens[0]?.width ?? 1920
        return Math.max(300, screenW * 0.88)
    }

    implicitWidth: Math.min(maxAllowedWidth, Math.max(cardWidth + rowPadding * 2, calculatedWidth))
    // The secondary action has its own toolbar row above the thumbnails.
    implicitHeight: 204
    color: "transparent"
    grabFocus: false

    function requestAllThumbnails() {
        const list = preview.effectiveWindows
        for (let i = 0; i < list.length; i++) {
            if (list[i]?.windowId)
                WindowService.requestThumbnail(list[i].windowId)
        }
    }

    onVisibleChanged: {
        if (visible)
            requestAllThumbnails()
    }

    onEffectiveWindowsChanged: {
        if (visible) {
            if (effectiveWindows.length === 0)
                dismissDockPopupImmediately()
            else
                requestAllThumbnails()
        }
    }

    function setDockPopupVisible(shouldOpen) {
        if (shouldOpen) {
            previewExit.stop()
            closing = false
            preview.visible = true
            revealProgress = 0.0
            previewRevealStart.restart()
            return
        }
        if (!preview.visible || closing)
            return
        closing = true
        previewExit.restart()
    }

    function dismissDockPopupImmediately() {
        previewRevealStart.stop()
        previewEntrance.stop()
        previewExit.stop()
        closing = false
        revealProgress = 0.0
        preview.visible = false
    }

    Timer {
        id: previewRevealStart
        interval: 16
        repeat: false
        onTriggered: {
            if (preview.visible && !preview.closing)
                previewEntrance.restart()
        }
    }

    NumberAnimation {
        id: previewEntrance
        target: preview
        property: "revealProgress"
        to: 1.0
        duration: 120
        easing.type: DockAnimation.elementEnterEasing
    }

    SequentialAnimation {
        id: previewExit
        NumberAnimation {
            target: preview
            property: "revealProgress"
            to: 0.0
            duration: 90
            easing.type: DockAnimation.elementExitEasing
        }
        ScriptAction {
            script: {
                preview.closing = false
                preview.visible = false
            }
        }
    }

    anchor {
        item: preview.anchorItem
        edges: Edges.Top
        gravity: Edges.Top
        margins.top: -6
    }

    LiquidGlassSurface {
        id: background
        anchors.fill: parent
        opacity: preview.revealProgress
        transform: Translate {
            y: (1.0 - preview.revealProgress) * 7
        }
        radius: 14
        baseColor: ThemeService.backgroundColor
        surfaceOpacity: 0.88
        materialDepth: 2
        material: "clear"

        HoverHandler {
            id: backgroundHover
        }

        MouseArea {
            id: previewRootMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }

        Column {
            anchors.fill: parent
            anchors.margins: preview.rowPadding
            spacing: 2

            Item {
                id: previewToolbar
                width: parent.width
                height: 26

                Text {
                    id: previewTitle
                    anchors.left: parent.left
                    anchors.right: plusBg.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: preview.title || preview.effectiveWindows[0]?.title || "窗口"
                    color: ThemeService.foregroundColor
                    elide: Text.ElideRight
                    font {
                        pixelSize: 12
                        weight: Font.DemiBold
                    }
                }

                Rectangle {
                    id: plusBg
                    width: 34
                    height: 26
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 8
                    color: plusMouse.containsMouse
                        ? Qt.rgba(ThemeService.accentColor.r, ThemeService.accentColor.g, ThemeService.accentColor.b, 0.35)
                        : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.07))
                    border.width: 1
                    border.color: plusMouse.containsMouse
                        ? Qt.rgba(ThemeService.accentColor.r, ThemeService.accentColor.g, ThemeService.accentColor.b, 0.65)
                        : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.16))

                    Behavior on color {
                        ColorAnimation { duration: 100 }
                    }
                    Behavior on border.color {
                        ColorAnimation { duration: 100 }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        color: ThemeService.foregroundColor
                        font.pixelSize: 21
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: plusMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const targetAppId = preview.appId
                                || (preview.effectiveWindows.length > 0
                                    ? (preview.effectiveWindows[0].identity?.desktopId
                                       || preview.effectiveWindows[0].desktopId
                                       || preview.effectiveWindows[0].appId
                                       || preview.effectiveWindows[0].identity?.rawAppId
                                       || preview.effectiveWindows[0].rawAppId)
                                    : "")
                            console.log("[DockPreview] new window clicked targetAppId=" + targetAppId)
                            if (targetAppId)
                                DockModelService.launchNewWindow(targetAppId)
                            DockModelService.setDockPopupVisible(preview, false)
                        }
                    }
                }
            }

            Flickable {
                id: cardsFlickable
                width: parent.width
                height: preview.cardHeight
                contentWidth: cardsRow.implicitWidth
                contentHeight: height
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                Row {
                    id: cardsRow
                    spacing: preview.rowSpacing
                    height: parent.height

                Repeater {
                    model: preview.effectiveWindows
                    delegate: Item {
                        id: cardDelegate
                        required property var modelData
                        required property int index

                        width: preview.cardWidth
                        height: preview.cardHeight

                        readonly property string winId: modelData.windowId ?? ""
                        readonly property string winTitle: modelData.title ?? ""
                        readonly property bool isWinActivated: !!(modelData.toplevel?.activated)
                        readonly property string thumbUrl: {
                            WindowService.thumbnailRevision
                            return winId ? WindowService.thumbnailUrl(winId) : ""
                        }

                        Rectangle {
                            id: cardBg
                            anchors.fill: parent
                            radius: 8
                            // Let the popup's glass show through; the card no
                            // longer adds a separate dark rectangle behind a
                            // window preview. Keep the active window visibly
                            // distinct when the pointer is elsewhere.
                            color: cardMouse.containsMouse
                                ? (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06))
                                : (isWinActivated
                                    ? Qt.rgba(ThemeService.accentColor.r,
                                        ThemeService.accentColor.g,
                                        ThemeService.accentColor.b, 0.16)
                                    : "transparent")
                            border.width: 0

                            Behavior on color {
                                ColorAnimation { duration: 100 }
                            }

                            // Thumbnail display container
                            Item {
                                id: thumbnailBox
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.topMargin: 6
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                anchors.bottomMargin: 6

                                Image {
                                    id: thumbMetrics
                                    anchors.fill: parent
                                    source: cardDelegate.thumbUrl
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    cache: false
                                    opacity: 0
                                }

                                Rectangle {
                                    id: thumbCrop
                                    width: Math.round(thumbMetrics.paintedWidth)
                                    height: Math.round(thumbMetrics.paintedHeight)
                                    anchors.centerIn: parent
                                    radius: 4
                                    color: "transparent"
                                    visible: thumbMetrics.status === Image.Ready
                                    layer.enabled: true
                                    layer.effect: OpacityMask {
                                        maskSource: Rectangle {
                                            width: thumbCrop.width
                                            height: thumbCrop.height
                                            radius: thumbCrop.radius
                                            color: "black"
                                            visible: false
                                        }
                                    }

                                    Image {
                                        anchors.fill: parent
                                        source: cardDelegate.thumbUrl
                                        fillMode: Image.Stretch
                                        asynchronous: true
                                        cache: false
                                    }
                                }

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    visible: !thumbCrop.visible

                                    AppIcon {
                                        width: 32
                                        height: 32
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        source: modelData.iconSource ?? modelData.identity?.iconSource ?? ""
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: cardDelegate.thumbUrl ? "正在刷新…" : "正在获取预览…"
                                        color: ThemeService.foregroundColor
                                        style: Text.Outline
                                        styleColor: Qt.rgba(0, 0, 0, 0.40)
                                        opacity: 0.72
                                        font {
                                            pixelSize: 10
                                            weight: Font.Normal
                                        }
                                    }
                                }
                            }

                            // Close button '×'
                            Rectangle {
                                id: closeBtn
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 5
                                width: 20
                                height: 20
                                radius: 10
                                color: closeMouse.containsMouse
                                    ? Qt.rgba(0.92, 0.25, 0.25, 0.90)
                                    : (ThemeService.isDark ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(0, 0, 0, 0.35))
                                opacity: cardMouse.containsMouse || closeMouse.containsMouse ? 1.0 : 0.0
                                visible: opacity > 0.01
                                z: 5

                                Behavior on opacity {
                                    NumberAnimation { duration: 100 }
                                }
                                Behavior on color {
                                    ColorAnimation { duration: 100 }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: "✕"
                                    color: "white"
                                    font.pixelSize: 10
                                    font.bold: true
                                }

                                MouseArea {
                                    id: closeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: function(mouse) {
                                        mouse.accepted = true
                                        WindowService.closeWindow(cardDelegate.winId)
                                        if (preview.effectiveWindows.length <= 1)
                                            DockModelService.setDockPopupVisible(preview, false)
                                    }
                                }
                            }

                            // Card click to activate window
                            MouseArea {
                                id: cardMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    WindowService.activateWindow(cardDelegate.winId)
                                    DockModelService.setDockPopupVisible(preview, false)
                                }
                            }
                        }
                    }
                }

            }
        }
    }

        }

    BackgroundEffect.blurRegion: preview.visible ? previewBlurHolder : null

    Region {
        id: previewBlurHolder
        RoundedBlurRegion {
            item: background
            radius: background.radius
        }
    }
}
