pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Kos.Ui

// P01: compact app-owned neutral detail popover for a calendar item.
// Title, then time/date, then optional location/notes, a subdued Edit
// action and a close affordance. Local neutral palette (no blue-gray tint),
// hairline border and an app-painted soft shadow. The popover never edits
// anything itself: closing it never saves, and Edit hands the record to the
// existing editor dialogs.
Popup {
    id: root

    // Local neutral tokens (dark branches off AppTheme.dark only for the
    // light/dark choice; the greys themselves stay neutral).
    readonly property color surfaceColor: AppTheme.dark ? "#262626" : "#F5F5F5"
    readonly property color borderColor: AppTheme.dark
        ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.12)
    readonly property color titleColor: AppTheme.dark ? "#F2F2F2" : "#1A1A1A"
    readonly property color secondaryColor: AppTheme.dark
        ? Qt.rgba(1, 1, 1, 0.58) : Qt.rgba(0, 0, 0, 0.55)

    property string itemTitle: ""
    property string itemTime: ""
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

    width: 340
    padding: 14
    modal: false
    closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
    onClosed: root.dismissed()

    background: Item {
        // Soft app-painted shadow behind a neutral surface.
        Rectangle {
            x: 2; y: 5
            width: parent.width - 4; height: parent.height - 4
            radius: 14
            color: AppTheme.dark ? "#B3000000" : "#59000000"
            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blurMax: 24
                blur: 0.6
                autoPaddingEnabled: false
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: 12
            color: root.surfaceColor
            border.width: 1
            border.color: root.borderColor
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
            objectName: "detailsTime"
            Layout.fillWidth: true
            text: root.itemTime
            color: root.secondaryColor
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            visible: root.itemTime.length > 0
        }

        Label {
            objectName: "detailsLocation"
            Layout.fillWidth: true
            text: root.itemLocation
            color: root.secondaryColor
            font.pixelSize: 12
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
                width: root.availableWidth - root.padding * 2
                text: root.itemNotes
                color: root.secondaryColor
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8

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
                    font.pixelSize: 12
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
