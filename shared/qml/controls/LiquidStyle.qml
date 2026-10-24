pragma Singleton
import QtQuick

QtObject {
    property var _backdrops: []

    // §5 输入/搜索焦点补充：焦点外环颜色回退（系统 accent 无彩或明度越界时用）。
    readonly property color focusFallback: "#3478f6"

    // §5 焦点外环取色：accent 全透明、无彩（RGB max-min < .08）或 HSL 明度
    // （按 (max+min)/2 计）越出 [.25,.85] 时回退 focusFallback。
    function focusColor(accent) {
        if (!accent || accent.a <= 0) return focusFallback
        const max = Math.max(accent.r, accent.g, accent.b)
        const min = Math.min(accent.r, accent.g, accent.b)
        if (max - min < 0.08) return focusFallback
        const lightness = (max + min) / 2
        if (lightness < 0.25 || lightness > 0.85) return focusFallback
        return accent
    }

    function registerBackdrop(backdrop) {
        _backdrops = _backdrops.concat([backdrop])
    }

    function unregisterBackdrop(backdrop) {
        _backdrops = _backdrops.filter(item => item !== backdrop)
    }

    function backdropFor(window) {
        if (!window) return null
        for (let index = _backdrops.length - 1; index >= 0; --index) {
            const backdrop = _backdrops[index]
            if (backdrop && backdrop.registerAsDefault && backdrop.available
                    && backdrop.hostWindow === window)
                return backdrop
        }
        return null
    }
}
