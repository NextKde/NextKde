pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs.desktop.modules.platform

// 系统托盘应用身份智能解析服务 / System Tray Identity Service
//
// 通过平台 daemon 的 tray.identify op 解析未规范设置 Title 的托盘项
// （如 Linux QQ、Antigravity 等 Electron 应用）：daemon 读取 SNI watcher 的
// 注册项、逐项取 Id/Title 与所属连接的 PID，再本地读取 /proc/<pid>/comm 与
// cmdline，按别名表 / 标题 / 进程名顺序定名。整个 D-Bus 遍历跑在 daemon 的
// worker 池上，Shell 侧不再生成任何子进程。
QtObject {
    id: svc

    // 解析后的应用名映射字典：itemId -> 友好应用名
    property var resolvedNames: ({})
    property int revision: 0

    // 内置常见已知应用快速别名表（零延迟同步兜底，与 daemon 侧的
    // trayIdentityAlias 保持一致；新增条目时两边都要改）
    readonly property var _knownAliases: ({
        "qq": "QQ",
        "linuxqq": "QQ",
        "antigravity": "Antigravity",
        "rustdesk": "RustDesk",
        "karing": "Karing",
        "sunshine": "Sunshine",
        "wechat": "微信",
        "fcitx": "输入法",
        "fcitx5": "输入法",
        "google-chrome": "Google Chrome",
        "chrome": "Google Chrome",
        "chromium": "Chromium",
        "code": "VS Code"
    })

    // 判断一个 ID 是否为生硬的内部生成标识符
    function isInternalId(id) {
        if (!id || typeof id !== "string") return true
        const str = id.trim()
        if (str.length === 0) return true
        // Chromium / Electron 自动生成的托盘 ID
        if (str.indexOf("chrome_status_icon") === 0) return true
        if (str.indexOf("_status_icon_") >= 0) return true
        if (str.indexOf("tray-icon tray app") === 0) return true
        // 随机生成的无意义短哈希标识（如 2cUW32wlKy）
        if (/^[0-9a-zA-Z]{8,16}$/.test(str) && !/^[A-Z][a-z]+$/.test(str)) return true
        return false
    }

    // 获取托盘项的友好显示名称
    function friendlyName(item) {
        if (!item) return ""
        const _rev = svc.revision // 触发 QML 响应式依赖

        // 1. 优先使用显式设置的有效 Tooltip 标题
        if (item.tooltipTitle && typeof item.tooltipTitle === "string" && item.tooltipTitle.trim().length > 0) {
            const tt = item.tooltipTitle.trim()
            if (!isInternalId(tt)) return tt
        }

        // 2. 其次使用显式设置的有效 Title
        if (item.title && typeof item.title === "string" && item.title.trim().length > 0) {
            const title = item.title.trim()
            if (!isInternalId(title)) return title
        }

        const id = (item.id || "").trim()

        // 3. 从异步解析结果中查找
        if (id && svc.resolvedNames[id]) {
            return svc.resolvedNames[id]
        }

        // 4. 如果 id 自身是有意义的可读名称，则可以作为兜底
        if (id && !isInternalId(id)) {
            const lower = id.toLowerCase()
            if (svc._knownAliases[lower]) {
                return svc._knownAliases[lower]
            }
            return id
        }

        // 5. 完全为内部生硬 ID 且尚未解析出时安全返回空，避免把内部 ID 显示
        // 给用户。此处不做猜测：曾把任意 Chromium 系托盘应用一律猜成 QQ。
        return ""
    }

    // 托盘项的变化很密集（聊天类应用每条消息都会改 tooltip），而 daemon 侧的
    // 遍历要扫全部注册项，所以合并成一次防抖查询。
    property Timer _refreshTimer: Timer {
        interval: 1200
        onTriggered: svc._query()
    }

    // 触发异步解析更新
    function refresh() {
        _refreshTimer.restart()
    }

    function _query() {
        PlatformClient.request("tray.identify", {}, function(response) {
            if (!response?.ok) {
                console.warn("[SysTrayIdentityService] identify failed: "
                    + (response?.error?.message || "platform unavailable"))
                return
            }
            const data = response.result?.names ?? {}
            const next = Object.assign({}, svc.resolvedNames)
            let changed = false
            for (const k in data) {
                if (next[k] !== data[k]) {
                    next[k] = data[k]
                    changed = true
                }
            }
            if (changed) {
                svc.resolvedNames = next
                svc.revision++
            }
        })
    }

    // 监听托盘项数量与增删变化
    property Instantiator _trayWatcher: Instantiator {
        model: SystemTray.items
        delegate: QtObject {
            required property var modelData
            property Connections _itemConn: Connections {
                target: modelData
                function onIdChanged() { svc.refresh() }
                function onTitleChanged() { svc.refresh() }
                function onTooltipTitleChanged() { svc.refresh() }
            }
        }
        onObjectAdded: svc.refresh()
        onObjectRemoved: svc.refresh()
    }

    Component.onCompleted: svc.refresh()
}
