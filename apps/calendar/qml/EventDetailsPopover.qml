pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui

// P01: compact app-owned neutral detail popover for a calendar item.
// Title, then time/date, then optional location/notes, a subdued Edit
// action and a close affordance. Local neutral palette (no blue-gray tint),
// plain upper-layer fill and a soft shared outer shadow. The popover never
// edits anything itself: closing it never saves, and Edit hands the record
// to the existing editor dialogs.
Popup {
    id: root

    // Local neutral tokens (dark branches off AppTheme.dark only for the
    // light/dark choice; the greys themselves stay neutral). The values now
    // live in AppTheme (M05) so the popover and the Tahoe content plane are
    // themed from one place.
    readonly property color borderColor: AppTheme.popoverBorder
    readonly property color titleColor: AppTheme.popoverInk
    readonly property color secondaryColor: AppTheme.popoverInkSecondary
    // Interior margin reserved for the app-painted shadow: the visible
    // surface is inset by this much on every side while the popup itself
    // grows by 2 * shadowInset, so the surface box keeps its size/position.
    // 36 = shadowLevel 3 spread 32 + its 3px downward offset + slack, so the
    // shared shadow shader never gets clipped by the Popup bounds.
    readonly property real shadowInset: 36

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

    // The popup grows by 2 * shadowInset; contentItem is inset by
    // padding, so the content width stays 340 - 2 * 14 = 312.
    width: 340 + 2 * shadowInset
    padding: 14 + shadowInset
    // LQ09: the 340-wide surface keeps its box; only its radius moves from
    // 12 to the popover token 16. Contents keep the 14px inset, so every
    // P01 label position is unchanged (the popup bounds are just larger).
    modal: false
    closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
    onClosed: root.dismissed()

    background: Item {
        // LQ09: the detail popover is an L2 transient over L0 content. Its
        // base plane is the same solid sheet as the content plane, then the
        // spec's upper-layer fill (plain α .06) rides on a LiquidSurface —
        // never a second glass layer, so the popover stays legible even when
        // it crosses the toolbar/sidebar glass. Radius 16 and the soft
        // shared E2-class outer shadow follow liquid-spec §4 (弹出框).
        Rectangle {
            id: popoverPlane
            anchors.fill: parent
            anchors.margins: root.shadowInset
            radius: 16
            color: AppTheme.neutralPlane
            border.width: 1
            border.color: AppTheme.dark ? root.borderColor : "transparent"
        }
        // Painted before the plane so the plane owns the centre; the shader
        // has zero alpha inside its body. It stays INSIDE the popup's own
        // bounds (the shadowInset margin) so the Popup cannot clip it.
        LiquidOuterShadow {
            anchors.fill: popoverPlane
            radius: 16
            shadowLevel: 3
        }
        LiquidSurface {
            anchors.fill: popoverPlane
            radius: 16
            backdrop: null
            tintColor: AppTheme.dark ? "#FFFFFF" : "#000000"
            tintStrength: .06
            diffuseStrength: 1
            reflectionStrength: 0
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
                // 14 is the content inset, independent of shadowInset; the
                // wrap must not depend on the shadow margin. Using
                // root.padding here made the label 28px narrower.
                width: root.availableWidth - 2 * 14
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
    // viewport and its shadow keeps an interior margin (P03). Bounds are
    // converted to the visible surface (root.x + shadowInset) because the
    // Popup itself now carries the shadow margin. The guard makes the
    // re-clamp safe against a transient/unavailable parent and re-entry.
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
            const inset = root.shadowInset
            const minX = margin - inset
            const minY = margin - inset
            const maxX = host.width - (root.width - 2 * inset) - margin - inset
            const maxY = host.height - (root.height - 2 * inset) - margin - inset
            if (maxX < minX || maxY < minY) return
            root.x = Math.max(minX, Math.min(root.x, maxX))
            root.y = Math.max(minY, Math.min(root.y, maxY))
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
            const inset = root.shadowInset
            const surfaceW = root.width - 2 * inset
            const surfaceH = root.height - 2 * inset
            const maxX = Math.max(margin, host.width - surfaceW - margin)
            const maxY = Math.max(margin, host.height - surfaceH - margin)
            let surfaceX
            let surfaceY
            if (point) {
                surfaceX = Math.max(margin, Math.min(point.x, maxX))
                surfaceY = Math.max(margin, Math.min(point.y, maxY))
            } else {
                surfaceX = Math.max(margin, Math.min(
                    (host.width - surfaceW) / 2, maxX))
                surfaceY = Math.max(margin, Math.min(
                    (host.height - surfaceH) / 2, maxY))
            }
            root.x = surfaceX - inset
            root.y = surfaceY - inset
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
