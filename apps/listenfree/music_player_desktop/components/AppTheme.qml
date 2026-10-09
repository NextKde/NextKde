pragma Singleton

import QtQuick

QtObject {
    id: theme

    function artworkUrl(source, pixels) {
        let url = String(source || "")
        if (url.indexOf("image://artwork/") === 0) url = decodeURIComponent(url.substring(16))
        const size = Math.min(2048, pixels)
        if (/music\.126\.net/.test(url)) {
            if (/([?&])param=/.test(url)) url=url.replace(/([?&])param=[^&]+/, "$1param="+size+"y"+size)
            else url += (url.indexOf("?")>=0 ? "&" : "?")+"param="+size+"y"+size
        } else if (/y\.gtimg\.cn/.test(url)) {
            // QQ serves fixed CDN variants, not arbitrary decoder dimensions.
            // Round up so high-DPI thumbnails retain their requested detail.
            const supported = [90, 150, 300, 500, 800]
            const remoteSize = supported.find(value => value >= size) || 800
            url=url.replace(/T002R\d+x\d+M/,"T002R"+remoteSize+"x"+remoteSize+"M")
        }
        else if (/kuwo\.cn/.test(url)) url=url.replace(/(\/albumcover\/)\d+\//,"$1"+Math.min(500,size)+"/")
        else if (/kugou\.com/.test(url)) url=url.replace(/(\/stdmusic\/)\d+\//,"$1"+Math.min(480,size)+"/")
        return textureUrl(url)
    }
    function textureUrl(source) {
        const url = String(source || "")
        return typeof backendArtworkTextures !== "undefined" && backendArtworkTextures && /^https?:\/\//.test(url)
            ? "image://artwork/" + encodeURIComponent(url) : url
    }
    function artworkPixels(tier, dpr) {
        const sizes = { Thumbnail: 64, Small: 128, Medium: 320, Large: 640, XLarge: 1024, Hero: 1600 }
        return Math.min(2400, Math.ceil((sizes[tier] || sizes.Medium) * Math.max(1, dpr)))
    }
    property var currentPopup: null
    readonly property real expandedPlayerCornerRadius: 18
    readonly property real playerEdgeMargin: 14
    // Equal side/bottom insets keep the window and expanded island concentric.
    readonly property real normalWindowCornerRadius: expandedPlayerCornerRadius + playerEdgeMargin
    property real windowCornerRadius: normalWindowCornerRadius
    readonly property real toolbarHeight: 58
    readonly property real toolbarControlHeight: 32
    readonly property var playbackModes: [
        {mode: "listLoop", kind: "repeat", label: qsTr("列表循环")},
        {mode: "singleLoop", kind: "repeatOne", label: qsTr("单曲循环")},
        {mode: "shuffle", kind: "shuffle", label: qsTr("随机播放")},
        {mode: "endless", kind: "infinity", label: qsTr("无尽模式")},
        {mode: "stopAfterCurrent", kind: "stop", label: qsTr("播完当前停止")}
    ]
    function playbackModeInfo(mode) { return playbackModes.find(item => item.mode === mode) || playbackModes[0] }
    function presentPopup(popup) {
        if (currentPopup && currentPopup !== popup) currentPopup.close()
        currentPopup = popup
    }
    function closePopup() { if (currentPopup) currentPopup.close(); currentPopup = null }
    property bool darkMode: false
    readonly property color albumShellTint: darkMode ? "#b147535d" : "#8a777f84"
    readonly property color albumWindowTint: darkMode ? "#bd303b45" : "#b24e5962"
    property bool darkArtworkCanvas: false
    readonly property bool canvasDark: darkArtworkCanvas || (typeof backendBackgroundContrast !== "undefined" && backendBackgroundContrast ? backendBackgroundContrast.dark : darkMode)
    readonly property color canvasText: canvasDark ? "#f9fbff" : "#20262b"
    readonly property color canvasSecondary: canvasDark ? "#d4dce5" : "#4e5864"
    readonly property color canvasSelected: canvasDark ? "#28ffffff" : "#50ffffff"
    readonly property color canvasHover: canvasDark ? "#12ffffff" : "#24ffffff"
    // A thin tint preserves the artwork's hue. Adapt foregrounds to the
    // background instead of turning the sidebar into a heavy white panel.
    readonly property color sidebarSurface: darkMode ? "#1f141c24" : "#24ffffff"
    readonly property color sidebarText: canvasText
    readonly property color sidebarSecondary: canvasSecondary
    readonly property color sidebarSelected: canvasDark ? "#26ffffff" : "#38ffffff"
    readonly property color sidebarHover: canvasDark ? "#10ffffff" : "#18ffffff"

    // Segoe UI Variable has no CJK glyphs in Qt's off-screen renderer and
    // produces tofu boxes in Chinese. YaHei UI keeps the Windows look while
    // covering both interface languages consistently.
    property string fontFamily: "Microsoft YaHei UI"

    // Global motion tokens.  Settings or the backend may update the first two;
    // every visible animation derives its effective duration from here.
    property bool motionEnabled: true
    property string motionStyle: "Elegant"
    readonly property real motionScale: motionStyle === "Bright" ? 0.72 : 1.0

    function duration(baseMs) {
        return motionEnabled ? Math.max(0, Math.round(Number(baseMs) * motionScale)) : 0
    }

    readonly property color accent: darkMode ? "#b5bdc5" : "#58636d"
    readonly property color actionSurface: canvasDark ? "#24ffffff" : "#18606a74"
    readonly property color actionHover: canvasDark ? "#38ffffff" : "#29606a74"
    readonly property color actionPressed: canvasDark ? "#50ffffff" : "#40606a74"
    readonly property color actionBorder: canvasDark ? "#24ffffff" : "#16606a74"
    readonly property color pageBackground: darkMode ? "#171d23" : "#f5f6f8"
    readonly property color contentBackground: darkMode ? "#1d242b" : "#eef1f3"
    readonly property color sidebarStart: darkMode ? "#2b333b" : "#e7edf3"
    readonly property color sidebarEnd: darkMode ? "#222a31" : "#e3eaf1"
    readonly property color topBarStart: darkMode ? "#303943" : "#f8fafc"
    readonly property color topBarEnd: darkMode ? "#252d35" : "#f0f3f7"
    readonly property color textPrimary: darkMode ? "#f3f6f8" : "#20262b"
    readonly property color textSecondary: darkMode ? "#bdc6cd" : "#68747c"
    readonly property color textMuted: darkMode ? "#89959f" : "#858d93"
    readonly property color card: darkMode ? "#e629323a" : "#dff7f8f9"
    readonly property color cardStrong: darkMode ? "#f02d3740" : "#f2ffffff"
    readonly property color control: darkMode ? "#b937424c" : "#c8f6f6f6"
    readonly property color controlHover: darkMode ? "#e0495661" : "#efffffff"
    readonly property color tabSelected: darkMode ? "#d4434f59" : "#d9f7f8fa"
    readonly property color selected: darkMode ? "#30ffffff" : "#22000000"
    readonly property color border: darkMode ? "#56ffffff" : "#8fffffff"
    readonly property color divider: darkMode ? "#2effffff" : "#26000000"
    readonly property color floatingSurface: darkMode ? "#ee2b343d" : "#e9ffffff"
    readonly property color scrim: darkMode ? "#86101519" : "#5c13191d"
    readonly property color field: darkMode ? "#cf222a32" : "#e9ffffff"
    readonly property color fieldBorder: darkMode ? "#58ffffff" : "#b9d7e3ec"
}
