import QtQuick
import QtQuick.Layouts

// One name and an optional description; no leading icon or second heading.
Item {
    id: root
    default property alias controls: actions.data
    property string title: ""
    property string description: ""
    property real minimumRowHeight: 28
    property real horizontalPadding: 16
    property real verticalPadding: 2
    property real controlSpacing: 12
    property real minimumLabelWidth: 120
    property bool separator: true
    property bool allowStacking: true
    property color titleColor: AppTheme.text
    property color descriptionColor: AppTheme.dark ? "#98989D" : "#8E8E93"
    property color separatorColor: AppTheme.dark ? "#38383a" : "#E5E5E5"
    property alias titleFont: nameLabel.font
    property alias descriptionFont: detailLabel.font
    readonly property bool isSettingsItem: true
    readonly property real availableWidth: Math.max(0, width - horizontalPadding * 2)
    readonly property bool hasControls: actions.implicitWidth > 0
    readonly property real controlsWidth: Math.min(allowStacking ? availableWidth
        : Math.max(0, availableWidth - minimumLabelWidth - controlSpacing), actions.implicitWidth)
    readonly property bool stacked: allowStacking && hasControls
        && availableWidth < minimumLabelWidth + controlSpacing + actions.implicitWidth
    readonly property bool followedByItem: {
        const siblings = parent ? parent.children : []
        let afterSelf = false
        for (let i = 0; i < siblings.length; ++i) {
            const item = siblings[i]
            if (item === root) afterSelf = true
            else if (afterSelf && item.visible && item.isSettingsItem === true) return true
        }
        return false
    }
    readonly property real bodyHeight: stacked
        ? labels.implicitHeight + 6 + actions.implicitHeight
        : Math.max(labels.implicitHeight, actions.implicitHeight)

    implicitWidth: 420
    implicitHeight: Math.max(minimumRowHeight, bodyHeight + verticalPadding * 2)
    Layout.fillWidth: true
    Layout.minimumWidth: 0
    Layout.minimumHeight: implicitHeight
    Accessible.role: Accessible.Grouping
    Accessible.name: title
    Accessible.description: description

    data: [Column {
        id: labels
        x: root.horizontalPadding
        y: root.stacked ? root.verticalPadding : (root.height - height) / 2
        width: root.stacked || !root.hasControls ? root.availableWidth
            : Math.max(0, root.availableWidth - root.controlsWidth - root.controlSpacing)
        spacing: 2
        Text {
            id: nameLabel
            width: parent.width
            visible: text.length > 0
            text: root.title
            color: root.enabled ? root.titleColor : AppTheme.disabledText
            font.pixelSize: 12
            font.weight: Font.Normal
            wrapMode: root.allowStacking ? Text.Wrap : Text.NoWrap
            elide: Text.ElideRight
            Accessible.ignored: true
        }
        Text {
            id: detailLabel
            width: parent.width
            visible: text.length > 0
            text: root.description
            color: root.enabled ? root.descriptionColor : AppTheme.withAlpha(root.descriptionColor, .65)
            font.pixelSize: 10
            font.weight: Font.Normal
            wrapMode: Text.Wrap
            Accessible.ignored: true
        }
    },

    RowLayout {
        id: actions
        x: root.width - root.horizontalPadding - root.controlsWidth
        y: root.stacked ? labels.y + labels.height + 6 : (root.height - height) / 2
        width: root.controlsWidth
        height: implicitHeight
        spacing: 8
    },

    Rectangle {
        x: root.horizontalPadding
        y: parent.height - 1
        width: root.availableWidth
        height: 1
        color: root.separatorColor
        visible: root.separator && root.followedByItem
    }]
}
