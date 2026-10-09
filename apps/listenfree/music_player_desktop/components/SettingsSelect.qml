pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

Item {
    id: control

    property var options: []
    property int currentIndex: 0
    property int visualIndex: currentIndex
    property bool darkMode: false
    // These two switches are intentionally public.  A settings host can turn
    // off decorative motion without changing the select's interaction model.
    property bool animationsEnabled: true
    property bool reducedMotion: false
    property int maxVisibleItems: 6
    readonly property var currentValue: optionValue(visualIndex)
    readonly property string currentLabel: optionLabel(visualIndex)
    readonly property bool menuOpen: menu.visible
    readonly property bool effectiveReducedMotion: reducedMotion || !animationsEnabled || !inheritedAnimationsEnabled()
    property int popupPositionRevision: 0
    signal valueSelected(var value, int index)

    onCurrentIndexChanged: visualIndex = currentIndex

    implicitWidth: Math.max(96, valueText.implicitWidth + 38)
    implicitHeight: 28
    activeFocusOnTab: enabled

    function optionAt(index) {
        if (!options || options.length === 0)
            return ""
        return options[Math.max(0, Math.min(options.length - 1, index))]
    }

    function optionLabel(index) {
        const option = optionAt(index)
        return option && typeof option === "object" && option.label !== undefined ? option.label : String(option)
    }

    function optionValue(index) {
        const option = optionAt(index)
        return option && typeof option === "object" && option.value !== undefined ? option.value : option
    }

    function inheritedAnimationsEnabled() {
        return animationsEnabledInAncestor(control.parent)
    }

    function animationsEnabledInAncestor(ancestor) {
        if (!ancestor)
            return true
        if (ancestor.objectName === "settingsPage")
            return ancestor.animationsEnabled
        return animationsEnabledInAncestor(ancestor.parent)
    }

    function select(index) {
        if (!enabled || !options || options.length === 0)
            return
        visualIndex = Math.max(0, Math.min(options.length - 1, index))
        valueSelected(optionValue(visualIndex), visualIndex)
        menu.close()
    }

    function openMenu() {
        if (!enabled || !options || options.length === 0)
            return
        if (menu.visible)
            return
        forceActiveFocus()
        // mapToItem() is not itself a binding dependency.  Bump a revision for
        // every open so the popup follows a row after the settings page scrolls.
        popupPositionRevision += 1
        menu.open()
    }

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: !control.enabled ? (control.darkMode ? "#303a43" : "#f0f1f2")
                                : triggerHover.hovered || control.menuOpen ? (control.darkMode ? "#4a5661" : "#ffffff")
                                                                            : (control.darkMode ? "#3a4650" : "#fafafa")
        border.width: control.activeFocus || control.menuOpen ? 2 : 1
        border.color: control.activeFocus || control.menuOpen ? AppTheme.accent : (control.darkMode ? "#5c6872" : "#d9dade")
        Behavior on color { ColorAnimation { duration: control.effectiveReducedMotion ? 0 : AppTheme.duration(100) } }
        Behavior on border.color { ColorAnimation { duration: control.effectiveReducedMotion ? 0 : AppTheme.duration(100) } }

        Text {
            id: valueText
            anchors.left: parent.left
            anchors.leftMargin: 11
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 32
            text: control.currentLabel
            elide: Text.ElideRight
            color: control.darkMode ? "#eef2f5" : "#303236"
            font.family: AppTheme.fontFamily
            font.pixelSize: 11
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            text: "⌄"
            color: control.darkMode ? "#c8d0d6" : "#72767a"
            font.pixelSize: 10
            rotation: control.menuOpen ? 180 : 0
            Behavior on rotation { NumberAnimation { duration: control.effectiveReducedMotion ? 0 : AppTheme.duration(160); easing.type: Easing.OutCubic } }
        }
    }

    HoverHandler { id: triggerHover }
    TapHandler {
        onPressedChanged: if (pressed) control.forceActiveFocus()
        onTapped: control.menuOpen ? menu.close() : control.openMenu()
    }
    Keys.onSpacePressed: control.menuOpen ? menu.close() : control.openMenu()
    Keys.onReturnPressed: control.menuOpen ? menu.close() : control.openMenu()
    Keys.onDownPressed: control.openMenu()
    Keys.onEscapePressed: menu.close()

    Popup {
        id: menu
        parent: Overlay.overlay
        popupType: Popup.Item
        property point anchorPoint: {
            control.popupPositionRevision
            return Overlay.overlay ? control.mapToItem(Overlay.overlay, 0, control.height + 3)
                                   : Qt.point(0, control.height + 3)
        }
        property real revealOffset: 0
        x: {
            if (!Overlay.overlay)
                return menu.anchorPoint.x
            return Math.max(0, Math.min(menu.anchorPoint.x, Overlay.overlay.width - width))
        }
        y: menu.anchorPoint.y + menu.revealOffset
        width: control.width
        height: Math.min(control.options ? control.options.length : 0, control.maxVisibleItems) * 34 + 10
        padding: 5
        margins: 0
        focus: true
        modal: false
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
        transformOrigin: Item.Top

        background: Rectangle {
            radius: 11
            color: control.darkMode ? "#f238424c" : "#f7ffffff"
            border.width: 1
            border.color: control.darkMode ? "#66727c" : "#d7dadd"
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: 10
                color: "transparent"
                border.width: 1
                border.color: control.darkMode ? "#12ffffff" : "#8affffff"
            }
        }

        contentItem: ListView {
            id: menuList
            clip: true
            model: control.options
            currentIndex: control.visualIndex
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: true
            keyNavigationWraps: true
            focus: true

            delegate: Rectangle {
                id: optionDelegate
                required property int index
                required property var modelData
                width: menuList.width
                height: 34
                radius: 8
                color: optionHover.hovered || optionDelegate.index === menuList.currentIndex
                       ? (control.darkMode ? "#344f6475" : "#dbeef9") : "transparent"
                Behavior on color { ColorAnimation { duration: control.effectiveReducedMotion ? 0 : AppTheme.duration(90) } }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 11
                    anchors.right: parent.right
                    anchors.rightMargin: 11
                    anchors.verticalCenter: parent.verticalCenter
                    text: control.optionLabel(optionDelegate.index)
                    elide: Text.ElideRight
                    color: control.darkMode ? "#f0f4f7" : "#25282b"
                    font.family: AppTheme.fontFamily
                    font.pixelSize: 11
                    font.weight: optionDelegate.index === control.visualIndex ? Font.DemiBold : Font.Normal
                }
                HoverHandler { id: optionHover; onHoveredChanged: if (hovered) menuList.currentIndex = optionDelegate.index }
                TapHandler { onTapped: control.select(optionDelegate.index) }
            }

            Keys.onReturnPressed: control.select(currentIndex)
            Keys.onSpacePressed: control.select(currentIndex)
            Keys.onEscapePressed: menu.close()
        }

        onOpened: {
            menuList.currentIndex = control.visualIndex
            menuList.forceActiveFocus()
        }

        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: control.effectiveReducedMotion ? 0 : AppTheme.duration(190); easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.985; to: 1; duration: control.effectiveReducedMotion ? 0 : AppTheme.duration(190); easing.type: Easing.OutCubic }
                NumberAnimation { property: "revealOffset"; from: -5; to: 0; duration: control.effectiveReducedMotion ? 0 : AppTheme.duration(190); easing.type: Easing.OutCubic }
            }
        }
        exit: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 1; to: 0; duration: control.effectiveReducedMotion ? 0 : AppTheme.duration(150); easing.type: Easing.InCubic }
                NumberAnimation { property: "scale"; from: 1; to: 0.985; duration: control.effectiveReducedMotion ? 0 : AppTheme.duration(150); easing.type: Easing.InCubic }
                NumberAnimation { property: "revealOffset"; from: 0; to: -5; duration: control.effectiveReducedMotion ? 0 : AppTheme.duration(150); easing.type: Easing.InCubic }
            }
        }
    }

    opacity: enabled ? 1 : 0.5
}
