pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Window
import "../foundation" as Foundation

// Host-owned select state with a shared liquid surface or preserved Material
// outline. Decorative reflection is independent from actual keyboard focus.
Item {
    id: root

    // Width follows the content: left pad + label + gap + glyph + right pad.
    // The floor keeps a placeholder-only field from collapsing.
    implicitWidth: Math.max(72, 13 + label.implicitWidth + 9 + chevron.implicitWidth + 12)
    implicitHeight: 36
    activeFocusOnTab: true
    opacity: enabled ? 1 : .38

    property LiquidBackdrop backdrop: LiquidStyle.backdropFor(root.Window.window)
    property bool reduceMotion: Foundation.AppTheme.reduceMotion
    property var model: []
    property string textRole: ""
    property int currentIndex: 0
    property string placeholder: ""
    property string appearanceMode: "system"
    // App accent for the selection highlight; bind it at the call site, like
    // LiquidGlassSwitch. SystemPalette.highlight would follow the desktop
    // colour scheme (often pink) instead of the app's accent.
    property color accentColor: "#0a84ff"
    property color focusRingColor: accentColor
    property color selectedTextColor: accentColor
    property color textColor: darkAppearance ? "#f5f5f7" : "#1d1d1f"
    property color mutedTextColor: darkAppearance ? "#98989d" : "#6e6e73"
    property color sheetColor: darkAppearance ? "#262b31" : "#f6f8fb"
    property color outlineColor: darkAppearance ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12)
    // Material 3 hosts draw the full-radius outlined dropdown; everything
    // else gets the plain rounded field. Follows the application-wide form.
    property bool materialForm: ControlForm.materialForm

    readonly property real fieldRadius: height / 2

    // Fired when the user picks a row. Owners update their persistent state
    // through IPC and write currentIndex back; the visual result is drawn
    // optimistically and rolled back below if that acknowledgement never
    // arrives (same contract as LiquidSegmentedControl).
    signal activated(int index)

    SystemPalette {
        id: controlPalette
        colorGroup: SystemPalette.Active
    }

    readonly property bool darkAppearance: {
        if (root.appearanceMode === "dark") return true
        if (root.appearanceMode === "light") return false
        const color = controlPalette.window
        return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722 < 0.5
    }

    property bool _hovered: false
    // Optimistic visual selection, confirmed or rolled back by
    // confirmationTimer once the owner's async write lands (or doesn't).
    property int _visualIndex: 0

    readonly property int safeIndex: clampedIndex(currentIndex)

    function clampedIndex(index) {
        return model.length > 0
            ? Math.max(0, Math.min(model.length - 1, index)) : 0
    }

    function labelAt(index) {
        if (index < 0 || index >= model.length) return ""
        const value = model[index]
        return textRole ? String(value[textRole] || "") : String(value)
    }

    onCurrentIndexChanged: {
        _visualIndex = clampedIndex(currentIndex)
        confirmationTimer.stop()
    }
    onModelChanged: _visualIndex = clampedIndex(currentIndex)
    Component.onCompleted: _visualIndex = safeIndex

    Timer {
        id: confirmationTimer
        interval: 420
        repeat: false
        // Roll the highlight back only if the externally-owned state did not
        // acknowledge this optimistic selection.
        onTriggered: root._visualIndex = root.safeIndex
    }

    function openMenu() {
        if (!enabled || menu.opened) return
        const overlay = Overlay.overlay
        if (!overlay) return
        const origin = root.mapToItem(overlay, 0, 0)
        const openUp = origin.y + root.height + menu.implicitHeight + 5
            > overlay.height - 12
        menu.x = Math.max(12, Math.min(overlay.width - menu.width - 12,
            origin.x + root.width - menu.width)) - origin.x
        menu.y = openUp ? -menu.implicitHeight - 5 : root.height + 5
        menu.open()
    }

    function closeMenu() { menu.close() }

    function toggleMenu() {
        if (menu.opened) menu.close()
        else openMenu()
    }

    function select(index) {
        if (index < 0 || index >= model.length) return
        // Draw the result first. The owner may update its persistent state
        // through IPC, but that round trip must not consume the first click.
        _visualIndex = index
        activated(index)
        confirmationTimer.restart()
        menu.close()
    }

    // ── Closed field ─────────────────────────────────────────────────────

    Accessible.role: Accessible.ComboBox
    Accessible.name: placeholder || labelAt(safeIndex)
    Accessible.focusable: enabled
    Accessible.focused: activeFocus
    Accessible.onPressAction: root.toggleMenu()

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Down || event.key === Qt.Key_Up
                || event.key === Qt.Key_Space
                || event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
            toggleMenu()
            event.accepted = true
        }
    }

    Item {
        id: field
        anchors.fill: parent

        // Preserve the tonal branch's solid outline and flat inset fill.
        Rectangle {
            anchors.fill: parent
            visible: root.materialForm
            radius: root.fieldRadius
            color: root.activeFocus || menu.opened ? root.focusRingColor : root.outlineColor
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: Math.max(0, root.fieldRadius - 1)
                color: root.darkAppearance
                    ? Qt.rgba(1, 1, 1, root._hovered || menu.opened ? .12 : .08)
                    : Qt.rgba(0, 0, 0, root._hovered || menu.opened ? .08 : .05)
            }
        }
        LiquidSurface {
            anchors.fill: parent
            visible: !root.materialForm
            radius: root.fieldRadius
            backdrop: root.backdrop
            darkAppearance: root.darkAppearance
            tintColor: root.darkAppearance ? "#ffffff" : "#000000"
            tintStrength: root.darkAppearance
                ? (root._hovered || menu.opened ? .12 : .08)
                : (root._hovered || menu.opened ? .08 : .05)
            readability: 0
            blurStrength: .35
            refractionStrength: 1.5
            magnification: 1.015
            reflectionStrength: pointer.pressed ? .65 : root._hovered || menu.opened ? .52 : .38
            rimColor: root.outlineColor
            Behavior on reflectionStrength { NumberAnimation { duration: root.reduceMotion ? 0 : 150; easing.type: Easing.OutCubic } }
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: -1
            radius: root.fieldRadius
            visible: !root.materialForm && (root.activeFocus || menu.opened)
            color: "transparent"
            border.width: 2
            border.color: root.focusRingColor
        }
        Text {
            id: label
            x: 13
            width: Math.max(0, parent.width - x - 12 - chevron.implicitWidth - 9)
            anchors.verticalCenter: parent.verticalCenter
            text: root.labelAt(root._visualIndex) || root.placeholder
            color: root.labelAt(root._visualIndex).length > 0 ? root.textColor : root.mutedTextColor
            font.pixelSize: 13
            font.weight: Font.Medium
            elide: Text.ElideRight
        }
        Text {
            id: chevron
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: "↕"
            color: root.mutedTextColor
            font.pixelSize: 13
        }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onEntered: root._hovered = true
        onExited: root._hovered = false
        onPressed: root.forceActiveFocus()
        onClicked: root.toggleMenu()
    }

    // ── Choice sheet ─────────────────────────────────────────────────────

    Popup {
        id: menu
        width: Math.max(188, root.width + 34)
        implicitHeight: Math.min(360, choices.implicitHeight + 12)
        padding: 6
        modal: false
        focus: true
        // Not CloseOnPressOutside: that closes on the pill press itself, and
        // the pill's click would then toggle straight back open. Outside
        // presses close here; the pill toggles through its own MouseArea.
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        onOpened: scroller.focusCurrent()
        onClosed: { if (root.enabled) root.forceActiveFocus(Qt.PopupFocusReason) }
        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: root.reduceMotion ? 0 : 140; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: root.reduceMotion ? 0 : 150; easing.type: Easing.OutCubic }
            }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; to: 0; duration: root.reduceMotion ? 0 : 100 }
        }
        background: Item {
            Rectangle {
                anchors.fill: parent
                visible: root.materialForm
                radius: 12
                color: root.sheetColor
                border.width: 1
                border.color: root.outlineColor
            }
            LiquidSurface {
                anchors.fill: parent
                visible: !root.materialForm
                radius: 12
                backdrop: root.backdrop
                darkAppearance: root.darkAppearance
                tintColor: Qt.rgba(root.sheetColor.r, root.sheetColor.g, root.sheetColor.b, 1)
                tintStrength: root.sheetColor.a
                readability: 0
                blurStrength: .55
                refractionStrength: 1.5
                magnification: 1.015
                reflectionStrength: .35
                rimColor: root.outlineColor
            }
        }
        contentItem: Flickable {
            id: scroller
            clip: true
            contentHeight: choices.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            function focusCurrent() {
                const target = choiceRepeater.itemAt(root.safeIndex)
                if (target) target.forceActiveFocus()
            }

            Column {
                id: choices
                Repeater {
                    id: choiceRepeater
                    model: root.model
                    delegate: Item {
                        id: choiceDelegate

                        required property var modelData
                        required property int index
                        width: menu.width - 12
                        height: 36
                        enabled: root.enabled
                        activeFocusOnTab: false

                        Accessible.role: Accessible.MenuItem
                        Accessible.name: root.labelAt(choiceDelegate.index)
                        Accessible.focusable: true
                        Accessible.focused: activeFocus
                        Accessible.onPressAction: root.select(choiceDelegate.index)

                        Keys.onPressed: function(event) {
                            if (event.key === Qt.Key_Down) {
                                const next = choiceRepeater.itemAt(Math.min(root.model.length - 1, choiceDelegate.index + 1))
                                if (next) next.forceActiveFocus()
                            } else if (event.key === Qt.Key_Up) {
                                const prev = choiceRepeater.itemAt(Math.max(0, choiceDelegate.index - 1))
                                if (prev) prev.forceActiveFocus()
                            } else if (event.key === Qt.Key_Home) {
                                const first = choiceRepeater.itemAt(0)
                                if (first) first.forceActiveFocus()
                            } else if (event.key === Qt.Key_End) {
                                const last = choiceRepeater.itemAt(root.model.length - 1)
                                if (last) last.forceActiveFocus()
                            } else if (event.key === Qt.Key_Space
                                       || event.key === Qt.Key_Enter
                                       || event.key === Qt.Key_Return) {
                                root.select(choiceDelegate.index)
                            } else {
                                return
                            }
                            event.accepted = true
                        }

                        // Keep the highlighted row visible while navigating.
                        onActiveFocusChanged: {
                            if (!activeFocus) return
                            const yTop = choiceDelegate.mapToItem(scroller, 0, 0).y
                            if (yTop < 0)
                                scroller.contentY = Math.max(0, scroller.contentY + yTop)
                            else if (yTop + height > scroller.height)
                                scroller.contentY = Math.min(
                                    scroller.contentHeight - scroller.height,
                                    scroller.contentY + yTop + height - scroller.height)
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: choiceDelegate.index === root._visualIndex
                                ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                                          root.accentColor.b, root.darkAppearance ? 0.22 : 0.13)
                                : (hit.containsMouse
                                   ? (root.darkAppearance ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.05))
                                   : "transparent")
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            radius: 7
                            visible: choiceDelegate.activeFocus
                            color: "transparent"
                            border.width: 2
                            border.color: root.focusRingColor
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.labelAt(parent.index)
                            color: choiceDelegate.index === root._visualIndex
                                ? root.selectedTextColor : root.textColor
                            font.pixelSize: 13
                            font.weight: choiceDelegate.index === root._visualIndex
                                ? Font.DemiBold : Font.Normal
                        }
                        VectorIcon {
                            anchors.right: parent.right
                            anchors.rightMargin: 13
                            anchors.verticalCenter: parent.verticalCenter
                            visible: choiceDelegate.index === root._visualIndex
                            name: "check"
                            color: root.selectedTextColor
                            size: 13
                        }
                        MouseArea {
                            id: hit
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.select(parent.index)
                        }
                    }
                }
            }
        }
    }
}
