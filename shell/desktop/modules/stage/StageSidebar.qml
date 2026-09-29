import Quickshell
import Quickshell.Io
import qs.desktop.modules.common
import qs.desktop.modules.dock

// Stage Sidebar controller — macOS Stage Manager 式常驻窗口卡片侧栏。
// 消费 WindowService（KWin 桥：窗口列表/实时缩略图/激活），卡片区排除
// 当前活动窗口（它就是"主窗"），其余窗口全部以缩略卡片常驻左侧，
// 点击卡片激活置顶。
// 显隐由 StageModeService.enabled 驱动（前台调度总开关，控制中心/Meta+Y 可切）。
Scope {
    id: root

    // 前台调度设置页的数据源：当前运行的窗口应用（去重，人类可读名+类名）。
    IpcHandler {
        target: "fg-sched"
        function runningApps(): string {
            const seen = ({})
            const out = []
            const records = WindowService.records || []
            for (let i = 0; i < records.length; i++) {
                const r = records[i]
                const cls = r.identity?.rawAppId || ""
                if (!cls || seen[cls])
                    continue
                seen[cls] = true
                out.push({ name: r.identity?.name || r.title || cls, appId: cls })
            }
            return JSON.stringify(out)
        }
    }

    IpcHandler {
        target: "stage-sidebar"
        function show(): void { StageModeService.setEnabled(true) }
        function hide(): void { StageModeService.setEnabled(false) }
        function toggle(): void { StageModeService.toggle() }
        // 无头验证钩子（同 dock-debug 惯例）：模拟点击第一张卡走同拍交换
        function debugEngageFirst(): string { return stageWindow.debugEngageFirst() }
        // 无头点击任意卡（排障钩子；跨应用退位/停泊路径的确定性复现）
        function debugEngageIndex(index: int): string {
            return stageWindow.debugEngageIndex(index)
        }
        // 无头悬停模拟：debugHover <index> <true|false>（验证 hover 管线）
        function debugHover(index: int, over: bool): string {
            return stageWindow.debugHover(index, over)
        }
        // 显示桌面开关（与空桌面左键同路径）：收编全部 / 整组放出来
        function deskReveal(): void { stageWindow.toggleDeskReveal() }
        // 无头拖拽模拟：debugDrag <from> <to>（顺序表转正+矩形重发布链路）
        function debugDrag(fromIndex: int, toIndex: int): string {
            return stageWindow.debugDrag(fromIndex, toIndex)
        }
        // 几何快照：窗口/堆叠区高度 + 各卡当前 y/scale/z（排障用）
        function debugGeom(): string { return stageWindow.debugGeom() }
        // 显示桌面开关状态机快照（抗打断排障）
        function deskState(): string { return stageWindow.deskState() }
        // round30 调研探针：对第 index 张卡的窗口发起 zkde_screencast 活体流
        // 请求，journal 里看 stream probe nodeId=（>0 = 授权+协议全通）
        function debugStreamProbe(index: int): string {
            return stageWindow.debugStreamProbe(index)
        }
    }

    // 台前调度可调参数（设置应用 → 前台调度页走这里实时改）
    IpcHandler {
        target: "stage-config"
        function snapshot(): string { return StageConfigService.snapshotJson() }
        function set(key: string, value: string): string {
            return StageConfigService.set(key, value)
        }
    }

    StageSidebarWindow {
        id: stageWindow
        screen: ScreenLifecycle.activeScreen
        // 读 ScreenLifecycle 而非窗口自身的 screen 属性——后者随 open 的
        // 映射而变化，会构成 open 绑定环（旧 WARN 的根源）
        open: StageModeService.enabled
            && ScreenLifecycle.outputAvailable
            && ScreenLifecycle.activeScreen !== null
    }
}
