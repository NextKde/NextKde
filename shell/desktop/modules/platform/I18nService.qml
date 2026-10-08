pragma Singleton

import QtQuick
import Quickshell
import "../../../shared/qml/i18n"

// 界面语言的持久化与应用。Settings 应用通过 i18n-settings IPC 目标
// （见 DesktopEnvironment.qml）读写这里；值落在 <state>/i18n/language.json，
// 启动时读回并写入共享的 I18n 单例，所有 I18n.tr() 绑定随之刷新。
QtObject {
    id: service

    property string language: "zh-CN"
    property bool loaded: false

    readonly property string _stateDir: Quickshell.stateDir + "/i18n"

    Component.onCompleted: {
        JsonConfigStore.read(_stateDir, "language.json", function(data, exists) {
            if (exists) {
                try {
                    const parsed = JSON.parse(data)
                    const lang = String(parsed.language || "")
                    if (lang === "en" || lang === "zh-CN")
                        service.language = lang
                } catch (error) {
                    console.warn("[I18nService] unreadable language state: " + error)
                }
            }
            service.loaded = true
            I18n.language = service.language
        })
    }

    onLanguageChanged: I18n.language = language

    function setLanguage(lang) {
        const next = lang === "en" ? "en" : "zh-CN"
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
