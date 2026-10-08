pragma Singleton

import QtQuick
import "ZhCatalog.mjs" as ZhCN

// UI 翻译单例。源语言是英文：代码里一律写 I18n.tr("English text")，
// 词典按 "英文源串 -> 译文" 映射；zh-CN 激活时查 ZhCN.catalog，
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

    // "zh-CN"（默认，保持现有中文界面）或 "en"。
    // 持久化与切换入口在 shell 侧 I18nService（state 文件 + IPC），
    // settings 通过 i18n-settings IPC 目标读写同一个值。
    property string language: "zh-CN"

    readonly property var _catalogs: ({
        "en": ({}),
        "zh-CN": ZhCN.catalog
    })

    readonly property var _localeNames: ({
        "en": "en_US",
        "zh-CN": "zh_CN"
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
        return Qt.formatDateTime(date, pattern, qtLocale())
    }

    function qtLocale() {
        return Qt.locale(_localeNames[language] || "zh_CN")
    }
}
