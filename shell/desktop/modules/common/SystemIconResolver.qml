pragma Singleton

import QtQuick
import Quickshell
import "ShellIconMap.mjs" as IconMap

// 系统图标主题解析通道 —— **仅供明确要求跟随系统主题的图标使用**。
//
// 默认路径是 BundledIcons（shell 自带一套图案，任何机器上一致）。只有少数
// 刻意要求"跟随用户图标主题"的地方才调本文件，例如 Dock 回收站和桌面文件类型。
//
// Consumers ask for a role instead of embedding a Font Awesome glyph, an SVG
// path, or a theme-specific filename. Candidate names follow the freedesktop /
// KDE naming conventions and are resolved by the active system icon theme.
// IconThemeReloadService publishes a revision when that theme changes, so no
// component needs to watch kdeglobals independently.
QtObject {
    id: resolver

    function candidates(role, state) { return IconMap.themeCandidates(role, state) }

    function networkCandidates(connectionType, deviceState, signalStrength, limited) {
        return IconMap.networkCandidates(connectionType, deviceState, signalStrength, limited)
    }

    function nameFromCandidates(candidateNames, fallbackName) {
        const values = typeof candidateNames === "string"
            ? [candidateNames] : (candidateNames || [])
        for (let index = 0; index < values.length; ++index) {
            const name = String(values[index] || "").trim()
            if (name && Quickshell.hasThemeIcon(name))
                return name
        }
        const fallback = String(fallbackName || "image-missing").trim()
        return fallback && Quickshell.hasThemeIcon(fallback) ? fallback : ""
    }

    function sourceFromCandidates(candidateNames, fallbackName) {
        const name = nameFromCandidates(candidateNames, fallbackName)
        return name ? (Quickshell.iconPath(name, true) || "") : ""
    }

    function source(role, state) {
        return sourceFromCandidates(candidates(role, state), "image-missing")
    }
}
