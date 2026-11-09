pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import "../../../shared/qml/i18n"
import qs.desktop.modules.platform
import "TrayIdentity.mjs" as Identity

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
    property int _generation: 0

    // 内置常见已知应用快速别名表（零延迟同步兜底，与 daemon 侧的
    // trayIdentityAlias 保持一致；新增条目时两边都要改）
    readonly property var _knownAliases: ({
        "qq": "QQ",
        "linuxqq": "QQ",
        "antigravity": "Antigravity",
        "rustdesk": "RustDesk",
        "karing": "Karing",
        "sunshine": "Sunshine",
        "wechat": I18n.tr("WeChat"),
        "fcitx": I18n.tr("Input Method"),
        "fcitx5": I18n.tr("Input Method"),
        "google-chrome": "Google Chrome",
        "chrome": "Google Chrome",
        "chromium": "Chromium",
        "code": "VS Code"
    })

    function isInternalId(id) { return Identity.isInternalId(id) }

    function friendlyName(item) {
        const revision = svc.revision
        return Identity.friendlyName(item, svc.resolvedNames, svc._knownAliases, SystemTray.items.values)
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
    function invalidate() {
        svc._generation++
        if (Object.keys(svc.resolvedNames).length) {
            svc.resolvedNames = ({})
            svc.revision++
        }
        refresh()
    }

    function refresh() {
        _refreshTimer.restart()
    }

    function _query() {
        const generation = svc._generation
        PlatformClient.request("tray.identify", {}, function(response) {
            if (generation !== svc._generation) return
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
            _retryTimer.stop()
            const data = response.result?.names ?? {}
            // The daemon returns the complete live snapshot. Merging into
            // the previous map retains every generated ID after its app exits.
            const next = Object.assign({}, data)
            let changed = Object.keys(next).length !== Object.keys(svc.resolvedNames).length
            for (const k in data) {
                if (svc.resolvedNames[k] !== data[k]) {
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
                function onIdChanged() { svc.invalidate() }
                function onTitleChanged() { svc.refresh() }
                function onTooltipTitleChanged() { svc.refresh() }
            }
        }
        onObjectAdded: svc.invalidate()
        onObjectRemoved: svc.invalidate()
    }

    // daemon 重启或晚于 Shell 启动时，重连成功就是重新解析的时机；不依赖
    // 退避重试的次数上限。
    property Connections _clientConn: Connections {
        target: PlatformClient
        function onTransportChanged(connected) {
            svc.invalidate()
        }
    }

    Component.onCompleted: svc.refresh()
}
