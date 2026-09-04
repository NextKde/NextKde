pragma ComponentBehavior: Bound

import QtQuick

// A fixed-geometry segmented control with an optimistic liquid-glass lens.
// Keeping each segment's width stable avoids the label-resize artefacts that
// make custom segmented controls feel as if they need a second click.
Item {
    id: root

    implicitWidth: 180
    implicitHeight: 34

    property var labels: []
    property int currentIndex: 0
    property color backgroundColor: AppTheme.button
    property color selectionColor: AppTheme.cardHover
    property color textColor: AppTheme.text
    property color mutedTextColor: AppTheme.mutedText
    property int _pressedIndex: -1
    property int _visualIndex: 0
    property int _pendingIndex: -1

    readonly property int safeIndex: clampedIndex(currentIndex)
    readonly property real segmentWidth: labels.length > 0 ? (width - 4) / labels.length : 0

    signal selectionRequested(int index)

    function clampedIndex(index) {
        return labels.length > 0
            ? Math.max(0, Math.min(labels.length - 1, index)) : 0
    }

    function select(index) {
        if (index < 0 || index >= labels.length)
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
        interval: Math.max(420, AppTheme.motionNormal * 3)
        repeat: false
        // Roll the lens back only if the externally-owned state did not
        // acknowledge this optimistic selection.
        onTriggered: {
            root._visualIndex = root.safeIndex
            root._pendingIndex = -1
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: height * 0.38
        color: root.backgroundColor
        border.width: 1
        border.color: AppTheme.border

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.04) }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.02) }
            }
        }
    }

    Rectangle {
        id: lensShadow
        x: lens.x
        y: lens.y + 1
        width: lens.width
        height: lens.height
        radius: lens.radius
        color: Qt.rgba(0, 0, 0, AppTheme.dark ? 0.24 : 0.10)
        Behavior on x { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutQuint } }
    }

    Rectangle {
        id: lens
        x: 2 + root._visualIndex * root.segmentWidth
        y: 2
        width: root.segmentWidth
        height: root.height - 4
        radius: height * 0.42
        color: root.selectionColor
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.16)

        Behavior on x { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutQuint } }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.09) }
                GradientStop { position: 0.58; color: Qt.rgba(1, 1, 1, 0.025) }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.025) }
            }
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
                text: segmentDelegate.modelData
                color: segmentDelegate.index === root._visualIndex
                    ? root.textColor : root.mutedTextColor
                font.pixelSize: 12
                font.weight: segmentDelegate.index === root._visualIndex
                    ? Font.DemiBold : Font.Normal
                scale: root._pressedIndex === segmentDelegate.index ? 0.96 : 1.0
                Behavior on color {
                    ColorAnimation { duration: AppTheme.motionFast }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: AppTheme.motionFast
                        easing.type: Easing.OutCubic
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: {
                    segmentDelegate.forceActiveFocus()
                    root._pressedIndex = segmentDelegate.index
                }
                onCanceled: root._pressedIndex = -1
                onReleased: root._pressedIndex = -1
                onClicked: root.select(segmentDelegate.index)
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                radius: Math.max(3, height * 0.34)
                color: "transparent"
                border.width: 2
                border.color: AppTheme.accent
                visible: segmentDelegate.activeFocus
            }
        }
    }
}
