import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.desktop.modules.common
import qs.desktop.modules.dock

// Stage-Manager / Mission Control styled workspace overview.
// Presents a liquid-frosted backdrop, top virtual-desktop pill capsule,
// and adaptive window cards with live thumbnails, headers, and quick-close buttons.
PanelWindow {
    id: root

    WlrLayershell.namespace: "quickshell-overview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    property bool open: false
    property int selectedDesktopIndex: 0
    property int selectedWindowIndex: 0

    signal closeRequested

    // The controller already suppresses `open` while no real output exists.
    // Reading PanelWindow.screen from its own visibility binding creates a
    // Quickshell window/screen resolution cycle.
    visible: open
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    focusable: open
    anchors { top: true; left: true; right: true; bottom: true }

    // Fluid reveal transition
    property real revealProgress: open ? 1.0 : 0.0
    Behavior on revealProgress {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    readonly property var desktops: WindowService.desktops || []
    readonly property int desktopCount: desktops.length
    readonly property int currentDesktopIndex: {
        for (let i = 0; i < desktops.length; i++) {
            if (desktops[i].id === WindowService.currentDesktopId)
                return i
        }
        return -1
    }

    // Windows on the current desktop (or pinned to all desktops).
    readonly property var currentWindows: {
        WindowService.revision
        const currentId = WindowService.currentDesktopId
        const records = WindowService.records || []
        const result = []
        for (let i = 0; i < records.length; i++) {
            const record = records[i]
            const onDesktop = record.onAllDesktops
                || (Array.isArray(record.desktopIds) && record.desktopIds.indexOf(currentId) >= 0)
            if (onDesktop)
                result.push(record)
        }
        return result
    }

    // KWin compositor backdrop blur
    BackgroundEffect.blurRegion: (root.visible && root.open) ? overviewBlurRegionHolder : null

    Region {
        id: overviewBlurRegionHolder
        RoundedBlurRegion {
            item: backdrop
            radius: 0
        }
    }

    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Qt.rgba(0.02, 0.03, 0.06, 0.65)
        opacity: root.revealProgress
    }

    // Fullscreen keyboard navigation handler
    Item {
        id: keyboardHandler
        anchors.fill: parent
        focus: root.open

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.closeRequested()
                event.accepted = true
            } else if (event.key === Qt.Key_Tab) {
                if (root.currentWindows.length > 0) {
                    if (event.modifiers & Qt.ShiftModifier) {
                        root.selectedWindowIndex = (root.selectedWindowIndex - 1 + root.currentWindows.length) % root.currentWindows.length
                    } else {
                        root.selectedWindowIndex = (root.selectedWindowIndex + 1) % root.currentWindows.length
                    }
                }
                event.accepted = true
            } else if (event.key === Qt.Key_Backtab) {
                if (root.currentWindows.length > 0) {
                    root.selectedWindowIndex = (root.selectedWindowIndex - 1 + root.currentWindows.length) % root.currentWindows.length
                }
                event.accepted = true
            } else if (event.key === Qt.Key_Left) {
                if (root.currentWindows.length > 0)
                    root.selectedWindowIndex = Math.max(0, root.selectedWindowIndex - 1)
                event.accepted = true
            } else if (event.key === Qt.Key_Right) {
                if (root.currentWindows.length > 0)
                    root.selectedWindowIndex = Math.min(root.currentWindows.length - 1, root.selectedWindowIndex + 1)
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (root.selectedWindowIndex >= 0 && root.selectedWindowIndex < root.currentWindows.length) {
                    const winId = root.currentWindows[root.selectedWindowIndex].windowId
                    WindowService.activateWindow(winId)
                    root.closeRequested()
                } else if (root.desktops[root.selectedDesktopIndex]) {
                    WindowService.switchDesktop(root.desktops[root.selectedDesktopIndex].id)
                    root.closeRequested()
                }
                event.accepted = true
            } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
                if (root.selectedWindowIndex >= 0 && root.selectedWindowIndex < root.currentWindows.length) {
                    const winId = root.currentWindows[root.selectedWindowIndex].windowId
                    WindowService.closeWindow(winId)
                    event.accepted = true
                }
            }
        }
    }

    // Dismiss on click outside any card
    MouseArea {
        anchors.fill: parent
        z: 0
        onClicked: root.closeRequested()
    }

    // Main layout container
    Item {
        anchors.fill: parent
        opacity: root.revealProgress
        scale: 0.96 + 0.04 * root.revealProgress
        Behavior on scale {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }

        Column {
            anchors {
                fill: parent
                topMargin: 36
                bottomMargin: 36
                leftMargin: 48
                rightMargin: 48
            }
            spacing: 32

            // ── 1. Top Virtual Desktops Pill Bar ──────────────────────────────
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: desktopPillRow.width + 16
                height: 48

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1
                    border.color: Qt.rgba(255, 255, 255, 0.16)
                }

                Row {
                    id: desktopPillRow
                    anchors.centerIn: parent
                    spacing: 8

                    Repeater {
                        model: root.desktops
                        delegate: Rectangle {
                            required property var modelData
                            required property int index

                            readonly property bool isCurrent: index === root.currentDesktopIndex
                            readonly property bool isSelected: index === root.selectedDesktopIndex
                            readonly property bool isHovered: desktopPillMouse.containsMouse

                            width: Math.max(92, desktopLabel.implicitWidth + 36)
                            height: 34
                            radius: 17

                            color: isCurrent
                                ? Qt.rgba(255, 255, 255, 0.24)
                                : (isSelected ? Qt.rgba(255, 255, 255, 0.14) : (isHovered ? Qt.rgba(255, 255, 255, 0.09) : "transparent"))
                            border.width: isCurrent || isSelected ? 1 : 0
                            border.color: isCurrent ? Qt.rgba(255, 255, 255, 0.45) : Qt.rgba(255, 255, 255, 0.25)

                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }

                            Row {
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    text: "󰍹"
                                    font.pixelSize: 13
                                    color: isCurrent ? "#ffffff" : Qt.rgba(1, 1, 1, 0.65)
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    id: desktopLabel
                                    text: modelData.name || ("桌面 " + (index + 1))
                                    color: isCurrent ? "#ffffff" : Qt.rgba(1, 1, 1, 0.78)
                                    font { pixelSize: 12; weight: isCurrent ? Font.Bold : Font.DemiBold }
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: desktopPillMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.selectedDesktopIndex = index
                                    WindowService.switchDesktop(modelData.id)
                                }
                            }
                        }
                    }
                }
            }

            // ── 2. Current-Desktop Window Grid ────────────────────────────────
            Item {
                id: windowGridContainer
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width, windowGrid.implicitWidth)
                height: windowGrid.implicitHeight

                readonly property real maxContentWidth: Math.min(1400, root.width - 120)
                readonly property int windowCount: root.currentWindows.length
                readonly property int targetColumns: {
                    if (windowCount <= 2) return Math.max(1, windowCount)
                    if (windowCount <= 4) return Math.min(windowCount, 4)
                    return Math.min(4, Math.max(2, Math.floor(maxContentWidth / 300)))
                }
                readonly property real cardWidth: {
                    if (windowCount <= 1) return Math.min(540, maxContentWidth)
                    if (windowCount === 2) return Math.min(440, (maxContentWidth - 24) / 2)
                    if (windowCount <= 4) return Math.min(350, (maxContentWidth - (targetColumns - 1) * 24) / targetColumns)
                    return Math.min(310, Math.floor((maxContentWidth - (targetColumns - 1) * 20) / targetColumns))
                }
                readonly property real cardHeight: cardWidth * 0.65 + 46

                Grid {
                    id: windowGrid
                    anchors.horizontalCenter: parent.horizontalCenter
                    columns: windowGridContainer.targetColumns
                    spacing: windowGridContainer.windowCount <= 4 ? 24 : 18

                    Repeater {
                        model: root.currentWindows
                        delegate: Item {
                            id: cardDelegate
                            required property var modelData
                            required property int index

                            width: windowGridContainer.cardWidth
                            height: windowGridContainer.cardHeight

                            readonly property bool isSelected: index === root.selectedWindowIndex
                            readonly property bool isHovered: cardMouse.containsMouse

                            scale: isHovered || isSelected ? 1.028 : 1.0
                            y: isHovered || isSelected ? -4 : 0
                            Behavior on scale {
                                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                            }
                            Behavior on y {
                                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                            }

                            // Card Glass Surface
                            Rectangle {
                                id: cardBg
                                anchors.fill: parent
                                radius: 16
                                color: cardDelegate.isSelected
                                    ? Qt.rgba(0.12, 0.18, 0.28, 0.88)
                                    : (cardDelegate.isHovered ? Qt.rgba(0.08, 0.11, 0.18, 0.80) : Qt.rgba(0.04, 0.06, 0.10, 0.65))
                                border.width: cardDelegate.isSelected ? 2 : 1
                                border.color: cardDelegate.isSelected
                                    ? "#38bdf8"
                                    : (cardDelegate.isHovered ? Qt.rgba(255, 255, 255, 0.38) : Qt.rgba(255, 255, 255, 0.14))

                                Behavior on color { ColorAnimation { duration: 140 } }
                                Behavior on border.color { ColorAnimation { duration: 140 } }

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 8

                                    // Card Header: App Icon + App Name + Window Title + Close Button
                                    Item {
                                        width: parent.width
                                        height: 28

                                        Row {
                                            anchors {
                                                left: parent.left
                                                right: closeBtn.left
                                                rightMargin: 8
                                                verticalCenter: parent.verticalCenter
                                            }
                                            spacing: 8

                                            IconImage {
                                                width: 20
                                                height: 20
                                                anchors.verticalCenter: parent.verticalCenter
                                                source: modelData.iconSource || ""
                                            }

                                            Text {
                                                text: modelData.identity?.name || modelData.title || "应用"
                                                color: "white"
                                                font { pixelSize: 12; weight: Font.Bold }
                                                elide: Text.ElideRight
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            Text {
                                                visible: text.length > 0
                                                text: "— " + (modelData.title || "")
                                                color: Qt.rgba(1, 1, 1, 0.58)
                                                font { pixelSize: 11; weight: Font.Normal }
                                                elide: Text.ElideRight
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        // Close Button
                                        Rectangle {
                                            id: closeBtn
                                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                            width: 22
                                            height: 22
                                            radius: 11
                                            color: closeMouse.containsMouse
                                                ? "#ef4444"
                                                : (cardDelegate.isHovered ? Qt.rgba(1, 1, 1, 0.16) : "transparent")
                                            opacity: cardDelegate.isHovered || cardDelegate.isSelected ? 1.0 : 0.0

                                            Behavior on opacity { NumberAnimation { duration: 120 } }
                                            Behavior on color { ColorAnimation { duration: 120 } }

                                            Text {
                                                anchors.centerIn: parent
                                                text: "✕"
                                                font.pixelSize: 10
                                                color: "white"
                                            }

                                            MouseArea {
                                                id: closeMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    WindowService.closeWindow(modelData.windowId)
                                                }
                                            }
                                        }
                                    }

                                    // Thumbnail / Window Preview Viewport
                                    Rectangle {
                                        width: parent.width
                                        height: parent.height - 36
                                        radius: 10
                                        color: Qt.rgba(0, 0, 0, 0.35)
                                        clip: true

                                        readonly property string thumbUrl: WindowService.thumbnailUrl(modelData.windowId)

                                        Image {
                                            id: previewImg
                                            anchors.fill: parent
                                            visible: !!parent.thumbUrl
                                            source: parent.thumbUrl
                                            sourceSize: Qt.size(600, 400)
                                            fillMode: Image.PreserveAspectCrop
                                            smooth: true
                                        }

                                        // Placeholder when no live thumbnail is available yet
                                        Item {
                                            anchors.fill: parent
                                            visible: !previewImg.visible

                                            Column {
                                                anchors.centerIn: parent
                                                spacing: 8

                                                IconImage {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    width: 44
                                                    height: 44
                                                    source: modelData.iconSource || ""
                                                }

                                                Text {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    text: modelData.title || "窗口预览"
                                                    color: Qt.rgba(1, 1, 1, 0.40)
                                                    font.pixelSize: 11
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Card Click to Activate Window
                            MouseArea {
                                id: cardMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const windowId = modelData.windowId
                                    WindowService.activateWindow(windowId)
                                    root.closeRequested()
                                    WindowService.requestThumbnail(windowId)
                                }
                            }
                        }
                    }
                }
            }

            // Empty State Notice
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 320
                height: 120
                visible: root.currentWindows.length === 0

                Column {
                    anchors.centerIn: parent
                    spacing: 12

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "󰖲"
                        font.pixelSize: 32
                        color: Qt.rgba(1, 1, 1, 0.25)
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "当前桌面没有打开的应用窗口"
                        color: Qt.rgba(1, 1, 1, 0.45)
                        font { pixelSize: 13; weight: Font.Medium }
                    }
                }
            }
        }
    }

    onOpenChanged: {
        if (open) {
            selectedDesktopIndex = Math.max(0, root.currentDesktopIndex)
            selectedWindowIndex = 0
            // Request thumbnails for all current desktop windows
            const windows = root.currentWindows
            for (let i = 0; i < windows.length; i++) {
                WindowService.requestThumbnail(windows[i].windowId)
            }
        }
    }
}
