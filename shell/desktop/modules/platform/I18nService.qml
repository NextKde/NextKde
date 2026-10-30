pragma Singleton

import QtQuick
import Quickshell
import "../../../shared/qml/i18n"

// 界面语言的持久化与应用。Settings 应用通过 i18n-settings IPC 目标
// （见 DesktopEnvironment.qml）读写这里；值落在 <state>/i18n/language.json，
// 启动时读回并写入共享的 I18n 单例，所有 I18n.tr() 绑定随之刷新。
// 持久值："auto"（跟随系统语言，每次启动时解析，默认）或具体语言。
QtObject {
    id: service

    // 持久值："auto"（默认，跟随系统）| "zh-CN" | "pt-BR" | "en"
    property string language: "auto"
    // 应用到 I18n 单例的生效值（auto 已解析）。
    readonly property string effectiveLanguage:
        language === "auto" ? I18n.systemDefault() : language
    property bool loaded: false

    readonly property string _stateDir: Quickshell.stateDir + "/i18n"

    Component.onCompleted: {
        JsonConfigStore.read(_stateDir, "language.json", function(data, exists) {
            if (exists) {
                try {
                    const parsed = JSON.parse(data)
                    const lang = String(parsed.language || "")
                    if (service.isSupported(lang))
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
        // 非法输入回落到默认档（跟随系统），与"无持久文件"时的行为一致。
        const next = service.isSupported(lang) ? lang : "auto"
        if (service.loaded && next === service.language)
            return
        service.language = next
        JsonConfigStore.write(_stateDir, "language.json",
            JSON.stringify({ language: next }))
    }

    function isSupported(lang) {
        return lang === "auto" || lang === "en" || lang === "zh-CN" || lang === "pt-BR"
    }

    function snapshot() {
        return JSON.stringify({ language: service.language })
    }
}
