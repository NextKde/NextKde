import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

function read(relativePath) {
    return readFileSync(fileURLToPath(new URL(relativePath, import.meta.url)), "utf8");
}

function rgb(hex) {
    return [1, 3, 5].map(offset => Number.parseInt(
        hex.slice(offset, offset + 2), 16) / 255);
}

function channel(value) {
    return value <= 0.04045 ? value / 12.92
        : Math.pow((value + 0.055) / 1.055, 2.4);
}

function luminance(color) {
    return channel(color[0]) * 0.2126
        + channel(color[1]) * 0.7152
        + channel(color[2]) * 0.0722;
}

function contrast(first, second) {
    const light = Math.max(luminance(first), luminance(second));
    const dark = Math.min(luminance(first), luminance(second));
    return (light + 0.05) / (dark + 0.05);
}

for (const accent of ["#3478f6", "#8b5cf6", "#16875f", "#d66a20"]) {
    const background = rgb(accent);
    assert.ok(Math.max(contrast(background, [0, 0, 0]),
                       contrast(background, [1, 1, 1])) >= 4.5,
              `${accent} has an AA foreground candidate`);
}

const windowSource = read("./foundation/KosApplicationWindow.qml");
const themeSource = read("./foundation/AppTheme.qml");
assert.match(windowSource, /color:\s*AppTheme\.glassActive\s*\?\s*"transparent"/,
    "glass mode clears the native window exactly once");
assert.match(windowSource, /background:[\s\S]*color:\s*AppTheme\.windowSurface/,
    "window background uses the material surface selected by the shared theme");
assert.match(windowSource, /color:\s*AppTheme\.windowTintSurface/,
    "window gradient starts with the matching material tint");
