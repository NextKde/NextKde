import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

const here = dirname(fileURLToPath(import.meta.url))
const traffic = readFileSync(join(here, "NetworkTraffic.qml"), "utf8")
const networkService = readFileSync(join(here, "NetworkService.qml"), "utf8")

// ── 1. The readout no longer sizes itself from its own text ─────────────────
// Every 1 Hz sample used to change this item's implicit width, which moved the
// whole status cluster (and the Global Menu's width budget) with it.
assert.match(traffic,
    /implicitWidth:\s*directionGlyph\.width\s*\+\s*trafficContent\.spacing\s*\n\s*\+\s*labelColumnWidth\s*\+\s*columnGap\s*\+\s*numberColumnWidth\s*\n\s*\+\s*columnGap\s*\+\s*unitColumnWidth/,
    "the readout reserves its three columns instead of measuring its live text")
assert.doesNotMatch(traffic,
    /implicitWidth:[^\n]*trafficContent\.implicitWidth/,
    "the implicit width is no longer taken from the live content row")
assert.doesNotMatch(traffic, /rateSlotWidth/,
    "the older single slot is gone, not left behind beside the columns")

const branches = traffic.match(/readonly property var rateBranches:([\s\S]*?)\n\n/)?.[1] ?? ""
assert.ok(branches.length > 0, "NetworkTraffic declares the widest-label set")
assert.match(branches,
    /NetworkService\.formatRate\(1023\.99\)[\s\S]*?NetworkService\.formatRate\(1023\.99 \* 1024\)[\s\S]*?NetworkService\.formatRate\(1023\.99 \* 1024 \* 1024\)[\s\S]*?NetworkService\.formatRate\(1023\.99 \* 1024 \* 1024 \* 1024\)/,
    "all four formatter branches contribute their upper bound")

// ── 2. Number and unit are split out of the shared formatter ───────────────
// formatRate keeps owning the numeric formatting; the readout only separates
// the three pieces it lays out.
const splitNumber = traffic.match(/function rateNumber\(formatted\) \{([\s\S]*?)\n    \}/)?.[1] ?? ""
const splitUnit = traffic.match(/function rateUnit\(formatted\) \{([\s\S]*?)\n    \}/)?.[1] ?? ""
assert.ok(splitNumber.length > 0 && splitUnit.length > 0,
    "NetworkTraffic splits the formatted rate into number and unit")
assert.match(splitNumber, /String\(formatted\)\.split\(" "\)\[0\]/,
    "the number is the leading field of formatRate's output")
assert.match(splitUnit, /String\(formatted\)\.split\(" "\)/,
    "the unit is the remainder of formatRate's output")

// ── 3. Each column is reserved once, from the widest it can hold ───────────
for (const [name, measurement, description] of [
    ["labelColumnWidth", /Math\.max\(rateMetrics\.advanceWidth\(I18n\.tr\("Down"\)\),\s*\n\s*rateMetrics\.advanceWidth\(I18n\.tr\("Up"\)\)\)/,
        "the wider of the two localized direction labels"],
    ["numberColumnWidth", /rateMetrics\.advanceWidth\(rateNumber\(branch\)\)/,
        "the widest number across the formatter's branches"],
    ["unitColumnWidth", /rateMetrics\.advanceWidth\(rateUnit\(branch\)\)/,
        "the widest unit across the formatter's branches"]]) {
    const block = traffic.match(new RegExp(`readonly property real ${name}:([\\s\\S]*?)\\n\\n`))?.[1] ?? ""
    assert.ok(block.length > 0, `NetworkTraffic declares ${name}`)
    assert.match(block, measurement, `${name} is measured from ${description}`)
    assert.match(block, /Math\.ceil\([\s\S]*?\)\s*\+\s*1/,
        `${name} rounds up and carries Text's one-pixel content box`)
    assert.match(block, /const _font = rateMetrics\.font/,
        `${name} reads the metrics font as its dependency, so a binding that runs`
        + ` during construction cannot freeze at the application default's metrics`)
}

