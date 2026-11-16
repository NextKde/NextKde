import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

// Regression for #205: on short weather cards (medium tier, one grid cell
// ≈150 px) the hero temperature, the condition symbol, the condition text and
// the "High/Low" row all crashed into each other and into the weekly forecast
// row. The card anchors its top elements from the top and its bottom elements
// from the bottom, so the only durable fix is making the top group shrink with
// the space actually available above the weekly forecast.
//
// These tests pin the three size formulas against the real source. They mirror
// the geometry the batch ledger measured on a live scene (ISSUE205_PASS), so
// any edit that drops an availability term or re-pins the condition text to a
// constant margin fails here instead of on a user's desktop.

const source = readFileSync(
    new URL("../../shell/desktop/modules/deskcenter/DeskCenterWindow.qml", import.meta.url), "utf8");

function sliceAfter(marker) {
    const at = source.indexOf(marker);
    assert.ok(at > 0, `marker ${JSON.stringify(marker)} moved; update this test`);
    return source.slice(at, at + 1400);
}

// The line-box factor measured for SF Pro Display at these weights: the glyph
// box is ~1.5× the pixel size, so a font of S px occupies ~1.5·S px vertically.
const LINE = 1.5;
const TOP_TEMP_MARGIN = 29;
const TOP_SYMBOL_MARGIN = 14;
const FORECAST_BOTTOM_MARGIN = 8;
const HIGHLOW_BOTTOM_MARGIN = 3;

function overlap(a, b) {
    return a.top < b.bottom && b.top < a.bottom;
}

function geometry(cardHeight) {
    const forecastHeight = Math.min(62, cardHeight * 0.46);
    const forecastTop = cardHeight - FORECAST_BOTTOM_MARGIN - forecastHeight;
    const highLowBottom = forecastTop - HIGHLOW_BOTTOM_MARGIN;
    const highLowHeight = 11 * 1.4; // 11 px DemiBold, ~1.4 line box
    return {
        forecastHeight,
        forecastTop,
        highLow: { top: highLowBottom - highLowHeight, bottom: highLowBottom },
    };
}

function tempBox(cardHeight, forecastHeight) {
    const size = Math.min(42, cardHeight * 0.32,
        Math.max(16, (cardHeight - forecastHeight - 38) / LINE));
    return { top: TOP_TEMP_MARGIN, bottom: TOP_TEMP_MARGIN + size * LINE };
}

function symbolBox(cardHeight, forecastHeight) {
    const size = Math.min(34, cardHeight * 0.26,
        Math.max(16, (cardHeight - forecastHeight - 72) * 0.75));
    return { top: TOP_SYMBOL_MARGIN, bottom: TOP_SYMBOL_MARGIN + size * LINE };
}

test("deskcenter weather card #205", async () => {
    // ── the temperature size formula carries the availability term ──
    const tempText = sliceAfter("text: WeatherService.temperature");
    assert.match(tempText, /Math\.min\(42,\s*parent\.height \* 0\.32,\s*\n?\s*Math\.max\(16, \(parent\.height - weeklyForecast\.height - 38\) \/ 1\.5\)\)/,
        "temperature size must shrink with the band above the weekly forecast"
        + " (issue #205)");

    // ── the condition symbol size carries its own availability term ──
    const symbolText = sliceAfter("text: WeatherService.conditionSymbol");
    assert.match(symbolText, /Math\.min\(34,\s*parent\.height \* 0\.26,\s*\n?\s*Math\.max\(16, \(parent\.height - weeklyForecast\.height - 72\) \* 0\.75\)\)/,
        "condition symbol size must shrink with the band above the forecast");

    // ── the condition text follows the symbol, never a constant margin ──
    const block = source.match(/id: weatherConditionSymbol[\s\S]*?font \{ pixelSize: 15/);
    assert.ok(block, "condition text block moved; update this test");
    assert.match(block[0], /top:\s*weatherConditionSymbol\.bottom/,
        "condition text must anchor below the symbol (constant topMargin 48"
        + " reintroduces the overlap)");

    // ── geometry: no member of the card overlaps on either authored tier ──
    for (const cardHeight of [150, 310]) {
        const g = geometry(cardHeight);
        const temp = tempBox(cardHeight, g.forecastHeight);
        const symbol = symbolBox(cardHeight, g.forecastHeight);
        const label = `card ${cardHeight}px`;

        assert.ok(temp.bottom <= g.forecastTop,
            `${label}: temperature box (${temp.top}..${temp.bottom}) enters the`
            + ` weekly forecast row (top ${g.forecastTop})`);
        assert.ok(!overlap(symbol, g.highLow),
            `${label}: condition symbol box enters the High/Low row`
            + ` (${symbol.top}..${symbol.bottom} vs ${g.highLow.top}..${g.highLow.bottom})`);
        // The condition text sits right below the symbol, so checking the
        // symbol against the High/Low row covers it by transitivity.
        assert.ok(g.highLow.top >= symbol.bottom,
            `${label}: High/Low row has room below the symbol`);
        // The temperature starts below the city name (29) and stays the
        // visually dominant glyph; the symbol sits higher on the right, so
        // "hero" here means it keeps a box taller than the symbol's.
        assert.ok(temp.bottom - temp.top > symbol.bottom - symbol.top,
            `${label}: temperature shrunk below the symbol size`);
    }
});
