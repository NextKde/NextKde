import QtQuick
import QtQuick.Controls
import Quickshell
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../shared/qml/i18n"
import "../../../Kos/Ui"

// Content stays in the list. Only the visible glass outline is published to
// KWin, against the popup's stationary capture, so scrolling neither allocates
// a texture per card nor lets an off-viewport shape blur the controls above it.
Item {
    id: card
    objectName: "notification-history-card"
    property int historyKey: 0
    property string summary: ""
    property string body: ""
    property string appName: ""
    property string appIcon: ""
    property string desktopEntry: ""
    property real timestamp: 0
    property real clockNow: Date.now()
    property bool showPreview: true
    property bool detailsExpanded: false
    property bool sizeReady: false
    property bool interactive: true
    property bool compositorGlass: AppearanceTokens.surface.usesKwinBlur
    property Item captureAnchor: null
    property rect clipSceneRect: Qt.rect(0, 0, -1, -1)
    property real backdropScale: 1
    property real glassOpacity: 1
    readonly property real compactHeight: 112
    readonly property bool canExpand: showPreview && (detailsExpanded || bodyText.truncated || summaryText.truncated)
    readonly property color ink: glass.foregroundColor
    readonly property alias blurRegion: glass.blurRegion
    readonly property alias fixedCaptureSupported: glass.fixedCaptureSupported
    readonly property bool backdropVisible: visible && nativeOutline.height > 0 && nativeOutline.width > 0
    property SceneBounds sceneBounds: SceneBounds { item: card }
    readonly property rect visibleRect: {
        const bounds = sceneBounds.rect
        if (bounds.width <= 0 || bounds.height <= 0) return Qt.rect(0, 0, 0, 0)
        if (clipSceneRect.width < 0) return Qt.rect(0, 0, width, height)
        const left = Math.max(bounds.x, clipSceneRect.x)
        const top = Math.max(bounds.y, clipSceneRect.y)
        const right = Math.min(bounds.x + bounds.width, clipSceneRect.x + clipSceneRect.width)
        const bottom = Math.min(bounds.y + bounds.height, clipSceneRect.y + clipSceneRect.height)
        return Qt.rect((left - bounds.x) * width / bounds.width,
            (top - bounds.y) * height / bounds.height,
            Math.max(0, right - left) * width / bounds.width,
            Math.max(0, bottom - top) * height / bounds.height)
    }
    implicitHeight: detailsExpanded && showPreview ? Math.max(compactHeight, message.implicitHeight + 54) : compactHeight
    height: implicitHeight
    Component.onCompleted: sizeReady = true
    Behavior on height {
        enabled: card.sizeReady && !AppTheme.reduceMotion
        NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic }
    }
    clip: true
    enabled: interactive
    activeFocusOnTab: canExpand && backdropVisible
    Accessible.role: Accessible.Button
    Accessible.name: appName + (showPreview ? I18n.tr(", %1").arg(summary) : I18n.tr(", notification received"))
    Accessible.description: canExpand ? (detailsExpanded ? I18n.tr("collapse details") : I18n.tr("expand details")) : ""
    Keys.onReturnPressed: if (canExpand) detailsRequested(!detailsExpanded)
    Keys.onSpacePressed: if (canExpand) detailsRequested(!detailsExpanded)
    signal removeRequested(int key)
    signal detailsRequested(bool expanded)

    Item {
        id: nativeOutline
        x: card.visibleRect.x; y: card.visibleRect.y
        width: card.visibleRect.width; height: card.visibleRect.height
    }
    ControlCenterGlass {
        id: glass
        anchors.fill: parent
        radius: 24
        // Text is a sibling, and never paints into the rounded corners. Native
        // glass needs no offscreen QML layer or mask for this empty surface.
        maskContent: !useKwinEffect || fallbackEnabled
        useKwinEffect: card.compositorGlass
        blurAnchor: nativeOutline
        captureAnchor: card.captureAnchor
        backdropScale: card.backdropScale
        backdropRadius: Math.min(radius, nativeOutline.width / 2, nativeOutline.height / 2)
        visible: card.backdropVisible
        scrimOpacity: card.glassOpacity
        materialOpacity: card.glassOpacity
    }
    Rectangle {
        anchors.fill: parent
        radius: 24
        visible: hover.hovered || card.activeFocus
        color: card.ink
        opacity: card.activeFocus ? 0.07 : 0.025
        border.width: card.activeFocus ? 1 : 0
        border.color: card.ink
    }
    HoverHandler { id: hover }
    Rectangle { x: 16; y: 12; width: 22; height: 22; radius: 7; color: card.ink; opacity: 0.08 }
    NotificationSourceIcon {
        x: 19; y: 15
        width: 16; height: 16
        appIcon: card.appIcon
        desktopEntry: card.desktopEntry
        ink: card.ink
    }
    GlassText {
        x: 44; y: 15
        width: Math.max(0, timeText.x - x - 10)
        text: card.appName || I18n.tr("Notification")
        textFormat: Text.PlainText
        color: card.ink
        opacity: 1
        font { pixelSize: 11; weight: Font.DemiBold }
        elide: Text.ElideRight
    }
    GlassText {
        id: timeText
        anchors { right: closeButton.left; rightMargin: 3; top: parent.top; topMargin: 15 }
        text: {
            const minutes = Math.max(0, Math.floor((card.clockNow - card.timestamp) / 60000))
            return minutes < 1 ? I18n.tr("now") : minutes < 60 ? I18n.tr("%1 minutes ago").arg(minutes)
                : minutes < 1440 ? I18n.tr("%1 hours ago").arg(Math.floor(minutes / 60)) : I18n.tr("%1 days ago").arg(Math.floor(minutes / 1440))
        }
        color: card.ink
        opacity: 0.85
        font.pixelSize: 11
    }
    Column {
        id: message
        x: 16; y: 38
        width: Math.max(0, parent.width - 32)
        spacing: 4
        GlassText {
            id: summaryText
            width: parent.width
            text: card.showPreview ? card.summary || I18n.tr("Notification") : I18n.tr("Notification received")
            textFormat: Text.PlainText
            color: card.ink
            font { pixelSize: 15; weight: Font.DemiBold }
            wrapMode: Text.Wrap
            maximumLineCount: card.detailsExpanded ? 2 : 1
            elide: Text.ElideRight
        }
        GlassText {
            id: bodyText
            width: parent.width
            visible: card.showPreview && text.length > 0
            text: card.body
            textFormat: Text.PlainText
            color: card.ink
            opacity: 1
            font.pixelSize: 13
            lineHeight: 1.15
            wrapMode: Text.Wrap
            maximumLineCount: card.detailsExpanded ? 7 : 2
            elide: Text.ElideRight
        }
    }
    TapHandler {
        enabled: card.canExpand && card.interactive
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: eventPoint => {
            if (eventPoint.position.x < card.width - 46 || eventPoint.position.y > 38)
                card.detailsRequested(!card.detailsExpanded)
        }
    }
    AbstractButton {
        id: closeButton
        objectName: "notification-remove-button"
        anchors { right: parent.right; top: parent.top; rightMargin: 8; topMargin: 7 }
        width: 30; height: 30
        activeFocusOnTab: card.backdropVisible && card.visibleRect.y <= y
            && card.visibleRect.y + card.visibleRect.height >= y + height
        Accessible.name: I18n.tr("Remove %1's notification").arg(card.appName)
        background: Rectangle {
            radius: 15
            color: card.ink
            opacity: closeButton.down ? 0.14 : closeButton.hovered || closeButton.activeFocus ? 0.08 : 0
        }
        contentItem: GlassText {
            text: "×"
            color: card.ink
            opacity: closeButton.hovered || closeButton.activeFocus ? 0.85 : 0.4
            font.pixelSize: 17
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        onClicked: card.removeRequested(card.historyKey)
    }
    GlassText {
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: 14; bottomMargin: 7 }
        visible: card.canExpand
        text: card.detailsExpanded ? "⌃" : "⌄"
        color: card.ink
        opacity: 0.4
        font.pixelSize: 10
    }
}