assert.doesNotMatch(windowSource, /withAlpha\(AppTheme\.accent/,
    "window base must not depend on compositor blur for readability");
assert.match(themeSource, /function mix[\s\S]*Qt\.rgba\([\s\S]*,\s*1\s*\)/,
    "semantic colour mixing always produces an opaque result");
assert.match(themeSource, /systemPaletteValid/,
    "invalid platform palettes have a readable fallback");
assert.match(themeSource, /Math\.max\(0\.93,[\s\S]*materialOpacity/,
    "forced glass remains readable without compositor blur");
assert.match(themeSource, /appearanceMode === "dark"/,
    "the shared theme supports a forced dark appearance");
assert.match(themeSource, /contrastRatio\(accent, blackSeed\)[\s\S]*contrastRatio\(accent, whiteSeed\)/,
    "accent foreground chooses the stronger black-or-white contrast");

for (const button of ["KosButton", "KosToolButton", "KosRoundButton",
                      "KosSwitch", "KosSlider"]) {
    const source = read(`./foundation/${button}.qml`);
    assert.match(source, /radius:/, `${button} defines rounded geometry`);
    assert.match(source, /AppTheme\./, `${button} uses semantic application colours`);
}

for (const app of ["calendar", "todo", "weather", "music"]) {
    const source = read(`../../apps/${app}/qml/Main.qml`);
    assert.match(source, /color:\s*AppTheme\.sidebarSurface/,
        `${app} has an adaptive semantic sidebar material`);
    assert.doesNotMatch(source, /withAlpha\(AppTheme\.sidebar/,
        `${app} sidebar does not expose desktop content`);
    assert.doesNotMatch(source, /\b(?:Button|ToolButton|RoundButton)\s*\{/,
        `${app} uses the shared rounded button controls`);
    assert.match(source, /KosSettingsDialog\s*\{/,
        `${app} exposes the shared settings panel`);
    assert.match(source, /Accessible\.name:\s*qsTr\(".*settings"\)/,
        `${app} settings entry has an accessible label`);
    assert.match(source, /function handleActivation\(activationArgs, workingDirectory\)/,
        `${app} accepts normalized reuse context from the shared runner`);
    assert.doesNotMatch(source,
        /function [A-Za-z0-9_]+\([^)]*\barguments\b/,
        `${app} does not shadow JavaScript's implicit arguments object`);
}

const settingsDialog = read("./foundation/KosSettingsDialog.qml");
for (const option of ["appearanceMode", "materialMode", "materialOpacity",
                      "accentName", "reduceTransparency", "reduceMotion"])
    assert.match(settingsDialog, new RegExp(`settings\\.${option}`),
        `settings panel exposes ${option}`);
assert.match(settingsDialog, /settings\.effectiveMaterialOpacity/,
    "settings reports the opacity that is actually rendered");
assert.match(settingsDialog, /Accessible\.name:\s*root\.title/,
    "settings dialog exposes its application-specific title");
assert.match(settingsDialog, /StandardKey\.Preferences/,
    "settings use the platform Preferences shortcut");
assert.match(settingsDialog, /Accessible\.RadioButton[\s\S]*Accessible\.checked/,
    "accent swatches expose selection state to assistive technology");

const switchSource = read("./foundation/KosSwitch.qml");
const segmentedSource = read("./controls/LiquidSegmentedControl.qml");
assert.match(switchSource, /Accessible\.onPressAction/,
    "custom switches expose an assistive press action");
assert.match(segmentedSource, /Accessible\.RadioButton/,
    "segmented choices expose radio-button semantics");
assert.match(segmentedSource,
    /Keys\.onPressed[\s\S]*Qt\.Key_Left[\s\S]*Qt\.Key_Right[\s\S]*Qt\.Key_Home[\s\S]*Qt\.Key_End/,
    "segmented choices support portable radio-group keyboard navigation");
assert.doesNotMatch(segmentedSource, /Keys\.onEndPressed/,
    "segmented choices avoid the unavailable Keys.endPressed convenience signal");
assert.match(segmentedSource,
    /onCurrentIndexChanged:[\s\S]{0,320}_visualIndex = clampedIndex\(currentIndex\)/,
    "segmented choices immediately mirror externally changed state");

const calendar = read("../../apps/calendar/qml/Main.qml");
assert.match(calendar, /model:\s*42/, "calendar mini-month contains six complete weeks");
assert.doesNotMatch(calendar, /\bCheckBox\s*\{/,
    "calendar uses custom rounded toggles instead of native checkboxes");
assert.match(calendar, /property date now[\s\S]*interval:\s*60000/,
    "calendar refreshes date and time-dependent UI while it remains open");
assert.match(calendar, /Qt\.locale\(\)\.firstDayOfWeek/,
    "calendar follows the locale's first weekday");
assert.match(calendar, /date\.getDay\(\) - localeFirstDayOfWeek \+ 7/,
    "calendar date offsets support both Sunday- and Monday-first locales");
for (const calendarView of ["CalendarMonthView.qml", "CalendarScheduleView.qml"]) {
    const source = read(`../../apps/calendar/qml/${calendarView}`);
    assert.match(source, /required property date currentTime/,
        `${calendarView} receives the observable application clock`);
    assert.doesNotMatch(source, /new Date\(\)/,
        `${calendarView} does not freeze an unobservable current time in bindings`);
}
const calendarMonth = read("../../apps/calendar/qml/CalendarMonthView.qml");
assert.doesNotMatch(calendarMonth, /"✓ "/,
    "completed calendar items use shape and typography instead of checkmark text");
assert.doesNotMatch(calendarMonth, /\b(?:Button|ToolButton|RoundButton)\s*\{/,
    "the full calendar month view uses rounded shared or custom controls");

const todo = read("../../apps/todo/qml/Main.qml");
assert.match(todo, /property date now[\s\S]*interval:\s*60000/,
    "Todo refreshes today and overdue state while it remains open");
assert.doesNotMatch(todo, /function todayKey\(\)[\s\S]{0,80}new Date\(\)/,
    "Todo date filters depend on its observable application clock");
assert.match(todo, /pendingItemId[\s\S]*onSnapshotChanged:\s*root\.openPendingItem/,
    "Todo retains widget item deep links until its async snapshot arrives");

const music = read("../../apps/music/qml/Main.qml");
assert.match(music, /function activationUri[\s\S]*workingDirectory/,
    "reused Music instances resolve relative files in the caller's directory");
assert.match(music,
    /ButtonGroup \{ id: navigationGroup \}[\s\S]*ButtonGroup\.group: navigationGroup[\s\S]*ButtonGroup\.group: navigationGroup/,
    "Music navigation stays exclusively selected when its active item is clicked again");

const weather = read("../../apps/weather/qml/Main.qml");
assert.match(weather, /ButtonGroup \{ id: unitsGroup \}[\s\S]*ButtonGroup\.group: unitsGroup[\s\S]*ButtonGroup\.group: unitsGroup/,
    "Weather unit choices form one exclusive accessible group");

const textField = read("./controls/LiquidTextField.qml");
assert.doesNotMatch(textField, /duration:\s*(?:130|150)/,
    "shared text fields honor the reduce-motion duration tokens");

const preferences = read("../../apps/common/src/ApplicationPreferences.cpp");
assert.match(preferences, /KosApplications/,
    "appearance preferences share one store across all applications");
assert.match(preferences, /setInterval\(1000\)/,
    "appearance preferences refresh across running application processes");

const runner = read("../../apps/common/src/ApplicationRunner.cpp");
assert.match(runner, /KWindowEffects::enableBlurBehind/,
    "application windows request KDE native blur when it is available");
assert.match(runner, /QQuickWindow::setDefaultAlphaBuffer\(true\)/,
    "application windows allocate an alpha-capable framebuffer before creation");
assert.match(runner, /isolatedTestRun[\s\S]*!isolatedTestRun/,
    "smoke and screenshot runs cannot be short-circuited by a primary instance");

const activation = read("../../apps/common/src/ApplicationActivation.cpp");
assert.match(activation, /XDG_ACTIVATION_TOKEN[\s\S]*setCurrentXdgActivationToken/,
    "secondary launches forward the Wayland activation token to the primary window");
assert.match(activation, /AcquireResult::Error/,
    "a failed single-instance hand-off is not reported as a successful launch");

const glassEffect = read("../../integrations/kwin-effects-glass/src/blur.cpp");
assert.match(glassEffect, /hasExplicitBlurRequest[\s\S]*explicitlyRequestedBlur/,
    "explicit application and decoration blur bypass force-blur filtering");
assert.match(glassEffect,
    /addBlurCapability\(\)[\s\S]*m_blurCapabilityRegistered = true[\s\S]*if \(m_blurCapabilityRegistered\)[\s\S]*removeBlurCapability/,
    "new KWin blur capability is released only after successful registration");
assert.match(glassEffect, /if \(m_valid\)[\s\S]*stackingOrder\(\)[\s\S]*updateBlurRegion/,
    "reconfiguration refreshes existing windows from a stable snapshot");

const deskCenter = read("../../desktop/modules/deskcenter/DeskCenterWindow.qml");
assert.doesNotMatch(deskCenter, /#101010|#17151c|#170f14/,
    "desktop widget palette avoids near-black blocks");

const appActions = read("../../desktop/modules/common/AppActionService.qml");
assert.doesNotMatch(appActions,
    /function [A-Za-z0-9_]+\([^)]*\barguments\b/,
    "desktop deep links do not shadow JavaScript's implicit arguments object");

console.log("KOS UI visual contract: all checks passed");
