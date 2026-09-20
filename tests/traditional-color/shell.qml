import QtQuick
import "Kos/Ui"
import qs.desktop.modules.common

// Smoke host for the traditional-colour scheme, loaded offscreen by run.mjs.
//
// The node suite in test_traditional_color.mjs proves the algorithm. What it
// cannot cover is whether the QML engine can load this module graph at all:
// ColorScheme.qml imports TraditionalColorScheme.mjs by relative path, and that
// module in turn imports ChineseColors.mjs, JapaneseColors.mjs, Cam16Hct.mjs and
// MaterialColorScheme.mjs. Under Node those resolve as ESM; under QML the QML
// module system resolves them, and a file missing from that graph is a runtime
// failure that neither the Node suite nor qmllint would catch. That is what this
// fixture is for — not the colour maths, the wiring.
Item {
    id: root

    width: 10
    height: 10

    property var failures: []

    // Probe: how the shell actually consumes ColorScheme — through a property
    // BINDING, not by calling color() again. Every other assertion in this file
    // and in the node suite calls color() explicitly, which returns the fresh
    // value regardless of whether binding propagation works. This is the one
    // thing that decides whether a scheme switch reaches the UI.
    property color probePrimary: ColorScheme.color("primary", false)
    property color probeSurface: ColorScheme.color("surface", false)


    function check(label, condition) {
        if (!condition)
            root.failures.push(label)
    }

    Component.onCompleted: {
        const schemes = ["monet", "chinese", "japanese"]
        const seed = "#e60012"

        check("ColorScheme singleton is reachable through Kos.Ui",
            typeof ColorScheme !== "undefined")
        check("setScheme exists", typeof ColorScheme.setScheme === "function")
        check("accentName is exposed",
            typeof ColorScheme.accentName === "string")

        ColorScheme.setSeed(seed)
        check("seed accepted and normalised", ColorScheme.seed === seed)

        const accents = ({})
        for (const scheme of schemes) {
            ColorScheme.setScheme(scheme)
            check(scheme + " is selected", ColorScheme.scheme === scheme)
            check(scheme + " reports ready", ColorScheme.ready === true)
            // 49 roles + source_color, the shape every shell consumer reads.
            check(scheme + " produces 50 entries",
                Object.keys(ColorScheme.palette).length === 50)
            for (const role of ["primary", "on_primary", "primary_container",
                "secondary", "tertiary", "error", "surface", "on_surface",
                "outline", "background"]) {
                const light = String(ColorScheme.color(role, false))
                const dark = String(ColorScheme.color(role, true))
                check(scheme + " " + role + ":light resolves",
                    /^#[0-9a-f]{6,8}$/i.test(light))
                check(scheme + " " + role + ":dark resolves",
                    /^#[0-9a-f]{6,8}$/i.test(dark))
            }
            accents[scheme] = String(ColorScheme.color("primary", false))
        }

        // If a traditional table returned Monet's accent the setting would be a
        // no-op that still costs the user a choice.
        check("chinese accent differs from monet",
            accents.chinese !== accents.monet)
        check("japanese accent differs from monet",
            accents.japanese !== accents.monet)

        ColorScheme.setScheme("chinese")
        check("a matched seed reports its swatch name",
            ColorScheme.accentName.length > 0)

        ColorScheme.setScheme("monet")
        check("monet reports no swatch name",
            ColorScheme.accentName === "")

        // ── binding propagation ──────────────────────────────────────────
        // A bound property must re-evaluate when the palette is rebuilt; if it
        // does not, the scheme switch never reaches a consumer.
        ColorScheme.setSeed("#4a4a6a")
        ColorScheme.setScheme("monet")
        const boundMonet = String(root.probePrimary)
        const boundSurfaceMonet = String(root.probeSurface)
        ColorScheme.setScheme("chinese")
        const boundChinese = String(root.probePrimary)
        const boundSurfaceChinese = String(root.probeSurface)
        check("bound primary follows setScheme (monet " + boundMonet
            + " vs chinese " + boundChinese + ")", boundMonet !== boundChinese)
        check("bound surface follows setScheme (monet " + boundSurfaceMonet
            + " vs chinese " + boundSurfaceChinese + ")",
            boundSurfaceMonet !== boundSurfaceChinese)
        console.log("BINDING_PROBE monet=" + boundMonet + "/" + boundSurfaceMonet
            + " chinese=" + boundChinese + "/" + boundSurfaceChinese)

        // ColorScheme.revision is what Canvas consumers repaint on; if it stops
        // moving, a theme switch or colour-source switch leaves stale drawings
        // — which is exactly what happened to the clock hands and the CPU ring.
        ColorScheme.setScheme("monet")
        const revisionBefore = ColorScheme.revision
        ColorScheme.setScheme("chinese")
        check("revision bumps when the palette is rebuilt",
            ColorScheme.revision > revisionBefore)

        // ── layer ladder ─────────────────────────────────────────────────
        // AppearanceTokens tints each Material surface with the accent, and the
        // ratios live on the singleton itself. An earlier revision declared
        // them inside the nested `colors` object while referencing
        // `tokens._layerTint0` — an unresolvable path, so the ratio came back
        // undefined and every layer became Qt.rgba(NaN, NaN, NaN, 1). Invalid
        // colours paint black: cards turned illegible, and because a broken
        // value is the same broken value under every scheme, switching colour
        // sources looked like a no-op. Both symptoms are asserted against here,
        // and neither is visible to the node suite or to qmllint.
        check("layer tint ratios resolve",
            AppearanceTokens._layerTint0 > 0 && AppearanceTokens._layerTint1 > 0
            && AppearanceTokens._layerTint2 > 0 && AppearanceTokens._layerTint3 > 0
            && AppearanceTokens._layerTint4 > 0)

        ColorScheme.setScheme("monet")
        const layersMonet = [AppearanceTokens.colors.layer0,
            AppearanceTokens.colors.layer1, AppearanceTokens.colors.layer2,
            AppearanceTokens.colors.layer3,
            AppearanceTokens.colors.layer4].map(c => String(c))
        ColorScheme.setScheme("chinese")
        const layersChinese = [AppearanceTokens.colors.layer0,
            AppearanceTokens.colors.layer1, AppearanceTokens.colors.layer2,
            AppearanceTokens.colors.layer3,
            AppearanceTokens.colors.layer4].map(c => String(c))
        for (let i = 0; i < 5; i++) {
            check("layer" + i + " is a valid colour under monet ("
                + layersMonet[i] + ")",
                /^#[0-9a-f]{6,8}$/i.test(layersMonet[i]))
            check("layer" + i + " is a valid colour under chinese ("
                + layersChinese[i] + ")",
                /^#[0-9a-f]{6,8}$/i.test(layersChinese[i]))
            check("layer" + i + " follows the colour source",
                layersMonet[i] !== layersChinese[i])
        }

        // ── the tonal plate ──────────────────────────────────────────────
        // The Bar paints a plain Rectangle while the Dock's pill paints through
        // LiquidGlassSurface, so the two hosts reach the plate by different
        // code paths. They have to land on the same fill and the same opacity,
        // or fusing the Bar into the Dock changes the Bar's colour. That is
        // what shipped: the Dock painted layer1 at 0.60, the Bar layer0 at
        // 1.00, so a Bar matched the Dock only while it was fused into it.
        const previousStyle = AppearanceConfigService.shellStyle
        AppearanceConfigService.shellStyle = "material"
        check("Material resolves as the tonal treatment",
            AppearanceTokens.surface.usesTonalRoles === true)
        check("the Bar and the Dock share one plate fill",
            String(AppearanceTokens.surface.barFill)
                === String(AppearanceTokens.surface.panelFill))
        check("the Bar and the Dock share one plate opacity",
            AppearanceTokens.surface.barOpacity
                === AppearanceTokens.surface.panelOpacity)
        check("widget cards share the same plate",
            String(AppearanceTokens.surface.widgetFill)
                === String(AppearanceTokens.surface.panelFill)
            && AppearanceTokens.surface.widgetOpacity
                === AppearanceTokens.surface.panelOpacity)
        check("the plate is the tinted container role, not a bare surface",
            String(AppearanceTokens.surface.panelFill)
                === String(AppearanceTokens.colors.layer1))
        // Translucent on purpose: at 1.0 the KWin blur behind a Material
        // surface is hidden completely, which is what the Bar used to do.
        check("the plate stays translucent ("
            + AppearanceTokens.surface.panelOpacity + ")",
            AppearanceTokens.surface.panelOpacity > 0
            && AppearanceTokens.surface.panelOpacity < 1)

        // Glass forms keep their own treatment: no plate at all, so a Bar in a
        // glass style stays as transparent as the layout asks for.
        AppearanceConfigService.shellStyle = "macos"
        check("a glass form paints no plate for the Bar",
            AppearanceTokens.surface.barOpacity === 0
            && AppearanceTokens.surface.barFill.a === 0)
        AppearanceConfigService.shellStyle = previousStyle

        // ── wallpaper config parsing ─────────────────────────────────────
        // The wallpaper URL sits upstream of every colour asserted above: if it
        // stops moving, the seed stops moving and all three colour sources
        // freeze together — which is exactly how it shipped. Plasma keeps one
        // `[Wallpaper][<plugin>][General]` block per plugin that has ever been
        // configured, and the retired ones keep their keys. A parser that does
        // not reset its cursor on unrecognised headers attributes the slideshow
        // plugin's `Image=` to the image block and overwrites the real
        // wallpaper, so the resolved URL never changes.
        const plasmaConfig = [
            "[Containments][55]",
            "lastScreen=0",
            "wallpaperplugin=org.kde.image",
            "",
            "[Containments][55][Wallpaper][org.kde.image][General]",
            "Image=/home/user/wallpapers/real.jpeg",
            "SlidePaths=/usr/share/wallpapers/",
            "",
            "[Containments][55][Wallpaper][org.kde.potd][General]",
            "FillMode=1",
            "",
            "[Containments][55][Wallpaper][org.kde.slideshow][General]",
            "Image=file:///home/user/wallpapers/stale.jpg",
            "",
            "[Containments][89]",
            "lastScreen=1",
            "wallpaperplugin=org.kde.image",
            "",
            "[Containments][89][Wallpaper][org.kde.image][General]",
            "Image=/home/user/wallpapers/second.jpeg",
            "",
        ].join("\n")

        const parsed = WallpaperColorSource._parseWallpaperConfig(plasmaConfig)
        const imageBlock = parsed.wallpapers["55"] || ({})
        check("the image block keeps its own wallpaper ("
            + imageBlock["org.kde.image"] + ")",
            imageBlock["org.kde.image"] === "/home/user/wallpapers/real.jpeg")
        check("the slideshow block keeps its own wallpaper",
            imageBlock["org.kde.slideshow"]
                === "file:///home/user/wallpapers/stale.jpg")
        check("an unrecognised block keeps nothing",
            imageBlock["org.kde.potd"] === undefined)
        check("screen 0 resolves to the image plugin's wallpaper",
            WallpaperColorSource._pickWallpaperUrl(parsed, 0)
                === "/home/user/wallpapers/real.jpeg")
        check("screen 1 resolves to its own containment",
            WallpaperColorSource._pickWallpaperUrl(parsed, 1)
                === "/home/user/wallpapers/second.jpeg")

        // The user-visible symptom: pick a new wallpaper, get the same colours
        // because this string never changed.
        const afterChange = plasmaConfig.replace(
            "/home/user/wallpapers/real.jpeg", "/home/user/wallpapers/new.png")
        check("changing the wallpaper changes the resolved URL",
            WallpaperColorSource._pickWallpaperUrl(
                WallpaperColorSource._parseWallpaperConfig(afterChange), 0)
                === "/home/user/wallpapers/new.png")

        // Switching plugins must follow the plugin, not the hardcoded name.
        const slideshowActive = plasmaConfig.replace(
            "wallpaperplugin=org.kde.image", "wallpaperplugin=org.kde.slideshow")
        check("an active slideshow plugin resolves to its own image",
            WallpaperColorSource._pickWallpaperUrl(
                WallpaperColorSource._parseWallpaperConfig(slideshowActive), 0)
                === "file:///home/user/wallpapers/stale.jpg")

        // ── which applets config is live ─────────────────────────────────
        // Fixing the parser above is not enough on its own: the *file* the
        // parser reads is not a constant either. Plasma names it after the
        // session's shell package (`plasmashellrc [Shell] ShellPackage`), and
        // the KOS lock screen makes `kosctl` point that key at its own package.
        // The desktop wallpapers then move to `plasma-org.kos.desktop-appletsrc`
        // and the hardcoded KDE filename becomes a file nobody writes — the URL
        // stays put, nothing is re-sampled, all three sources freeze again.
        check("ShellPackage is read from the [Shell] group",
            WallpaperColorSource._parseShellPackage(
                "[PlasmaViews][Panel 122]\nShellPackage=org.kde.plasma.desktop\n"
                + "[Shell]\nShellPackage=org.kos.desktop\n") === "org.kos.desktop")
        check("a ShellPackage key outside [Shell] is ignored",
            WallpaperColorSource._parseShellPackage(
                "[Other]\nShellPackage=org.example\n") === "")
        check("a missing ShellPackage parses as empty",
            WallpaperColorSource._parseShellPackage("[Shell]\n") === "")

        const configDirectory = WallpaperColorSource.configDirectory
        const kdeConfigPath = configDirectory
            + "/plasma-org.kde.plasma.desktop-appletsrc"
        WallpaperColorSource._applyShellPackage("org.kos.desktop")
        check("the session's shell package wins the applets config ("
            + WallpaperColorSource.configPath + ")",
            WallpaperColorSource.configPath
                === configDirectory + "/plasma-org.kos.desktop-appletsrc")
        check("the KDE config stays as the fallback candidate",
            WallpaperColorSource.configCandidates.length === 2
            && WallpaperColorSource.configCandidates[1] === kdeConfigPath)
        WallpaperColorSource._fallBackToNextConfig("missing")
        check("a named config that is not there yet falls through",
            WallpaperColorSource.configPath === kdeConfigPath
            && WallpaperColorSource.configCandidateIndex === 1)
        // The uninstall path: kosctl deletes the key, so the KDE file returns.
        WallpaperColorSource._applyShellPackage("")
        check("no shell package leaves the KDE config in charge",
            WallpaperColorSource.configPath === kdeConfigPath
            && WallpaperColorSource.configCandidates.length === 1)

        // Back to the default so the assertions above cannot have left the
        // singleton in a state the next load would inherit.
        ColorScheme.setScheme("monet")
        ColorScheme.setSeed("#64c4d4")
    }

    // Let the palette rebuilds above settle into the scene graph before the
    // verdict, so a binding error raised by them is reported as a failure.
    Timer {
        interval: 300
        running: true
        onTriggered: {
            if (root.failures.length > 0)
                console.error("TRADITIONAL_COLOR_FAIL: "
                    + root.failures.join("; "))
            else
                console.log("TRADITIONAL_COLOR_PASS")
            Qt.quit()
        }
    }

    Timer {
        interval: 6000
        running: true
        onTriggered: {
            console.error("TRADITIONAL_COLOR_FAIL: timeout")
            Qt.quit()
        }
    }
}
