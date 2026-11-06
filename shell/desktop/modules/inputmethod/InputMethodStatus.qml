import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "../../../shared/qml/i18n"
import qs.desktop.modules.common
import qs.desktop.modules.dock
import qs.desktop.modules.bar
import "../../../Kos/Ui"

Item {
    id: root

    property bool dockHosted: false
    property string dockEdge: "bottom"
    property bool verticalDock: false
    property real iconSize: 18

    readonly property string displayLabel: {
        const raw = InputMethodService.imLabel || "中";
        if (raw.indexOf("中") >= 0) return "中";
        if (raw.toLowerCase().indexOf("en") >= 0 || raw.indexOf("英") >= 0) return "英";
        if (raw === "不可用") return "中";
        return raw.length > 2 ? raw.slice(0, 1) : raw;
    }

    rotation: verticalDock ? -90 : 0
    implicitWidth: Math.max(24, badgeText.implicitWidth + 10)
    implicitHeight: 24
    width: implicitWidth
    height: implicitHeight

    readonly property real cellExtraWidth: Math.max(0, implicitWidth - 24)

    property bool menuOpen: false

    SelectionHighlight {
        objectName: "inputmethod-status-selection-highlight"
        anchors.fill: parent
        cornerRadius: 8
        enabled: AppearanceTokens.surface.selectionHighlightStyle === "glass"
        hovered: hoverArea.containsMouse || hoverArea.activeFocus
        pressed: hoverArea.pressed
        selected: root.menuOpen
        dark: AppearanceTokens.isDarkTheme
        fillStrength: 0.85
    }

    Rectangle {
        anchors.fill: parent
        radius: 8
        visible: AppearanceTokens.surface.selectionHighlightStyle !== "glass"
            && (hoverArea.containsMouse || root.menuOpen)
        color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.08)
    }

    // Status glyph / Chinese-English badge
    Item {
        anchors.centerIn: parent
        width: badgeText.implicitWidth
        height: root.iconSize

        Text {
            id: badgeText
            anchors.centerIn: parent
            text: root.displayLabel
            font.pixelSize: 13
            font.bold: true
            font.family: "Noto Sans CJK SC, sans-serif"
            color: ThemeService.barInk
            style: (AppearanceTokens.isDarkTheme && !AppearanceTokens.bar.macStyle)
                ? Text.Outline : Text.Normal
            styleColor: Qt.rgba(0, 0, 0, 0.40)
            scale: hoverArea.pressed ? 0.90 : hoverArea.containsMouse ? 1.05 : 1
            Behavior on scale {
                NumberAnimation { duration: AppearanceTokens.motion.fastDuration; easing.type: Easing.OutCubic }
            }
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor

        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                root.menuOpen = !root.menuOpen;
            } else {
                root.menuOpen = false;
                InputMethodService.toggleInputMethod();
            }
        }
    }

    StatusTooltip {
        anchorItem: root
        shown: hoverArea.containsMouse && !root.menuOpen
        dockHosted: root.dockHosted
        dockEdge: root.dockEdge
        primaryText: (InputMethodService.imName || "输入法") + " (" + root.displayLabel + ")"
        secondaryText: I18n.tr("左键切换模式，右键弹出菜单")
        minimumWidth: 120
    }

    // Liquid Glass Context Menu Popup
    AnimatedPopupWindow {
        id: menuPopup
        property Item anchorItem: root
        requestedOpen: root.menuOpen
        implicitWidth: 200
        implicitHeight: menuColumn.implicitHeight + 20
        color: "transparent"
        contentItem.scale: 1

        PopupAnchorBinding { popupAnchor: menuPopup.anchor; sourceItem: root }
        anchor {
            edges: !root.dockHosted ? Edges.Bottom
                : root.dockEdge === "left" ? Edges.Right
                : root.dockEdge === "right" ? Edges.Left : Edges.Top
            gravity: !root.dockHosted ? Edges.Bottom
                : root.dockEdge === "left" ? Edges.Right
                : root.dockEdge === "right" ? Edges.Left : Edges.Top
            adjustment: PopupAdjustment.Slide
            margins.top: root.dockHosted && root.dockEdge === "bottom" ? -6 : 0
            margins.bottom: root.dockHosted ? 0 : -6
        }

        onClosed: root.menuOpen = false

        BackgroundEffect.blurRegion: menuPopup.visible && menuPopup.revealProgress > 0
            && AppearanceTokens.surface.usesKwinBlur ? menuGlass.blurRegion : null

        KosCardShadow {
            cardWidth: menuGlass.width
            cardHeight: menuGlass.height
            cornerRadius: menuGlass.radius
            cornerExponent: menuGlass.cornerExponent
            x: menuGlass.x - margin
            y: menuGlass.y - margin
            offsetX: 0
            offsetY: 6
            softness: 24
            opacity: AppearanceTokens.isDarkTheme ? 0.45 : 0.22
        }

        LiquidGlassPanel {
            id: menuGlass
            anchors.fill: parent
            radius: 12
            cornerExponent: AppearanceTokens.shape.cornerExponent
            scrimLevel: "balanced"

            Column {
                id: menuColumn
                anchors.centerIn: parent
                width: parent.width - 16
                spacing: 4

                // Header
                Item {
                    width: parent.width
                    height: 24
                    GlassText {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        text: InputMethodService.imName || "中州韵 (Rime)"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        opacity: 0.70
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: AppearanceTokens.isDarkTheme ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
                }

                // Dynamic Rime Properties list from Fcitx5 Kimpanel
                Repeater {
                    model: {
                        const all = InputMethodService.properties;
                        if (!Array.isArray(all)) return [];
                        return all.filter(p => p && p.id !== "/Fcitx/im" && (p.label || p.shortText));
                    }

                    delegate: MenuItemDelegate {
                        readonly property var prop: modelData
                        text: prop.label ? (prop.label + (prop.shortText ? " (" + prop.shortText + ")" : "")) : prop.shortText
                        iconName: prop.icon || "system-run"
                        onTriggered: {
                            root.menuOpen = false;
                            InputMethodService.triggerProperty(prop.id);
                        }
                    }
                }

                // If no dynamic properties loaded yet, show core Rime fallback actions
                MenuItemDelegate {
                    visible: !InputMethodService.properties || InputMethodService.properties.length <= 1
                    text: I18n.tr("重新部署 (Rime)")
                    iconName: "system-run"
                    onTriggered: {
                        root.menuOpen = false;
                        InputMethodService.triggerProperty("/Fcitx/rime-deploy");
                    }
                }

                MenuItemDelegate {
                    visible: !InputMethodService.properties || InputMethodService.properties.length <= 1
                    text: I18n.tr("简繁切换")
                    iconName: "character-set"
                    onTriggered: {
                        root.menuOpen = false;
                        InputMethodService.triggerProperty("/Fcitx/chttrans");
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: AppearanceTokens.isDarkTheme ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
                }

                MenuItemDelegate {
                    text: I18n.tr("输入法设置...")
                    iconName: "configure"
                    onTriggered: {
                        root.menuOpen = false;
                        InputMethodService.configure();
                    }
                }

                MenuItemDelegate {
                    text: I18n.tr("重新加载配置")
                    iconName: "view-refresh"
                    onTriggered: {
                        root.menuOpen = false;
                        InputMethodService.reloadConfig();
                    }
                }
            }
        }
    }

    component MenuItemDelegate: Item {
        id: mi
        property string text: ""
        property string iconName: ""
        signal triggered()

        width: parent ? parent.width : 160
        height: 28

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: miMouse.containsMouse
                ? (AppearanceTokens.isDarkTheme ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06))
                : "transparent"
        }

        GlassText {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 8
            text: mi.text
            font.pixelSize: 13
        }

        MouseArea {
            id: miMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: mi.triggered()
        }
    }
}
