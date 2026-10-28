pragma Singleton

import QtQuick
import "ZhCatalog.mjs" as ZhCN
import "PtBrCatalog.mjs" as PtBR
import "SystemLanguage.mjs" as LanguagePolicy

// UI 翻译单例。源语言是英文：代码里一律写 I18n.tr("English text")，
// 词典按 "英文源串 -> 译文" 映射；zh-CN / pt-BR 激活时查对应词典，
// en 激活时英文源串原样通过（无需词典）。
//
// 本文件被 shell(quickshell) 与 apps/settings(纯 Qt Quick) 以相对路径
// 目录导入共用，因此禁止 import 任何 Quickshell 类型。
//
// v1 约束：
// - 在绑定表达式里调用 tr() 的字符串随 language 实时刷新；
//   JS 赋值或常量模型里的字符串在下次赋值/重建时才更新。
// - 不做复数；占位符用 %1/%2 配合 .arg()，词典两端占位符序号可换序。
// - 日期/时间模式串同样走 tr()（如 "M月d日 dddd" <-> "dddd, MMMM d"）；
//   星期/月份名需要随语言本地化时用 fmt()/qtLocale()。
QtObject {
    id: root

    // 生效语言：只接受 "zh-CN" / "pt-BR" / "en"。"auto" 由 shell 侧 I18nService 解析
    // 后写入，绝不能直接落进这里（否则 tr() 查不到词典目录会全部回退英文）。
    // 默认按系统语言解析：覆盖 I18nService 异步加载持久值之前的启动窗口，
    // 让英文系统的用户从第一帧起就是英文。
    // 持久化与切换入口在 shell 侧 I18nService（state 文件 + IPC），
    // settings 通过 i18n-settings IPC 目标读写同一个值。
    property string language: systemDefault()

    // 系统语言解析的唯一实现（I18nService 与 settings 的本地兜底都走这里）：
    // 只看首选语言：zh/zh-* -> zh-CN，pt/pt-* -> pt-BR，其余（含空列表）为 en。
    // 与 shared/i18n/SystemLanguage.h 保持一致，不用后续备用语言覆盖首选项。
    function systemDefault() {
        return LanguagePolicy.systemLanguage(Qt.locale().uiLanguages)
    }

    readonly property var _catalogs: ({
        "en": ({}),
        "zh-CN": ZhCN.catalog,
        "pt-BR": PtBR.catalog
    })

    readonly property var _localeNames: ({
        "en": "en_US",
        "zh-CN": "zh_CN",
        "pt-BR": "pt_BR"
    })

    function tr(source) {
        const catalog = _catalogs[language]
        if (catalog && catalog[source] !== undefined)
            return String(catalog[source])
        return String(source)
    }

    // 按当前语言格式化日期/时间。pattern 传 tr() 之后的模式串，
    // 星期/月份名按 locale 输出（zh_CN -> 星期四，en_US -> Thursday）。
    function fmt(date, pattern) {
        return date.toLocaleString(qtLocale(), pattern)
    }

    // 不含日期语义、只含文案的模式串翻译（如 "yyyy年M月" <-> "MMMM yyyy"）。
    // 供不能直接用 fmt() 的地方（按 locale 传给 Qt 的调用点）复用。
    function trPattern(pattern) {
        return tr(pattern)
    }

    function qtLocale() {
        return Qt.locale(_localeNames[language] || "zh_CN")
    }
}
