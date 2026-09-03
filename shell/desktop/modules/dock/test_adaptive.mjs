// Test harness for AdaptiveMath.mjs — run with: node test_adaptive.mjs
import { computeLayout, MIN_ICON_SIZE } from "./AdaptiveMath.mjs";

const cases = [
    [60, 5, 3, false, 1920, 'few icons, no music'],
    [60, 5, 3, true,  1920, 'few icons, with music'],
    [60, 15, 18, false, 1920, 'medium icons, no music'],
    [60, 15, 18, true,  1920, 'medium icons, with music'],
    [60, 30, 30, false, 1920, 'many icons, no music'],
    [60, 30, 30, true,  1920, 'many icons, with music'],
    [60, 0, 0, false,   1920, 'empty dock'],
    [60, 0, 0, true,    1920, 'music only'],
];

let errors = 0;
for (const [bh, pc, wc, hasInfoSlot, sw, desc] of cases) {
    const r = computeLayout(bh, pc, wc, hasInfoSlot, sw);
    const issues = [];
    if (r.iconUnits > 0) {
        if (r.dockHeight > 100) issues.push('dockHeight exceeds max: ' + r.dockHeight);
        if (r.iconSize < MIN_ICON_SIZE && r.iconSize !== 0) issues.push('iconSize below min');
        if (r.dockWidth > sw * 0.98 + 2) issues.push('dockWidth > 98%');
        if (r.infoUnits !== (hasInfoSlot ? 4 : 0)) issues.push('wrong infoUnits');
        if (r.activeBackgroundGap <= 0) issues.push('missing active background gap');
    } else {
        if (r.dockHeight !== 0 || r.iconSize !== 0) issues.push('empty dock non-zero');
    }
    if (issues.length) {
        console.log('FAIL:', desc, issues.join(', ')); errors++;
    } else {
        console.log('OK:  ', desc.padEnd(25), 'H=' + r.dockHeight, 'icon=' + r.iconSize, 'W=' + r.dockWidth);
    }
}

// Spacing proportions must affect the calculation, while the width cap stays
// fixed at 98% for every caller.
const configured = computeLayout(60, 5, 3, false, 1920, {
    vpad: 0.2, hpad: 0.3, spacing: 0.1, divmargin: 0.25,
});
if (configured.dockWidth > 1920 * 0.98 + 2)
    errors++, console.log('FAIL: fixed 98% max width ignored');
if (configured.vPadding !== Math.round(configured.iconSize * 0.2))
    errors++, console.log('FAIL: configured vpad ignored');
if (configured.hPadding !== Math.round(configured.iconSize * 0.3))
    errors++, console.log('FAIL: configured hpad ignored');

const normal = computeLayout(60, 1, 1, false, 1920);
if (Math.abs(normal.activeBackgroundGap - normal.iconSize * 0.1) > 0.001)
    errors++, console.log('FAIL: active background gap is not proportional');

const sideInfo = computeLayout(60, 3, 2, true, 1080, {}, 0.95, 2);
if (sideInfo.infoUnits !== 2)
    errors++, console.log('FAIL: side info slot did not reserve two units');

const invalidInfo = computeLayout(60, 3, 2, true, 1080, {}, 0.95, NaN);
if (invalidInfo.infoUnits !== 0)
    errors++, console.log('FAIL: invalid info unit override was not rejected');

const crowded = computeLayout(60, 80, 80, true, 800);
if (crowded.iconSize !== MIN_ICON_SIZE)
    errors++, console.log('FAIL: crowded layout did not clamp to icon floor');

console.log(errors ? '\n' + errors + ' FAILED'
    : '\nAll ' + (cases.length + 3) + ' passed');
process.exit(errors ? 1 : 0);
