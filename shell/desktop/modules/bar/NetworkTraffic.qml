import QtQuick
import "../../../shared/qml/i18n"
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.dock

// Presentational transfer-rate readout for the network tray cell. Sampling
// lives in NetworkService (1 Hz while a device is connected) so the Wi-Fi
// tooltip can show the same rates; this component only formats the shared
// snapshot and never performs network-management actions.
Item {
    id: root

    signal panelToggleRequested()

    // The readouts already take the glass tint through ThemeService; the
    // arrow glyph has to move with them or the two halves of one indicator
    // disagree. The ink follows the glass, so while 液态玻璃跟随外观模式 is off
    // the arrow still strokes exactly the white it stroked before. With the
    // mac-style ground on, both halves take the strip's own ink instead.
    readonly property color glyphInk: AppearanceTokens.bar.macStyle
        ? ThemeService.barInk : AppearanceTokens.content.glassInk()
    // The arrow's readability edge. It keeps the exact condition it had before
    // and is dropped while the ground paints a plate under the mark. The two
    // labels take the same condition (see the Texts below), where the edge was
    // unconditional.
    readonly property bool arrowOutlined: AppearanceTokens.isDarkTheme
        && !AppearanceTokens.bar.macStyle

    // ── Fixed rate slot ──────────────────────────────────────────────────
    // The readout used to size itself from its own text, so every 1 Hz sample
    // moved the whole status cluster (the tray grid, this cluster's centred
    // Row, and the Global Menu's width budget) by a digit or a unit. Reserve
    // the widest label the formatter can produce once, and lay the live text
    // out inside that slot instead.
    //
    // The one font the readout measures and draws with: with no fallback list, a
    // machine without SF Pro Display resolves measuring and drawing through the
    // same platform font, so the reserved columns cannot disagree with what is
    // painted. `font.features` (tabular figures, which keep every digit on one
    // advance width) is Qt 6.7+ while this shell still supports 6.5, where
    // naming the member in a component body is a property error -- building the
    // value through Qt.font() and adding the feature to the font object keeps
    // both halves identical and degrades silently where the engine has no such
    // member.
    readonly property font rateFont: {
        const spec = Qt.font({
            family: AppearanceTokens.typography.displayFamily,
            pixelSize: 9,
            weight: Font.DemiBold
        })
        try {
            spec.features = ({ "tnum": 1 })
        } catch (error) {
            // Qt < 6.7: proportional digits; the fixed columns still hold.
        }
        return spec
    }

    FontMetrics {
        id: rateMetrics
        font: root.rateFont
    }

    // The readout is three fixed columns -- direction label, number, unit -- so
    // a sample changes digits without moving anything else, and the two rows
    // line up as a table. Every column is reserved from the widest piece the
    // formatter can produce, read through formatRate itself so a change to its
    // precision or units cannot silently under-reserve the slot.
    readonly property var rateBranches: [
        NetworkService.formatRate(1023.99),
        NetworkService.formatRate(1023.99 * 1024),
        NetworkService.formatRate(1023.99 * 1024 * 1024),
        NetworkService.formatRate(1023.99 * 1024 * 1024 * 1024)
    ]

    // formatRate emits "<number> <unit>". Splitting its output keeps it the one
    // source of the numeric formatting; the Wi-Fi tooltip and the temperature
    // popup keep consuming the unsplit string.
    function rateNumber(formatted) {
        return String(formatted).split(" ")[0]
    }
    function rateUnit(formatted) {
        const parts = String(formatted).split(" ")
        return parts.length > 1 ? parts.slice(1).join(" ") : ""
    }

    // One pixel per column is Text's own content box, which reports
    // `advanceWidth + 1` for the longer mixed labels. Each binding reads the
    // metrics font first: that is both the value the columns must be measured
    // with and the dependency that re-runs them, because a binding evaluated
    // during construction can otherwise run before `rateMetrics` received its
    // font and then freeze at the application default's (much wider) metrics --
    // `advanceWidth()` is a method and would not re-measure on its own.
    readonly property real labelColumnWidth: {
        const _font = rateMetrics.font
        return Math.ceil(Math.max(rateMetrics.advanceWidth(I18n.tr("Down")),
            rateMetrics.advanceWidth(I18n.tr("Up")))) + 1
    }
    readonly property real numberColumnWidth: {
        const _font = rateMetrics.font
        let widest = 0
        for (const branch of rateBranches)
            widest = Math.max(widest, rateMetrics.advanceWidth(rateNumber(branch)))
        return Math.ceil(widest) + 1
    }
    readonly property real unitColumnWidth: {
        const _font = rateMetrics.font
        let widest = 0
        for (const branch of rateBranches)
            widest = Math.max(widest, rateMetrics.advanceWidth(rateUnit(branch)))
        return Math.ceil(widest) + 1
    }

    // Gap between the three columns of a row.
    readonly property int columnGap: 3

    implicitWidth: directionGlyph.width + trafficContent.spacing
        + labelColumnWidth + columnGap + numberColumnWidth
        + columnGap + unitColumnWidth
    implicitHeight: 22
    width: implicitWidth
    height: implicitHeight
    visible: NetworkService.available && NetworkService.deviceState === "connected"

    Row {
        id: trafficContent
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3

        // Draw arrows ourselves so their white foreground is as dependable as
        // NetworkStatus on transparent glass, independent of icon themes.
        Canvas {
            id: directionGlyph
            width: 13
            height: 18
            // glyphInk lives on the root item, so the change signal is
            // reconnected here instead of as a Canvas-scoped handler.
            Connections {
                target: root
                function onGlyphInkChanged() { directionGlyph.requestPaint() }
            }
            // The two labels beside this glyph carry Text.Outline; the arrows
            // are painted, not typeset, so they draw the same edge themselves:
            // the whole mark once more with a wider stroke underneath.
            function traceArrows(ctx) {
                ctx.beginPath()
                // Keep the opposing arrows offset: together they read as one
                // compact traffic glyph, rather than two independent controls.
                // The adjacent labels explicitly identify the two data rows.
                // Download arrow.
                ctx.moveTo(3.5, 2.5); ctx.lineTo(3.5, 7.5)
                ctx.moveTo(1.4, 5.5); ctx.lineTo(3.5, 7.7); ctx.lineTo(5.6, 5.5)
                // Upload arrow.
                ctx.moveTo(9.5, 15.5); ctx.lineTo(9.5, 10.5)
                ctx.moveTo(7.4, 12.5); ctx.lineTo(9.5, 10.3); ctx.lineTo(11.6, 12.5)
                ctx.stroke()
            }
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                if (root.arrowOutlined) {
                    ctx.save()
                    ctx.strokeStyle = Qt.rgba(0, 0, 0, 0.38)
                    ctx.lineWidth = 1.35 + 2.2
                    traceArrows(ctx)
                    ctx.restore()
                }
                ctx.strokeStyle = root.glyphInk
                ctx.lineWidth = 1.35
                traceArrows(ctx)
            }
        }

        Column {
            spacing: -1
            RateRow {
                directionLabel: I18n.tr("Down")
                formattedRate: NetworkService.formatRate(
                    NetworkService.downloadBytesPerSecond)
            }
            RateRow {
                directionLabel: I18n.tr("Up")
                formattedRate: NetworkService.formatRate(
                    NetworkService.uploadBytesPerSecond)
            }
        }
    }

    // Shared cell styling: every column takes the readout's single ink, outline
    // and font policy, so the three cells of a row can never drift apart.
    component RateCell: Text {
        required property real columnWidth
        required property int cellAlignment

        width: columnWidth
        horizontalAlignment: cellAlignment
        color: ThemeService.barInk
        style: AppearanceTokens.bar.macStyle ? Text.Normal : Text.Outline
        styleColor: Qt.rgba(0, 0, 0, 0.38)
        font: root.rateFont
    }

    // One direction row: the label aligned left, the number right-aligned in the
    // middle column (so its unit side stays put), the unit aligned left on the
    // right. The columns are fixed, so the whole readout keeps one width per
    // sample-independent reserve.
    component RateRow: Row {
        id: rateRow

        required property string directionLabel
        required property string formattedRate

        spacing: root.columnGap

        RateCell {
            text: rateRow.directionLabel
            columnWidth: root.labelColumnWidth
            cellAlignment: Text.AlignLeft
        }
        RateCell {
            text: root.rateNumber(rateRow.formattedRate)
            columnWidth: root.numberColumnWidth
            cellAlignment: Text.AlignRight
        }
        RateCell {
            text: root.rateUnit(rateRow.formattedRate)
            columnWidth: root.unitColumnWidth
            cellAlignment: Text.AlignLeft
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.panelToggleRequested()
    }
}
