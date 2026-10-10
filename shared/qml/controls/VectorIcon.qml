import QtQuick

Item {
    id: root
    property string name: "check"
    property color color: "white"
    property real size: 16
    implicitWidth: size
    implicitHeight: size
    readonly property var paths: ({
        check: "M5 12l5 5L20 7",
        close: "M6 6l12 12M18 6L6 18",
        chevron: "M6 9l6 6 6-6",
        preview: "M7 17L17 7M8 7h9v9",
        theme: "M12 3l9 9-9 9-9-9zM8 12l4-4 4 4-4 4z",
        wallpaper: "M3 4h18v16H3zM3 16l5-5 4 4 3-3 6 5M16 8h.01",
        panel: "M3 5h18v14H3zM3 9h18M7 9v10",
        dock: "M3 13h18v7H3zM7 16v1M12 16v1M17 16v1",
        grid: "M3 3h6v6H3zM15 3h6v6h-6zM3 15h6v6H3zM15 15h6v6h-6z",
        keyboard: "M3 6h18v12H3zM7 10h.01M12 10h.01M17 10h.01M7 14h10",
        settings: "M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8M12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6L7 7M17 17l1.4 1.4M5.6 18.4L7 17M17 7l1.4-1.4",
        trash: "M3 6h18M8 6V3h8v3M6 6l1 15h10l1-15M10 10v7M14 10v7",
        arrows: "M3 12h18M7 8l-4 4 4 4M17 8l4 4-4 4",
        circle: "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8",
        contrast: "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18M12 3v18M12 7h5M12 11h8M12 15h7",
        waves: "M3 8c3-4 6 4 9 0s6 4 9 0M3 16c3-4 6 4 9 0s6 4 9 0",
        copy: "M8 8h13v13H8zM16 8V3H3v13h5",
        home: "M3 10l9-7 9 7M5 9v12h14V9M10 21v-7h4v7",
        search: "M10 3a7 7 0 1 0 0 14 7 7 0 0 0 0-14M15 15l6 6",
        resize: "M4 10V4h6M20 14v6h-6M4 4l6 6M20 20l-6-6",
        undo: "M8 4L3 9l5 5M3 9h11a6 6 0 0 1 0 12",
        bold: "M6 3h7a4.5 4.5 0 0 1 0 9H6zM6 12h8a4.5 4.5 0 0 1 0 9H6z",
        corners: "M4 12V8a4 4 0 0 1 4-4h4M12 20h4a4 4 0 0 0 4-4v-4",
        shadow: "M4 4h13v13H4zM8 20h12V8",
        minimize: "M4 6h16v12H4zM9 12l3 3 3-3M12 9v6",
        plus: "M12 4v16M4 12h16"
    })
    Image {
        anchors.fill: parent
        sourceSize: Qt.size(root.size * 2, root.size * 2)
        source: "data:image/svg+xml;utf8," + encodeURIComponent(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="rgb('
            + Math.round(root.color.r * 255) + ',' + Math.round(root.color.g * 255) + ','
            + Math.round(root.color.b * 255) + ')" stroke-opacity="' + root.color.a
            + '" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" d="'
            + (root.paths[root.name] || root.paths.check) + '"/></svg>')
    }
}
