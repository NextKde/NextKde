import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../../../shared/qml/controls" as LiquidControls
import "../../../shared/qml/i18n"

// IslandSettingsPage — settings for the top-edge island.
//
// Ported from the NookX Dynamic Island. The original exposes its own
// appearance choices (islandShapeMode, islandBackgroundMode,
// DynamicIslandDisplayPolicy), its widget catalogue and enabled-widget order,
// and a quick-launch list of applications.
//
// The page is one master switch plus the configuration that only makes sense
// while the island is on. Everything below the switch is disabled while the
// island is off, so the page reads as one decision plus its consequences
// rather than a list of unrelated options.
ColumnLayout {
    id: islandPage
    objectName: "islandSettingsPage"

    required property var colors
    property bool materialForm: false
    property var bridge: null

    spacing: 10

    // --- Local mirror of the shell's state ---------------------------------
    // The Settings process cannot import Shell modules, so the authoritative
    // state arrives over IPC as a snapshot and every edit goes back over the
    // same channel. These properties are the optimistic local copy.
    property bool islandEnabled: false
    property string shapeMode: "capsule"
    property string backgroundMode: "glass"
    property string expandMode: "hover"
    property real islandWidth: 320
    property real islandHeight: 44
    property real expandedScale: 1.0
    property string theme: "graphite"
    property string layoutMode: "columns"
    property real glassStrength: 0.65
    property real topMargin: 6
    property int expandDurationMs: 220
    property int collapseDurationMs: 180
    property bool quickLaunchEnabled: true
    property bool quickLaunchShowLabels: true
    property int quickLaunchPageSize: 12
    property bool dropFilesEnabled: true
    property string dropAction: "shortcut"
    property var catalogue: []
    property var enabledWidgetOrder: []
    property var pinnedApps: []
    property var pinnedAppsDetail: []
    // Live desktop entries the island can pin, supplied by the shell because
    // the Settings process cannot enumerate them itself.
    property var availableApps: []
    property int pomodoroWorkMinutes: 25
    property int pomodoroShortBreakMinutes: 5
    property int pomodoroLongBreakMinutes: 15
    property int pomodoroLongBreakTriggerCount: 4
    property bool ready: false
    property string errorText: ""

    function applySnapshot(snapshot) {
        if (!snapshot) return
        islandEnabled = snapshot.enabled === true
        theme = snapshot.theme || "graphite"
        layoutMode = snapshot.layoutMode || "columns"
        glassStrength = snapshot.glassStrength !== undefined ? snapshot.glassStrength : 0.65
        shapeMode = snapshot.shapeMode || "capsule"
        backgroundMode = snapshot.backgroundMode || "glass"
        expandMode = snapshot.expandMode || "hover"
        islandWidth = snapshot.width !== undefined ? snapshot.width : 320
        islandHeight = snapshot.height !== undefined ? snapshot.height : 44
        expandedScale = snapshot.expandedScale !== undefined ? snapshot.expandedScale : 1.0
        topMargin = snapshot.topMargin !== undefined ? snapshot.topMargin : 6
        expandDurationMs = snapshot.expandDurationMs !== undefined ? snapshot.expandDurationMs : 220
        collapseDurationMs = snapshot.collapseDurationMs !== undefined ? snapshot.collapseDurationMs : 180
        quickLaunchEnabled = snapshot.quickLaunchEnabled !== false
        quickLaunchShowLabels = snapshot.quickLaunchShowLabels !== false
        quickLaunchPageSize = snapshot.quickLaunchPageSize !== undefined ? snapshot.quickLaunchPageSize : 12
        dropFilesEnabled = snapshot.dropFilesEnabled !== false
        dropAction = snapshot.dropAction || "shortcut"
        catalogue = snapshot.catalogue || []
        enabledWidgetOrder = snapshot.enabledWidgetOrder || []
        pinnedApps = snapshot.pinnedApps || []
        pinnedAppsDetail = snapshot.pinnedAppsDetail || []
        availableApps = snapshot.availableApps || []
        pomodoroWorkMinutes = snapshot.pomodoroWorkMinutes !== undefined ? snapshot.pomodoroWorkMinutes : 25
        pomodoroShortBreakMinutes = snapshot.pomodoroShortBreakMinutes !== undefined ? snapshot.pomodoroShortBreakMinutes : 5
        pomodoroLongBreakMinutes = snapshot.pomodoroLongBreakMinutes !== undefined ? snapshot.pomodoroLongBreakMinutes : 15
        pomodoroLongBreakTriggerCount = snapshot.pomodoroLongBreakTriggerCount !== undefined ? snapshot.pomodoroLongBreakTriggerCount : 4
        ready = snapshot.ready === true
        errorText = snapshot.lastError || ""
    }

    function refresh() {
        if (bridge)
            bridge.islandSnapshot()
    }

    Component.onCompleted: refresh()

    // The shell answers every request with a fresh snapshot, so the page
    // always reflects the authoritative state rather than a local guess.
    Connections {
        target: islandPage.bridge
        enabled: islandPage.bridge !== null
        function onIslandSnapshotChanged(snap) {
            islandPage.applySnapshot(snap)
            if (islandPage.bridge.lastError)
                islandPage.errorText = I18n.tr(islandPage.bridge.lastError)
        }
    }

    Connections {
        target: Qt.application
        function onStateChanged() {
            if (Qt.application.state === Qt.ApplicationActive)
                islandPage.refresh()
        }
    }

    // ----------------------------------------------------------------------
    // Failure notice
    // ----------------------------------------------------------------------
    // The island lives in the shell process. If its module failed to load,
    // the shell answers this page with an error instead of a snapshot, and
    // without this banner the page would silently show default values — the
    // user would think the switch simply did nothing.
    Rectangle {
        Layout.fillWidth: true
        visible: islandPage.errorText.length > 0
        implicitHeight: visible ? errorBanner.implicitHeight + 24 : 0
        radius: islandPage.materialForm ? 20 : 18
        color: Qt.rgba(0.85, 0.20, 0.20, 0.16)
        border.width: 1
        border.color: Qt.rgba(0.95, 0.35, 0.35, 0.45)

        ColumnLayout {
            id: errorBanner
            anchors { fill: parent; margins: 12 }
            spacing: 4

            Text {
                Layout.fillWidth: true
                text: I18n.tr("The dynamic island could not be reached")
                color: islandPage.colors.primaryText
                font.pixelSize: 13
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
            }

            Text {
                Layout.fillWidth: true
                text: islandPage.errorText
                color: islandPage.colors.secondaryText
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }

            Text {
                Layout.fillWidth: true
                text: I18n.tr("The shell log records the reason; run kosctl doctor to check the installation.")
                color: islandPage.colors.secondaryText
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }
        }
    }

    // ----------------------------------------------------------------------
    // Master switch
    // ----------------------------------------------------------------------
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 86
        radius: islandPage.materialForm ? 20 : 18
        color: islandPage.colors.card

        RowLayout {
            anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
            spacing: 14

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                Text {
                    text: I18n.tr("Dynamic island")
                    color: islandPage.colors.primaryText
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: I18n.tr("Show a compact panel at the top of the screen that expands on hover or click, with widgets and quick launch.")
                    color: islandPage.colors.secondaryText
                    font.pixelSize: 11
                }
            }

            LiquidControls.LiquidGlassSwitch {
                id: islandSwitch
                width: 64
                height: 25
                checked: islandPage.islandEnabled
                accentColor: islandPage.colors.accent
                trackColor: islandPage.colors.divider
                onToggled: function(checked) {
                    islandPage.islandEnabled = checked
                    if (islandPage.bridge)
                        islandPage.bridge.setIslandEnabled(checked)
                }
            }
        }
    }

    // ----------------------------------------------------------------------
    // Everything below is inert until the island is on.
    // ----------------------------------------------------------------------
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 10
        enabled: islandPage.islandEnabled
        opacity: islandPage.islandEnabled ? 1 : 0.45

        // --- Appearance ----------------------------------------------------
        Text {
            text: I18n.tr("Appearance")
            color: islandPage.colors.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: appearanceRows.implicitHeight
            radius: islandPage.materialForm ? 20 : 18
            color: islandPage.colors.card

            ColumnLayout {
                id: appearanceRows
                width: parent.width
                spacing: 0

                // Shape
                Item {
                    Layout.fillWidth: true
                    height: 62
                    RowLayout {
                        anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                        spacing: 14
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Shape")
                            color: islandPage.colors.primaryText
                            font.pixelSize: 13
                        }
                        LiquidControls.LiquidSegmentedControl {
                            // The control defaults to the shell-wide
                            // AppTheme, which is not the theme this
                            // window is painted with: on a dark theme
                            // the labels were unreadable against the
                            // panel. The page hands its own roles in.
                            textColor: islandPage.colors.primaryText
                            mutedTextColor: islandPage.colors.secondaryText
                            backgroundColor: islandPage.colors.searchField
                            selectionColor: islandPage.colors.selectedContainer
                            labels: [I18n.tr("Capsule"), I18n.tr("Rounded"), I18n.tr("Squircle"),
                                     I18n.tr("Notch")]
                            currentIndex: {
                                const idx = ["capsule", "rounded", "squircle", "notch"]
                                    .indexOf(islandPage.shapeMode)
                                return idx >= 0 ? idx : 0
                            }
                            onSelectionRequested: function(index) {
                                const values = ["capsule", "rounded", "squircle", "notch"]
                                islandPage.shapeMode = values[index]
                                if (islandPage.bridge)
                                    islandPage.bridge.setIslandShapeMode(islandPage.shapeMode)
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: islandPage.colors.separator
                    Layout.leftMargin: 18
                    Layout.rightMargin: 18
                }

                // Glass
                Item {
                    Layout.fillWidth: true
                    height: 62
                    RowLayout {
                        anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                        spacing: 14
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Glass")
                                + " · " + Math.round(islandPage.glassStrength * 100) + "%"
                            color: islandPage.colors.primaryText
                            font.pixelSize: 13
                        }
                        LiquidControls.LiquidSlider {
                            Layout.preferredWidth: 220
                            accentColor: islandPage.colors.accent
                            trackColor: islandPage.colors.divider
                            value: islandPage.glassStrength
                            onPreviewChanged: function(position) {
                                islandPage.glassStrength = position
                            }
                            onCommitRequested: function(position) {
                                islandPage.glassStrength = position
                                if (islandPage.bridge)
                                    islandPage.bridge.setIslandGlassStrength(position)
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: islandPage.colors.separator
                    Layout.leftMargin: 18
                    Layout.rightMargin: 18
                }

                // Layout
                Item {
                    Layout.fillWidth: true
                    height: 62
                    RowLayout {
                        anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                        spacing: 14
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Layout")
                            color: islandPage.colors.primaryText
                            font.pixelSize: 13
                        }
                        LiquidControls.LiquidSegmentedControl {
                            textColor: islandPage.colors.primaryText
                            mutedTextColor: islandPage.colors.secondaryText
                            backgroundColor: islandPage.colors.searchField
                            selectionColor: islandPage.colors.selectedContainer
                            labels: [I18n.tr("Shelf"), I18n.tr("Cards")]
                            currentIndex: {
                                const idx = ["columns", "cards"].indexOf(islandPage.layoutMode)
                                return idx >= 0 ? idx : 0
                            }
                            onSelectionRequested: function(index) {
                                const values = ["columns", "cards"]
                                islandPage.layoutMode = values[index]
                                if (islandPage.bridge)
                                    islandPage.bridge.setIslandLayoutMode(islandPage.layoutMode)
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: islandPage.colors.separator
                    Layout.leftMargin: 18
                    Layout.rightMargin: 18
                }

                // Theme
                Item {
                    Layout.fillWidth: true
                    height: 62
                    RowLayout {
                        anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                        spacing: 14
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Theme")
                            color: islandPage.colors.primaryText
                            font.pixelSize: 13
                        }
                        LiquidControls.LiquidSegmentedControl {
                            textColor: islandPage.colors.primaryText
                            mutedTextColor: islandPage.colors.secondaryText
                            backgroundColor: islandPage.colors.searchField
                            selectionColor: islandPage.colors.selectedContainer
                            labels: [I18n.tr("Graphite"), I18n.tr("Celadon"),
                                     I18n.tr("Azure"), I18n.tr("Cinnabar")]
                            currentIndex: {
                                const idx = ["graphite", "celadon", "azure", "cinnabar"]
                                    .indexOf(islandPage.theme)
                                return idx >= 0 ? idx : 0
                            }
                            onSelectionRequested: function(index) {
                                const values = ["graphite", "celadon", "azure", "cinnabar"]
                                islandPage.theme = values[index]
                                if (islandPage.bridge)
                                    islandPage.bridge.setIslandTheme(islandPage.theme)
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: islandPage.colors.separator
                    Layout.leftMargin: 18
                    Layout.rightMargin: 18
                }

                // Background
                Item {
                    Layout.fillWidth: true
                    height: 62
                    RowLayout {
                        anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                        spacing: 14
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Background")
                            color: islandPage.colors.primaryText
                            font.pixelSize: 13
                        }
                        LiquidControls.LiquidSegmentedControl {
                            // The control defaults to the shell-wide
                            // AppTheme, which is not the theme this
                            // window is painted with: on a dark theme
                            // the labels were unreadable against the
                            // panel. The page hands its own roles in.
                            textColor: islandPage.colors.primaryText
                            mutedTextColor: islandPage.colors.secondaryText
                            backgroundColor: islandPage.colors.searchField
                            selectionColor: islandPage.colors.selectedContainer
                            labels: [I18n.tr("Glass"), I18n.tr("Solid"), I18n.tr("None")]
                            currentIndex: {
                                const idx = ["glass", "solid", "none"].indexOf(islandPage.backgroundMode)
                                return idx >= 0 ? idx : 0
                            }
                            onSelectionRequested: function(index) {
                                const values = ["glass", "solid", "none"]
                                islandPage.backgroundMode = values[index]
                                if (islandPage.bridge)
                                    islandPage.bridge.setIslandBackgroundMode(islandPage.backgroundMode)
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: islandPage.colors.separator
                    Layout.leftMargin: 18
                    Layout.rightMargin: 18
                }

                // Expand trigger
                Item {
                    Layout.fillWidth: true
                    height: 62
                    RowLayout {
                        anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                        spacing: 14
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Expand on")
                            color: islandPage.colors.primaryText
                            font.pixelSize: 13
                        }
                        LiquidControls.LiquidSegmentedControl {
                            // The control defaults to the shell-wide
                            // AppTheme, which is not the theme this
                            // window is painted with: on a dark theme
                            // the labels were unreadable against the
                            // panel. The page hands its own roles in.
                            textColor: islandPage.colors.primaryText
                            mutedTextColor: islandPage.colors.secondaryText
                            backgroundColor: islandPage.colors.searchField
                            selectionColor: islandPage.colors.selectedContainer
                            labels: [I18n.tr("Hover"), I18n.tr("Click"), I18n.tr("Always")]
                            currentIndex: {
                                const idx = ["hover", "click", "always"].indexOf(islandPage.expandMode)
                                return idx >= 0 ? idx : 0
                            }
                            onSelectionRequested: function(index) {
                                const values = ["hover", "click", "always"]
                                islandPage.expandMode = values[index]
                                if (islandPage.bridge)
                                    islandPage.bridge.setIslandExpandMode(islandPage.expandMode)
                            }
                        }
                    }
                }
            }
        }

        // --- Size ----------------------------------------------------------
        Text {
            text: I18n.tr("Size")
            color: islandPage.colors.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: sizeRows.implicitHeight
            radius: islandPage.materialForm ? 20 : 18
            color: islandPage.colors.card

            ColumnLayout {
                id: sizeRows
                width: parent.width

                Item {
                    Layout.fillWidth: true
                    height: 62
                    RowLayout {
                        anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                        spacing: 14
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Width")
                            color: islandPage.colors.primaryText
                            font.pixelSize: 13
                        }
                        LiquidControls.LiquidSlider {
                            Layout.preferredWidth: 220
                            accentColor: islandPage.colors.accent
                            trackColor: islandPage.colors.divider
                            // The shared slider is normalized to 0..1, so the
                            // pixel range lives here and the slider only ever
                            // sees a fraction.
                            value: (islandPage.islandWidth - 180) / (720 - 180)
                            // Two phases: the drag only moves the local
                            // value, the write happens on release. Sending
                            // every preview step wrote the whole
                            // configuration dozens of times per second and
                            // made the thumb jump when the snapshot came
                            // back.
                            onPreviewChanged: function(position) {
                                islandPage.islandWidth = Math.round(180 + position * (720 - 180))
                            }
                            onCommitRequested: function(position) {
                                const w = Math.round(180 + position * (720 - 180))
                                islandPage.islandWidth = w
                                if (islandPage.bridge)
                                    islandPage.bridge.setIslandGeometry(w, islandPage.islandHeight)
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: islandPage.colors.separator
                    Layout.leftMargin: 18
                    Layout.rightMargin: 18
                }

                Item {
                    Layout.fillWidth: true
                    height: 62
                    RowLayout {
                        anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                        spacing: 14
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Height")
                            color: islandPage.colors.primaryText
                            font.pixelSize: 13
                        }
                        LiquidControls.LiquidSlider {
                            Layout.preferredWidth: 220
                            accentColor: islandPage.colors.accent
                            trackColor: islandPage.colors.divider
                            value: (islandPage.islandHeight - 28) / (120 - 28)
                            onPreviewChanged: function(position) {
                                islandPage.islandHeight = Math.round(28 + position * (120 - 28))
                            }
                            onCommitRequested: function(position) {
                                const h = Math.round(28 + position * (120 - 28))
                                islandPage.islandHeight = h
                                if (islandPage.bridge)
                                    islandPage.bridge.setIslandGeometry(islandPage.islandWidth, h)
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: islandPage.colors.separator
                    Layout.leftMargin: 18
                    Layout.rightMargin: 18
                }

                // The width/height above are the *collapsed* pill. The expanded panel is
                // derived from the screen, so it needs its own control -- and a multiplier
                // rather than a second pair of pixels keeps the reference proportions.
                Item {
                    Layout.fillWidth: true
                    height: 62
                    RowLayout {
                        anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                        spacing: 14
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Expanded size")
                                + " · " + Math.round(islandPage.expandedScale * 100) + "%"
                            color: islandPage.colors.primaryText
                            font.pixelSize: 13
                        }
                        LiquidControls.LiquidSlider {
                            Layout.preferredWidth: 220
                            accentColor: islandPage.colors.accent
                            trackColor: islandPage.colors.divider
                            value: (islandPage.expandedScale - 0.6) / (1.4 - 0.6)
                            onPreviewChanged: function(position) {
                                islandPage.expandedScale =
                                    Math.round((0.6 + position * (1.4 - 0.6)) * 100) / 100
                            }
                            onCommitRequested: function(position) {
                                const v = Math.round((0.6 + position * (1.4 - 0.6)) * 100) / 100
                                islandPage.expandedScale = v
                                if (islandPage.bridge)
                                    islandPage.bridge.setIslandExpandedScale(v)
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: islandPage.colors.separator
                    Layout.leftMargin: 18
                    Layout.rightMargin: 18
                }

                Item {
                    Layout.fillWidth: true
                    height: 62
                    RowLayout {
                        anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                        spacing: 14
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Top margin")
                            color: islandPage.colors.primaryText
                            font.pixelSize: 13
                        }
                        LiquidControls.LiquidSlider {
                            Layout.preferredWidth: 220
                            accentColor: islandPage.colors.accent
                            trackColor: islandPage.colors.divider
                            value: islandPage.topMargin / 80
                            onPreviewChanged: function(position) {
                                islandPage.topMargin = Math.round(position * 80)
                            }
                            onCommitRequested: function(position) {
                                const m = Math.round(position * 80)
                                islandPage.topMargin = m
                                if (islandPage.bridge)
                                    islandPage.bridge.setIslandTopMargin(m)
                            }
                        }
                    }
                }
            }
        }

        // --- Motion ---------------------------------------------------------
        Text {
            text: I18n.tr("Motion")
            color: islandPage.colors.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: motionRows.implicitHeight
            radius: islandPage.materialForm ? 20 : 18
            color: islandPage.colors.card

            ColumnLayout {
                id: motionRows
                width: parent.width

                Item {
                    Layout.fillWidth: true
                    height: 62
                    RowLayout {
                        anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                        spacing: 14
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Expand duration")
                            color: islandPage.colors.primaryText
                            font.pixelSize: 13
                        }
                        Text {
                            text: I18n.tr("%1 ms").arg(islandPage.expandDurationMs)
                            color: islandPage.colors.secondaryText
                            font.pixelSize: 12
                        }
                        LiquidControls.LiquidSlider {
                            Layout.preferredWidth: 150
                            accentColor: islandPage.colors.accent
                            trackColor: islandPage.colors.divider
                            value: (islandPage.expandDurationMs - 60) / (600 - 60)
                            onPreviewChanged: function(position) {
                                islandPage.expandDurationMs = Math.round(60 + position * (600 - 60))
                            }
                            onCommitRequested: function(position) {
                                const v = Math.round(60 + position * (600 - 60))
                                islandPage.expandDurationMs = v
                                if (islandPage.bridge)
                                    islandPage.bridge.setIslandExpandDuration(v)
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: islandPage.colors.separator
                    Layout.leftMargin: 18
                    Layout.rightMargin: 18
                }

                Item {
                    Layout.fillWidth: true
                    height: 62
                    RowLayout {
                        anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                        spacing: 14
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Collapse duration")
                            color: islandPage.colors.primaryText
                            font.pixelSize: 13
                        }
                        Text {
                            text: I18n.tr("%1 ms").arg(islandPage.collapseDurationMs)
                            color: islandPage.colors.secondaryText
                            font.pixelSize: 12
                        }
                        LiquidControls.LiquidSlider {
                            Layout.preferredWidth: 150
                            accentColor: islandPage.colors.accent
                            trackColor: islandPage.colors.divider
                            value: (islandPage.collapseDurationMs - 60) / (600 - 60)
                            onPreviewChanged: function(position) {
                                islandPage.collapseDurationMs = Math.round(60 + position * (600 - 60))
                            }
                            onCommitRequested: function(position) {
                                const v = Math.round(60 + position * (600 - 60))
                                islandPage.collapseDurationMs = v
                                if (islandPage.bridge)
                                    islandPage.bridge.setIslandCollapseDuration(v)
                            }
                        }
                    }
                }
            }
        }

        // --- Widgets -------------------------------------------------------
        Text {
            text: I18n.tr("Widgets")
            color: islandPage.colors.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: widgetRows.implicitHeight
            radius: islandPage.materialForm ? 20 : 18
            color: islandPage.colors.card

            ColumnLayout {
                id: widgetRows
                width: parent.width

                Repeater {
                    model: islandPage.catalogue

                    delegate: Item {
                        id: widgetRow
                        required property var modelData
                        required property int index

                        readonly property bool isOn: islandPage.enabledWidgetOrder.indexOf(modelData.id) >= 0

                        Layout.fillWidth: true
                        height: 56

                        RowLayout {
                            anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                            spacing: 14
                            Text {
                                Layout.fillWidth: true
                                text: widgetRow.modelData.name
                                color: islandPage.colors.primaryText
                                font.pixelSize: 13
                            }
                            LiquidControls.LiquidGlassSwitch {
                                width: 64
                                height: 25
                                checked: widgetRow.isOn
                                accentColor: islandPage.colors.accent
                                trackColor: islandPage.colors.divider
                                onToggled: function(checked) {
                                    if (islandPage.bridge)
                                        islandPage.bridge.setIslandWidgetEnabled(widgetRow.modelData.id, checked)
                                }
                            }
                        }

                        Rectangle {
                            visible: widgetRow.index < islandPage.catalogue.length - 1
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 18; rightMargin: 18 }
                            height: 1
                            color: islandPage.colors.separator
                        }
                    }
                }
            }
        }

        // --- Quick launch --------------------------------------------------
        Text {
            text: I18n.tr("Quick launch")
            color: islandPage.colors.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: quickRows.implicitHeight
            radius: islandPage.materialForm ? 20 : 18
            color: islandPage.colors.card

            ColumnLayout {
                id: quickRows
                width: parent.width

                Item {
                    Layout.fillWidth: true
                    height: 56
                    RowLayout {
                        anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                        spacing: 14
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Show quick launch")
                            color: islandPage.colors.primaryText
                            font.pixelSize: 13
                        }
                        LiquidControls.LiquidGlassSwitch {
                            width: 64
                            height: 25
                            checked: islandPage.quickLaunchEnabled
                            accentColor: islandPage.colors.accent
                            trackColor: islandPage.colors.divider
                            onToggled: function(checked) {
                                islandPage.quickLaunchEnabled = checked
                                if (islandPage.bridge)
                                    islandPage.bridge.setIslandQuickLaunchEnabled(checked)
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: islandPage.colors.separator
                    Layout.leftMargin: 18
                    Layout.rightMargin: 18
                }

                Item {
                    Layout.fillWidth: true
                    height: 56
                    RowLayout {
                        anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                        spacing: 14
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Show app names")
                            color: islandPage.colors.primaryText
                            font.pixelSize: 13
                        }
                        LiquidControls.LiquidGlassSwitch {
                            width: 64
                            height: 25
                            checked: islandPage.quickLaunchShowLabels
                            accentColor: islandPage.colors.accent
                            trackColor: islandPage.colors.divider
                            onToggled: function(checked) {
                                islandPage.quickLaunchShowLabels = checked
                                if (islandPage.bridge)
                                    islandPage.bridge.setIslandQuickLaunchLabels(checked)
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: islandPage.colors.separator
                    Layout.leftMargin: 18
                    Layout.rightMargin: 18
                }

                Item {
                    Layout.fillWidth: true
                    height: 62
                    RowLayout {
                        anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                        spacing: 14
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Apps per page")
                            color: islandPage.colors.primaryText
                            font.pixelSize: 13
                        }
                        LiquidControls.LiquidSlider {
                            Layout.preferredWidth: 180
                            accentColor: islandPage.colors.accent
                            trackColor: islandPage.colors.divider
                            value: (islandPage.quickLaunchPageSize - 4) / (24 - 4)
                            onPreviewChanged: function(position) {
                                islandPage.quickLaunchPageSize = Math.round(4 + position * (24 - 4))
                            }
                            onCommitRequested: function(position) {
                                const n = Math.round(4 + position * (24 - 4))
                                islandPage.quickLaunchPageSize = n
                                if (islandPage.bridge)
                                    islandPage.bridge.setIslandQuickLaunchPageSize(n)
                            }
                        }
                    }
                }
            }
        }

        // --- Drop handling --------------------------------------------------
        Text {
            text: I18n.tr("Dropped files")
            color: islandPage.colors.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: dropRows.implicitHeight
            radius: islandPage.materialForm ? 20 : 18
            color: islandPage.colors.card

            ColumnLayout {
                id: dropRows
                width: parent.width

                Item {
                    Layout.fillWidth: true
                    height: 56
                    RowLayout {
                        anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                        spacing: 14
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Accept dropped files")
                            color: islandPage.colors.primaryText
                            font.pixelSize: 13
                        }
                        LiquidControls.LiquidGlassSwitch {
                            width: 64
                            height: 25
                            checked: islandPage.dropFilesEnabled
                            accentColor: islandPage.colors.accent
                            trackColor: islandPage.colors.divider
                            onToggled: function(checked) {
                                islandPage.dropFilesEnabled = checked
                                if (islandPage.bridge)
                                    islandPage.bridge.setIslandDropFilesEnabled(checked)
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: islandPage.colors.separator
                    Layout.leftMargin: 18
                    Layout.rightMargin: 18
                }

                Item {
                    Layout.fillWidth: true
                    height: 62
                    RowLayout {
                        anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                        spacing: 14
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Drop action")
                            color: islandPage.colors.primaryText
                            font.pixelSize: 13
                        }
                        LiquidControls.LiquidSegmentedControl {
                            // The control defaults to the shell-wide
                            // AppTheme, which is not the theme this
                            // window is painted with: on a dark theme
                            // the labels were unreadable against the
                            // panel. The page hands its own roles in.
                            textColor: islandPage.colors.primaryText
                            mutedTextColor: islandPage.colors.secondaryText
                            backgroundColor: islandPage.colors.searchField
                            selectionColor: islandPage.colors.selectedContainer
                            labels: [I18n.tr("Add shortcut"), I18n.tr("Open"),
                                     I18n.tr("Copy path"), I18n.tr("Reveal")]
                            currentIndex: {
                                const idx = ["shortcut", "open", "copyPath", "reveal"]
                                    .indexOf(islandPage.dropAction)
                                return idx >= 0 ? idx : 0
                            }
                            onSelectionRequested: function(index) {
                                const values = ["shortcut", "open", "copyPath", "reveal"]
                                islandPage.dropAction = values[index]
                                if (islandPage.bridge)
                                    islandPage.bridge.setIslandDropAction(islandPage.dropAction)
                            }
                        }
                    }
                }
            }
        }

        // --- Pinned applications -------------------------------------------
        // The original's QuickLaunch surface: a user-owned list of
        // applications with a custom order. Here the list itself is edited
        // from the island (drag to reorder) and from this page (add/remove);
        // both write through the same island-settings endpoint.
        Text {
            text: I18n.tr("Pinned applications")
            color: islandPage.colors.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Math.max(80, pinnedRows.implicitHeight)
            radius: islandPage.materialForm ? 20 : 18
            color: islandPage.colors.card

            ColumnLayout {
                id: pinnedRows
                width: parent.width
                spacing: 0

                Repeater {
                    model: islandPage.pinnedAppsDetail

                    delegate: Item {
                        id: pinnedRow
                        required property var modelData
                        required property int index

                        readonly property string appName: modelData.name || modelData.id || ""

                        Layout.fillWidth: true
                        height: 48

                        RowLayout {
                            anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                            spacing: 12
                            Text {
                                Layout.fillWidth: true
                                text: pinnedRow.appName
                                color: islandPage.colors.primaryText
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }
                            Button {
                                text: I18n.tr("Remove")
                                implicitHeight: 28
                                onClicked: {
                                    if (islandPage.bridge)
                                        islandPage.bridge.setIslandAppPinned(pinnedRow.modelData.id, false)
                                }
                            }
                        }

                        Rectangle {
                            visible: pinnedRow.index < islandPage.pinnedAppsDetail.length - 1
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 18; rightMargin: 18 }
                            height: 1
                            color: islandPage.colors.separator
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.margins: 18
                    visible: islandPage.pinnedAppsDetail.length === 0
                    text: I18n.tr("No applications pinned yet")
                    color: islandPage.colors.secondaryText
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: islandPage.colors.separator
                    Layout.leftMargin: 18
                    Layout.rightMargin: 18
                }

                Item {
                    Layout.fillWidth: true
                    height: 52
                    RowLayout {
                        anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                        spacing: 12
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Add applications to the island's quick launch strip.")
                            color: islandPage.colors.secondaryText
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                        }
                        Button {
                            id: addAppToggle
                            text: addAppPanel.visible ? I18n.tr("Done") : I18n.tr("Add app")
                            implicitHeight: 28
                            onClicked: addAppPanel.visible = !addAppPanel.visible
                        }
                    }
                }
            }
        }

        // Add-app picker. Mirrors the original's QuickLaunch app picker: a
        // search field over the live application list, each row pinning on
        // click. The shell supplies the catalogue in the snapshot because the
        // Settings process cannot enumerate desktop entries itself.
        Rectangle {
            id: addAppPanel
            Layout.fillWidth: true
            visible: false
            Layout.topMargin: 10
            implicitHeight: visible ? 300 : 0
            radius: islandPage.materialForm ? 20 : 18
            color: islandPage.colors.card
            clip: true

            ColumnLayout {
                id: addAppRows
                anchors { fill: parent; margins: 12 }
                spacing: 8

                LiquidControls.LiquidTextField {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    placeholderText: I18n.tr("Search apps")
                    glassColor: islandPage.colors.searchField
                    textColor: islandPage.colors.primaryText
                    mutedTextColor: islandPage.colors.secondaryText
                    font.pixelSize: 13
                    onTextChanged: addAppPanel.searchText = text
                }

                ListView {
                    id: addAppList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: {
                        const needle = addAppPanel.searchText.trim().toLowerCase()
                        const all = islandPage.availableApps || []
                        if (!needle)
                            return all
                        return all.filter(function(app) {
                            return String(app.name || app.id || "").toLowerCase().indexOf(needle) >= 0
                        })
                    }
                    spacing: 2
                    clip: true

                    delegate: Item {
                        required property var modelData
                        width: addAppList.width
                        height: 40

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: appRowMouse.containsMouse
                                ? islandPage.colors.searchField
                                : "transparent"
                        }

                        RowLayout {
                            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                            spacing: 10
                            Text {
                                Layout.fillWidth: true
                                text: modelData.name || modelData.id || ""
                                color: islandPage.colors.primaryText
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }
                            Button {
                                text: I18n.tr("Add")
                                implicitHeight: 26
                                onClicked: {
                                    if (islandPage.bridge)
                                        islandPage.bridge.setIslandAppPinned(modelData.id, true)
                                }
                            }
                        }

                        MouseArea {
                            id: appRowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (islandPage.bridge)
                                    islandPage.bridge.setIslandAppPinned(modelData.id, true)
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: addAppList.count === 0
                        text: I18n.tr("No matching apps")
                        color: islandPage.colors.secondaryText
                        font.pixelSize: 12
                    }
                }
            }

            property string searchText: ""
        }

        // --- Pomodoro ------------------------------------------------------
        Text {
            text: I18n.tr("Pomodoro")
            color: islandPage.colors.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: pomodoroRows.implicitHeight
            radius: islandPage.materialForm ? 20 : 18
            color: islandPage.colors.card

            ColumnLayout {
                id: pomodoroRows
                width: parent.width

                Item {
                    Layout.fillWidth: true
                    height: 62
                    RowLayout {
                        anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                        spacing: 14
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Focus length")
                            color: islandPage.colors.primaryText
                            font.pixelSize: 13
                        }
                        Text {
                            text: I18n.tr("%1 min").arg(islandPage.pomodoroWorkMinutes)
                            color: islandPage.colors.secondaryText
                            font.pixelSize: 12
                        }
                        LiquidControls.LiquidSlider {
                            Layout.preferredWidth: 150
                            accentColor: islandPage.colors.accent
                            trackColor: islandPage.colors.divider
                            value: (islandPage.pomodoroWorkMinutes - 5) / (90 - 5)
                            onPreviewChanged: function(position) {
                                const v = Math.round(5 + position * (90 - 5))
                                islandPage.pomodoroWorkMinutes = v
                            }
                            onCommitRequested: function(position) {
                                const v = Math.round(5 + position * (90 - 5))
                                islandPage.pomodoroWorkMinutes = v
                                if (islandPage.bridge)
                                    islandPage.bridge.setIslandPomodoro(v,
                                        islandPage.pomodoroShortBreakMinutes,
                                        islandPage.pomodoroLongBreakMinutes,
                                        islandPage.pomodoroLongBreakTriggerCount)
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: islandPage.colors.separator
                    Layout.leftMargin: 18
                    Layout.rightMargin: 18
                }

                Item {
                    Layout.fillWidth: true
                    height: 62
                    RowLayout {
                        anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                        spacing: 14
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Short break")
                            color: islandPage.colors.primaryText
                            font.pixelSize: 13
                        }
                        Text {
                            text: I18n.tr("%1 min").arg(islandPage.pomodoroShortBreakMinutes)
                            color: islandPage.colors.secondaryText
                            font.pixelSize: 12
                        }
                        LiquidControls.LiquidSlider {
                            Layout.preferredWidth: 150
                            accentColor: islandPage.colors.accent
                            trackColor: islandPage.colors.divider
                            value: (islandPage.pomodoroShortBreakMinutes - 1) / (30 - 1)
                            onPreviewChanged: function(position) {
                                const v = Math.round(1 + position * (30 - 1))
                                islandPage.pomodoroShortBreakMinutes = v
                            }
                            onCommitRequested: function(position) {
                                const v = Math.round(1 + position * (30 - 1))
                                islandPage.pomodoroShortBreakMinutes = v
                                if (islandPage.bridge)
                                    islandPage.bridge.setIslandPomodoro(islandPage.pomodoroWorkMinutes,
                                        v, islandPage.pomodoroLongBreakMinutes,
                                        islandPage.pomodoroLongBreakTriggerCount)
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: islandPage.colors.separator
                    Layout.leftMargin: 18
                    Layout.rightMargin: 18
                }

                Item {
                    Layout.fillWidth: true
                    height: 62
                    RowLayout {
                        anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                        spacing: 14
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Long break")
                            color: islandPage.colors.primaryText
                            font.pixelSize: 13
                        }
                        Text {
                            text: I18n.tr("%1 min").arg(islandPage.pomodoroLongBreakMinutes)
                            color: islandPage.colors.secondaryText
                            font.pixelSize: 12
                        }
                        LiquidControls.LiquidSlider {
                            Layout.preferredWidth: 150
                            accentColor: islandPage.colors.accent
                            trackColor: islandPage.colors.divider
                            value: (islandPage.pomodoroLongBreakMinutes - 5) / (60 - 5)
                            onPreviewChanged: function(position) {
                                const v = Math.round(5 + position * (60 - 5))
                                islandPage.pomodoroLongBreakMinutes = v
                            }
                            onCommitRequested: function(position) {
                                const v = Math.round(5 + position * (60 - 5))
                                islandPage.pomodoroLongBreakMinutes = v
                                if (islandPage.bridge)
                                    islandPage.bridge.setIslandPomodoro(islandPage.pomodoroWorkMinutes,
                                        islandPage.pomodoroShortBreakMinutes, v,
                                        islandPage.pomodoroLongBreakTriggerCount)
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: islandPage.colors.separator
                    Layout.leftMargin: 18
                    Layout.rightMargin: 18
                }

                Item {
                    Layout.fillWidth: true
                    height: 62
                    RowLayout {
                        anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                        spacing: 14
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Long break after")
                            color: islandPage.colors.primaryText
                            font.pixelSize: 13
                        }
                        Text {
                            text: I18n.tr("%1 sessions").arg(islandPage.pomodoroLongBreakTriggerCount)
                            color: islandPage.colors.secondaryText
                            font.pixelSize: 12
                        }
                        LiquidControls.LiquidSlider {
                            Layout.preferredWidth: 150
                            accentColor: islandPage.colors.accent
                            trackColor: islandPage.colors.divider
                            value: (islandPage.pomodoroLongBreakTriggerCount - 2) / (8 - 2)
                            onPreviewChanged: function(position) {
                                const v = Math.round(2 + position * (8 - 2))
                                islandPage.pomodoroLongBreakTriggerCount = v
                            }
                            onCommitRequested: function(position) {
                                const v = Math.round(2 + position * (8 - 2))
                                islandPage.pomodoroLongBreakTriggerCount = v
                                if (islandPage.bridge)
                                    islandPage.bridge.setIslandPomodoro(islandPage.pomodoroWorkMinutes,
                                        islandPage.pomodoroShortBreakMinutes,
                                        islandPage.pomodoroLongBreakMinutes, v)
                            }
                        }
                    }
                }
            }
        }
    }
}
