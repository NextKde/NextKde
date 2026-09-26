pragma Singleton
import QtQuick
import "../../../Kos/Ui"

// Semantic shell-shape values. Consumers should depend on these roles instead
// of branching on shellStyle themselves. Values describe geometry and motion;
// color continues to come from the active system palette and semantic roles.
QtObject {
    id: tokens

    readonly property int version: 9
    readonly property string style: AppearanceConfigService.shellStyle
    readonly property bool isWindows12: style === "windows12"
    readonly property bool isMacos: style === "macos"
    readonly property bool isMaterial: style === "material"

    readonly property SystemPalette systemPalette: SystemPalette {
        colorGroup: SystemPalette.Active
    }
    readonly property color seedColor: AppearanceConfigService.wallpaperSeedColor.a > 0
        ? AppearanceConfigService.wallpaperSeedColor : systemPalette.highlight
    readonly property bool systemIsDark: systemPalette.window.r * 0.2126
        + systemPalette.window.g * 0.7152
        + systemPalette.window.b * 0.0722 < 0.5
    // Explicit light/dark choices must override KDE; only "system" follows
    // SystemPalette.
    readonly property bool resolvedAppearanceIsDark:
        AppearanceConfigService.themeMode === "dark" ? true
        : AppearanceConfigService.themeMode === "light" ? false
        : systemIsDark
    // Material always follows the selected appearance so its Monet tonal
    // palette switches between distinct light and dark schemes. Glass can
    // independently stay in its dark, high-contrast presentation.
    readonly property bool isDarkTheme:
        tokens.isMaterial || AppearanceConfigService.glassFollowsAppearanceMode
            ? resolvedAppearanceIsDark : true

    // ────────────────────────────────────────────────────────────────
    // Wallpaper colour bridge
    // ────────────────────────────────────────────────────────────────
    // `WallpaperColorSource` lives in the shared Kos.Ui layer, which must not
    // import `qs.desktop.modules.*`. This adapter is the shell-side half of that
    // contract: it feeds the resolved light/dark branch in, and persists the
    // sampled seed colour back into shell configuration.
    //
    // The bridge is a direct child of this singleton so that instantiating
    // AppearanceTokens is enough to create it — a nested QtObject without a
    // consumer could otherwise be elided, leaving the sampler unwired.
    readonly property Connections _wallpaperRequest: Connections {
        target: tokens
        function onIsDarkThemeChanged() {
            WallpaperColorSource.darkMode = tokens.isDarkTheme
        }
    }

    readonly property Connections _wallpaperResult: Connections {
        target: WallpaperColorSource
        function onPaletteChanged(primary, secondary) {
            AppearanceConfigService.wallpaperSeedColor = primary
        }
        function onPaletteCleared() {
            AppearanceConfigService.wallpaperSeedColor = "transparent"
        }
    }

    // Fallback seed for the scheme until a wallpaper has been sampled. Using the
    // KDE accent keeps the very first frame on-palette instead of flashing a
    // hardcoded default; once the wallpaper resolves this is replaced by the
    // sampled colour via `_wallpaperResult`.
    readonly property Connections _seedFallback: Connections {
        target: tokens
        function onSeedColorChanged() {
            if (!WallpaperColorSource.ready)
                ColorScheme.setSeed(tokens.seedColor)
        }
    }

    // Which colour source feeds ColorScheme. The traditional tables are a
    // Material-style preference, so every other style stays on Monet and a
    // switch away from Material cannot restyle it.
    readonly property string resolvedColorScheme: tokens.isMaterial
        ? AppearanceConfigService.materialColorScheme : "monet"

    readonly property Connections _schemeSource: Connections {
        target: tokens
        function onResolvedColorSchemeChanged() {
            ColorScheme.setScheme(tokens.resolvedColorScheme)
        }
    }

    // Name of the traditional swatch the accent resolved to (e.g. "朱砂"), so
    // the settings page can show which colour was chosen. Empty under Monet and
    // for seeds that fell back to it.
    readonly property string materialAccentName: ColorScheme.accentName

    // Seed both halves of the pipeline as soon as this singleton loads: the
    // sampler needs the resolved light/dark branch, the scheme needs a starting
    // seed, and the colour source has to be selected before the first palette.
    //
    // These share one handler because QML allows only a single
    // Component.onCompleted per object — a second one is not an override, it is
    // a hard "Property value set multiple times" load error, and it surfaces
    // only at runtime: qmllint accepts it.
    Component.onCompleted: {
        WallpaperColorSource.darkMode = tokens.isDarkTheme
        ColorScheme.setScheme(tokens.resolvedColorScheme)
        ColorScheme.setSeed(tokens.seedColor)
        // Populate the deferred preview swatches once the seed/scheme calls
        // above have settled the first palette.
        _swatchTimer.restart()
    }

    function _mix(base, tint, amount, alpha) {
        return Qt.rgba(base.r + (tint.r - base.r) * amount,
            base.g + (tint.g - base.g) * amount,
            base.b + (tint.b - base.b) * amount,
            alpha === undefined ? 1.0 : alpha)
    }

    function _luminance(value) {
        return value.r * 0.2126 + value.g * 0.7152 + value.b * 0.0722
    }

    // How much accent the layer ladder mixes into each Material surface.
    //
    // Declared HERE, on the singleton itself, and not inside `colors` below —
    // which is not a style choice. An earlier revision put them inside the
    // nested `colors` QtObject while the layer properties referenced
    // `tokens._layerTint0`. That path does not resolve (it would have to be
    // `tokens.colors._layerTint0`), so the value was `undefined`, `_mix` did
    // `(tint.r - base.r) * undefined`, and every layer0..4 became
    // `Qt.rgba(NaN, NaN, NaN, 1)`. Invalid colours render as black, which
    // destroyed card legibility, and because a broken value is the same broken
    // value in every scheme, switching colour sources appeared to do nothing.
    // tests/traditional-color/run.mjs now asserts these resolve, so the failure
    // cannot come back silently.
    readonly property real _layerTint0: tokens.isDarkTheme ? 0.30 : 0.20
    readonly property real _layerTint1: tokens.isDarkTheme ? 0.26 : 0.17
    readonly property real _layerTint2: tokens.isDarkTheme ? 0.23 : 0.15
    readonly property real _layerTint3: tokens.isDarkTheme ? 0.20 : 0.13
    readonly property real _layerTint4: tokens.isDarkTheme ? 0.18 : 0.11

    // Mirrors ColorScheme.revision: one signal that fires whenever the palette
    // is rebuilt, for the Canvas consumers that only read colours while
    // painting. Their repaint lists covered the date, the metrics and the icon
    // tint, so a shell-style switch (material -> macos) or a colour-source
    // switch left them drawing the previous theme's colours.
    readonly property int colorRevision: ColorScheme.revision
    // One entry per colour source, each carrying representative swatches for the
    // settings page to draw its picker from. The page runs in a separate
    // process and cannot evaluate the scheme itself, so the swatches travel over
    // the appearance snapshot.
    //
    // Rebuilding this inline in the binding would run three buildSchemePair
    // calls (a full 49-role x 2-mode solve each) synchronously inside the
    // palette revision change — on the same stack that is already paying for
    // the active scheme. The preview does not feed anything the next frame
    // needs, so the rebuild is deferred one event-loop turn through a
    // zero-interval timer: the wallpaper switch finishes first, and the
    // swatches refresh a moment later. With the module-level memoization in
    // the scheme builders, the deferral is what keeps the *cold* rebuild off
    // the critical path.
    readonly property var colorSchemeSwatches: _colorSchemeSwatches
    property var _colorSchemeSwatches: []

    function _rebuildSwatches() {
        _colorSchemeSwatches = [
            { id: "monet", colors: ColorScheme.previewSwatches("monet") },
            { id: "chinese", colors: ColorScheme.previewSwatches("chinese") },
            { id: "japanese", colors: ColorScheme.previewSwatches("japanese") },
        ]
    }

    property Timer _swatchTimer: Timer {
        interval: 0
        onTriggered: tokens._rebuildSwatches()
    }

    // Palette revision covers every way the swatches can go stale: a new seed,
    // a scheme switch, a variant change. Restarting the timer coalesces the
    // bursts a rebuild produces (seed then revision fire together). The first
    // population is armed in the singleton's single Component.onCompleted above
    // — QML allows only one per object.
    onColorRevisionChanged: _swatchTimer.restart()
    readonly property QtObject colors: QtObject {
        readonly property color primary: ColorScheme.color("primary", tokens.isDarkTheme)
        readonly property color primaryForeground: ColorScheme.color("on_primary", tokens.isDarkTheme)
        readonly property color primaryContainer: ColorScheme.color("primary_container", tokens.isDarkTheme)
        readonly property color primaryContainerForeground: ColorScheme.color("on_primary_container", tokens.isDarkTheme)
        readonly property color secondary: ColorScheme.color("secondary", tokens.isDarkTheme)
        readonly property color secondaryForeground: ColorScheme.color("on_secondary", tokens.isDarkTheme)
        readonly property color secondaryContainer: ColorScheme.color("secondary_container", tokens.isDarkTheme)
        readonly property color secondaryContainerForeground: ColorScheme.color("on_secondary_container", tokens.isDarkTheme)
        readonly property color tertiary: ColorScheme.color("tertiary", tokens.isDarkTheme)
        readonly property color tertiaryContainer: ColorScheme.color("tertiary_container", tokens.isDarkTheme)
        readonly property color tertiaryContainerForeground: ColorScheme.color("on_tertiary_container", tokens.isDarkTheme)
        readonly property color background: ColorScheme.color("background", tokens.isDarkTheme)
        readonly property color surface: ColorScheme.color("surface", tokens.isDarkTheme)
        readonly property color surfaceContainerLow: ColorScheme.color("surface_container_low", tokens.isDarkTheme)
        readonly property color surfaceContainer: ColorScheme.color("surface_container", tokens.isDarkTheme)
        readonly property color surfaceContainerHigh: ColorScheme.color("surface_container_high", tokens.isDarkTheme)
        readonly property color surfaceContainerHighest: ColorScheme.color("surface_container_highest", tokens.isDarkTheme)
        // Layer ladder: each surface is its Material role tinted with the
        // accent. The tint is what makes the shell read as *this wallpaper*
        // rather than generic grey, and it has to be large enough to survive
        // the compositor: a tonal plate paints panelFill (layer1) at
        // panelOpacity 0.60, so 40% of any tint on it is replaced by the
        // blurred backdrop.
        //
        // These numbers were measured, not picked. At layer0 = 0.30 (dark) the
        // worst text contrast across 200 seeds x 2 schemes x 2 modes is 5.71:1,
        // still above the 4.5:1 requirement; the next step up (0.40) fell to
        // 4.0:1 and was rejected. The values below step down per elevation so
        // higher cards keep their ordering instead of converging on one tint.
        //
        // History worth keeping: light mode used to tint layer0 by 0.01 and
        // layer1-4 not at all, with the comment that "light surfaces use the
        // unmodified Material roles". The visible consequence was that
        // switching the colour source changed nothing a user could see — two
        // schemes produced #eefafe and #ecf5f0, both effectively white. The
        // tint is now meaningful in both appearances.
        readonly property color layer0: tokens._mix(background, primary,
            tokens._layerTint0)
        readonly property color layer1: tokens._mix(surfaceContainerLow, primary,
            tokens._layerTint1)
        readonly property color layer2: tokens._mix(surfaceContainer, primary,
            tokens._layerTint2)
        readonly property color layer3: tokens._mix(surfaceContainerHigh, primary,
            tokens._layerTint3)
        readonly property color layer4: tokens._mix(surfaceContainerHighest,
            primary, tokens._layerTint4)
        readonly property bool surfaceIsDark:
            tokens._luminance(surfaceContainer) < 0.48
        // QML reserves onXxx names for signal handlers, so foreground roles
        // use explicit, QML-safe names instead of Material's onSurface form.
        readonly property color surfaceForeground: ColorScheme.color("on_surface", tokens.isDarkTheme)
        readonly property color surfaceVariantForeground: ColorScheme.color("on_surface_variant", tokens.isDarkTheme)
        readonly property color outline: ColorScheme.color("outline", tokens.isDarkTheme)
        readonly property color outlineVariant: ColorScheme.color("outline_variant", tokens.isDarkTheme)
        readonly property color error: ColorScheme.color("error", tokens.isDarkTheme)
        readonly property color scrim: Qt.rgba(0, 0, 0,
            tokens.isDarkTheme ? 0.42 : 0.24)
    }

    readonly property QtObject shape: QtObject {
        // Matches the practical scale used by end4-pC: 6/8/12/17/23/30.
        readonly property real unsharpened: tokens.isMaterial ? 6 : 5
        readonly property real extraSmall: tokens.isMaterial ? 8 : 5
        readonly property real small: tokens.isMaterial ? 12 : 10
        readonly property real medium: tokens.isMaterial ? 17 : 14
        readonly property real large: tokens.isMaterial ? 23 : 20
        readonly property real extraLarge: tokens.isMaterial ? 30 : 26
        readonly property real full: 999
        // Corner continuity, not corner size: 2.0 is a circular arc and keeps
        // Rectangle.radius and today's compositor mask. Everything above it
        // sweeps the corner towards the continuous-curvature profile iOS uses,
        // which makes the corner fuller without moving where the straight edge
        // ends. The geometry lives in Squircle.mjs / SquircleMask.qml; this is
        // only the knob. 2.5-4 is the useful range, and the dial is easy to
        // read: the corner overhangs the circular arc by 2^(1/2-1/n) - 1 along
        // the diagonal, so 7% at 2.5, 12% at 3, 19% at 4 -- bigger n hugs the
        // corner tip harder, which reads as "squarer". The anti-aliasing band
        // does not widen with the exponent: test_squircle.mjs measures it, and
        // beyond that the only way to judge the shape is to look at a card.
        //
        // The 6.0 experiment settled it: the unblurred corner ring does scale
        // with the radius, and pushing the dial up revealed it on the music
        // popup and the window preview too, so every surface is on the same
        // path. Nothing in QML can close that gap -- the compositor replaces
        // whatever region we publish with a circle -- so the only fix left is
        // on the effect side.
        //
        // Surfaces that honour the token: the Dock pill itself, plus its Home
        // Indicator, music and window-preview popups and the trash
        // confirmation, plus the notification card (which carries its own
        // inline mask). The rest of the shell still draws Rectangle.radius.
        // Back at 2.0 every mask switches off and the corners are circular
        // again -- but the Dock pill is not the pre-token surface either way,
        // because it now carries a LiquidGlassPanel where the compositor used
        // to paint alone.
        readonly property real cornerExponent: 3.0
    }

    // Every shell surface consumes this policy rather than treating Material as
    // the only special case. New themes add their visual treatment here; views
    // keep their structure and ask only whether they need a backdrop or a
    // paint layer. Material retains its tonal paint layer, and separately
    // opts into a KWin blur region with no refraction.
    readonly property QtObject surface: QtObject {
        readonly property string treatment: tokens.isMaterial ? "tonal" : "glass"
        readonly property bool usesBackdrop: treatment !== "tonal"
        readonly property bool usesKwinBlur: usesBackdrop || tokens.isMaterial
        readonly property bool usesTonalRoles: treatment === "tonal"
        // ── Which surface a view instantiates, and who paints it ─────────────
        //
        // Views read these instead of branching on the shell style themselves,
        // so a new form is a row here rather than another `isMaterial` in every
        // card. The two are complements, and the complement is load-bearing:
        // a card that paints itself publishes no shape declaration, and one that
        // does not paint itself hands the finish to the compositor through a
        // declaration -- which is also what selects the compositor's material
        // (a declared shape gets the liquid finish, no declaration gets plain
        // frost). Changing one without the other makes the two forms drift.
        readonly property string cardBackend: usesTonalRoles ? "tonal" : "glass"
        readonly property bool paintInQml: usesTonalRoles
        // ── The tonal plate: one fill and one opacity ───────────────────────
        //
        // A tonal surface is a single plate, so every host has to agree on
        // both numbers or one role renders as two materials. It did: the
        // Dock's pill paints through LiquidGlassSurface (layer1 at 0.60) while
        // the standalone Bar hardcoded opacity 1.0 over layer0 -- so the Bar
        // matched the Dock exactly when it was fused into it, and stopped
        // matching the moment it was not. The pair is declared once here and
        // read by the Bar, the widget cards and the glass surface alike.
        //
        // Below 1.0 on purpose: a Material surface stays tonal *and*
        // translucent so the KWin blur behind it still reads through. At 1.0
        // the backdrop is hidden completely, which is what the Bar used to do.
        readonly property color panelFill: tokens.colors.layer1
        readonly property real panelOpacity: tokens.glass.materialOpacity
        readonly property color barFill: usesTonalRoles
            ? panelFill : "transparent"
        readonly property real barOpacity: usesTonalRoles ? panelOpacity : 0.0
        readonly property color widgetFill: usesTonalRoles
            ? panelFill : "transparent"
        readonly property real widgetOpacity: usesTonalRoles ? panelOpacity : 0.0
        // Card ink. A tonal card is a light plate and takes the scheme's own
        // foreground; a glass card is dark and takes white.
        readonly property color widgetForeground: usesTonalRoles
            ? tokens.colors.surfaceVariantForeground : Qt.rgba(1, 1, 1, 0.78)
        readonly property color outline: usesTonalRoles
            ? tokens.colors.outlineVariant : "transparent"

        // One role, two forms. Views hand over the pair instead of testing which
        // form is active, so the choice lives here with the rest of the policy --
        // `pick(tonal, glass)`.
        function pick(tonalValue, glassValue) {
            return tokens.isMaterial ? tonalValue : glassValue
        }
    }

    // ────────────────────────────────────────────────────────────────
    // Card content ink
    // ────────────────────────────────────────────────────────────────
    // What a widget draws *inside* its card. A card that lets a backdrop through
    // -- a glass card, or a tonal plate -- needs ink that reads against the
    // wallpaper; a colour-artwork card is its own solid backdrop and keeps the
    // widget's own colours. Content asks here and never tests the shell style,
    // so one drawing serves every form.
    readonly property QtObject content: QtObject {
        // True when the card has a backdrop behind it (a glass panel, or a tonal
        // plate). False only for a colour-artwork card in the glass form, where
        // the card paints its own gradient.
        readonly property bool onBackdrop: tokens.surface.paintInQml
            || AppearanceConfigService.widgetStyle === "glass"

        // Ink for shell chrome that always sits on the shell's own backdrop
        // (Bar, Dock, Control Centre, glass panels). Unlike ink() this never
        // falls back to a caller's artwork colour, because a control's glyph or
        // label is not the card's own picture. The material/glass branch is
        // shared with ink() rather than re-derived here, so a chrome glyph and
        // a card's own text can never disagree. `alpha` is optional.
        function glassInk(alpha) {
            return IconAppearanceService.glassContentColor(alpha)
        }

        // Ink over the backdrop, or the caller's own colour when the card is its
        // own artwork. `alpha` is optional and applies only to the ink.
        function ink(ownColor, alpha) {
            if (!onBackdrop)
                return ownColor
            return alpha === undefined
                ? IconAppearanceService.glassContentColor()
                : IconAppearanceService.glassContentColor(alpha)
        }

        // Emphasis for one semantic accent: the Material scheme's own role where
        // the tonal plate can carry it, otherwise the same rule as ink().
        function accent(materialColor, ownColor, alpha) {
            return tokens.isMaterial ? materialColor : ink(ownColor, alpha)
        }
    }

    readonly property QtObject state: QtObject {
        readonly property color hover: tokens._mix(tokens.colors.layer2,
            tokens.colors.surfaceForeground, 0.08)
        readonly property color pressed: tokens._mix(tokens.colors.layer2,
            tokens.colors.surfaceForeground, 0.12)
        readonly property color selected: tokens.colors.primaryContainer
        readonly property color disabled: Qt.rgba(tokens.colors.surfaceVariantForeground.r,
            tokens.colors.surfaceVariantForeground.g,
            tokens.colors.surfaceVariantForeground.b, 0.38)
    }

    readonly property QtObject typography: QtObject {
        readonly property string recommendedDisplayFamily: "SF Pro Display"
        readonly property bool hasRecommendedDisplayFamily:
            Qt.fontFamilies().indexOf(recommendedDisplayFamily) >= 0
        // An empty family delegates fallback to the user's Qt/KDE font setup.
        readonly property string displayFamily: hasRecommendedDisplayFamily
            ? recommendedDisplayFamily : ""
    }

    readonly property QtObject dock: QtObject {
        readonly property string form: tokens.isWindows12 ? "taskbar"
            : tokens.isMaterial ? "navigationDock" : "floatingDock"
        readonly property string position: "bottom"
        // Pill radius as a fraction of the Dock's height, so the cap keeps its
        // shape as the Dock grows. 0.5 is the ceiling that still means
        // something -- the cap becomes a half circle -- and both glass
        // styles are pinned to it; Windows 12 stays a taskbar, where a
        // full-round cap would be out of place.
        readonly property real radiusRatio: tokens.isWindows12 ? 0.20 : 0.50
        readonly property real horizontalPaddingRatio: tokens.isWindows12 ? 0.24
            : tokens.isMaterial ? 0.32 : 0.40
        readonly property real verticalPaddingRatio: tokens.isWindows12 ? 0.12
            : tokens.isMaterial ? 0.16 : 0.20
        readonly property real itemSpacingRatio: tokens.isWindows12 ? 0.07
            : tokens.isMaterial ? 0.08 : 0.09
        readonly property real dividerMarginRatio: tokens.isWindows12 ? 0.16
            : tokens.isMaterial ? 0.18 : 0.20
        readonly property int edgeMargin: tokens.isWindows12 ? 0
            : tokens.isMaterial ? 8 : 5
        // Match the float between the glass and the screen edge with an equal
        // visual breathing space between the glass and windows. DockWindow
        // applies this only while the Dock is permanently visible, so hidden
        // modes do not create an invisible spatial dead strip.
        readonly property int workspaceGap: edgeMargin
        readonly property string indicatorStyle: tokens.isWindows12 ? "underline"
            : tokens.isMaterial ? "tonal" : "dot"
        readonly property real indicatorLengthRatio: tokens.isWindows12 ? 0.42
            : tokens.isMaterial ? 0.34 : 0.13
        readonly property real indicatorThicknessRatio: tokens.isMacos ? 0.13 : 0.07
        readonly property real activeRadiusRatio: tokens.isWindows12 ? 0.18
            : tokens.isMaterial ? 0.28 : 0.30
        readonly property string activeBackgroundMode: tokens.isWindows12
            ? "subtle" : tokens.isMaterial ? "tonal" : "glass"
        readonly property bool magnificationEnabled: tokens.isMacos
        readonly property real hoverScale: tokens.isMacos ? 1.20 : 1.0
        readonly property real hoverLiftRatio: tokens.isMacos ? 0.08 : 0.0
        // The pointer influence is intentionally wider than one icon. Each
        // icon scales visually inside a fixed slot, so magnification never
        // changes the Dock's measured width.
        readonly property real magnificationRadius: tokens.isMacos ? 140 : 0
        readonly property real magnificationMaxScale: tokens.isMacos ? 1.19 : 1.0
        readonly property real magnificationLiftRatio: tokens.isMacos ? 0.04 : 0.0
    }

    readonly property QtObject bar: QtObject {
        // Bar keeps one visual language across shell styles. Integration is a
        // user choice, not an implicit Windows-theme side effect.
        readonly property string placement: "top"
        readonly property int height: 35
        readonly property int radius: 0
        readonly property string surfaceMode: "transparent"
        readonly property bool unifiedWithDock:
            AppearanceConfigService.barIntegratedWithDock
    }

    readonly property QtObject widget: QtObject {
        // The Material form's cards wear the scale's extra-large corner, which
        // is what makes a desktop card read as Material rather than as macOS:
        // the corner radius is a *scale* shared by every container, not a
        // shape per card. Its neighbours stay where they were.
        readonly property int radius: tokens.isWindows12 ? 12
            : tokens.isMaterial ? tokens.shape.extraLarge : tokens.shape.large
        readonly property int gap: tokens.isWindows12 ? 8
            : tokens.isMaterial ? 12 : 10
        readonly property int elevation: tokens.isWindows12 ? 2
            : tokens.isMaterial ? 3 : 1
        readonly property string surfaceMode: tokens.isWindows12 ? "acrylic"
            : tokens.isMaterial ? "tonal" : "glass"
        readonly property color surfaceColor: tokens.isMaterial
            ? tokens.colors.surfaceContainer : "transparent"
        readonly property color elevatedSurfaceColor: tokens.isMaterial
            ? tokens.colors.surfaceContainerHigh : "transparent"
    }

    readonly property QtObject glass: QtObject {
        readonly property real dockBlur: AppearanceConfigService.effectiveDockBlur
        readonly property real dockLiquid: AppearanceConfigService.effectiveDockLiquid
        readonly property real barBlur: AppearanceConfigService.effectiveBarBlur
        readonly property real barLiquid: AppearanceConfigService.effectiveBarLiquid
        readonly property real launcherBlur: AppearanceConfigService.effectiveLauncherBlur
        readonly property real launcherLiquid: AppearanceConfigService.effectiveLauncherLiquid
        readonly property real blurStrength: dockBlur
        readonly property real liquidStrength: dockLiquid
        readonly property real highlightMultiplier: tokens.isWindows12 ? 0.72
            : tokens.isMaterial ? 0.55 : 1.0
        readonly property real ambientMultiplier: tokens.isWindows12 ? 0.85
            : tokens.isMaterial ? 0.70 : 1.0
        // Keep Material surfaces visibly tonal while allowing the KWin blur to
        // read through them. Full opacity would hide the backdrop completely.
        readonly property real materialOpacity: tokens.isMaterial ? 0.60 : 1.0
        readonly property real borderOpacity: tokens.isMaterial ? 0.30 : 0.16
    }

    readonly property QtObject motion: QtObject {
        readonly property int fastDuration: tokens.isWindows12 ? 120
            : tokens.isMaterial ? 100 : 135
        readonly property int normalDuration: tokens.isWindows12 ? 180
            : tokens.isMaterial ? 220 : 200
        readonly property int slowDuration: tokens.isWindows12 ? 260
            : tokens.isMaterial ? 300 : 360
        readonly property int standardEasing: tokens.isMaterial
            ? Easing.OutQuart : Easing.OutCubic
        readonly property bool springEnabled: tokens.isMacos
        // Whether a popup plays its entrance at all. Currently the macOS form's
        // trait; a host asks this instead of naming the style.
        readonly property bool popupAnimatesOnShow: tokens.isMacos
        // Whether the shell draws the extra faces a form brings with it -- the
        // Dock clock's dial, for instance. Same reason as above.
        readonly property bool drawsFormDecorations: tokens.isMacos
        // Anchored popups share Launchpad's entrance rhythm: a short cubic
        // settle from 0.96 scale with a directional fade/translation.
        readonly property int popupOpenDuration: 150
        readonly property int popupCloseDuration: 140
        readonly property real popupStartScale: 0.96
        readonly property real popupAnchorOffset: 20
    }
}
