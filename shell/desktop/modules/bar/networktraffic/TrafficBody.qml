import QtQuick
import QtQuick.Window
import "../../../../shared/qml/i18n"
import "../NetworkRateFormat.mjs" as RateFormat

// Card contents for the network traffic panel. The header is pinned; everything
// below it scrolls inside one Flickable, which is also the only wheel target
// (the process ListView is non-interactive).
Item {
    id: body
    property color ink: "white"
    property color mutedInk: Qt.rgba(1, 1, 1, 0.7)
    property bool dark: true
    property bool connected: false
    property string connectivity: "unknown"
    property real downloadRate: 0
    property real uploadRate: 0
    property real totalDownload: -1
    property real totalUpload: -1
    property string interfaceName: ""
    property string networkName: ""
    property string macAddress: ""
    property string localIp: ""
    property string publicIp: ""
    property var downloadHistory: []
    property var uploadHistory: []
    property var connectivityHistory: []
    property bool detailsExpanded: false

    // The collapsible sections. The process list is never collapsed any more:
    // it is the one thing in this panel that is worth reading, and it used to
    // be the last thing in a long scroll. Everything else folds away, and a
    // folded section takes no space at all -- the wrapper's height is zero, so
    // there is no gap left under the header.
    property bool connectivityOpen: false
    property bool interfaceOpen: false
    property bool interface2Open: false
    property bool addressOpen: false
    property var applications: []
    property string applicationsError: ""

    readonly property alias processModel: processList.model
    readonly property alias processCount: processList.count
    readonly property real hairline: 1 / (Screen.devicePixelRatio || 1)
    readonly property bool internetKnown: ["full", "limited", "none", "portal"].indexOf(connectivity) >= 0
    readonly property string statusState: connected ? "up" : "down"
    readonly property string internetState: !internetKnown ? "unknown"
        : (connected && connectivity === "full" ? "up" : "down")
    readonly property var downloadParts: RateFormat.rateParts(downloadRate)
    readonly property var uploadParts: RateFormat.rateParts(uploadRate)

    signal closeRequested()
    signal detailsToggleRequested()
    signal refreshRequested()
    signal resetTotalsRequested()

    implicitHeight: 42 + scroll.contentHeight

    function setApplications(rows) {
        processList.sync(rows)
    }
    function clearApplications() {
        processList.clear()
    }

    // ---- fixed header ---------------------------------------------------
    Item {
        id: header
        width: parent.width
        height: 42
        Canvas {
            id: signalGlyph
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            onPaint: {
                const c = getContext("2d")
                c.reset()
                c.clearRect(0, 0, width, height)
                c.fillStyle = body.mutedInk
                for (let i = 0; i < 4; ++i)
                    c.fillRect(i * 4, height - 5 - i * 2, 3, 5 + i * 2)
            }
        }
        Text {
            objectName: "traffic-heading"
            anchors.centerIn: parent
            width: parent.width - 68
            text: I18n.tr("Network")
            color: body.ink
            font.pixelSize: 14
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
        TrafficActionButton {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 22
            glyphSize: 12
            kind: "close"
            ink: body.mutedInk
            onClicked: body.closeRequested()
        }
    }

    Flickable {
        id: scroll
        y: 42
        width: parent.width
        height: Math.max(0, parent.height - 42)
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: content
            width: scroll.width

            // ---- large rates --------------------------------------------
            Item {
                width: parent.width
                height: 90
                Item {
                    x: 8
                    width: (parent.width - 16) / 2
                    height: 90
                    // Number and unit share a baseline; a plain Row would
                    // top-align the 13 px unit inside the 26 px number.
                    Item {
                        width: downloadNumber.implicitWidth + 3 + downloadUnit.implicitWidth
                        height: downloadNumber.implicitHeight
                        x: (parent.width - width) / 2
                        y: 19
                        Text {
                            id: downloadNumber
                            x: 0
                            y: 0
                            text: body.downloadParts.number
                            color: body.ink
                            font.pixelSize: 26
                            font.weight: Font.Light
                            textFormat: Text.PlainText
                        }
                        Text {
                            id: downloadUnit
                            x: downloadNumber.implicitWidth + 3
                            y: downloadNumber.baselineOffset - baselineOffset
                            text: body.downloadParts.unit
                            color: body.mutedInk
                            font.pixelSize: 13
                            font.weight: Font.Light
                            textFormat: Text.PlainText
                        }
                    }
                    Row {
                        x: (parent.width - width) / 2
                        y: 50
                        spacing: 4
                        Rectangle {
                            y: 5
                            width: 10
                            height: 10
                            radius: 2.5
                            color: "#0099ff"
                        }
                        Text {
                            text: I18n.tr("Download")
                            color: body.ink
                            font.pixelSize: 11
                            textFormat: Text.PlainText
                        }
                    }
                }
                Item {
                    x: 8 + (parent.width - 16) / 2
                    width: (parent.width - 16) / 2
                    height: 90
                    Item {
                        width: uploadNumber.implicitWidth + 3 + uploadUnit.implicitWidth
                        height: uploadNumber.implicitHeight
                        x: (parent.width - width) / 2
                        y: 19
                        Text {
                            id: uploadNumber
                            x: 0
                            y: 0
                            text: body.uploadParts.number
                            color: body.ink
                            font.pixelSize: 26
                            font.weight: Font.Light
                            textFormat: Text.PlainText
                        }
                        Text {
                            id: uploadUnit
                            x: uploadNumber.implicitWidth + 3
                            y: uploadNumber.baselineOffset - baselineOffset
                            text: body.uploadParts.unit
                            color: body.mutedInk
                            font.pixelSize: 13
                            font.weight: Font.Light
                            textFormat: Text.PlainText
                        }
                    }
                    Row {
                        x: (parent.width - width) / 2
                        y: 50
                        spacing: 4
                        Rectangle {
                            y: 5
                            width: 10
                            height: 10
                            radius: 2.5
                            color: "#ff3b40"
                        }
                        Text {
                            text: I18n.tr("Upload")
                            color: body.ink
                            font.pixelSize: 11
                            textFormat: Text.PlainText
                        }
                    }
                }
            }

            // ---- usage history ------------------------------------------
            TrafficSection {
                x: 8
                width: content.width - 16
                title: I18n.tr("Usage history")
                ink: body.ink
                dark: body.dark
            }
            TrafficChart {
                x: 8
                width: content.width - 16
                height: 90
                download: body.downloadHistory
                upload: body.uploadHistory
                ink: body.ink
                mutedInk: body.mutedInk
                separator: body.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.1)
            }

            // ---- top processes ------------------------------------------
            TrafficSection {
                x: 8
                width: content.width - 16
                title: I18n.tr("Top processes")
                ink: body.ink
                dark: body.dark
                actionKind: body.detailsExpanded ? "up" : "down"
                actionObjectName: "traffic-details-toggle"
                onActionTriggered: body.detailsToggleRequested()
            }
            Item {
                width: content.width
                height: 22
                visible: true
                Text {
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 16 - 116
                    text: I18n.tr("Process")
                    color: body.mutedInk
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
                Item {
                    x: 8 + parent.width - 16 - 108
                    width: 54
                    height: 22
                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 10
                        height: 10
                        radius: 2.5
                        color: "#0099ff"
                    }
                }
                Item {
                    x: 8 + parent.width - 16 - 54
                    width: 54
                    height: 22
                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 10
                        height: 10
                        radius: 2.5
                        color: "#ff3b40"
                    }
                }
            }
            TrafficProcessList {
                id: processList
                x: 8
                width: content.width - 16
                height: body.detailsExpanded ? processList.contentHeight : 0
                visible: true
                ink: body.ink
                mutedInk: body.mutedInk
            }
            Text {
                x: 8
                width: content.width - 16
                topPadding: 8
                visible: body.applications.length === 0
                text: body.applicationsError.length > 0 ? body.applicationsError
                    : I18n.tr("Sampling application traffic…")
                color: body.mutedInk
                font.pixelSize: 11
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
            Text {
                x: 8
                width: content.width - 16
                topPadding: 8
                visible: processList.count > 0
                text: I18n.tr("Visible TCP connections only. Proxy traffic may be counted twice; UDP/QUIC is excluded.")
                color: body.mutedInk
                font.pixelSize: 10
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
            // ---- connectivity history (collapsible) -------------------------------
            Column {
                width: parent.width
                height: body.connectivityOpen ? implicitHeight : 0
                visible: body.connectivityOpen

            TrafficSection {
                x: 8
                width: content.width - 16
                title: I18n.tr("Connectivity history")
                ink: body.ink
                dark: body.dark
            }

                ConnectivityGrid {
                    x: 8
                    width: content.width - 16
                    height: 30
                    samples: body.connectivityHistory
                    ink: body.ink
                }
            }

            // ---- interface (collapsible) -------------------------------
            Column {
                width: parent.width
                height: body.interfaceOpen ? implicitHeight : 0
                visible: body.interfaceOpen

            TrafficSection {
                x: 8
                width: content.width - 16
                title: I18n.tr("Interface")
                ink: body.ink
                dark: body.dark
                actionKind: "reset"
                onActionTriggered: body.resetTotalsRequested()
            }

                TrafficFieldRow {
                    x: 8
                    width: content.width - 16
                    title: I18n.tr("Total upload:")
                    value: RateFormat.bytes(body.totalUpload)
                    ink: body.ink
                    mutedInk: body.mutedInk
                    showSwatch: true
                    swatchColor: "#ff3b40"
                }
                TrafficFieldRow {
                    x: 8
                    width: content.width - 16
                    title: I18n.tr("Total download:")
                    value: RateFormat.bytes(body.totalDownload)
                    ink: body.ink
                    mutedInk: body.mutedInk
                    showSwatch: true
                    swatchColor: "#0099ff"
                }
                TrafficStatusRow {
                    x: 8
                    width: content.width - 16
                    title: I18n.tr("Status:")
                    state: body.statusState
                    upText: I18n.tr("UP")
                    downText: I18n.tr("DOWN")
                    ink: body.ink
                    mutedInk: body.mutedInk
                    pillObjectName: "traffic-status-pill"
                }
                TrafficStatusRow {
                    x: 8
                    width: content.width - 16
                    title: I18n.tr("Internet connection:")
                    state: body.internetState
                    upText: I18n.tr("UP")
                    downText: I18n.tr("DOWN")
                    ink: body.ink
                    mutedInk: body.mutedInk
                    pillObjectName: "traffic-internet-pill"
                }
                TrafficFieldRow {
                    x: 8
                    width: content.width - 16
                    title: I18n.tr("Latency:")
                    value: "—"
                    ink: body.ink
                    mutedInk: body.mutedInk
                }
                TrafficFieldRow {
                    x: 8
                    width: content.width - 16
                    title: I18n.tr("Jitter:")
                    value: "—"
                    ink: body.ink
                    mutedInk: body.mutedInk
                }
            }

            // ---- second interface block (collapsible) -------------------------------
            Column {
                width: parent.width
                height: body.interface2Open ? implicitHeight : 0
                visible: body.interface2Open

            TrafficSection {
                x: 8
                width: content.width - 16
                title: I18n.tr("Interface")
                ink: body.ink
                dark: body.dark
                actionKind: "reset"
                onActionTriggered: body.refreshRequested()
            }

                TrafficFieldRow {
                    x: 8
                    width: content.width - 16
                    title: I18n.tr("Interface:")
                    value: body.interfaceName || "—"
                    ink: body.ink
                    mutedInk: body.mutedInk
                }
                TrafficStatusRow {
                    x: 8
                    width: content.width - 16
                    title: I18n.tr("Status:")
                    state: body.statusState
                    upText: I18n.tr("UP")
                    downText: I18n.tr("DOWN")
                    ink: body.ink
                    mutedInk: body.mutedInk
                    pillObjectName: "traffic-interface-pill"
                }
                TrafficFieldRow {
                    x: 8
                    width: content.width - 16
                    title: I18n.tr("Physical address:")
                    value: body.macAddress || "—"
                    ink: body.ink
                    mutedInk: body.mutedInk
                }
                TrafficFieldRow {
                    x: 8
                    width: content.width - 16
                    title: I18n.tr("Network:")
                    value: body.networkName || "—"
                    ink: body.ink
                    mutedInk: body.mutedInk
                }
            }

            // ---- address (collapsible) -------------------------------
            Column {
                width: parent.width
                height: body.addressOpen ? implicitHeight : 0
                visible: body.addressOpen

            TrafficSection {
                x: 8
                width: content.width - 16
                title: I18n.tr("Address")
                ink: body.ink
                dark: body.dark
                actionKind: "reset"
                onActionTriggered: body.refreshRequested()
            }

                TrafficFieldRow {
                    x: 8
                    width: content.width - 16
                    title: I18n.tr("Local IP:")
                    value: body.localIp || "—"
                    ink: body.ink
                    mutedInk: body.mutedInk
                }
                TrafficFieldRow {
                    x: 8
                    width: content.width - 16
                    title: I18n.tr("Public IP:")
                    value: body.publicIp || "—"
                    ink: body.ink
                    mutedInk: body.mutedInk
                }
            }

            Item {
                width: parent.width
                height: 8
            }
        }
    }
}
