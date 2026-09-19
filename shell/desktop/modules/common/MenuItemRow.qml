import QtQuick
import qs.desktop.modules.dock

// A row in a ContextMenu: icon + label, with optional checkmark (checkable),
// submenu chevron, and a thin separator variant. Hover only changes the row's
// visual highlight; navigation is owned by ContextMenu's click handler.
//
// `icon` 是 BundledIcons 的登记名（不是字形、不是路径，也不是主题图标名）。
// 图案与数据都在那一张表里，渲染不查系统图标主题、不依赖任何字体。
Item {
    id: row

    property string label: ""
    property string icon: ""
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

    // Bind directly to MouseArea.containsMouse instead of maintaining a
    // transient flag.  Delegates are replaced when entering a submenu, and a
    // flag set by onEntered/onExited can otherwise be stale or miss the first
    // hover event in a PopupWindow.
    readonly property bool _hover: pointer.containsMouse
    readonly property color _hi: AppearanceTokens.isMaterial
        ? (itemEnabled ? AppearanceTokens.state.hover
            : AppearanceTokens.state.disabled)
        : Qt.rgba(row.foregroundColor.r, row.foregroundColor.g,
            row.foregroundColor.b,
            itemEnabled ? (ThemeService.isDark ? 0.22 : 0.10) : 0.05)

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

    // Hover background (behind all other content).
    Rectangle {
        id: bg
        anchors.fill: parent
        radius: AppearanceTokens.shape.medium
        color: (row._hover && row.itemEnabled && !row.separator) ? row._hi : "transparent"
        Behavior on color { ColorAnimation { duration: 90 } }
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: row._hasIcon ? 9 : 0
        visible: !row.separator

        // Shell-owned artwork, resolved through the single BundledIcons table.
        // White-stroked SVG used as an alpha mask and projected onto the menu
        // foreground colour, so the mark never depends on an installed icon
        // theme or glyph font.
        BundledIcon {
            visible: BundledIcons.has(row.icon)
            width: visible ? 18 : 0
            height: 18
            size: 18
            name: row.icon
            color: row.foregroundColor
            anchors.verticalCenter: parent.verticalCenter
            opacity: row.itemEnabled ? 0.9 : 0.5
        }

        // External icon (URL or image-provider path) for items such as
        // DBusMenu tray entries. Stays synchronous on purpose: the icon
        // provider can reach KIconEngine, which is not thread-safe.
        Image {
            visible: !BundledIcons.has(row.icon) && row.iconSource.length > 0
            width: visible ? 18 : 0
            height: 18
            source: row.iconSource
            asynchronous: false
            sourceSize.width: 18
            sourceSize.height: 18
            anchors.verticalCenter: parent.verticalCenter
            opacity: row.itemEnabled ? 0.9 : 0.5
        }

        Text {
            text: row.label
            elide: Text.ElideRight
            font.family: "SF Pro Display, Noto Sans CJK SC, sans-serif"
            font.pixelSize: 13
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
            color: row.foregroundColor
            opacity: row.itemEnabled ? 1.0 : 0.6
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, (row.width - 24) - (row._hasIcon ? 27 : 0) - ((row.checked || row.hasSubmenu) ? 24 : 0))
        }
    }

    // Trailing checkmark or submenu chevron — bundled artwork, same contract
    // as the leading icon (no glyph font, no icon theme).
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
            name: row.checked ? "check" : "submenu"
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
