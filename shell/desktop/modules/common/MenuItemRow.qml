import QtQuick
import qs.desktop.modules.dock
import "../../../Kos/Ui"

// A row in a ContextMenu: icon + label, with optional checkmark (checkable),
// submenu chevron, and a thin separator variant. Hover only changes the row's
// visual highlight; navigation is owned by ContextMenu's click handler.
//
// `icon` 是 ShellIconMap.mjs 的功能名；外部菜单图片单独通过 iconSource 传入。
// 界面图标通过共享字形库渲染，不查系统图标主题。
Item {
    id: row

    property string label: ""
    property string icon: ""
    property bool reserveIconSpace: false
    // Image URL for entries whose icon does not come from BundledIcons
    // (e.g. DBusMenu-provided tray menu icons). Only used when `icon` is
    // not a registered bundled name.
    property string iconSource: ""
    property color foregroundColor: "#ffffff"
    property bool itemEnabled: true
    property bool hasSubmenu: false
    property bool checkable: false
    property bool checked: false
    property bool separator: false
    signal clicked()

    readonly property bool _hasIcon: BundledIcons.has(row.icon)
        || row.iconSource.length > 0
    readonly property bool _reserveIconSlot: row.reserveIconSpace || row._hasIcon

    // Bind directly to MouseArea.containsMouse instead of maintaining a
    // transient flag.  Delegates are replaced when entering a submenu, and a
    // flag set by onEntered/onExited can otherwise be stale or miss the first
    // hover event in a PopupWindow.
    readonly property bool _hover: pointer.containsMouse
    readonly property color _hi: AppearanceTokens.surface.pick((itemEnabled ? AppearanceTokens.state.hover
            : AppearanceTokens.state.disabled), Qt.rgba(row.foregroundColor.r, row.foregroundColor.g,
            row.foregroundColor.b,
            itemEnabled ? (ThemeService.isDark ? 0.22 : 0.10) : 0.05))

    height: row.separator ? 1 : 38
    visible: row.separator || label.length > 0
    width: parent ? parent.width : 0

    // Separator line.
    Rectangle {
        visible: row.separator
        x: 10
        width: parent.width - 20
        height: 1
        anchors.verticalCenter: parent.verticalCenter
        color: Qt.rgba(row.foregroundColor.r, row.foregroundColor.g,
            row.foregroundColor.b, 0.12)
    }

    readonly property bool _useGlassSelection: AppearanceTokens.surface.selectionHighlightStyle === "glass"

    // Glass selection plate
    SelectionHighlight {
        objectName: "menu-item-selection-highlight"
        anchors.fill: parent
        cornerRadius: AppearanceTokens.shape.medium
        enabled: row._useGlassSelection && row.itemEnabled && !row.separator
        hovered: row._hover
        pressed: pointer.pressed
        selected: row.checked
        dark: ThemeService.isDark
        fillStrength: 0.90
        z: -1
    }

    // Legacy hover background (behind all other content).
    Rectangle {
        id: bg
        anchors.fill: parent
        radius: AppearanceTokens.shape.medium
        visible: !row._useGlassSelection
        color: (row._hover && row.itemEnabled && !row.separator) ? row._hi : "transparent"
        Behavior on color { ColorAnimation { duration: AppearanceTokens.motion.instant.duration; easing.type: AppearanceTokens.motion.enterCurve } }
        z: -1
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: row._reserveIconSlot ? 9 : 0
        visible: !row.separator

        // Keep text aligned when only a few actions have leading icons.
        Item {
            visible: row._reserveIconSlot
            width: 18
            height: 18
            anchors.verticalCenter: parent.verticalCenter
            opacity: row.itemEnabled ? 0.9 : 0.5
            BundledIcon {
                anchors.fill: parent
                visible: BundledIcons.has(row.icon)
                size: 18
                name: row.icon
                color: row.foregroundColor
            }
            // External DBusMenu icons stay synchronous for KIconEngine.
            AppIcon {
                anchors.fill: parent
                visible: !BundledIcons.has(row.icon) && row.iconSource.length > 0
                source: row.iconSource
                asynchronous: false
            }
        }

        ShellText {
            text: row.label
            elide: Text.ElideRight
            font.family: AppearanceTokens.typography.displayChain
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: row.foregroundColor
            opacity: row.itemEnabled ? 1.0 : 0.6
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, Math.min(implicitWidth, (row.width - 24) - (row._reserveIconSlot ? 27 : 0) - ((row.checked || row.hasSubmenu) ? 24 : 0)))
        }
    }

    // Trailing checkmark or submenu chevron — bundled artwork, same contract
    // as the leading icon (the shared font, no system icon theme).
    Item {
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: 16
        height: 16
        visible: !row.separator && (row.checked || row.hasSubmenu)

        BundledIcon {
            anchors.centerIn: parent
            size: row.checked ? 14 : 16
            name: row.checked ? "menu.trailing.checked" : "menu.trailing.submenu"
            color: row.checked ? row.foregroundColor
                : Qt.rgba(row.foregroundColor.r, row.foregroundColor.g,
                    row.foregroundColor.b, 0.55)
        }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        enabled: row.itemEnabled && !row.separator
        onClicked: row.clicked()
    }
}
