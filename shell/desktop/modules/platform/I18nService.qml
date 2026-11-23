pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../../../shared/qml/i18n"

// 界面语言的持久化与应用。Settings 应用通过 i18n-settings IPC 目标
// （见 DesktopEnvironment.qml）读写这里；值落在 <state>/i18n/language.json，
// 启动时读回并写入共享的 I18n 单例，所有 I18n.tr() 绑定随之刷新。
// 持久值："auto"（跟随系统语言，每次启动时解析，默认）或具体语言。
//
// 持久值在单例创建时同步读取（FileView blockLoading + text()），而不是经
// 平台守护进程异步 read：异步读会让每次启动先按系统语言渲染、回包后才切到
// 用户选的语言——更新重启后尤其明显。同步读也让 DesktopEnvironment 能在
// 创建任何表面之前就应用持久语言（见其第一处属性绑定的注释）。
QtObject {
    id: service

    readonly property string _stateDir: Quickshell.stateDir + "/i18n"

    // blockLoading 让 text() 同步返回磁盘内容（文件很小）。不 watch：
    // 写入只有 Settings 经 IPC 调 setLanguage 这一条路，改值已在内存里。
    readonly property FileView _state: FileView {
        path: service._stateDir + "/language.json"
        blockLoading: true
        printErrors: false
    }

    // 持久值："auto"（默认，跟随系统）| "zh-CN" | "pt-BR" | "en"。
    // 创建时即同步读出，不等 Component.onCompleted：若干表面在创建时一次性
    // 构建 tr() 文案（如 Dock 的回收站菜单），之后再改 I18n.language 不会
    // 重翻那些字符串。
    property string language: service.readPersisted()

    // 应用到 I18n 单例的生效值（auto 已解析）。
    readonly property string effectiveLanguage:
        language === "auto" ? I18n.systemDefault() : language

    // 初始化赋值也会触发，因此单例一创建 I18n 就拿到持久语言；之后
    // setLanguage 的每次改动同样经这里下发。这里按 language 直接换算而不读
    // effectiveLanguage：属性变更处理器先于依赖它的绑定重算，读绑定拿到的是
    // 旧值（切换会慢一拍）。
    onLanguageChanged: I18n.language = service.language === "auto"
        ? I18n.systemDefault() : service.language

    // "auto" 档在运行中跟随系统语言变化（绑定重算后生效）。
    onEffectiveLanguageChanged: I18n.language = service.effectiveLanguage

    // 首次运行或文件损坏时回落到 "auto"（跟随系统），与 setLanguage 对
    // 非法输入的处理一致。
    function readPersisted() {
        const raw = service._state.text()
        if (raw.length > 0) {
            try {
                const parsed = JSON.parse(raw)
                const lang = String(parsed.language || "")
                if (service.isSupported(lang))
                    return lang
            } catch (error) {
                console.warn("[I18nService] unreadable language state: " + error)
            }
        }
        return "auto"
    }

    function setLanguage(lang) {
        // 非法输入回落到默认档（跟随系统），与"无持久文件"时的行为一致。
        const next = service.isSupported(lang) ? lang : "auto"
        if (next === service.language)
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
