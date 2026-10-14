pragma Singleton

import QtQuick
import Quickshell
import "../../../shared/qml/i18n"

// 界面语言的持久化与应用。Settings 应用通过 i18n-settings IPC 目标
// （见 DesktopEnvironment.qml）读写这里；值落在 <state>/i18n/language.json，
// 启动时读回并写入共享的 I18n 单例，所有 I18n.tr() 绑定随之刷新。
// 持久值可以是 "auto"（跟随系统语言，每次启动时解析）或具体语言。
QtObject {
    id: service

    // 持久值："auto" | "zh-CN" | "en"
    property string language: "zh-CN"
    // 应用到 I18n 单例的生效值（auto 已解析）。
    readonly property string effectiveLanguage:
        language === "auto" ? systemLanguage() : language
    property bool loaded: false

    readonly property string _stateDir: Quickshell.stateDir + "/i18n"

    // 系统语言解析：zh* -> zh-CN，其余一律 en。uiLanguages 为空时保持 zh-CN
    // （与历史默认一致，避免意外切成英文）。
    function systemLanguage() {
        const tags = Qt.locale().uiLanguages || []
        for (let i = 0; i < tags.length; ++i)
            if (/^zh/i.test(String(tags[i]))) return "zh-CN"
        return tags.length > 0 ? "en" : "zh-CN"
    }

    Component.onCompleted: {
        JsonConfigStore.read(_stateDir, "language.json", function(data, exists) {
            if (exists) {
                try {
                    const parsed = JSON.parse(data)
                    const lang = String(parsed.language || "")
                    if (lang === "en" || lang === "zh-CN" || lang === "auto")
                        service.language = lang
                } catch (error) {
                    console.warn("[I18nService] unreadable language state: " + error)
                }
            }
            service.loaded = true
            I18n.language = service.effectiveLanguage
        })
    }

    onLanguageChanged: I18n.language = effectiveLanguage

    function setLanguage(lang) {
        const next = lang === "en" ? "en" : lang === "auto" ? "auto" : "zh-CN"
        if (service.loaded && next === service.language)
            return
        service.language = next
        JsonConfigStore.write(_stateDir, "language.json",
            JSON.stringify({ language: next }))
    }

    function snapshot() {
        return JSON.stringify({ language: service.language })
    }
}
