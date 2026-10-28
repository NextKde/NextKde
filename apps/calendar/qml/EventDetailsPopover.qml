pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Kos.Ui

// One sampled liquid detail panel with ordinary interior actions. Closing it
// never saves; Edit hands the existing record to the application editor.
Popup {
    id: root
    CalendarStyle { id: design }

    // Local neutral tokens (dark branches off AppTheme.dark only for the
    // light/dark choice; the greys themselves stay neutral). The values now
    // live in AppTheme (M05) so the popover and the Tahoe content plane are
    // themed from one place.
    readonly property color surfaceColor: design.dialogPlane
    readonly property color borderColor: design.separator
    readonly property color titleColor: design.labelPrimary
    readonly property color secondaryColor: design.labelSecondary
    // Interior margin reserved for the app-painted shadow: the visible
    // surface is inset by this much on every side while the popup itself
    // grows by 2 * shadowInset, so the surface box keeps its size/position.
    readonly property real shadowInset: 14

    property string itemTitle: ""
    property string itemTime: ""
    property string itemCategory: ""
    property string itemSchedule: ""
    property bool canComplete: false
    signal completionRequested()
    property string itemLocation: ""
    property string itemNotes: ""
    property color kindColor: AppTheme.accent
    property bool kindCompleted: false

    signal editRequested()
    signal dismissed()

    // Notes scroll position does not leak across records: reset the
    // ScrollView's inner Flickable imperatively once content is ready. One-
    // shot per reset — no permanent binding fighting the user's scrolling.
    // Guarded against a not-yet-created content item / transition lifecycle.
    function resetNotesScroll() {
        Qt.callLater(function() {
            const flickable = notesScroll.contentItem
            if (flickable === null || flickable === undefined) return
            if (flickable.contentY !== undefined)
                flickable.contentY = 0
        })
    }
    onItemNotesChanged: resetNotesScroll()

    // The popup grows by 2 * shadowInset; contentItem is inset by
    // padding, so the content width stays 340 - 2 * 14 = 312.
    width: 320 + 2 * shadowInset
    padding: 14 + shadowInset
    modal: false
    popupType: Popup.Item
    objectName: "calendarEventDetails"
    closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
    onClosed: root.dismissed()

    background: Item {
        // Soft app-painted shadow behind a neutral surface. It is painted
        // INSIDE the popup's own bounds (into the shadowInset margin) so
        // the Popup cannot clip it; autoPaddingEnabled lets the blur bleed
        // ~2px past the surface on the top/left/right and ~4px below.
        Rectangle {
            x: root.shadowInset - 2
            y: root.shadowInset - 2
            width: parent.width - 2 * root.shadowInset + 4
            height: parent.height - 2 * root.shadowInset + 6
            radius: 14
            color: AppTheme.dark ? "#66000000" : "#22000000"
            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blurMax: 32
                blur: 0.5
                autoPaddingEnabled: true
            }
        }
        CalendarPopupSurface {
            anchors.fill: parent
            anchors.margins: root.shadowInset
            radius: 12
        }
    }

    contentItem: ColumnLayout {
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                Layout.preferredWidth: 10
                Layout.preferredHeight: 10
                Layout.alignment: Qt.AlignVCenter
                radius: 5
                color: root.kindColor
            }

            Label {
                objectName: "detailsTitle"
                Layout.fillWidth: true
                text: root.itemTitle
                color: root.titleColor
                font.pixelSize: 15
                font.weight: Font.DemiBold
                // 20px = 1.33em. The CJK fallback stack's natural line box is
                // 1.47em (22px at 15px), which reads looser than macOS body text.
                lineHeightMode: Text.FixedHeight
                lineHeight: 20
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }

            AbstractButton {
                id: closeButton
                objectName: "detailsClose"
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                hoverEnabled: true
                Accessible.name: qsTr("Close")

                contentItem: Item {
                    // Local ×: two crossed rounded bars.
                    Rectangle {
                        width: 10; height: 1.6; radius: 0.8
                        anchors.centerIn: parent
                        rotation: 45
                        color: root.secondaryColor
                    }
                    Rectangle {
                        width: 10; height: 1.6; radius: 0.8
                        anchors.centerIn: parent
                        rotation: -45
                        color: root.secondaryColor
                    }
                }
                background: Rectangle {
                    radius: height / 2
                    color: closeButton.hovered ? root.borderColor : "transparent"
                }
                onClicked: root.close()
            }
        }

        Label {
            Layout.fillWidth: true
            text: root.itemCategory
            color: root.secondaryColor
            font.pixelSize: 11
        }
        Label {
            Layout.fillWidth: true
            text: root.itemSchedule
            color: root.secondaryColor
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }

        Label {
            objectName: "detailsTime"
            Layout.fillWidth: true
            text: root.itemTime
            color: root.secondaryColor
            font.pixelSize: 13
            wrapMode: Text.WordWrap
            visible: root.itemTime.length > 0
        }

        Label {
            objectName: "detailsLocation"
            Layout.fillWidth: true
            text: root.itemLocation
            color: root.secondaryColor
            font.pixelSize: 13
            wrapMode: Text.Wrap
            visible: root.itemLocation.length > 0
        }

        ScrollView {
            id: notesScroll
            Layout.fillWidth: true
            Layout.maximumHeight: 120
            visible: root.itemNotes.length > 0
            contentWidth: availableWidth
            clip: true
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            Label {
                objectName: "detailsNotes"
                // 14 is the content inset, independent of shadowInset; the
                // wrap must not depend on the shadow margin. Using
                // root.padding here made the label 28px narrower.
                width: root.availableWidth - 2 * 14
                text: root.itemNotes
                color: root.secondaryColor
                font.pixelSize: 13
                wrapMode: Text.Wrap
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8

            CalendarCheckBox {
                objectName: "detailsComplete"
                visible: root.canComplete
                checked: root.kindCompleted
                text: qsTr("Completed")
                onClicked: root.completionRequested()
            }
            Item { Layout.fillWidth: true }

            AbstractButton {
                id: editButton
                objectName: "detailsEdit"
                implicitHeight: 26
                implicitWidth: editLabel.implicitWidth + 24
                hoverEnabled: true
                Accessible.name: qsTr("Edit")

                contentItem: Label {
                    id: editLabel
                    anchors.centerIn: parent
                    text: qsTr("Edit")
                    color: root.titleColor
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }
                background: Rectangle {
                    radius: height / 2
                    color: editButton.pressed ? root.borderColor
                        : (editButton.hovered
                           ? Qt.rgba(root.titleColor.r, root.titleColor.g,
                                     root.titleColor.b, 0.08)
                           : "transparent")
                    border.width: 1
                    border.color: root.borderColor
                }
                onClicked: {
                    root.close()
                    root.editRequested()
                }
            }
        }
    }

    // Clamp into the window content on open, on parent resize, and on
    // content-height changes so the popover never leaves the client
    // viewport and its shadow keeps an interior margin (P03). The guard
    // makes the re-clamp safe against a transient/unavailable parent and
    // against re-entry.
    property bool _clamping: false
    function reclamp() {
        if (_clamping || !root.opened) return
        const surface = root.parent
        if (!surface || surface.width <= 0 || surface.height <= 0) return
        _clamping = true
        Qt.callLater(function() {
            _clamping = false
            if (!root.opened) return
            const host = root.parent
            if (!host || host.width <= 0 || host.height <= 0) return
            const margin = 12
            const maxX = host.width - root.width - margin
            const maxY = host.height - root.height - margin
            if (maxX < margin || maxY < margin) return
            root.x = Math.max(margin, Math.min(root.x, maxX))
            root.y = Math.max(margin, Math.min(root.y, maxY))
        })
    }
    function openAt(point) {
        root.open()
        // The popover's height depends on content, settle first.
        Qt.callLater(function() {
            if (!root.opened) return
            const host = root.parent
            if (!host || host.width <= 0 || host.height <= 0) return
            const margin = 12
            const maxX = host.width - root.width - margin
            const maxY = host.height - root.height - margin
            if (point) {
                root.x = Math.max(margin, Math.min(point.x, Math.max(margin, maxX)))
                root.y = Math.max(margin, Math.min(point.y, Math.max(margin, maxY)))
            } else {
                root.x = Math.max(margin, Math.min(
                    (host.width - root.width) / 2, Math.max(margin, maxX)))
                root.y = Math.max(margin, Math.min(
                    (host.height - root.height) / 2, Math.max(margin, maxY)))
            }
        })
    }

    Connections {
        target: root.parent
        ignoreUnknownSignals: true
        function onWidthChanged() { root.reclamp() }
        function onHeightChanged() { root.reclamp() }
    }
    // Content-height changes (long notes wrap, fields reveal) also move the
    // bottom edge.
    onContentItemChanged: reclamp()
    onAboutToShow: {
        resetNotesScroll()
        reclamp()
    }
    onOpenedChanged: if (opened) {
        resetNotesScroll()
        reclamp()
    }
}
