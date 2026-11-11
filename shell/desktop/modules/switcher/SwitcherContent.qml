import QtQuick
import qs.desktop.modules.common
import qs.desktop.modules.dock

Item {
    id: content
    // TODO: optional same-application columns; native TabBox order stays authoritative.
    property var windows: []
    property string selectedHandle: ""
    property bool requestedOpen: false
    property real revealProgress: 0
    property bool entrancePending: false
    property bool mapped: false
    readonly property int selectedIndex: windows.findIndex(row => row.handleId === selectedHandle)
    readonly property real cardWidth: 224
    readonly property real cardHeight: 172
    readonly property real desiredWidth: Math.max(cardWidth + 24, windows.length * (cardWidth + 8) + 16)
    implicitWidth: desiredWidth
    implicitHeight: cardHeight + 24
    readonly property var blurRegion: mapped && revealProgress > 0.01 ? glass.blurRegion : null

    onRequestedOpenChanged: {
        entrance.stop()
        exitAnimation.stop()
        if (requestedOpen && windows.length) {
            mapped = true
            entrancePending = true
        } else {
            entrancePending = false
            exitAnimation.start()
        }
    }
    FrameAnimation {
        running: content.entrancePending && content.mapped
        onTriggered: {
            content.entrancePending = false
            entrance.start()
        }
    }
    NumberAnimation {
        id: entrance
        target: content
        property: "revealProgress"
        to: 1
        duration: DockAnimation.windowPreviewEntranceDuration
        easing.type: DockAnimation.elementEnterEasing
    }
    SequentialAnimation {
        id: exitAnimation
        NumberAnimation {
            target: content
            property: "revealProgress"
            to: 0
            duration: DockAnimation.windowPreviewExitDuration
            easing.type: DockAnimation.elementExitEasing
        }
        ScriptAction { script: content.mapped = false }
    }

    Item {
        id: surface
        x: (content.width - width) / 2
        y: (content.height - height) / 2 + (1 - content.revealProgress) * 7
        width: content.width * (0.94 + 0.06 * content.revealProgress)
        height: content.height * (0.94 + 0.06 * content.revealProgress)
        LiquidGlassPanel {
            id: glass
            anchors.fill: parent
            blurAnchor: surface
            radius: 18
            cornerExponent: AppearanceTokens.shape.cornerExponent
            scrimEnabled: AppearanceTokens.surface.usesBackdrop
            scrimLevel: "transparent"
            effectOpacity: content.revealProgress
            opacity: content.revealProgress

            ListView {
                id: cards
                anchors.fill: parent
                anchors.margins: 12
                orientation: ListView.Horizontal
                spacing: 8
                clip: true
                interactive: false
                model: content.windows
                currentIndex: content.selectedIndex
                highlightMoveDuration: 90
                preferredHighlightBegin: 0
                preferredHighlightEnd: width - content.cardWidth
                highlightRangeMode: ListView.ApplyRange
                delegate: SwitcherCard {
                    required property var modelData
                    required property int index
                    width: content.cardWidth
                    height: content.cardHeight
                    windowRecord: modelData
                    selected: index === content.selectedIndex
                    previewActive: content.mapped && x + width > cards.contentX
                        && x < cards.contentX + cards.width
                }
                onCurrentIndexChanged: if (currentIndex >= 0)
                    positionViewAtIndex(currentIndex, ListView.Contain)
            }
        }
    }
}
