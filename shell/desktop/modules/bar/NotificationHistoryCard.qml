import QtQuick
import QtQuick.Controls
import Quickshell
import qs.desktop.modules.common
import qs.desktop.modules.dock
import qs.desktop.modules.notifications
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
    property int notifId: 0
    property string actionsJson: ""
    property real clockNow: Date.now()
    property bool showPreview: true
    property bool detailsExpanded: false
    property bool sizeReady: false
    property bool interactive: true
    property bool compositorGlass: AppearanceTokens.surface.usesKwinBlur
    // Forwarded by the embedding pane; the Control Center opts this card's
    // glass into the pointer effects, the standalone history window does not.
    property int pointerEffects: 0
    property Item captureAnchor: null
    property rect clipSceneRect: Qt.rect(0, 0, -1, -1)
    property real backdropScale: 1
    property real glassOpacity: 1
    readonly property real compactHeight: 112
    // Serialized {identifier, label} pairs from the live notification; the
    // labels are already translated at snapshot time.
    readonly property var parsedActions: {
        if (!actionsJson || actionsJson.length === 0)
            return []
        try { return JSON.parse(actionsJson) } catch (error) { return [] }
    }
    // Actions live in the expanded view: the chevron shows whenever a row
    // has actions, so a short-bodied notification still gets an expand
    // affordance, and the collapsed deck keeps its fixed 112px geometry.
    readonly property bool canExpand: showPreview && (detailsExpanded || bodyText.truncated
        || summaryText.truncated || parsedActions.length > 0)
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
    implicitHeight: {
        let base = detailsExpanded && showPreview ? Math.max(compactHeight, message.implicitHeight + 54) : compactHeight
        if (actionRows.visible)
            base += actionRows.implicitHeight + 6
        return base
    }
    height: implicitHeight
    Component.onCompleted: sizeReady = true
    Behavior on height {
        enabled: card.sizeReady && !AppTheme.reduceMotion
        NumberAnimation { duration: AppTheme.motionNormal; easing.type: AppearanceTokens.motion.enterCurve }
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
    signal actionActivated(string identifier)

    Item {
        id: nativeOutline
        x: card.visibleRect.x; y: card.visibleRect.y
        width: card.visibleRect.width; height: card.visibleRect.height
    }
    ControlCenterGlass {
        id: glass
        anchors.fill: parent
        radius: 24
        pointerEffects: card.pointerEffects
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
    // Action rows, anchored under the message block (never a child of the
    // Column positioner -- invisible children still take layout space).
    // Same NotificationActionRow the banner's expanded list uses; this card
    // answers activated by bubbling the identifier to the pane, which
    // invokes through the live registry and relaunches the app on a miss.
    Column {
        id: actionRows
        visible: card.detailsExpanded && card.parsedActions.length > 0
        anchors { left: message.left; right: message.right; top: message.bottom; topMargin: 6 }
        spacing: 6
        Repeater {
            model: card.parsedActions
            NotificationActionRow {
                required property var modelData
                label: modelData.label || modelData.identifier || ""
                textColor: card.ink
                onActivated: card.actionActivated(modelData.identifier || "")
            }
        }
    }
    TapHandler {
        enabled: card.canExpand && card.interactive
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: eventPoint => {
            if ((eventPoint.position.x < card.width - 46 || eventPoint.position.y > 38)
                && eventPoint.position.y < (actionRows.visible ? actionRows.y - 6 : Infinity))
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
        contentItem: BundledIcon {
            name: "notification.remove"
            color: card.ink
            opacity: closeButton.hovered || closeButton.activeFocus ? 0.85 : 0.4
            size: 14
        }
        onClicked: card.removeRequested(card.historyKey)
    }
    BundledIcon {
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: 14; bottomMargin: 7 }
        visible: card.canExpand
        name: card.detailsExpanded ? "notification.details.collapse" : "notification.details.expand"
        color: card.ink
        opacity: 0.4
        size: 10
    }
}