// ── 4. One font value feeds measuring and drawing ──────────────────────────
// `Qt.font()` builds the value once; the tabular feature is added to that same
// value, so the FontMetrics that reserves the columns and the cells that render
// them can never measure different fonts.
assert.match(traffic,
    /readonly property font rateFont: \{\s*const spec = Qt\.font\(\{\s*family: AppearanceTokens\.typography\.displayFamily,\s*pixelSize: 9,\s*weight: Font\.DemiBold\s*\}\)/,
    "the readout declares its font once, through Qt.font")
assert.match(traffic,
    /FontMetrics \{\s*id: rateMetrics\s*font: root\.rateFont/,
    "the measuring object uses that font value")
assert.match(traffic,
    /component RateCell: Text \{[\s\S]*?font: root\.rateFont/,
    "every rendered cell uses the same font value")
assert.doesNotMatch(traffic, /font \{ family: "SF Pro Display"/,
    "no second font declaration can drift from the measured one")

// ── 5. Tabular figures, applied where the engine supports them ─────────────
assert.match(traffic,
    /try \{\s*spec\.features = \(\{ "tnum": 1 \}\)[\s\S]*?\} catch \(error\) \{/,
    "tabular figures are added to the font value with a guarded path")
assert.doesNotMatch(traffic, /^\s*font\.features:/m,
    "font.features is never named in a component body (Qt 6.5 has no such member)")
assert.match(traffic, /readonly property font rateFont/,
    "the font value carries the figures, so no post-creation mutation is needed")
assert.doesNotMatch(traffic, /tabularFiguresApplied/,
    "the retired post-creation mutation flag is gone, not left beside the value")

// ── 6. The row layout the user asked for: label left, number middle, unit right
const row = traffic.match(/component RateRow: Row \{([\s\S]*?)\n    \}/)?.[1] ?? ""
assert.ok(row.length > 0, "the readout still has one row component")
const cells = [...row.matchAll(/RateCell \{[\s\S]*?\n        \}/g)].map(match => match[0])
assert.equal(cells.length, 3, "a row is exactly label + number + unit")
assert.match(cells[0],
    /columnWidth: root\.labelColumnWidth[\s\S]*?cellAlignment: Text\.AlignLeft/,
    "the direction label sits left in the first column")
assert.match(cells[1],
    /columnWidth: root\.numberColumnWidth[\s\S]*?cellAlignment: Text\.AlignRight/,
    "the number is right-aligned inside the middle column")
assert.match(cells[2],
    /columnWidth: root\.unitColumnWidth[\s\S]*?cellAlignment: Text\.AlignLeft/,
    "the unit starts the right-hand column")
assert.match(row,
    /required property string directionLabel[\s\S]*?required property string formattedRate/,
    "the row takes the label and the formatted rate as parameters")
assert.match(traffic,
    /Column \{[\s\S]*?RateRow \{[\s\S]*?directionLabel: I18n\.tr\("Down"\)[\s\S]*?NetworkService\.downloadBytesPerSecond[\s\S]*?RateRow \{[\s\S]*?directionLabel: I18n\.tr\("Up"\)[\s\S]*?NetworkService\.uploadBytesPerSecond/,
    "both live rates drive the two rows")

// ── 7. The shared formatter and its other consumers are untouched ──────────
const formatRate = networkService.match(/function formatRate\([\s\S]*?\n    \}/)?.[0] ?? ""
assert.ok(formatRate.length > 0, "NetworkService still owns formatRate")
for (const branch of ["toFixed(2) + \" B/s\"", "(value / 1024).toFixed(2) + \" KB/s\"",
                      "(value / (1024 * 1024)).toFixed(2) + \" MB/s\"",
                      "(value / (1024 * 1024 * 1024)).toFixed(2) + \" GB/s\""])
    assert.ok(formatRate.includes(branch), `formatRate keeps its ${branch} branch`);
assert.match(readFileSync(join(here, "NetworkStatus.qml"), "utf8"),
    /NetworkService\.formatRate\(NetworkService\.downloadBytesPerSecond\)/,
    "the Wi-Fi tooltip keeps showing live rates")
assert.match(readFileSync(join(here, "TemperatureSensorPopups.qml"), "utf8"),
    /NetworkService\.formatRate\(NetworkService\.downloadBytesPerSecond\)/,
    "the temperature popup keeps showing live rates")

console.log("network traffic width contract: ok")
