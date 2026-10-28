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
    property color backgroundColor: Foundation.AppTheme.controlBackground
    property color selectionColor: Foundation.AppTheme.dark ? "#636363" : "#D1D1D1"
    property color textColor: Foundation.AppTheme.text
    property color mutedTextColor: Foundation.AppTheme.mutedText
    property int fontWeight: Font.Normal
    property int selectedFontWeight: Font.DemiBold
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
    property bool _ready: false
    property real _deformation: 0
    readonly property bool _motionEnabled: !materialForm && !Foundation.AppTheme.reduceMotion

    function animateSelection() {
        if (_ready && _motionEnabled) selectionMotion.restart()
    }
    function settleMotion() {
        selectionMotion.stop()
        _deformation = 0
    }
    onMaterialFormChanged: { if (materialForm) settleMotion() }
    Connections {
        target: Foundation.AppTheme
        function onReduceMotionChanged() {
            if (Foundation.AppTheme.reduceMotion) root.settleMotion()
        }
    }
    SequentialAnimation {
        id: selectionMotion
        NumberAnimation { target: root; property: "_deformation"; to: 1; duration: 85; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "_deformation"; to: -.18; duration: 155; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "_deformation"; to: 0; duration: 150; easing.type: Easing.OutCubic }
    }

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
        if (_visualIndex !== index) animateSelection()
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
        if (_visualIndex !== clampedIndex(currentIndex)) animateSelection()
        _visualIndex = clampedIndex(currentIndex)
        _pendingIndex = -1
        confirmationTimer.stop()
    }
    onLabelsChanged: {
        settleMotion()
        _visualIndex = clampedIndex(currentIndex)
        _pendingIndex = -1
    }
    Component.onCompleted: { _visualIndex = safeIndex; _ready = true }

    Timer {
        id: confirmationTimer
        interval: Math.max(420, Foundation.AppTheme.motionNormal * 3)
        repeat: false
        // Roll the lens back only if the externally-owned state did not
        // acknowledge this optimistic selection.
        onTriggered: {
            if (root._visualIndex !== root.safeIndex) root.animateSelection()
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
            border.color: Foundation.AppTheme.border
        }
        LiquidSurface {
            anchors.fill: parent
            visible: !root.materialForm
            radius: height / 2
            backdrop: root.backdrop
            convexLens: true
            edgeShadeStrength: .08
            blurStrength: 0
            readability: 0
            edgeWidth: Math.min(10, height * .28)
            refractionStrength: materialHover.hovered ? 4.5 : 3
            magnification: materialHover.hovered ? 1.045 : 1.025
            reflectionStrength: materialHover.hovered ? .72 : .50
            tintColor: root.backgroundColor
            tintStrength: .65
            Behavior on refractionStrength { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
            Behavior on magnification { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
            Behavior on reflectionStrength { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
            Behavior on tintStrength { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
        }
    }
    Item {
        id: lens
        x: 2 + root._visualIndex * root.segmentWidth
        y: 2
        width: root.segmentWidth
        height: root.height - 4
        // Uniform 2px inset: inner and outer endcaps share their centres.
        readonly property real radius: height / 2
        readonly property real deformation: root._motionEnabled ? root._deformation : 0
        readonly property real pressExpansion: root._motionEnabled && root._pressedIndex >= 0 ? .06 : 0
        transform: Scale {
            origin.x: lens.width / 2
            origin.y: lens.height / 2
            xScale: 1 + lens.deformation * .12 + lens.pressExpansion
            yScale: 1 - lens.deformation * .08 + lens.pressExpansion
            Behavior on xScale { enabled: root._motionEnabled && !selectionMotion.running; NumberAnimation { duration: Foundation.AppTheme.motionFast } }
            Behavior on yScale { enabled: root._motionEnabled && !selectionMotion.running; NumberAnimation { duration: Foundation.AppTheme.motionFast } }
        }
        Behavior on x {
            enabled: root._motionEnabled
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
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
            // Preserve a readable selected state after release, including on flat scenes.
            tintColor: root.selectionColor
            tintStrength: root._pressedIndex >= 0 ? .50 : .85
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
                font.pixelSize: Foundation.AppTheme.compactDesign ? Foundation.AppTheme.compactControlFontSize : 12
                font.weight: segmentDelegate.index === root._visualIndex
                    ? root.selectedFontWeight : root.fontWeight
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
