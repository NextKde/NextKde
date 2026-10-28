pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Window
import "../foundation" as Foundation

// Host-owned selection with the same solid/liquid trigger as LiquidActionButton.
// Decorative reflection is independent from actual keyboard focus.
Item {
    id: root

    // Width follows the content: left pad + label + gap + glyph + right pad.
    // The floor keeps a placeholder-only field from collapsing.
    implicitWidth: Math.ceil(Math.max(plainTrigger ? 0 : 72,
        (plainTrigger ? 0 : 25) + label.implicitWidth + 9 + chevron.implicitWidth))
    implicitHeight: Foundation.AppTheme.compactDesign ? 28 : 36
    activeFocusOnTab: true
    opacity: enabled ? 1 : .38

    property LiquidBackdrop backdrop: LiquidStyle.backdropForItem(root, root.Window.window)
    property bool reduceMotion: Foundation.AppTheme.reduceMotion
    property var model: []
    property string textRole: ""
    property int currentIndex: 0
    property string placeholder: ""
    // Settings pop-up buttons use paired up/down chevrons; other selects retain their indicator.
    property string indicatorStyle: "chevron"
    // Value-only settings trigger: no surface, border, shadow or button hover fill.
    // The popup keeps its independently chosen material.
    property bool plainTrigger: false
    property bool indicatorBackground: false
    property color indicatorBackgroundColor: darkAppearance ? "#48484a" : "#e1e1e3"
    property bool popupMaterialForm: materialForm
    property color popupTextColor: textColor
    property bool highlightSelectedOption: false
    property bool neutralOptionHighlight: false
    property bool compactPopup: false
    property real popupBorderWidth: 1
    property bool popupShadowEnabled: false
    property int popupFontWeight: Font.Medium
    readonly property bool popupOpened: menu.opened
    property string appearanceMode: "system"
    // App accent for the selection highlight; bind it at the call site, like
    // LiquidGlassSwitch. SystemPalette.highlight would follow the desktop
    // colour scheme (often pink) instead of the app's accent.
    property color accentColor: "#0a84ff"
    property color focusRingColor: accentColor
    property color selectedTextColor: accentColor
    property color textColor: plainTrigger || materialForm
        ? (darkAppearance ? "#f5f5f7" : "#000000")
        : (darkAppearance ? "#D6D6DA" : "#55555A")
    property color mutedTextColor: darkAppearance ? "#98989d" : "#6e6e73"
    property color sheetColor: darkAppearance
        ? (materialForm && Foundation.AppTheme.compactDesign ? Foundation.AppTheme.contentBackground : "#262b31")
        : "#f6f6f6"
    property color outlineColor: darkAppearance ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12)
    // Solid or liquid button appearance, following the application-wide form.
    property bool materialForm: ControlForm.materialForm

    property string liquidIntensity: LiquidStyle.intensityLevel
    property bool shadowEnabled: false
    property int shadowLevel: LiquidStyle.shadowLevel

    property real cornerRadius: height / 2
    readonly property real fieldRadius: cornerRadius

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
        const margin = root.popupShadowEnabled ? 20 : 12
        const openUp = origin.y + root.height + menu.implicitHeight + 5
            > overlay.height - margin
        menu.x = Math.max(margin, Math.min(overlay.width - menu.width - margin,
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

    LiquidActionButton {
        id: field
        anchors.fill: parent
        // Root owns keyboard focus and accessibility; the trigger handles pointer input.
        focusPolicy: Qt.NoFocus
        Accessible.ignored: true
        opacity: 1 // Disabled opacity is applied once by root.
        materialForm: root.plainTrigger || root.materialForm
        cornerRadius: root.cornerRadius
        backdrop: root.backdrop
        liquidIntensity: root.liquidIntensity
        darkAppearance: root.darkAppearance
        reduceMotion: root.reduceMotion
        shadowEnabled: root.shadowEnabled
        shadowLevel: root.shadowLevel
        textColor: root.textColor
        accentColor: root.accentColor
        focusRingColor: root.focusRingColor
        surfaceColor: root.darkAppearance
            ? (Foundation.AppTheme.compactDesign ? Foundation.AppTheme.controlBackground : "#303640")
            : "#f6f6f6"
        leftPadding: root.plainTrigger ? 0 : 13
        rightPadding: root.plainTrigger ? 0 : 12
        topPadding: 0
        bottomPadding: 0
        onPressed: root.forceActiveFocus(Qt.MouseFocusReason)
        onClicked: root.toggleMenu()

        contentItem: Item {
            implicitWidth: label.implicitWidth + 9 + chevron.implicitWidth
            implicitHeight: Math.max(label.implicitHeight, chevron.implicitHeight)
            Text {
                id: label
                width: Math.max(0, parent.width - chevron.width - 9)
                anchors.verticalCenter: parent.verticalCenter
                text: root.labelAt(root._visualIndex) || root.placeholder
                color: root.labelAt(root._visualIndex).length > 0 ? root.textColor : root.mutedTextColor
                font.pixelSize: root.plainTrigger ? 13 : Foundation.AppTheme.compactDesign ? Foundation.AppTheme.compactControlFontSize : 13
                font.weight: root.plainTrigger ? Font.Normal : Font.Medium
                elide: Text.ElideRight
            }
            Item {
                id: chevron
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: root.indicatorBackground ? 18 : 14
                implicitHeight: root.indicatorBackground ? 20 : 14
                Rectangle {
                    anchors.fill: parent
                    visible: root.indicatorBackground
                    radius: 5
                    color: root.indicatorBackgroundColor
                }
                VectorIcon {
                    anchors.centerIn: parent
                    name: root.indicatorStyle === "upDown" ? "chevronsUpDown" : "chevron"
                    size: root.indicatorBackground ? 12 : 14
                    color: root.mutedTextColor
                    rotation: root.indicatorStyle !== "upDown" && menu.opened ? 180 : 0
                    Behavior on rotation {
                        NumberAnimation { duration: root.reduceMotion ? 0 : 150; easing.type: Easing.OutCubic }
                    }
                }
            }
        }

    }

    Binding {
        target: field.background
        property: "visible"
        value: false
        when: root.plainTrigger
        restoreMode: Binding.RestoreBindingOrValue
    }

    // Keyboard focus belongs to root; only the solid button field draws a focus ring.
    Rectangle {
        anchors.fill: parent
        radius: root.fieldRadius
        color: "transparent"
        border.width: 2
        border.color: root.focusRingColor
        visible: !root.plainTrigger && root.materialForm && root.enabled && (root.activeFocus || menu.opened)
    }

    FontMetrics {
        id: optionMetrics
        font.pixelSize: Foundation.AppTheme.compactDesign ? Foundation.AppTheme.compactControlFontSize : 13
        font.weight: root.popupFontWeight
    }

    // ── Choice sheet ─────────────────────────────────────────────────────

    Popup {
        id: menu
        objectName: root.objectName + "Popup"
        readonly property real longestLabelWidth: {
            let longest = 0
            for (let i = 0; i < root.model.length; ++i)
                longest = Math.max(longest, optionMetrics.advanceWidth(root.labelAt(i)))
            return longest
        }
        width: root.compactPopup
            ? Math.min(Math.max(0, root.Window.window ? root.Window.window.width - (root.popupShadowEnabled ? 40 : 24) : 480),
                Math.ceil(Math.max(root.width, longestLabelWidth + 28 + 12 + padding * 2)))
            : Math.max(160, root.width)
        implicitHeight: Math.min(360, choices.implicitHeight + 2 * padding)
        readonly property real panelRadius: 8
        readonly property int optionHeight: 24
        padding: 3
        modal: false
        focus: true
        // Not CloseOnPressOutside: that closes on the pill press itself, and
        // the pill's click would then toggle straight back open. Outside
        // presses close here; the trigger button toggles itself.
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        onOpened: scroller.focusCurrent()
        onClosed: { if (root.enabled) root.forceActiveFocus(Qt.PopupFocusReason) }
        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: root.popupMaterialForm ? 1 : 0; to: 1; duration: root.reduceMotion || root.popupMaterialForm ? 0 : 140; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: root.reduceMotion ? 0 : 150; easing.type: Easing.OutCubic }
            }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; to: root.popupMaterialForm ? 1 : 0; duration: root.reduceMotion || root.popupMaterialForm ? 0 : 100 }
        }
        background: Item {
            LiquidOuterShadow {
                objectName: root.objectName + "PopupShadow"
                anchors.fill: parent
                visible: root.popupShadowEnabled
                radius: menu.panelRadius
                shadowOpacity: 0.14
                softness: 7
                spread: 18
                offset: Qt.vector2d(0, 0)
            }
            Rectangle {
                objectName: root.objectName + "PopupPanel"
                anchors.fill: parent
                visible: root.popupMaterialForm
                radius: menu.panelRadius
                color: root.sheetColor
                border.width: root.popupBorderWidth
                border.color: root.outlineColor
            }
            LiquidSurface {
                anchors.fill: parent
                visible: !root.popupMaterialForm
                radius: menu.panelRadius
                backdrop: root.backdrop
                darkAppearance: root.darkAppearance
                tintColor: Qt.rgba(root.sheetColor.r, root.sheetColor.g, root.sheetColor.b, 1)
                tintStrength: 0.92
                readability: 0
                blurStrength: LiquidStyle.intensityProfile(root.liquidIntensity).blur
                refractionStrength: LiquidStyle.intensityProfile(root.liquidIntensity).refraction
                magnification: LiquidStyle.intensityProfile(root.liquidIntensity).magnification
                reflectionStrength: LiquidStyle.intensityProfile(root.liquidIntensity).reflection
                fullHighlight: true
                edgeShadeStrength: 0
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
                        objectName: root.objectName + "Option" + index
                        readonly property bool selected: index === root._visualIndex
                        readonly property bool blueActive: !root.neutralOptionHighlight
                            && (root.highlightSelectedOption ? selected : hit.containsMouse && root.popupMaterialForm)

                        required property var modelData
                        required property int index
                        width: menu.width - menu.leftPadding - menu.rightPadding
                        height: menu.optionHeight
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

                        // Keep the keyboard target visible while navigating.
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

                        // One hover surface covers exactly one compact option row.
                        Rectangle {
                            anchors.fill: parent
                            radius: Math.max(0, menu.panelRadius - menu.padding)
                            color: choiceDelegate.blueActive ? root.accentColor
                                : !hit.containsMouse && !(choiceDelegate.activeFocus
                                    && !(root.neutralOptionHighlight && choiceDelegate.selected)) ? "transparent"
                                : root.darkAppearance && !root.highlightSelectedOption && !root.neutralOptionHighlight
                                    ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.07)
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 28
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.labelAt(parent.index)
                            elide: Text.ElideRight
                            color: choiceDelegate.blueActive ? "#ffffff" : root.popupTextColor
                            font.pixelSize: Foundation.AppTheme.compactDesign ? Foundation.AppTheme.compactControlFontSize : 13
                            font.weight: root.popupFontWeight
                        }
                        VectorIcon {
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            visible: choiceDelegate.selected
                            name: "check"
                            color: choiceDelegate.blueActive ? "#ffffff" : root.popupTextColor
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
