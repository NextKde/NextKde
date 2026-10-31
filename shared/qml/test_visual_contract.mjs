import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
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

function rgbaProperty(source, name) {
    const match = source.match(new RegExp(
        `readonly property color ${name}: Qt\\.rgba\\(([^)]*)\\)`));
    assert.ok(match, `${name} is an explicit RGBA role`);
    const values = match[1].split(",").map(value => Number(value.trim()));
    assert.equal(values.length, 4, `${name} has four RGBA channels`);
    assert.ok(values.every(Number.isFinite), `${name} uses numeric RGBA channels`);
    return values;
}

function composite(foreground, background) {
    return foreground.slice(0, 3).map((channelValue, index) =>
        channelValue * foreground[3] + background[index] * (1 - foreground[3]));
}

for (const accent of ["#3478f6", "#8b5cf6", "#16875f", "#d66a20"]) {
    const background = rgb(accent);
    assert.ok(Math.max(contrast(background, [0, 0, 0]),
                       contrast(background, [1, 1, 1])) >= 4.5,
              `${accent} has an AA foreground candidate`);
}

const windowSource = read("./foundation/KosApplicationWindow.qml");
const themeSource = read("./foundation/AppTheme.qml");
const uiModuleCmake = read("./CMakeLists.txt");
assert.doesNotMatch(uiModuleCmake,
    /colorize\/(?:Artwork|Wallpaper)ColorSource\.qml/,
    "standalone Kos.Ui never packages Quickshell-only color samplers");
assert.match(windowSource, /color:\s*modernDesign\s*\|\|\s*AppTheme\.glassActive\s*\?\s*"transparent"/,
    "glass and rounded windows clear the native window exactly once");
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

