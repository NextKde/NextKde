import QtQuick
import "../NetworkRateFormat.mjs" as RateFormat

// Process rows backed by a ListModel so a 2 s rate refresh only mutates
// properties. Rows are matched by name+iconSource, reordered with move() and
// never rebuilt; the outer Flickable owns scrolling, which is why this view is
// non-interactive and exactly as tall as its rows.
Item {
    id: root
    property color ink: "white"
    property color mutedInk: Qt.rgba(1, 1, 1, 0.7)
    readonly property alias model: processModel
    readonly property alias count: list.count
    readonly property real contentHeight: list.contentHeight

    implicitHeight: list.contentHeight

    function sync(rows) {
        const source = rows || []
        for (let i = 0; i < source.length; ++i) {
            const row = source[i]
            let existing = -1
            for (let j = i; j < processModel.count; ++j) {
                const candidate = processModel.get(j)
                if (candidate.name === row.name && candidate.iconSource === row.iconSource) {
                    existing = j
                    break
                }
            }
            if (existing < 0) {
                processModel.insert(i, {
                    name: row.name,
                    download: row.download,
                    upload: row.upload,
                    iconSource: row.iconSource || ""
                })
            } else {
                if (existing !== i)
                    processModel.move(existing, i, 1)
                const current = processModel.get(i)
                if (current.download !== row.download)
                    processModel.setProperty(i, "download", row.download)
                if (current.upload !== row.upload)
                    processModel.setProperty(i, "upload", row.upload)
                if (current.iconSource !== (row.iconSource || ""))
                    processModel.setProperty(i, "iconSource", row.iconSource || "")
            }
        }
        if (processModel.count > source.length)
            processModel.remove(source.length, processModel.count - source.length)
    }
    function clear() {
        if (processModel.count > 0)
            processModel.clear()
    }

    ListModel {
        id: processModel
    }
    ListView {
        id: list
        objectName: "traffic-process-list"
        width: root.width
        height: Math.max(0, contentHeight)
        // The panel's single Flickable scrolls the whole card; a second wheel
        // target here would trap scrolling inside the list.
        interactive: false
        reuseItems: true
        cacheBuffer: 240
        boundsBehavior: Flickable.StopAtBounds
        model: processModel
        delegate: Item {
            id: rowItem
            required property string name
            required property string iconSource
            required property real download
            required property real upload
            width: ListView.view.width
            height: 22

            Image {
                id: artwork
                x: 0
                anchors.verticalCenter: parent.verticalCenter
                width: 12
                height: 12
                source: rowItem.iconSource
                sourceSize: Qt.size(16, 16)
                fillMode: Image.PreserveAspectFit
                // image://icon/* must stay synchronous: KIconEngine is not
                // thread safe and async decoding races the GUI thread.
                asynchronous: rowItem.iconSource.indexOf("file:") === 0
                    || rowItem.iconSource.indexOf("qrc:") === 0
                    || rowItem.iconSource.indexOf(":/") === 0
                visible: rowItem.iconSource.length > 0 && status !== Image.Error
            }
            Item {
                visible: !artwork.visible
                x: 0
                anchors.verticalCenter: parent.verticalCenter
                width: 12
                height: 12
                Rectangle {
                    anchors.fill: parent
                    radius: 2
                    color: Qt.rgba(root.mutedInk.r, root.mutedInk.g, root.mutedInk.b, 0.3)
                }
                Rectangle {
                    x: 3
                    y: 4
                    width: parent.width - 6
                    height: 0.8
                    color: root.mutedInk
                }
                Rectangle {
                    x: 3
                    y: 7
                    width: parent.width - 7
                    height: 0.8
                    color: root.mutedInk
                }
            }
            Text {
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 132
                text: rowItem.name
                color: root.ink
                font.pixelSize: 12
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
            Text {
                x: 152
                anchors.verticalCenter: parent.verticalCenter
                width: 54
                text: RateFormat.format(rowItem.download)
                color: root.ink
                font.pixelSize: 11
                font.weight: Font.Medium
                horizontalAlignment: Text.AlignRight
                clip: true
                textFormat: Text.PlainText
            }
            Text {
                x: 210
                anchors.verticalCenter: parent.verticalCenter
                width: 54
                text: RateFormat.format(rowItem.upload)
                color: root.ink
                font.pixelSize: 11
                font.weight: Font.Medium
                horizontalAlignment: Text.AlignRight
                clip: true
                textFormat: Text.PlainText
            }
        }
    }
}
