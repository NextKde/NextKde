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

    // 有些应用用自己的名字拼出 ID（如 WorkBuddy_status_icon_1），剥掉生成的
    // 后缀就能还原；纯运行时生成的 ID（chrome_status_icon_1）剥完不剩任何
    // 信息，此处返回空，绝不猜测它属于哪个应用。
    function _nameFromId(id) {
        if (!id) return ""
        if (/^chrome[_-]status[_-]icon/i.test(id)) return ""
        let name = id.replace(/^tray[-\s]?icon(\s+tray\s+app)?\s+/i, "")
        name = name.replace(/[_-]status[_-]icon[_-]?[0-9]*$/i, "").replace(/[_-]+$/, "").trim()
        // 只有确实剥掉了生成片段才算还原出名字：没有剥掉说明该 ID 自身就是
        // 无信息的标识（例如随机哈希），照原样显示等于没有名字。
        if (name === id.trim()) return ""
        if (name.length < 2 || !/^[A-Za-z0-9._-]+$/.test(name)) return ""
        if (svc._genericNames[name.toLowerCase()]) return ""
        // 已含大写说明是应用自己的拼写（WorkBuddy）；带分隔符的名字是应用自己
        // 的风格（cc-switch），只有单个小写单词才需要首字母大写。
        if (name.indexOf("-") < 0 && name.indexOf("_") < 0
                && name === name.toLowerCase())
            name = name.charAt(0).toUpperCase() + name.slice(1)
        return name
    }

    readonly property var _genericNames: ({
        "app": true, "apprun": true, "resources": true, "electron": true,
        "node": true, "chrome": true, "chromium": true, "python": true,
        "python3": true, "java": true, "sh": true, "bash": true, "env": true,
        "flatpak": true, "snap": true, "tray": true, "icon": true
    })

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

        // 5. id 是生成标识时，仍尝试从它自己拼出的名字还原
        const fromId = svc._nameFromId(id)
        if (fromId) return fromId

        // 6. 最后兜底回到改动前的行为：宁可显示原始 ID，也不要把提示整个变
        // 空。daemon 未部署 tray.identify（旧版本或连接断开）时，第 3 步永远
        // 不会命中，此处保证 QQ / WorkBuddy 一类应用至少仍有可读的提示。
        return item.tooltipTitle || item.title || id || ""
    }

    // 托盘项的变化很密集（聊天类应用每条消息都会改 tooltip），而 daemon 侧的
    // 遍历要扫全部注册项，所以合并成一次防抖查询。
    property Timer _refreshTimer: Timer {
        interval: 1200
        onTriggered: svc._query()
    }

    // 查询失败（daemon 未就绪、正在重启，或版本还不认识这个 op）时退避重试：
    // 否则解析结果会一直为空，直到下一次托盘事件才恢复。
    property int _failures: 0
    property Timer _retryTimer: Timer {
        interval: 2000
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
                if (svc._failures < 5) {
                    svc._failures++
                    _retryTimer.interval = 2000 * svc._failures
                    _retryTimer.restart()
                }
                return
            }
            svc._failures = 0
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

    // daemon 重启或晚于 Shell 启动时，重连成功就是重新解析的时机；不依赖
    // 退避重试的次数上限。
    property Connections _clientConn: Connections {
        target: PlatformClient
        function onTransportChanged(connected) {
            if (connected) svc.refresh()
        }
    }

    Component.onCompleted: svc.refresh()
}
