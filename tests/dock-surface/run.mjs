import assert from "node:assert/strict";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

// Exercise DockWindow's shipping bindings offscreen. Replace only the
// layer-shell boundary with a QQuickWindow; the geometry, region aggregation,
// glass visibility and input mask remain the actual source. This checks what
// we submit to the compositor, not KWin's rendering of the submitted regions.
const repository = fileURLToPath(new URL("../..", import.meta.url));
const directory = mkdtempSync(join(tmpdir(), "kos-dock-surface-"));
function module(name, files) {
    const path = join(directory, "desktop/modules", name);
    mkdirSync(path, { recursive: true });
    const entries = [`module qs.desktop.modules.${name}`];
    for (const [type, body] of Object.entries(files)) {
        const singleton = body.startsWith("pragma Singleton");
        writeFileSync(join(path, `${type}.qml`), body);
        entries.push(`${singleton ? "singleton " : ""}${type} 1.0 ${type}.qml`);
    }
    writeFileSync(join(path, "qmldir"), entries.join("\n") + "\n");
}
const object = body => `pragma Singleton\nimport QtQuick\nQtObject { ${body} }\n`;
try {
    const source = readFileSync(join(repository, "shell/desktop/modules/dock/DockWindow.qml"), "utf8");
    const window = source.replace('import "../../../Kos/Ui"', "import QtQuick.Window")
        .replace(/^import qs\.desktop\.modules\.(deskcenter|platform)\n/gm, "")
        .replace("PanelWindow {", "Window {")
        .replace(/^    WlrLayershell\.namespace:.*\n/m, "")
        .replace(/^    exclusionMode:.*\n/m, "")
        .replace(/^    WlrLayershell\.layer:[\s\S]*?WlrLayer\.Top\n/m, "")
        .replace("    anchors: ({", "    property var testAnchors: ({")
        .replace(/^    margins \{.*\}\n/m, "")
        .replace("    exclusiveZone:", "    property real exclusiveZone:")
        .replace("    implicitWidth:", "    property real implicitWidth:")
        .replace("    implicitHeight:", "    property real implicitHeight:")
        .replace("    BackgroundEffect.blurRegion:", "    property var testBlurRegion:")
        .replace("    mask: Region {", "    property Region testMask: Region {")
        .replace("    id: root", `    id: root
    width: vertical ? implicitWidth : 1000
    height: vertical ? 1000 : implicitHeight
    readonly property alias testContainer: dockContainer
    readonly property alias testController: hide
    readonly property alias testPill: pill
    readonly property alias testHandle: revealHandle
    readonly property alias testRegions: dockBlurRegionHolder`);
    module("dock", {
        DockWindow: window,
        ConfigService: object(`property string dockStyle: "floating"; property string visibilityMode: "always"
            property bool showRevealIndicator: true
            property bool ready: true; property int barHeight: 35`),
        DockContainer: `import QtQuick
Item {
    property var targetScreen; property real surfaceOriginX; property real surfaceOriginY
    property Component leadingAccessory; property Component trailingAccessory
    property bool clockInInfoCarousel; property bool pointerInside: false; property bool editMode: false
    property var draggedPinnedLoader: null; property real pillRadius: 28
    width: 56; height: 900
}`,
        DockAutoHideController: `import QtQuick
Item {
    property string mode; property bool configReady; property bool windowDataReady
    property string position; property var targetScreen
    property real dockWidth; property real dockHeight; property real edgeMargin
    property bool pointerInsideDock; property bool editing; property bool dragging
    property bool popupOpen; property bool launcherOpen
    property real revealProgress: 1; property real offsetX: 0; property real offsetY: 0
    property real dockOpacity: 1; property real dockScale: 1; property real handleOpacity: 0
    property bool handleActive: false; property string phase: "Shown"
    function handleEntered() {} function handleExited() {} function handleClicked() {}
    function requestReveal(reason, duration) {}
}`,
        DockModelService: object("property var activeDockPopup: null; signal urgentWindowAppeared()"),
        WindowService: object("property bool providerReady: true"),
        DockAnimation: object("property int smartHideUrgentRevealMs: 2200"),
        ThemeService: object('property color backgroundColor: "black"'),
        DockRevealHandle: readFileSync(join(repository, "shell/desktop/modules/dock/DockRevealHandle.qml"), "utf8"),
    });
    copyFileSync(join(repository, "shell/desktop/modules/dock/DockRevealGeometry.mjs"),
        join(directory, "desktop/modules/dock/DockRevealGeometry.mjs"));
    const glass = readFileSync(join(repository, "tests/dock-reveal/fixtures/LiquidGlassPanel.qml"), "utf8")
        .replace("import QtQuick", "import QtQuick\nimport Quickshell")
        .replace("property var blurRegion: null", "property Region blurRegion: Region {}");
    module("common", {
        LiquidGlassPanel: glass,
        AppearanceTokens: object(`property var surface: ({ usesKwinBlur: true, usesBackdrop: true })
            property var glass: ({ ambientMultiplier: 1 })`),
        AppearanceConfigService: object(`property real effectiveDockBlur: 1
            property real effectiveDockLiquid: 1; property bool barIntegratedWithDock: false`),
        WorkspaceLayoutService: object("function updateDock(screen, position, rect, margin) {}"),
    });
    module("applauncher", {
        AppLauncherService: object("property bool open: false"),
        AppLauncherConfigService: object('property string displayMode: "bottom"'),
    });
    module("wallpaper", {
        WallpaperColorSource: object('property color primary: "black"; property color secondary: "black"'),
        ThemeWallpaperService: object("property bool active: false; function setDockRect(screen, rect) {}"),
    });
    copyFileSync(new URL("shell.qml", import.meta.url), join(directory, "shell.qml"));
    const result = spawnSync(process.argv[2] || "quickshell", ["-p", directory], {
        encoding: "utf8", timeout: 6000,
        env: { ...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software",
            WAYLAND_DISPLAY: "", DISPLAY: "" },
    });
    const output = (result.stdout || "") + (result.stderr || "");
    assert.equal(result.error, undefined, String(result.error));
    assert.equal(result.status, 0, output);
    assert.doesNotMatch(output, /FAIL |ReferenceError|TypeError|Binding loop|is not a type|Cannot assign|Unable to assign/, output);
    assert.match(output, /DOCK_SURFACE_PASS/, output);
    console.log("Dock surface: proportional side margins, workspace reservation and hidden/shown glass declarations passed");
} finally {
    rmSync(directory, { recursive: true, force: true });
}
