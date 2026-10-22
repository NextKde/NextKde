pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import "../foundation" as Foundation

// A fixed-geometry segmented control with an optimistic liquid-glass lens.
// Keeping each segment's width stable avoids the label-resize artefacts that
// make custom segmented controls feel as if they need a second click.
Item {
    id: root

    implicitWidth: 180
    implicitHeight: 34
    opacity: enabled ? 1 : .5

    property LiquidBackdrop backdrop: LiquidStyle.backdropForItem(root, root.Window.window)
    property var labels: []
    property int currentIndex: 0
    property color backgroundColor: Foundation.AppTheme.button
    property color selectionColor: Foundation.AppTheme.cardHover
    property color textColor: Foundation.AppTheme.text
    property color mutedTextColor: Foundation.AppTheme.mutedText
    // Material-form container outline. Overridable because hosts draw the
    // track on very different planes: the default 14% border is right for a
    // dialog, but on an already-white toolbar it reads heavier than the
    // reference's hairline. Keeping the default preserves every existing use.
    property color borderColor: Foundation.AppTheme.border
    // A tonal host draws the Material 3 segmented button: a full-radius outline
    // container with a filled, shadowless selection. The liquid lens below
    // reflection and sampling are hidden rather than blended in that form.
    // Follows the
    // application-wide form by default.
    property bool materialForm: ControlForm.materialForm
    HoverHandler { id: materialHover }
    property int _pressedIndex: -1
    property int _visualIndex: 0
    property int _pendingIndex: -1

    readonly property real _lensPosition: lens.x
    readonly property bool sampling: !materialForm && lensSurface.sampling
    readonly property int safeIndex: clampedIndex(currentIndex)
    readonly property real segmentWidth: labels.length > 0 ? (width - 4) / labels.length : 0

    signal selectionRequested(int index)

    function clampedIndex(index) {
        return labels.length > 0
            ? Math.max(0, Math.min(labels.length - 1, index)) : 0
    }

    function select(index) {
        if (!enabled || index < 0 || index >= labels.length)
            return
        // Draw the result first. The owner may update its persistent state
        // through IPC, but that round trip must not consume the first click.
        _pendingIndex = index
        _visualIndex = index
        selectionRequested(index)
        confirmationTimer.restart()
    }

    function selectAndFocus(index) {
        const target = Math.max(0, Math.min(labels.length - 1, index))
        select(target)
        const segment = segments.itemAt(target)
        if (segment)
            segment.forceActiveFocus()
    }

    function _beginPress(index) {
        if (!enabled || index < 0 || index >= labels.length) return
        const segment = segments.itemAt(index)
        if (segment) segment.forceActiveFocus()
        _pressedIndex = index
    }
    function _endPress() { _pressedIndex = -1 }
    onEnabledChanged: { if (!enabled) _endPress() }

    onCurrentIndexChanged: {
        // Read the changed source property directly. A binding that depends on
        // currentIndex (such as safeIndex) may not have been re-evaluated yet
        // when this change handler runs.
        _visualIndex = clampedIndex(currentIndex)
        _pendingIndex = -1
        confirmationTimer.stop()
    }
    onLabelsChanged: {
        _visualIndex = clampedIndex(currentIndex)
        _pendingIndex = -1
    }
    Component.onCompleted: _visualIndex = safeIndex

    Timer {
        id: confirmationTimer
        interval: Math.max(420, Foundation.AppTheme.motionNormal * 3)
        repeat: false
        // Roll the lens back only if the externally-owned state did not
        // acknowledge this optimistic selection.
        onTriggered: {
            root._visualIndex = root.safeIndex
            root._pendingIndex = -1
        }
    }

    Item {
        anchors.fill: parent
        Rectangle {
            anchors.fill: parent
            visible: root.materialForm
            radius: height / 2
            color: root.backgroundColor
            border.width: 1
            border.color: root.borderColor
        }
        LiquidSurface {
            anchors.fill: parent
            visible: !root.materialForm
            radius: height * .48
            backdrop: root.backdrop
            convexLens: true
            edgeShadeStrength: .08
            blurStrength: 0
            readability: 0
            edgeWidth: Math.min(10, height * .28)
            refractionStrength: materialHover.hovered ? 4.5 : 3
            magnification: materialHover.hovered ? 1.045 : 1.025
            reflectionStrength: materialHover.hovered ? .72 : .50
            tintColor: Foundation.AppTheme.dark ? "#20252f" : "#ffffff"
            tintStrength: .30
            Behavior on refractionStrength { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
            Behavior on magnification { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
            Behavior on reflectionStrength { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
            Behavior on tintStrength { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
        }
    }
    Item {
        id: lens
        x: 4 + root._visualIndex * root.segmentWidth
        y: 2
        width: root.segmentWidth - 4
        height: root.height - 4
        readonly property real radius: root.materialForm ? height / 2 : height * .48
        scale: !root.materialForm && root._pressedIndex >= 0 ? 1.12 : 1
        Behavior on scale {
            NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast; easing.type: Easing.OutBack }
        }
        Behavior on x { NumberAnimation { duration: Foundation.AppTheme.motionNormal; easing.type: Easing.OutQuint } }
        Rectangle {
            anchors.fill: parent
            visible: root.materialForm
            radius: lens.radius
            color: root.selectionColor
        }
        LiquidSurface {
            id: lensSurface
            anchors.fill: parent
            visible: !root.materialForm
            radius: lens.radius
            backdrop: root.backdrop
            convexLens: true
            edgeShadeStrength: .08
            blurStrength: 0
            readability: 0
            edgeWidth: Math.min(10, height * .28)
            refractionStrength: materialHover.hovered ? 4.5 : 3
            magnification: materialHover.hovered ? 1.045 : 1.025
            reflectionStrength: materialHover.hovered ? .72 : .50
            tintColor: root._pressedIndex >= 0 ? "#ffffff" : (Foundation.AppTheme.dark ? "#20252f" : "#ffffff")
            tintStrength: root._pressedIndex >= 0 ? .06 : .80
            Behavior on refractionStrength { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
            Behavior on magnification { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
            Behavior on reflectionStrength { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
            Behavior on tintStrength { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
        }
    }

    Repeater {
        id: segments
        model: root.labels
        delegate: Item {
            id: segmentDelegate

            required property var modelData
            required property int index
            x: 2 + segmentDelegate.index * root.segmentWidth
            width: root.segmentWidth
            height: root.height
            enabled: root.enabled
            activeFocusOnTab: enabled

            Accessible.role: Accessible.RadioButton
            Accessible.name: String(segmentDelegate.modelData)
            Accessible.checked: segmentDelegate.index === root._visualIndex
            Accessible.focusable: enabled
            Accessible.focused: activeFocus
            Accessible.onPressAction: root.select(segmentDelegate.index)

            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Left) {
                    root.selectAndFocus(segmentDelegate.index - 1)
                } else if (event.key === Qt.Key_Right) {
                    root.selectAndFocus(segmentDelegate.index + 1)
                } else if (event.key === Qt.Key_Home) {
                    root.selectAndFocus(0)
                } else if (event.key === Qt.Key_End) {
                    root.selectAndFocus(root.labels.length - 1)
                } else if (event.key === Qt.Key_Space
                           || event.key === Qt.Key_Enter
                           || event.key === Qt.Key_Return) {
                    root.select(segmentDelegate.index)
                } else {
                    return
                }
                event.accepted = true
            }

            Text {
                anchors.centerIn: parent
                width: Math.max(0, parent.width - 16)
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: segmentDelegate.modelData
                color: segmentDelegate.index === root._visualIndex
                    ? root.textColor : root.mutedTextColor
                font.pixelSize: 12
                font.weight: segmentDelegate.index === root._visualIndex
                    ? Font.DemiBold : Font.Normal
                scale: root._pressedIndex === segmentDelegate.index ? 0.96 : 1.0
                Behavior on color {
                    ColorAnimation { duration: Foundation.AppTheme.motionFast }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: Foundation.AppTheme.motionFast
                        easing.type: Easing.OutCubic
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: root._beginPress(segmentDelegate.index)
                onCanceled: root._endPress()
                onReleased: root._endPress()
                onClicked: root.select(segmentDelegate.index)
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                radius: Math.max(3, height * 0.34)
                color: "transparent"
                border.width: 2
                border.color: Foundation.AppTheme.accent
                visible: false
            }
        }
    }
}
