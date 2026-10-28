import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Window
import "../controls" as Liquid

// A compact floating liquid panel; text and keyboard behavior stay independent.
Controls.ToolTip {
    id: root
    objectName: "kosToolTip"
    required property Item target
    property bool when: true
    // Controls expose hovered; generic Items can bind their own HoverHandler here.
    property bool hovered: target && "hovered" in target ? target.hovered : false
    property bool showOnFocus: true
    readonly property bool keyboardFocused: target && target.activeFocus
        && (!("visualFocus" in target) || target.visualFocus)
    property bool onlyWhenTruncated: false
    property bool truncated: false
    property real maximumWidth: 280
    property real targetGap: 6
    property real cornerRadius: 14
    property real materialOpacity: 0.7
    property bool reduceTransparency: AppTheme.reduceTransparency
    property Liquid.LiquidBackdrop backdrop: backdropForTarget()
    readonly property bool sampling: glassLoader.item !== null && glassLoader.item.sampling

    function backdropForTarget() {
        // Popups paint in the overlay, outside the target's content subtree.
        // Validate the bubble rather than the trigger against scoped sources.
        for (const role of ["toolTipBackdrop", "contentBackdrop"]) {
            for (let host = target; host; host = host.parent) {
                const candidate = role in host ? host[role] : null;
                if (candidate && candidate.canSample(background))
                    return candidate;
            }
        }
        return Liquid.LiquidStyle.backdropFor(hostWindow);
    }
    property bool darkAppearance: AppTheme.dark
    readonly property var hostWindow: target ? target.Window.window : null
    readonly property bool eligible: when && target !== null && target.visible && target.enabled && text.trim().length > 0 && (!onlyWhenTruncated || truncated)
    property bool _dismissed: false

    parent: target
    visible: eligible && !_dismissed && (hovered || (showOnFocus && keyboardFocused))
    delay: 700
    timeout: 5000
    focus: false
    modal: false
    dim: false
    margins: 8
    padding: 5
    leftPadding: 10
    rightPadding: 10
    font.pixelSize: 11
    font.weight: Font.Normal
    closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutsideParent

    implicitWidth: Math.min(Math.max(1, maximumWidth), hostWindow ? Math.max(1, hostWindow.width - margins * 2) : maximumWidth, implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: implicitContentHeight + topPadding + bottomPadding
    x: target ? (target.width - width) / 2 : 0
    y: {
        if (!target || !hostWindow)
            return -implicitHeight - targetGap;
        // Read local geometry too; the Popup positioner follows ancestor transforms.
        const localY = target.y;
        const top = target.mapToItem(hostWindow.contentItem, 0, 0).y;
        return top >= implicitHeight + targetGap + margins ? -implicitHeight - targetGap : target.height + targetGap;
    }

    onHoveredChanged: if (!hovered)
        _dismissed = false
    onWhenChanged: if (!when)
        _dismissed = false
    Connections {
        target: root.target
        ignoreUnknownSignals: true
        function onPressed() {
            root._dismissed = true;
        }
        function onClicked() {
            root._dismissed = true;
        }
        function onActiveFocusChanged() {
            if (!root.target || !root.target.activeFocus)
                root._dismissed = false;
        }
    }

    Shortcut {
        sequence: "Esc"
        context: Qt.WindowShortcut
        enabled: root.visible
        onActivated: root._dismissed = true
    }

    contentItem: Text {
        text: root.text
        textFormat: Text.PlainText
        font: root.font
        color: root.darkAppearance ? "#d6d6da" : "#55555a"
        wrapMode: Text.Wrap
    }
    background: Item {
        Liquid.LiquidOuterShadow {
            anchors.fill: parent
            visible: root.visible && !root.reduceTransparency
            radius: root.cornerRadius
            shadowOpacity: root.darkAppearance ? 0.24 : 0.12
            softness: 4
            spread: 12
            offset: Qt.vector2d(0, 1)
        }
        Rectangle {
            objectName: "toolTipFallback"
            anchors.fill: parent
            visible: !root.sampling
            radius: root.cornerRadius
            color: root.darkAppearance ? "#303034" : "#f0f0f1"
            border.width: 0
        }
        Loader {
            id: glassLoader
            anchors.fill: parent
            active: root.visible && !root.reduceTransparency
                && GraphicsInfo.api !== GraphicsInfo.Software
                && root.backdrop !== null && root.backdrop.canSample(root.background)
            sourceComponent: Liquid.LiquidSurface {
                objectName: "toolTipLiquidSurface"
                radius: root.cornerRadius
                backdrop: root.backdrop
                darkAppearance: root.darkAppearance
                tintColor: root.darkAppearance ? "#303034" : "#f0f0f1"
                tintStrength: Math.max(0, Math.min(1, root.materialOpacity))
                blurStrength: 0.65
                readability: 0
                refractionStrength: 2.5
                magnification: 1.025
                edgeWidth: 5
                reflectionStrength: 0.35
                fullHighlight: true
                edgeShadeStrength: 0
            }
        }
    }
}