const shellThemeSource = read("../../shell/desktop/modules/dock/DockThemeService.qml");
for (const mode of ["dark", "light"]) {
    const background = rgbaProperty(shellThemeSource, `${mode}Bg`);
    const primary = rgbaProperty(shellThemeSource, `${mode}Fg`);
    const secondary = rgbaProperty(shellThemeSource, `${mode}SecondaryFg`);
    const tertiary = rgbaProperty(shellThemeSource, `${mode}TertiaryFg`);
    assert.ok(contrast(primary, background) >= 7,
        `${mode} primary shell text reaches enhanced contrast`);
    assert.ok(contrast(composite(secondary, background), background) >= 4.5,
        `${mode} secondary shell text reaches AA contrast`);
    assert.ok(contrast(composite(tertiary, background), background) >= 4.5,
        `${mode} tertiary shell text remains readable at small sizes`);
    const indicator = rgbaProperty(shellThemeSource, `${mode}Indicator`);
    assert.ok(contrast(composite(indicator, background), background) >= 4.5,
        `${mode} dock indicator reaches AA contrast against dock background`);
}
const glassTextSource = read("../../shell/desktop/modules/common/GlassText.qml");
// GlassText inherits Text through ShellText so every Text property passes through
// natively. Readability is now a two-way contract driven by the appearance
// token: dark appearance keeps white type over a soft area backdrop; light
// appearance uses clean dark type. Neither branch adds a glyph outline.
assert.match(glassTextSource, /^ShellText \{/m,
    "glass text shares Shell text rendering while retaining Text properties");
assert.match(read("../../shell/desktop/modules/common/ShellText.qml"), /^Text \{/m,
    "shared Shell text retains Text layout and elision properties");
assert.match(glassTextSource,
    /color:[\s\S]*AppearanceTokens\.isDarkTheme[\s\S]*"#ffffff"[\s\S]*"#000000"/,
    "glass text picks black-or-white ink from the appearance token");
assert.match(glassTextSource, /style:\s*Text\.Normal/,
    "glass text retains clean glyphs");
assert.doesNotMatch(glassTextSource, /Text\.(?:Outline|Raised|Sunken)/,
    "readability must not add a glyph outline or embossing");
assert.match(glassTextSource, /property bool shadowEnabled:[^\n]*AppearanceTokens\.isDarkTheme/,
    "only light ink on dark glass requests the area backdrop");
assert.match(glassTextSource, /sourceComponent:\s*Canvas\s*\{[\s\S]*opacity:\s*strength/,
    "the area backdrop applies its faint strength during composition");
assert.match(glassTextSource, /textWidth \+ padX \* 2[\s\S]*textHeight \+ padY \* 2/,
    "the backdrop covers the text block with padding");
assert.doesNotMatch(glassTextSource, /inkLuminance/,
    "glass readability no longer depends on a sampled ink luminance");

for (const button of ["KosButton", "KosToolButton", "KosRoundButton",
                      "KosSwitch", "KosSlider"]) {
    const source = read(`./foundation/${button}.qml`);
    assert.match(source, /radius:/, `${button} defines rounded geometry`);
    assert.match(source, /AppTheme\./, `${button} uses semantic application colours`);
}

const surfaceSource = read("./foundation/KosSurface.qml");
assert.match(surfaceSource, /shadowAmbient[\s\S]*shadowKey/,
    "shared surfaces render ambient and key shadow layers");
assert.match(surfaceSource, /showInnerHighlight[\s\S]*innerHighlight/,
    "shared surfaces provide a restrained inner edge highlight");
assert.match(surfaceSource, /focused[\s\S]*focusRing/,
    "shared surfaces keep keyboard focus visible");
for (const button of ["KosButton", "KosToolButton", "KosRoundButton",
                      "KosNavigationButton"]) {
    const source = read(`./foundation/${button}.qml`);
    assert.match(source, /AppTheme\.pressScale/,
        `${button} provides consistent press feedback`);
    assert.match(source, /hoverEnabled:\s*true/,
        `${button} enables hover consistently across desktop styles`);
    assert.match(source, /background:\s*KosSurface/,
        `${button} uses the shared border and elevation treatment`);
}

const pageCacheSource = read("./foundation/KosPageCache.qml");
assert.match(pageCacheSource, /cacheLimit[\s\S]*PageCachePolicy\.trim/,
    "page cache has a bounded eviction policy");
assert.match(pageCacheSource, /_lastUsed[\s\S]*PageCachePolicy\.trim/,
    "page cache delegates eviction to its tested policy");
assert.match(pageCacheSource, /asynchronous:[\s\S]*index\s*!==\s*root\.currentIndex/,
    "inactive page construction cannot block the selected page");

const collapsibleSidebar = read("./foundation/KosSidebar.qml");
assert.match(collapsibleSidebar, /property color surfaceColor:\s*AppTheme\.sidebarSurface/,
    "collapsible sidebars default to the adaptive semantic material");
assert.match(collapsibleSidebar, /color:\s*root\.surfaceColor/,
    "collapsible sidebars render the selected semantic material");
assert.doesNotMatch(collapsibleSidebar, /withAlpha\(AppTheme\.sidebar/,
    "collapsible sidebars do not expose desktop content");
assert.match(collapsibleSidebar, /enabled:\s*expanded/,
    "collapsed navigation cannot take keyboard focus");
for (const app of ["calendar", "todo", "weather"]) {
    const source = read(`../../apps/${app}/qml/Main.qml`);
    if (app === "calendar") {
        // Calendar deliberately uses a flush sidebar and custom window dots.
        // Keep the focus, recovery and keyboard contracts without requiring
        // the older floating-card component names.
        assert.match(source, /objectName:\s*"applicationSidebar"[\s\S]*enabled:\s*root\.sidebarExpanded/,
            "collapsed calendar navigation cannot take keyboard focus");
        assert.match(source, /onClicked:\s*root\.sidebarExpanded\s*=\s*!root\.sidebarExpanded/,
            "calendar navigation can be restored");
        assert.match(source, /Accessible\.role:\s*Accessible\.Button/,
            "calendar window actions remain accessible buttons");
        for (const action of ["showMinimized", "showMaximized", "showNormal", "close"])
            assert.ok(source.includes(`root.${action}()`), `calendar exposes ${action}`);
        for (const key of ["Return", "Enter", "Space"])
            assert.ok(source.includes(`Keys.on${key}Pressed: windowDot.activate()`),
                `calendar window actions accept ${key}`);
    } else {
        assert.match(source, /KosSidebar\s*\{[\s\S]*expanded:\s*root\.sidebarExpanded/,
            `${app} uses the adaptive collapsible sidebar`);
        assert.match(source, /KosSidebarToggle\s*\{[\s\S]*targetWindow:\s*root/,
            `${app} provides a way to restore collapsed navigation`);
        assert.match(source, /KosWindowControls\s*\{[\s\S]{0,200}?targetWindow:\s*root/,
            `${app} exposes its frameless window controls`);
    }
    assert.doesNotMatch(source, /withAlpha\(AppTheme\.sidebar/,
        `${app} sidebar does not expose desktop content`);
    assert.doesNotMatch(source, /\b(?:Button|ToolButton|RoundButton)\s*\{/,
        `${app} uses the shared rounded button controls`);
    if (app === "weather") {
        // Weather deliberately exposes units inline, without a separate settings dialog.
        assert.match(source, /ButtonGroup\s*\{\s*id:\s*unitsGroup/,
            "weather retains its inline units controls");
        assert.doesNotMatch(source, /KosSettingsDialog\s*\{/,
            "weather does not restore the removed settings dialog");
    } else {
        assert.match(source, /KosSettingsDialog\s*\{/,
            `${app} exposes the shared settings panel`);
        assert.match(source, app === "calendar"
            ? /text:\s*qsTr\("Calendar settings"\)/
            : /Accessible\.name:\s*qsTr\(".*settings"\)/,
            `${app} settings entry has an accessible label`);
    }
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

// The settings app shows two different glass sections depending on the shell
// style. Under Material the liquid-only controls are absent, and each card's
// height has to shrink by exactly the rows it drops -- a height that ignores
// the hidden rows leaves a blank band where they used to be.
// The settings app is built from the shared compact form: Demo.SettingsGroup
// and Demo.SettingsItem size themselves from their rows, so hiding a row
// shrinks the card. The tripwire is therefore that the glass-follows row stays
// a conditional item inside such a group, and that no page reintroduces a
// hardcoded Material-conditional card height -- the old way to leave a blank
// band where the hidden rows used to be.
const settingsApp = read("../../apps/settings/main.qml");
const displaySettingsPage = read("../../apps/settings/pages/DisplaySettingsPage.qml");
const themeSettingsPage = read("../../apps/settings/pages/ThemeSettingsPage.qml");
assert.match(displaySettingsPage,
    /Demo\.SettingsGroup\s*\{[\s\S]{0,3000}?Demo\.SettingsItem\s*\{[\s\S]{0,400}?visible:\s*!displayPage\.isMaterialDesign/,
    "the glass-follows-mode row is a conditional item in a content-sized group");
assert.match(displaySettingsPage, /function saveGlassFollowsAppearanceMode/,
    "the glass-follows-mode preference stays wired for non-Material styles");
assert.doesNotMatch(displaySettingsPage,
    /implicitHeight:\s*[\w.]*[Pp]age\.isMaterialDesign\s*\?/,
    "the appearance cards no longer hardcode a Material-conditional height");
assert.match(themeSettingsPage,
    /Demo\.SettingsGroup\s*\{[\s\S]{0,4000}?Demo\.SettingsAppearancePreview/,
    "the theme shape gallery lives in a content-sized settings group");
assert.doesNotMatch(themeSettingsPage, /Layout\.preferredHeight:\s*550\b/,
    "the theme card no longer hardcodes the macOS-only height");

// 玻璃文字墨色 is driven by the one option the settings row above already owns
// (液态玻璃跟随外观模式), so these assertions pin the rule rather than a control:
// while the option is off the glass stays dark in both appearances and keeps the
// fixed white ink the shell has always drawn; turning it on lets a light
// appearance light the glass, and the ink turns dark with it. The branch keys on
// the appearance token, which already folds in "the glass does not follow, so it
// stays dark" -- reading the desktop theme instead would paint black type on a
// dark glass whenever the option is off on a light desktop.
const appearanceTokensSource = read("../../shell/desktop/modules/common/AppearanceTokens.qml");
assert.match(appearanceTokensSource,
    /function glassInk\(alpha\)[\s\S]{0,160}?glassContentColor\(alpha\)/,
    "shell chrome asks one glass ink resolver instead of testing the style itself");
const glassInkSurface = read("../../shell/desktop/modules/common/LiquidGlassSurface.qml");
const iconAppearanceSource = read("../../shell/desktop/modules/common/IconAppearanceService.qml");
assert.match(iconAppearanceSource,
    /isDarkTheme[\s\S]{0,200}?surfaceForeground[\s\S]{0,160}?Qt\.rgba\(1, 1, 1, opacity\)/,
    "glass ink stays white only while the glass itself is dark");
assert.doesNotMatch(iconAppearanceSource, /resolvedAppearanceIsDark|systemIsDark/,
    "glass ink never takes the desktop's theme for the glass's own ink");
// The white hierarchy the glass shipped with has to move as one: a role that
// keeps its own literal reads correctly while the glass is dark and turns
// invisible the moment a light appearance lights it.
for (const role of ["foregroundColor", "secondaryForegroundColor",
                    "tertiaryForegroundColor"])
    assert.match(glassInkSurface,
        new RegExp(`readonly property color ${role}:[\\s\\S]{0,400}?content\\.glassInk\\(`),
        `the glass ${role} follows the resolved ink`);
assert.match(read("../../shell/desktop/modules/bar/NetworkTraffic.qml"),
    /onGlyphInkChanged[\s\S]*?requestPaint\(\)/,
    "the Bar traffic arrow repaints when the ink it strokes with moves");
for (const [path, description] of [
    ["../../shell/desktop/modules/bar/controlcenter/SubmenuCard.qml", "Control Centre chrome"],
    ["../../shell/desktop/modules/bar/WifiSignalIcon.qml", "shared Wi-Fi glyph"],
    ["../../shell/desktop/modules/quicksearch/QuickSearchWindow.qml", "Quick Search chrome"],
]) {
    assert.match(read(path), /content\.glassInk\(/,
        `${description} takes the glass ink instead of a white literal`);
}
assert.match(read("../../shell/desktop/modules/bar/NetworkTraffic.qml"),
    /readonly property color glyphInk:\s*ThemeService\.barInk/,
    "the Bar traffic arrow shares the status labels' opaque appearance ink");
// NetworkPanel now delegates ink to the surface, which resolves the same
// glass roles. Assert both ends of that delegation rather than requiring the
// older direct AppearanceTokens call in every consumer.
const networkInkPanel = read("../../shell/desktop/modules/bar/NetworkPanel.qml");
assert.match(networkInkPanel, /LiquidGlassPanel\s*\{\s*id:\s*panelSurface/);
assert.match(networkInkPanel, /color:\s*panelSurface\.foregroundColor/);
assert.match(networkInkPanel, /color:\s*panelSurface\.secondaryForegroundColor/);
const glassPanel = read("../../shell/desktop/modules/common/LiquidGlassPanel.qml");
assert.match(glassPanel, /readonly property color foregroundColor:\s*bodySurface\.foregroundColor/);
assert.match(glassPanel, /readonly property color secondaryForegroundColor:\s*bodySurface\.secondaryForegroundColor/);
// A second switch would split one decision in two and let the halves disagree,
// and the rejected draft of this rule is exactly what that looked like.
assert.doesNotMatch(read("../../shell/desktop/modules/common/AppearanceConfigService.qml"),
    /glassInkFollowsAppearanceMode/,
    "the glass ink reuses the existing option instead of adding its own");
assert.doesNotMatch([settingsApp, displaySettingsPage, themeSettingsPage].join("\n"),
    /glassInkFollowsAppearanceMode|文字颜色跟随外观/,
    "the appearance card grows no second glass row");

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
assert.match(calendar,
    /KosPageCache[\s\S]{0,320}cacheLimit:\s*2[\s\S]{0,220}monthPage[\s\S]{0,100}weekPage[\s\S]{0,100}dayPage/,
    "Calendar keeps its active and recent date views without retaining every page");
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

const weather = read("../../apps/weather/qml/Main.qml");
assert.match(weather, /ButtonGroup \{ id: unitsGroup \}[\s\S]*ButtonGroup\.group: unitsGroup[\s\S]*ButtonGroup\.group: unitsGroup/,
    "Weather unit choices form one exclusive accessible group");

// LiquidTextField is shell-owned: it is directory-imported by the Quickshell
// surfaces where the AppTheme singleton is not in scope, so it keeps the
// shell's own fixed motion policy. The AppTheme-backed foundation controls
// are the ones that must honor the reduce-motion duration tokens.
for (const control of ["KosButton", "KosRoundButton", "KosSlider", "KosSwitch"]) {
    const source = read(`./foundation/${control}.qml`);
    assert.doesNotMatch(source, /duration:\s*(?:130|150)/,
        `${control} honors the reduce-motion duration tokens`);
}

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

const glassEffect = read("../../kwin/glass-effect/src/blur.cpp");
assert.match(glassEffect, /hasExplicitBlurRequest[\s\S]*explicitlyRequestedBlur/,
    "explicit application and decoration blur bypass force-blur filtering");
assert.match(glassEffect,
    /addBlurCapability\(\)[\s\S]*m_blurCapabilityRegistered = true[\s\S]*if \(m_blurCapabilityRegistered\)[\s\S]*removeBlurCapability/,
    "new KWin blur capability is released only after successful registration");
assert.match(glassEffect, /if \(m_valid\)[\s\S]*stackingOrder\(\)[\s\S]*updateBlurRegion/,
    "reconfiguration refreshes existing windows from a stable snapshot");

const deskCenter = read("../../shell/desktop/modules/deskcenter/DeskCenterWindow.qml");
assert.doesNotMatch(deskCenter, /#101010|#17151c|#170f14/,
    "desktop widget palette avoids near-black blocks");
for (const [widget, desktopId] of [
    ["Weather", "kos-weather"],
    ["Calendar", "kos-calendar"],
    ["Reminders", "kos-calendar"],
    ["Music", "listenfree"]
]) {
    assert.match(deskCenter, new RegExp(`launchById\\("${desktopId}"`),
        `${widget} widget launches its matching installed application`);
}

const appActions = read("../../shell/desktop/modules/common/AppActionService.qml");
assert.doesNotMatch(appActions,
    /function [A-Za-z0-9_]+\([^)]*\barguments\b/,
    "desktop deep links do not shadow JavaScript's implicit arguments object");
assert.match(appActions,
    /function launchById[\s\S]*Array\.from\(baseCommand\)\.concat\(extra\)/,
    "widget deep links preserve the DesktopEntry command and append context once");
assert.doesNotMatch(appActions, /_queueDeepLink|_deepLinkDelay/,
    "widget deep links never launch a second delayed process");

const popupMotion = read("../../shell/desktop/modules/common/PopupMotion.qml");
const appearanceTokens = read("../../shell/desktop/modules/common/AppearanceTokens.qml");
const contextMenu = read("../../shell/desktop/modules/common/ContextMenu.qml");
assert.match(appearanceTokens, /popupOpenDuration:\s*150[\s\S]*popupCloseDuration:\s*140/,
    "shared popup motion uses Launchpad's 150ms entrance timing");
assert.match(appearanceTokens, /popupStartScale:\s*0\.96[\s\S]*popupAnchorOffset:\s*20/,
    "shared popup motion uses Launchpad's 0.96 settle scale");
assert.match(popupMotion, /openEasing:\s*Easing\.OutCubic[\s\S]*closeEasing:\s*Easing\.InCubic/,
    "popup open and close use cubic easing without overshoot");
assert.match(contextMenu, /centerBelowAnchor[\s\S]*PopupAdjustment\.Slide/,
    "centered application menus only slide at screen edges");
const appLauncherWindow = read("../../shell/desktop/modules/applauncher/AppLauncherWindow.qml");
const controlCenterPanelSource = read("../../shell/desktop/modules/bar/ControlCenterPanel.qml");
assert.doesNotMatch(controlCenterPanelSource, /cascade|interval:\s*12/,
    "control-center cards use one synchronized animation");
const globalMenuSource = read("../../shell/desktop/modules/bar/GlobalMenu.qml");
const dockAnimationSource = read("../../shell/desktop/modules/dock/DockAnimation.qml");
const appIconSource = read("../../shell/desktop/modules/common/AppIcon.qml");
const iconThemeReloadSource = read("../../shell/desktop/modules/common/IconThemeReloadService.qml");
const quickSearchWindow = read("../../shell/desktop/modules/quicksearch/QuickSearchWindow.qml");
assert.match(appLauncherWindow,
    /LauncherMotion\s*\{[\s\S]*target:\s*launcherContent/,
    "the launcher coordinates tile motion while retaining its content container");
const launcherMotion = read("../../shell/desktop/modules/applauncher/LauncherMotion.qml");
assert.match(launcherMotion, /function finishIfSettled\(\)[\s\S]*changing \|\| !glassFinished \|\| pendingIcons !== 0[\s\S]*if \(!requestedOpen\) mapped = false/,
    "the launcher remains mapped until its closing tile animations finish");
assert.match(appLauncherWindow,
    /property var applications:\s*\[\][\s\S]*applicationCatalogRefresh[\s\S]*model:\s*root\.contentAlive && !root\.isFullscreenMode/,
    "Launchpad retains its catalogue while delegates follow the content lifetime and visible mode");
assert.match(appLauncherWindow,
    /property bool outputAvailable:\s*false[\s\S]*visible:\s*root\.outputAvailable/,
    "Launchpad retains one backing window while a real output is available");
assert.match(appLauncherWindow,
    /mask:\s*Region\s*\{[\s\S]*width:\s*root\.open && root\.panelVisible \? root\.width : 0[\s\S]*height:\s*root\.open && root\.panelVisible \? root\.height : 0/,
    "the closed Launchpad backing surface cannot intercept desktop input");
assert.match(appLauncherWindow,
    /anchors\s*\{[\s\S]*top:\s*true[\s\S]*left:\s*true[\s\S]*right:\s*true[\s\S]*bottom:\s*true[\s\S]*implicitWidth:\s*launcherWidth[\s\S]*implicitHeight:\s*launcherHeight/,
    "the retained Launchpad surface keeps stable output geometry between opens");
assert.match(appLauncherWindow,
    /BackgroundEffect\.blurRegion:[\s\S]*root\.panelVisible/,
    "the closed Launchpad surface never publishes a compositor blur region");
assert.match(appLauncherWindow, /blurAnchor:\s*background/,
    "launcher native glass follows the stationary backdrop");
assert.match(appLauncherWindow, /id:\s*launcherCard[\s\S]*width:\s*launcherRevealClip\.width\s+height:\s*launcherRevealClip\.height/,
    "the launcher backdrop retains its full dimensions during tile motion");
assert.match(appIconSource,
    /backer\.cache:\s*(?:!root\.needsEffect\s*&&\s*)?IconThemeReloadService\.pixmapCacheAllowed/,
    "shared app icons cache decoded pixmaps only on the direct-render path");
assert.match(quickSearchWindow,
    /backer\.cache:\s*!resultIcon\.needsEffect\s*&& IconThemeReloadService\.pixmapCacheAllowed/,
    "QuickSearch caches decoded result pixmaps only on the direct-render path");
assert.match(iconThemeReloadSource,
    /pixmapCacheAllowed:\s*true[\s\S]*pixmapCacheAllowed = false[\s\S]*revision\+\+/,
    "an icon-theme change bypasses stale process-wide decoded pixmaps");
assert.match(dockAnimationSource,
    /windowPreviewDelay:\s*220/,
    "Dock previews debounce pointer passes before requesting a full-screen capture");
// The four-pixel separation from the Bar moved from a per-card offset into the
// panel's own anchor margins when the panel became one window. The value and
// the intent are unchanged: standalone the panel starts four pixels below the
// Bar, dock-hosted it must keep its edge flush with the Dock.
assert.match(controlCenterPanelSource,
    /margins\.bottom:\s*panel\.dockHosted\s*\?\s*0\s*:\s*-4/,
    "standalone Control Center starts four pixels below the Bar");
assert.match(controlCenterPanelSource,
    /adjustment:\s*PopupAdjustment\.Slide/,
    "the Control Center still slides at screen edges instead of resizing");
assert.match(globalMenuSource, /root\.height\s*\+\s*4/,
    "application menus keep a four-pixel Bar gap");

const barStatusArea = read("../../shell/desktop/modules/bar/BarStatusArea.qml");
const barWindow = read("../../shell/desktop/modules/bar/BarWindow.qml");
const barAutoHide = read("../../shell/desktop/modules/bar/BarAutoHideController.qml");
const barDateStatus = read("../../shell/desktop/modules/bar/BarDateStatus.qml");
const controlCenterPanel = read("../../shell/desktop/modules/bar/ControlCenterPanel.qml");
const controlCenterModuleDirectory = new URL(
    "../../shell/desktop/modules/bar/controlcenter/", import.meta.url);
const controlCenterModules = new Map(readdirSync(controlCenterModuleDirectory, { withFileTypes: true })
    .filter(entry => entry.isFile() && entry.name.endsWith(".qml"))
    .map(entry => [entry.name, readFileSync(new URL(entry.name, controlCenterModuleDirectory), "utf8")]));
function controlCenterModule(name) {
    assert.ok(controlCenterModules.has(name), `Control Center module ${name} exists`);
    return controlCenterModules.get(name);
}
const networkStatus = read("../../shell/desktop/modules/bar/NetworkStatus.qml");
const networkPanel = read("../../shell/desktop/modules/bar/NetworkPanel.qml");
const wifiSignalIcon = read("../../shell/desktop/modules/bar/WifiSignalIcon.qml");
assert.doesNotMatch(barWindow, /LiquidGlassSurface\s*\{/,
    "the Bar keeps the compositor's clear refractive glass instead of a frosted fill");
assert.match(barWindow,
    /topTriggerArea[\s\S]*hide\.hidden[\s\S]*\?\s*2\s*:\s*0/,
    "the auto-hidden Bar exposes only a narrow top-edge reveal target");
assert.match(barAutoHide, /name:\s*s\.name\s*\|\|\s*""/,
    "Bar auto-hide identifies target screens by name as well as geometry");
assert.match(barDateStatus, /GlassText\s*\{/,
    "top-bar labels protect their glyph edges over changing wallpaper");
// Control-center labels that sit on the translucent glass must carry the
// readability outline. The session-confirmation dialog is the exception: it is
// a KosFloatPanel with its own opaque content surface, so its labels read
// ThemeService/content colours on a solid fill and an outline would be wrong.
// Check every glass module independently, exempting only the opaque dialog.
const sessionConfirmStart = controlCenterPanel.indexOf("id: sessionConfirm");
assert.ok(sessionConfirmStart > 0,
    "the session confirmation dialog is still present to be exempted");
assert.match(controlCenterPanel,
    /ControlParts\.SessionConfirmationDialog\s*\{\s*id:\s*sessionConfirm\b/,
    "the panel composes the opaque confirmation dialog");
controlCenterModule("SessionConfirmationDialog.qml");
for (const [name, source] of [["ControlCenterPanel.qml", controlCenterPanel],
    ...controlCenterModules]) {
    if (name !== "SessionConfirmationDialog.qml")
        assert.doesNotMatch(source, /^\s*Text\s*\{/m,
            `${name}: control-center labels use bidirectional glass readability outlines`);
}
assert.match(globalMenuSource,
    /ContextMenu\s*\{[\s\S]{0,180}baseColor:\s*ThemeService\.backgroundColor[\s\S]{0,120}foregroundColor:\s*ThemeService\.foregroundColor/,
    "application menus follow the stable light/dark material palette");
assert.match(barStatusArea, /iconSize:\s*18/,
    "top-bar tray icons use the enlarged 18px optical size");
assert.match(wifiSignalIcon,
    /signalStrength\s*<\s*30\s*\?\s*1\s*:\s*\(signalStrength\s*<\s*60\s*\?\s*2\s*:\s*3\)/,
    "the shared Wi-Fi glyph exposes three live signal-quality levels");
assert.match(networkStatus,
    /WifiSignalIcon\s*\{[\s\S]{0,420}signalStrength:\s*NetworkService\.signalStrength/,
    "the top-bar Wi-Fi icon renders NetworkManager signal quality");
assert.match(networkPanel,
    /id:\s*rowWifiGlyph[\s\S]{0,300}signalStrength:\s*modelData\.signalStrength[\s\S]{0,160}onSignalStrengthChanged:\s*requestPaint\(\)/,
    "each network row repaints its own signal strength rather than the connected network strength");
for (const [name, owner, intent] of [
    ["WifiCard", "wifiCard", "networkRequested"],
    ["BluetoothCard", "bluetoothCard", "bluetoothRequested"]]) {
    const section = controlCenterModule(name + ".qml");
    assert.match(section,
        /id:\s*(?:wifi|bluetooth)TogglePointer[\s\S]{0,420}onClicked:[\s\S]{0,140}set(?:Wifi|Bluetooth)Enabled/,
        `${name} round disc owns its power toggle`);
    assert.match(section,
        new RegExp(`leftMargin:\\s*49[\\s\\S]{0,520}onClicked:\\s*${owner}\\.pageRequested\\(\\)`),
        `${name} card body requests details without covering the toggle`);
    assert.match(controlCenterPanel,
        new RegExp(`ControlParts\\.${name}\\s*\\{[\\s\\S]*?onPageRequested:\\s*panel\\.${intent}\\(\\)`),
        `${name} detail intent is forwarded by the panel`);
}
for (const component of ["NetworkStatus", "Battery", "SettingsButton",
                         "ControlCenterToggle"]) {
    assert.match(barStatusArea,
        new RegExp(component + "\\s*\\{[\\s\\S]{0,800}iconSize:\\s*systemTray\\.iconSize(?:\\s*\\+\\s*\\d+)?"),
        component + " shares the native tray icon size");
}
assert.doesNotMatch(controlCenterPanel,
    /Card 5:[\s\S]{0,1000}(?:cardBorderColor|color):[^\n]*#0a84ff/,
    "theme toggle does not use the blue active treatment");
const controlCenterCard = read("../../shell/desktop/modules/bar/ControlCenterCard.qml");
const controlCenterSlider = read("../../shell/desktop/modules/bar/ControlCenterSlider.qml");
const statusTooltip = read("../../shell/desktop/modules/bar/StatusTooltip.qml");
assert.match(statusTooltip, /ControlCenterGlass\s*\{/,
    "built-in status tooltips use the shared glass surface");
assert.ok((statusTooltip.match(/color:\s*tooltipSurface\.(?:foregroundColor|secondaryForegroundColor)/g) || []).length >= 2,
    "built-in status tooltip text follows the surface colors");
for (const statusSource of [networkStatus, read("../../shell/desktop/modules/bar/Battery.qml"),
                            read("../../shell/desktop/modules/bar/ControlCenterToggle.qml")]) {
    assert.match(statusSource, /StatusTooltip\s*\{/,
        "built-in status items share the edge-aware tooltip component");
}
assert.match(controlCenterSlider, /LiquidControls\.LiquidSlider\s*\{/,
    "Control Center sliders share one styled LiquidSlider wrapper");
const sliderSources = ["SoundCard.qml", "BrightnessCard.qml", "SoundPage.qml", "BrightnessPage.qml"]
    .map(controlCenterModule);
for (const [index, source] of sliderSources.entries())
    assert.match(source, /ControlCenterSlider\s*\{/,
        `volume/brightness surface ${index + 1} uses the shared slider`);
assert.ok(sliderSources.reduce((count, source) =>
    count + (source.match(/ControlCenterSlider\s*\{/g) || []).length, 0) >= 4,
    "volume and brightness surfaces reuse the Control Center slider style");
const wifiSubmenu = controlCenterModule("WifiPage.qml");
assert.doesNotMatch(wifiSubmenu, /glyphColor:[^\n]*#000000/,
    "Wi-Fi list icons never switch to black");
// The per-card coordinator suppression model is gone: the Control Center is
// one window now, so a card can no longer be independently dimmed while a
// sibling sheet finishes closing. What must survive is the simpler contract --
// a card's visibility is exactly its `cardShown` flag, it publishes no opacity
// veil of its own, and the leftover coordinator property stays inert so an old
// instance still compiles.
assert.match(controlCenterCard, /visible:\s*root\.cardShown\b/,
    "a card's visibility is exactly its cardShown flag");
assert.doesNotMatch(controlCenterCard, /visuallySuppressed/,
    "cards no longer carry a suppression veil from the per-window model");
assert.match(controlCenterCard,
    /property bool managedByCoordinator:\s*true/,
    "the retired coordinator property stays declared so old instances compile");
assert.match(controlCenterPanel,
    /if\s*\(!coordinator\.open\)\s*\n\s*coordinator\.openAll\(\)/,
    "closing the power sheet can restore the primary Control Center state");
for (const marker of ["Card 4: Screenshot", "Card 5: Dark Mode", "Card 6: Power"]) {
    const start = controlCenterPanel.indexOf(marker);
    const section = controlCenterPanel.slice(start, start + 1800);
    assert.match(section, /width:\s*24[\s\S]{0,80}height:\s*24/,
        `${marker} uses a 24x24 icon container`);
}
// 图标自 2026-09-16 起内联在 BundledIcons.qml 里（例外只有两处：Dock 的启动器
// logo 读 shell/desktop/assets/applauncher.svg，Dock 的回收站跟随系统图标主题），
// 所以这里改从登记表里取那条数据来验证。
const iconRegistry = read("../../shell/desktop/modules/common/BundledIcons.qml");
// 注：登记名 "power" 画的是电源键（原先在 assets/logout.svg，现已内联）；"注销" 另画。
const powerEntry = iconRegistry.match(/^\s*"power": '(.*)',$/m);
assert.ok(powerEntry, "the power/logout icon is registered in BundledIcons");
const powerGlyph = powerEntry[1];
assert.match(powerGlyph, /fill="none"[\s\S]*stroke-width="70"/,
    "the power glyph uses the same light outline weight as adjacent controls");
assert.doesNotMatch(powerGlyph, /<path\s+fill=/,
    "the power glyph does not regress to an oversized solid silhouette");

// ── Glass selection highlight visual contracts ──────────────────────────────
const selectionHighlightSource = read("./controls/SelectionHighlight.qml");
assert.match(appearanceTokens,
    /readonly property string selectionHighlightStyle:\s*"glass"/,
    "AppearanceTokens sets glass selection as the default style");
assert.match(selectionHighlightSource,
    /readonly property real topAlpha:\s*dark\s*\?/,
    "SelectionHighlight branches topAlpha for dark and light contrast");
assert.match(selectionHighlightSource,
    /plate\.dark\s*\?\s*Qt\.rgba\(1,\s*1,\s*1,[\s\S]*Qt\.rgba\(0,\s*0,\s*0,/,
    "SelectionHighlight switches fill between white and dark ink for contrast");

for (const [path, desc] of [
    ["../../shell/desktop/modules/common/MenuItemRow.qml", "Context Menu items"],
    ["../../shell/desktop/modules/bar/GlobalMenu.qml", "Global Menu bar items"],
    ["../../shell/desktop/modules/bar/SysTray.qml", "System Tray icons"],
    ["../../shell/desktop/modules/bar/SettingsButton.qml", "Status Settings button"],
    ["../../shell/desktop/modules/quicksearch/QuickSearchWindow.qml", "Quick Search results"],
    ["../../shell/desktop/modules/dock/DockWindowPreview.qml", "Dock preview cards"],
    ["../../shell/desktop/modules/notifications/NotificationWindow.qml", "Notification action buttons"],
    ["../../shell/desktop/modules/bar/NetworkPanel.qml", "Network panel Wi-Fi list and settings"],
]) {
    assert.match(read(path), /SelectionHighlight\s*\{/,
        `${desc} integrates SelectionHighlight glass selection`);
}

// ── Notification history pane contracts ─────────────────────────────────────
const notificationHistoryPane = read("../../shell/desktop/modules/bar/NotificationHistoryPane.qml");
assert.match(notificationHistoryPane,
    /footerButton[\s\S]*visible:\s*NotificationHistoryService\.count\s*>\s*0\s*&&/,
    "notification deck footer button only appears when history is non-empty");
assert.match(notificationHistoryPane,
    /function clearHistory\(\)[\s\S]*reset\(\)/,
    "clearing notification history resets the deck expansion state");
assert.match(notificationHistoryPane,
    /onHistoryUpdated[\s\S]*NotificationHistoryService\.count === 0[\s\S]*pane\.reset\(\)/,
    "dropping notification count to zero resets deck expansion state");

console.log("KOS UI visual contract: all checks passed");
