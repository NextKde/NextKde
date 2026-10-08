// Quickshell's Plasma/KWin window provider.
// KWin owns the authoritative window list on Plasma Wayland. This script
// publishes snapshots to the local bridge and receives requested operations
// through its short D-Bus polling loop.

// The resident kos-platform process owns the private bridge endpoint. Shell
// clients never call this object directly; they subscribe through the
// platform JSONL socket instead.
const service = "org.kos.Platform";
const path = "/Platform";
const iface = "org.kos.Platform";

function normalizeId(value) {
    return String(value || "").replace(/[{}]/g, "");
}

function windowId(window) {
    return normalizeId(window.internalId);
}

// ── 停泊（实时卡片模式）──
// 收编窗静默还原后**移到屏幕外**：保持 mapped/客户端持续送帧（实时缩略图
// 的前提），桌面上不可见——旧方案只 keepBelow 压底，窗口全摊在桌面上
//（用户否决"桌面上全是应用程序"）。几何存图，所有把它带回屏幕的路径
//（activate / activate-group / engage-swap / park value=false）自动复位。
// ⚠️ 停泊命令经 50ms/条串行轮询执行，shell 入队时的"仍最小化"校验到执行
// 时可能已过时（快速连点卡片）——所以停泊侧还有两道防御：迟到的 park 绝不
// 碰未最小化的窗口（它已被展开到桌面）；档案侧拒绝把屏幕外几何存成"原始
// 位置"（否则展开时还原回屏幕外，KWin 还会把活动窗钳到工作区右缘窄条）。
const parkedGeometry = {};

// 屏外判定阈值：动态取虚拟屏（全部输出并集）右缘——单屏逻辑宽 ~1696 下
// 旧常量 3000 会让 parkedX（右缘+100）永远检不出"已在屏幕外"＝unpark
// 兜底救援与"档案丢失后再停泊跳过"守卫全体失效（v87 审查）；拿不到
// virtualScreenGeometry 时退回远超单屏宽的绝对常量
function offscreenThresholdX() {
    try {
        const vsg = workspace.virtualScreenGeometry;
        return vsg.x + vsg.width;
    } catch (geometryError) {
        return 3000;
    }
}

// 取出停泊档案（删除并返回普通对象 {x,y,width,height}；无档案返回 null）。
// 复位写入必须放在 workspace.activeWindow 赋值**之后**：几何写入是异步提交
// 的，先写后激活时 KWin 在激活瞬间看到的仍是停泊位（5000），会把活动窗
// 钳到工作区右缘窄条（1272）盖掉排队中的还原——实测窗口"飞到最右看不见"
// 即此。激活后再写，复位必然最后生效。
function takeParkedGeometry(window) {
    const key = windowId(window);
    const saved = parkedGeometry[key];
    if (!saved)
        return null;
    delete parkedGeometry[key];
    return saved;
}

// 应用复位：有档案写档案；无档案却在屏幕外（档案被清/迟到的停泊拽走过）
// 拉回工作区内——否则激活时 KWin 只把它钳到右缘窄条，窗口"飞到最右看不见"
// ⚠️ 整体捕获：调用点在 activate-group/engage-swap 的激活后循环里无守卫，
// 窗口在间隙销毁时 frameGeometry 读抛会把整条命令的 publishAction +
// scheduleSnapshot 一起跳过（无回执 + 快照停更到下个窗口事件）
function applyRestore(window, geo) {
    try {
        if (geo) {
            window.frameGeometry = geo;
            return;
        }
        const stranded = window.frameGeometry;
        if (stranded.x > offscreenThresholdX()) {
            window.frameGeometry = {
                x: 300, y: stranded.y,
                width: stranded.width, height: stranded.height
            };
            print("[QuickshellWindowBridge] unpark heal id=" + windowId(window)
                  + " x=" + stranded.x + " -> 300");
        }
    } catch (error) {
        print("[QuickshellWindowBridge] applyRestore failed id="
              + windowId(window) + " error=" + error);
    }
}

function parkWindow(window, on) {
    const key = windowId(window);
    if (on) {
        if (parkedGeometry[key])
            return;
        const current = window.frameGeometry;
        if (current.x > offscreenThresholdX()) {
            // 档案丢失后的再次停泊：窗口已在屏幕外，把停泊位存成原始位置
            // 会永久污染档案——跳过，保持停泊现状等展开路径兜底
            print("[QuickshellWindowBridge] park skip lost-archive id=" + key
                  + " x=" + current.x);
            return;
        }
        try {
            const g = window.frameGeometry;
            // ⚠️ KWin 脚本引擎对 QRect 属性返回的是引用——直接把
            // window.frameGeometry 存进档案，下一行把窗口移到屏幕外时档案会
            // 跟着变成停泊位（5000），展开时"还原"就是把 5000 写回去，活动
            // 窗随即被 KWin 钳到工作区右缘窄条（1272）。必须抄成普通对象。
            parkedGeometry[key] = {
                x: g.x, y: g.y, width: g.width, height: g.height
            };
            // 屏外停泊位 = 虚拟屏（全部输出并集）右缘外 100px——多屏右摆
            // 也安全。KWin 6.6 无 workspace.geometry，但 virtualScreenGeometry
            // 可用（实测 QRect(0,0,1696,1200)）；拿不到时退回绝对常量
            // （远超任何单屏逻辑宽）
            let parkedX = 5000;
            try {
                const vsg = workspace.virtualScreenGeometry;
                parkedX = vsg.x + vsg.width + 100;
            } catch (geometryError) {
                // 保持常量兜底
            }
            window.frameGeometry = {
                x: parkedX,
                y: g.y, width: g.width, height: g.height
            };
        } catch (error) {
            delete parkedGeometry[key];
            print("[QuickshellWindowBridge] park failed id=" + key
                  + " error=" + error);
        }
    } else {
        applyRestore(window, takeParkedGeometry(window));
    }
}

function propertyValue(window, name, fallback) {
    try {
        const value = window[name];
        return value === undefined || value === null ? fallback : value;
    } catch (error) {
        return fallback;
    }
}

// KWin's frameGeometry is a QRect exposed with x/y/width/height. Read each part
// defensively so an older scripting API cannot break the whole snapshot.
function frameGeometry(window) {
    try {
        const g = window.frameGeometry;
        if (!g)
            return null;
        return {
            x: Number(propertyValue(g, "x", 0)),
            y: Number(propertyValue(g, "y", 0)),
            width: Number(propertyValue(g, "width", 0)),
            height: Number(propertyValue(g, "height", 0))
        };
    } catch (error) {
        return null;
    }
}

// KWin 6 exposes maximizeMode as a flag set: vertical=1, horizontal=2. Read it
// first; the older `maximized` shapes remain only as a compatibility fallback.
function isMaximized(window) {
    const mode = Number(propertyValue(window, "maximizeMode", 0));
    if (Number.isFinite(mode) && (mode & 3) === 3)
        return true;
    const raw = propertyValue(window, "maximized", false);
    if (raw === null || raw === false || raw === undefined)
        return false;
    if (raw === true)
        return true;
    try {
        if (typeof raw === "object") {
            return !!(raw.horizontal && raw.vertical);
        }
        return false;
    } catch (error) {
        return false;
    }
}

function normalizedRect(value) {
    if (!value)
        return null;
    const rect = {
        x: Number(value.x),
        y: Number(value.y),
        width: Number(value.width),
        height: Number(value.height)
    };
    if (!Number.isFinite(rect.x) || !Number.isFinite(rect.y)
            || !Number.isFinite(rect.width) || !Number.isFinite(rect.height)
            || rect.width <= 0 || rect.height <= 0)
        return null;
    return rect;
}

function safeAreaForLayout(layout) {
    const output = normalizedRect(layout && layout.outputRect);
    const dock = normalizedRect(layout && layout.dockRect);
    if (!output || !dock)
        return null;

    const gap = Math.max(0, Number(layout.workspaceGap) || 0);
    const reserved = Math.max(0, Number(layout.barReservedHeight) || 0);
    let left = output.x;
    let top = output.y + Math.min(output.height, reserved);
    let right = output.x + output.width;
    let bottom = output.y + output.height;
    if (layout.dockPosition === "left")
        left = Math.max(left, dock.x + dock.width + gap);
    else if (layout.dockPosition === "right")
        right = Math.min(right, dock.x - gap);
    else
        bottom = Math.min(bottom, dock.y - gap);

    return {
        x: left,
        y: top,
        width: Math.max(1, right - left),
        height: Math.max(1, bottom - top)
    };
}

// Pure placement function kept free of KWin objects so its negative-output,
// oversized-window and minimum-size behaviour can be exercised by Node tests.
function calculateInitialPlacement(windowRect, minimumSize, safeArea) {
    const frame = normalizedRect(windowRect);
    const safe = normalizedRect(safeArea);
    if (!frame || !safe)
        return null;
    const minWidth = Math.max(1, Number(minimumSize && minimumSize.width) || 1);
    const minHeight = Math.max(1, Number(minimumSize && minimumSize.height) || 1);
    const width = Math.max(minWidth, Math.min(frame.width, safe.width));
    const height = Math.max(minHeight, Math.min(frame.height, safe.height));
    const maxX = safe.x + safe.width - width;
    const maxY = safe.y + safe.height - height;
    return {
        x: width > safe.width ? safe.x : Math.max(safe.x, Math.min(frame.x, maxX)),
        y: height > safe.height ? safe.y : Math.max(safe.y, Math.min(frame.y, maxY)),
        width: width,
        height: height
    };
}

let shellLayouts = {};
let placementTimers = [];
let initialPlacementState = {};

function keepPlacementTimer(timer) {
    placementTimers.push(timer);
    timer.timeout.connect(function() {
        const index = placementTimers.indexOf(timer);
        if (index >= 0)
            placementTimers.splice(index, 1);
    });
}

function finishInitialPlacement(window) {
    const id = windowId(window);
    if (id)
        initialPlacementState[id] = "done";
}

function schedulePlacementAttempt(window, attempt, delay) {
    const timer = new QTimer();
    timer.interval = delay;
    timer.singleShot = true;
    timer.timeout.connect(function() { placeInitialWindow(window, attempt); });
    keepPlacementTimer(timer);
    timer.start();
}

function updateLayout(command) {
    const name = String(command.outputName || "");
    const safeArea = safeAreaForLayout(command);
    if (!name || !safeArea)
        return false;
    shellLayouts[name] = {
        outputName: name,
        outputRect: normalizedRect(command.outputRect),
        barReservedHeight: Math.max(0, Number(command.barReservedHeight) || 0),
        dockPosition: String(command.dockPosition || "bottom"),
        dockRect: normalizedRect(command.dockRect),
        workspaceGap: Math.max(0, Number(command.workspaceGap) || 0)
    };
    return true;
}

function layoutForWindow(window) {
    const direct = outputName(window);
    if (direct && shellLayouts[direct])
        return shellLayouts[direct];
    const frame = frameGeometry(window);
    if (!frame)
        return null;
    const centerX = frame.x + frame.width / 2;
    const centerY = frame.y + frame.height / 2;
    for (const name in shellLayouts) {
        const output = shellLayouts[name].outputRect;
        if (centerX >= output.x && centerX < output.x + output.width
                && centerY >= output.y && centerY < output.y + output.height)
            return shellLayouts[name];
    }
    return null;
}

function eligibleForInitialPlacement(window) {
    return !!window && !window.deleted
        && !!propertyValue(window, "normalWindow", false)
        && !propertyValue(window, "specialWindow", false)
        && !propertyValue(window, "dialog", false)
        && !propertyValue(window, "modal", false)
        && !propertyValue(window, "transient", false)
        && !propertyValue(window, "transientFor", null)
        && !propertyValue(window, "fullScreen", false)
        && !isMaximized(window)
        && propertyValue(window, "moveable", true) !== false
        && propertyValue(window, "resizeable", true) !== false;
}

function placeInitialWindow(window, attempt) {
    const id = windowId(window);
    if (!id || initialPlacementState[id] === "done")
        return;
    if (!eligibleForInitialPlacement(window)) {
        finishInitialPlacement(window);
        return;
    }
    const layout = layoutForWindow(window);
    if (!layout) {
        if (attempt < 3)
            schedulePlacementAttempt(window, attempt + 1, 40);
        else
            finishInitialPlacement(window);
        return;
    }
    const frame = frameGeometry(window);
    if (!frame || frame.width <= 1 || frame.height <= 1) {
        if (attempt < 3)
            schedulePlacementAttempt(window, attempt + 1, 40);
        else
            finishInitialPlacement(window);
        return;
    }
    const minimum = propertyValue(window, "minSize", { width: 1, height: 1 });
    const target = calculateInitialPlacement(frame, minimum, safeAreaForLayout(layout));
    if (!target) {
        finishInitialPlacement(window);
        return;
    }
    if (target.x === frame.x && target.y === frame.y
            && target.width === frame.width && target.height === frame.height) {
        finishInitialPlacement(window);
        return;
    }
    // Mark the request complete before assigning geometry. KWin emits
    // synchronous geometry signals during this write; no later event may
    // reinterpret a maximize or user drag as another initial placement.
    finishInitialPlacement(window);
    try {
        window.frameGeometry = target;
        print("[QuickshellWindowBridge] placed new window id=" + windowId(window)
              + " output=" + layout.outputName);
    } catch (error) {
        print("[QuickshellWindowBridge] initial placement failed id=" + windowId(window)
              + " error=" + error);
    }
}

function scheduleInitialPlacement(window) {
    const id = windowId(window);
    if (!id || initialPlacementState[id])
        return;
    initialPlacementState[id] = "pending";
    schedulePlacementAttempt(window, 0, 0);
}

// Runtime-dependent bridge helpers start here. Tests evaluate the pure layout
// and placement helpers above this marker without a live KWin workspace.

// Preferred output for a window. Some KWin scripting versions do not expose
// `window.output`; fall back to empty so foreign-side collisions can fall back
// to geometry overlap.
function outputName(window) {
    try {
        const output = window.output;
        return output ? String(output.name || "") : "";
    } catch (error) {
        return "";
    }
}

function windowDebug(window) {
    return {
        id: windowId(window),
        pid: Number(propertyValue(window, "pid", 0)),
        resourceClass: String(propertyValue(window, "resourceClass", "")),
        resourceName: String(propertyValue(window, "resourceName", "")),
        desktopFileName: String(propertyValue(window, "desktopFileName", "")),
        caption: String(propertyValue(window, "caption", "")),
        normalWindow: !!propertyValue(window, "normalWindow", false),
        skipTaskbar: !!propertyValue(window, "skipTaskbar", false),
        skipSwitcher: !!propertyValue(window, "skipSwitcher", false),
        hidden: !!propertyValue(window, "hidden", false),
        inputMethod: !!propertyValue(window, "inputMethod", false),
        windowType: String(propertyValue(window, "windowType", "")),
        onAllDesktops: !!propertyValue(window, "onAllDesktops", false)
    };
}

function includeWindow(window) {
    // Workspace changes briefly expose transition/internal windows in
    // workspace.windowList(). They do not belong in a taskbar model.
    const pid = Number(propertyValue(window, "pid", 0));
    const resourceClass = String(propertyValue(window, "resourceClass", ""));
    const resourceName = String(propertyValue(window, "resourceName", ""));
    const caption = String(propertyValue(window, "caption", ""));
    const isKWinInternalWindow = pid <= 0
        && !resourceClass
        && !resourceName
        && !caption;
    return !!window
        && !window.deleted
        && window.normalWindow
        && !window.skipTaskbar
        && !window.skipSwitcher
        && !window.hidden
        && !window.inputMethod
        && !isKWinInternalWindow;
}

// The ids of the virtual desktops a window is on. KWin scripting exposes
// `window.desktops` as a list of VirtualDesktop objects with an id; some
// versions expose bare id strings, so accept both shapes.
function desktopIds(window) {
    try {
        const desktops = window.desktops;
        if (!desktops || !desktops.length)
            return [];
        const ids = [];
        for (let i = 0; i < desktops.length; i++) {
            const item = desktops[i];
            const id = item && typeof item === "object" ? item.id : item;
            if (id)
                ids.push(normalizeId(String(id)));
        }
        return ids;
    } catch (error) {
        return [];
    }
}

// Cached serialized snapshot. KWin can emit the same window state many times
// per second (e.g. a signal that fires repeatedly while nothing changed);
// republishing identical snapshots would make Quickshell rebuild its whole
// window model on every copy. Publish only on actual change.
let lastSnapshotJson = "";

// The scripting `workspace.activeWindow = w` assignment lands immediately,
// but the per-window `window.active` property only flips once KWin's focus
// pipeline finishes. A snapshot taken in that gap mixes fresh minimized
// flags with stale activated flags — the shell then sees the engaged app
// un-minimized yet inactive AND the demoted app already minimized, cards
// BOTH (N+1), and the column twitches toward the swapping slot and back
// when the next snapshot corrects the flags. Until the live property
// catches up, the window this script itself focused is authoritative;
// bounded by freshness so a user-driven focus change is never overridden.
const PENDING_ACTIVE_TTL_MS = 400;
let pendingActiveId = null;
let pendingActiveAt = 0;

function setActiveWindow(window) {
    workspace.activeWindow = window;
    if (window) {
        pendingActiveId = windowId(window);
        pendingActiveAt = Date.now();
    }
}

// ── 展开动画保证：状态感知翻转 ──
// stageanim 的收/放动画全部寄生在 minimizedChanged 上，而 KWin 的
// setMinimized 对同值写入直接 return（window.cpp：m_minimized ==
// effectiveSet 即短路，不发信号）。编排侧的快照滞后/多路重复批次会
// 写出同值——典型：窗口经旁路（alt-tab/上一手还原）已回到桌面、卡片
// 还没随快照消失时点卡——写 false 是静默 no-op＝窗口瞬现、无动画。
// 修复：需要展开而窗口已展开时，注入一次同 tick 真翻转（true→false）。
// KWin TimeLine 语义（effect/timeline.cpp）：新建后 elapsed=0，Forward
// 下 value()=0；紧随的 setDirection(Backward) 在 elapsed==0 且
// sourceRedirectMode=Relaxed 时**不镜像** elapsed，value()=1−progress
// 从 1.0 起步＝完整的"从卡片展开"动画；两次写入之间没有合成帧，窗口
// 不会闪现。若该窗展开动画正在播放（elapsed>0），两次 toggleDirection
// 各镜像一次 elapsed＝净零，动画连续无抖动。
// ⚠️ 仅 forceAnim 命令（点卡/卡侧整组放出）注入：dock 点应用对"已在
// 桌面的窗"是抬前语义，注入会先藏再从卡片长出（无中生有的伪影）。
function restoreWithAnimation(window, forceAnim) {
    if (forceAnim === true && !window.minimized) {
        window.minimized = true;
    }
    window.minimized = false;
}

function snapshot() {
    const all = workspace.windowList();
    // The real KWin-active window, scanned UNFILTERED (transient dialogs
    // are excluded from `windows` below, so activeId must not be derived
    // from the filtered list). Its minimized state is captured alongside:
    // in the focus-pipeline gap the scan still names the just-demoted
    // window, which is implausible as the active window.
    let liveActiveId = null;
    let liveActiveMinimized = false;
    for (let j = 0; j < all.length; j++) {
        const w = all[j];
        if (w && !w.deleted && w.active) {
            liveActiveId = windowId(w);
            liveActiveMinimized = !!w.minimized;
            break;
        }
    }
    // Lag guard (see pendingActiveId above): override with the scripted
    // target only while the live answer is implausible. A genuine user
    // focus change (live names an un-minimized window, or the desktop)
    // always wins immediately.
    let activeId = liveActiveId;
    if (pendingActiveId !== null
            && liveActiveId !== null
            && liveActiveId !== pendingActiveId
            && liveActiveMinimized
            && Date.now() - pendingActiveAt < PENDING_ACTIVE_TTL_MS) {
        activeId = pendingActiveId;
    }
    if (liveActiveId === pendingActiveId)
        pendingActiveId = null;
    // 桌面聚焦分类：KWin 的活动窗可以是我们自己的全屏桌面表面（桌面
    // 挂件层/壁纸——y=0 的 quickshell 表面），此刻 tracked 侧 activeId 为
    // 空、kwinActiveId 非空，旧判据把它误读成"未跟踪 transient"。只有
    // 覆盖整个输出的表面（顶栏 35px 高、启动台/概览 y=35 都不算）才视
    // 为"焦点在桌面上"。
    let activeOnDesktopSurface = false;
    if (activeId !== null && activeId !== pendingActiveId) {
        for (let k = 0; k < all.length; k++) {
            const w = all[k];
            if (w && !w.deleted && windowId(w) === activeId
                    && String(w.resourceClass) === "quickshell") {
                const g = w.frameGeometry;
                if (g && g.y === 0 && g.height >= 200)
                    activeOnDesktopSurface = true;
                break;
            }
        }
    }
    const windows = [];
    for (let i = 0; i < all.length; i++) {
        const window = all[i];
        if (!includeWindow(window))
            continue;
        windows.push({
            id: windowId(window),
            pid: Number(propertyValue(window, "pid", 0)),
            appId: String(window.desktopFileName || window.resourceClass || window.resourceName || ""),
            title: String(window.caption || ""),
            // Normalized against the authoritative activeId above: one frame
            // must never mix a stale window.active with fresh minimized.
            activated: windowId(window) === activeId,
            minimized: !!window.minimized,
            fullscreen: !!window.fullScreen,
            // KWin's authoritative _NET_WM_STATE_DEMANDS_ATTENTION state.
            // This is the provider boundary for the Dock's urgent styling.
            urgent: !!propertyValue(window, "demandsAttention", false),
            // Virtual desktops this window lives on (ids). Consumed by the
            // workspace overview to place each window on its desktop.
            desktops: desktopIds(window),
            onAllDesktops: !!propertyValue(window, "onAllDesktops", false),
            // Stable full-reveal geometry consumed by the Dock auto-hide
            // collision judgement. frameGeometry is the compositor's resolved
            // placement, so the user's actual drawn window is what occludes
            // the dock, not an app's requested size.
            geometry: frameGeometry(window),
            outputName: outputName(window),
            maximized: isMaximized(window),
            visible: !!propertyValue(window, "visible", true)
        });
    }
    const json = JSON.stringify({ type: "snapshot", activeId: activeId,
        activeDesktop: activeOnDesktopSurface, windows: windows });
    if (json === lastSnapshotJson)
        return;
    lastSnapshotJson = json;
    callDBus(service, path, iface, "Publish", json);
}

// KWin emits several metadata changes while switching virtual desktops. Wait
// for that burst to settle, rather than presenting a transient taskbar icon.
// Geometry is deliberately handled by the separate throttled timer below:
// debouncing frameGeometryChanged here made smart-hide wait until a window had
// stopped moving before it could notice that the Dock boundary was crossed.
const snapshotTimer = new QTimer();
snapshotTimer.interval = 120;
snapshotTimer.singleShot = true;
snapshotTimer.timeout.connect(snapshot);

function scheduleSnapshot() {
    snapshotTimer.start();
}

// 收放类命令（minimize/engage/park 等）处理完立即发快照：窗口状态已经
// 变了，迟到的快照让侧栏卡片晚 ~160-200ms 才出现（120ms 定时器 + QML
// 40ms 防抖重建），与窗口飞行不同拍——"收成卡片的动画和卡片的出现
// 不同时"的根源。零延迟补拍不绕过 QML 侧节流（那边自会折叠重复重建），
// 定时器保留作常规变化（标题/几何/桌面切换）的兜底节奏。
function publishSnapshotNow() {
    snapshotTimer.stop();
    snapshot();
}

// Publish at a reduced rate while a window is moving. A drag emits a
// geometry signal per compositor frame, and every published snapshot runs
// the bridge's icon-resolution pass plus a full window-model rebuild in
// Quickshell; 80 ms keeps the Dock auto-hide collision judgement responsive
// while cutting that work to ~12 snapshots/second. This is a
// leading/trailing-friendly throttle, not a debounce: repeated geometry
// signals do not restart the timer, and snapshot() always reads the latest
// frameGeometry when the timer fires.
const geometrySnapshotTimer = new QTimer();
geometrySnapshotTimer.interval = 80;
geometrySnapshotTimer.singleShot = true;
let geometrySnapshotPending = false;
geometrySnapshotTimer.timeout.connect(function() {
    geometrySnapshotPending = false;
    snapshot();
});

function scheduleGeometrySnapshot() {
    if (geometrySnapshotPending)
        return;
    geometrySnapshotPending = true;
    geometrySnapshotTimer.start();
}

function publishAction(command, found) {
    callDBus(service, path, iface, "Publish", JSON.stringify({
        type: "action",
        action: String(command.action || ""),
        id: normalizeId(command.id),
        // Shell-generated correlation id (e.g. engage-swap tickets). Absent
        // on commands that don't set one; round35 NEW-2 wires a consumer for
        // failed engage-swap receipts so a stuck engaging card can reset.
        ticket: command.ticket || undefined,
        found: found
    }));
}

function findWindow(id) {
    const wanted = normalizeId(id);
    const all = workspace.windowList();
    for (let i = 0; i < all.length; i++) {
        if (windowId(all[i]) === wanted)
            return all[i];
    }
    return null;
}

function findDesktop(id) {
    const wanted = normalizeId(id);
    const desktops = workspace.desktops;
    for (let i = 0; i < desktops.length; i++) {
        if (normalizeId(desktops[i].id) === wanted)
            return desktops[i];
    }
    return null;
}

function publishDesktops() {
    const desktops = workspace.desktops;
    const list = [];
    for (let i = 0; i < desktops.length; i++) {
        const item = desktops[i];
        const id = item && typeof item === "object" ? item.id : item;
        list.push({
            id: normalizeId(String(id || "")),
            name: item && typeof item === "object" ? String(item.name || "") : String(item || "")
        });
    }
    const current = workspace.currentDesktop;
    const currentId = current && typeof current === "object" ? current.id : current;
    callDBus(service, path, iface, "Publish", JSON.stringify({
        type: "desktops",
        desktops: list,
        current: normalizeId(String(currentId || ""))
    }));
}

function handleCommand(serialized) {
    if (!serialized)
        return;

    print("[QuickshellWindowBridge] polled command=" + serialized);

    let command;
    try {
        command = JSON.parse(serialized);
    } catch (error) {
        print("[QuickshellWindowBridge] command JSON error=" + error);
        return;
    }

    // Virtual-desktop commands do not target a window. Handle them before the
    // window lookup below.
    if (command.action === "desktops") {
        publishDesktops();
        return;
    }
    // Shell (re)subscribe asks for a fresh authoritative snapshot: the daemon
    // replays its cached one, which can predate the current focus (all
    // activated=false) and there is no later windowActivated event to correct
    // it if focus never changes again.
    if (command.action === "refresh-snapshot") {
        scheduleSnapshot();
        return;
    }
    if (command.action === "update-layout") {
        publishAction(command, updateLayout(command));
        return;
    }
    if (command.action === "switch-desktop") {
        const desktop = findDesktop(command.id);
        if (!desktop) {
            print("[QuickshellWindowBridge] switch-desktop missing id=" + command.id);
            publishAction(command, false);
            return;
        }
        workspace.currentDesktop = desktop;
        publishAction(command, true);
        return;
    }
    if (command.action === "move-to-desktop") {
        const window = findWindow(command.windowId);
        const desktop = findDesktop(command.desktopId);
        if (!window || !desktop) {
            print("[QuickshellWindowBridge] move-to-desktop missing window/desktop");
            publishAction(command, false);
            return;
        }
        window.desktops = [desktop];
        if (command.activate)
            setActiveWindow(window);
        publishAction(command, true);
        scheduleSnapshot();
        return;
    }

    // Group activation (macOS semantics): restore every window of an app
    // together, then focus the one the user targeted. This must be ONE atomic
    // command — the shell coalesces consecutive "activate" commands into a
    // single pending slot, so sibling restores sent separately get overwritten
    // by the focus activation and never reach KWin.
    if (command.action === "activate-group") {
        const ids = Array.isArray(command.ids) ? command.ids : [];
        const restores = [];
        let focused = null;
        let restored = 0;
        for (let i = 0; i < ids.length; i++) {
            const groupWindow = findWindow(ids[i]);
            if (!groupWindow)
                continue;
            try {
                const geo = takeParkedGeometry(groupWindow);
                // 先复位再解除最小化：解除最小化的重映射瞬间窗口必须已在
                // 真位置——映射在 5000 上再变活动窗，KWin 的"活动窗拽回
                // 工作区"钳位会在异步重放里盖掉之后排队的任何写入（实测）
                if (geo)
                    groupWindow.frameGeometry = geo;
                restoreWithAnimation(groupWindow, command.forceAnim);
                // 实时卡片模式把后台窗压在桌面底层（keepBelow）；整组激活
                // 即走向前台，压底标记必须一并摘掉
                groupWindow.keepBelow = false;
                if (geo)
                    restores.push({ window: groupWindow, geo: geo });
                restored++;
                if (ids[i] === command.focusId)
                    focused = groupWindow;
            } catch (error) {
                print("[QuickshellWindowBridge] activate-group restore failed"
                      + " id=" + ids[i] + " error=" + error);
            }
        }
        if (focused)
            setActiveWindow(focused);
        // 复位写在激活之后（见 takeParkedGeometry 头注释：先写后激活会被
        // KWin 的"活动窗拽回工作区"钳位盖掉）
        for (let r = 0; r < restores.length; r++)
            applyRestore(restores[r].window, restores[r].geo);
        print("[QuickshellWindowBridge] activate-group restored=" + restored
              + " focused=" + (focused ? 1 : 0));
        // 回执 = 真实结果：全部 findWindow 落空（窗在入队到执行的 50ms
        // 间隙全关了）必须报 found=false，shell 侧才知道命令没生效
        publishAction(command, restored > 0);
        scheduleSnapshot();
        return;
    }

    if (command.action === "engage-swap") {
        // 点击卡片的同拍交换（activate+minimize 一条命令一个 tick 处理完）：
        // 分开发 activate-group + N 条 minimize 会按桥 50ms 轮询一拍一条，
        // 收编比激活晚一拍起跑（实测 50ms，实时模式肉眼可见"慢半拍"）。
        // 顺序：还原/摘压底 → 聚焦 → 收编（三段事件在同一脚本 tick 内
        // 触发，特效动画同帧起跑）。
        const actIds = Array.isArray(command.ids) ? command.ids : [];
        const minIds = Array.isArray(command.minimizeIds)
            ? command.minimizeIds : [];
        const restores = [];
        let focused = null;
        let restored = 0;
        for (let i = 0; i < actIds.length; i++) {
            const groupWindow = findWindow(actIds[i]);
            if (!groupWindow)
                continue;
            try {
                const geo = takeParkedGeometry(groupWindow);
                // 先复位再解除最小化（同 activate-group：重映射在停泊位上
                // 会触发活动窗钳位的异步重放，盖掉后续写入）
                if (geo)
                    groupWindow.frameGeometry = geo;
                restoreWithAnimation(groupWindow, command.forceAnim);
                groupWindow.keepBelow = false;
                if (geo)
                    restores.push({ window: groupWindow, geo: geo });
                restored++;
                if (actIds[i] === command.focusId)
                    focused = groupWindow;
            } catch (error) {
                print("[QuickshellWindowBridge] engage-swap restore failed"
                      + " id=" + actIds[i] + " error=" + error);
            }
        }
        if (focused)
            setActiveWindow(focused);
        // 复位写在激活之后（activate-clamp 会盖掉激活前提交的几何写入）
        for (let r = 0; r < restores.length; r++)
            applyRestore(restores[r].window, restores[r].geo);
        let collected = 0;
        for (let m = 0; m < minIds.length; m++) {
            const demoted = findWindow(minIds[m]);
            if (!demoted)
                continue;
            try {
                demoted.minimized = true;
                collected++;
            } catch (error) {
                print("[QuickshellWindowBridge] engage-swap collect failed"
                      + " id=" + minIds[m] + " error=" + error);
            }
        }
        print("[QuickshellWindowBridge] engage-swap restored=" + restored
              + " collected=" + collected
              + " focused=" + (focused ? 1 : 0));
        // 回执锚在焦点窗：被点组在入队→执行间隙被关掉（focused 落空）=
        // 交换没发生，shell 侧据此复位 engaging 卡（"卡片消失"自愈）
        publishAction(command, focused !== null);
        publishSnapshotNow();
        return;
    }

    if (command.action === "minimize-group") {
        // 桌面收编/整组退位的原子最小化：N 窗一条命令一个轮询拍内完成。
        // 逐窗命令按桥 50ms/条排队能把 N 窗收编拖到 N*50ms 之后——比
        // 显示桌面开关的 400ms 防抖还长，快速第二击会在管线中途插进来
        //（实测复现：第一击的最小化还没全部落地、第二击已清状态跑恢复，
        // 用户看到"卡片出现、程序没收回去"）。
        const ids = Array.isArray(command.ids) ? command.ids : [];
        let collected = 0;
        for (let i = 0; i < ids.length; i++) {
            const demoted = findWindow(ids[i]);
            if (!demoted)
                continue;
            try {
                demoted.minimized = command.value !== false;
                collected++;
            } catch (error) {
                print("[QuickshellWindowBridge] minimize-group failed"
                      + " id=" + ids[i] + " error=" + error);
            }
        }
        print("[QuickshellWindowBridge] minimize-group collected=" + collected
              + " of " + ids.length);
        publishAction(command, collected > 0);
        publishSnapshotNow();
        return;
    }

    const window = findWindow(command.id);
    if (!window) {
        print("[QuickshellWindowBridge] command target missing id=" + command.id);
        publishAction(command, false);
        return;
    }

        try {
        if (command.action === "activate") {
            // An app on another virtual desktop can be minimized. Restore it
            // before making it active, otherwise KWin may accept the request but
            // leave it invisible. 停泊窗必须先复位几何再激活（否则激活到屏幕外）。
            const geo = takeParkedGeometry(window);
            // 先复位再解除最小化（同 activate-group：重映射在停泊位上
            // 会触发活动窗钳位的异步重放）
            if (geo)
                window.frameGeometry = geo;
            restoreWithAnimation(window, command.forceAnim);
            setActiveWindow(window);
            // 激活后再写一次复位（保险带：任何钳位/重放时序都盖不过最后写）
            applyRestore(window, geo);
        } else if (command.action === "minimize") {
            window.minimized = command.value !== false;
        } else if (command.action === "keep-below") {
            // 实时卡片模式：静默还原后的后台窗压到桌面底层，不抢活动窗
            window.keepBelow = command.value !== false;
        } else if (command.action === "park") {
            // 实时卡片模式收编停泊：静默还原（suppress 名单在 shell 侧已
            // 落盘）→ 压底兜底 → 移到屏幕外，一个 tick 内完成不闪现。
            // ⚠️ 迟到的 park（入队后用户又点开了这扇窗）绝不执行：目标已是
            // 未最小化 = 它已在桌面展示，拽去屏幕外就是"窗口飞出桌面"
            if (command.value !== false && !window.minimized) {
                print("[QuickshellWindowBridge] park skipped engaged id="
                      + command.id);
                publishAction(command, true);
                return;
            }
            parkWindow(window, command.value !== false);
            if (command.value !== false) {
                window.minimized = false;
                window.keepBelow = true;
            }
        } else if (command.action === "close") {
            window.closeWindow();
        } else {
            // 防御缺口：未知 action 拿假成功回执会骗过 shell 侧的状态机
            //（未来新增 action 拼写不一致时静默失效）
            print("[QuickshellWindowBridge] unknown action="
                  + command.action);
            publishAction(command, false);
            return;
        }
        print("[QuickshellWindowBridge] command executed action=" + command.action
              + " id=" + windowId(window));
    } catch (error) {
        print("[QuickshellWindowBridge] command failed action=" + command.action
              + " id=" + windowId(window) + " error=" + error);
        publishAction(command, false);
        return;
    }

    publishAction(command, true);
    // minimize/park/close 等改收放状态的命令：立即补拍（见
    // publishSnapshotNow 注释——迟到的快照 = 卡片晚 ~200ms 出现）
    publishSnapshotNow();
}

function watchWindow(window) {
    if (!window)
        return;
    const watchedId = windowId(window);
    window.captionChanged.connect(scheduleSnapshot);
    window.desktopFileNameChanged.connect(scheduleSnapshot);
    window.activeChanged.connect(scheduleSnapshot);
    window.minimizedChanged.connect(scheduleSnapshot);
    window.fullScreenChanged.connect(scheduleSnapshot);
    // Kept defensive for an older KWin scripting API that lacks this signal.
    try { window.demandsAttentionChanged.connect(scheduleSnapshot); } catch (error) {}
    window.skipTaskbarChanged.connect(scheduleSnapshot);
    // Geometry/placement changes drive the Dock auto-hide collision judgement.
    // Each connect is defensive: one missing signal must not kill the bridge.
    try { window.frameGeometryChanged.connect(scheduleGeometrySnapshot); } catch (error) {}
    try { window.outputChanged.connect(scheduleGeometrySnapshot); } catch (error) {}
    try { window.maximizedChanged.connect(scheduleSnapshot); } catch (error) {}
    try { window.maximizeModeChanged.connect(scheduleSnapshot); } catch (error) {}
    try { window.desktopsChanged.connect(scheduleSnapshot); } catch (error) {}
    window.closed.connect(function() {
        if (watchedId)
            delete initialPlacementState[watchedId];
        scheduleSnapshot();
    });
}

// Runtime wiring.
const initial = workspace.windowList();
for (let i = 0; i < initial.length; i++)
    watchWindow(initial[i]);

// Publish one snapshot right after load: the daemon's replay cache starts
// empty on every platform restart, so without this a freshly (re)subscribed
// shell stays recordless (and activeWindowId-less) until some window event
// happens to fire.
scheduleSnapshot();

workspace.windowAdded.connect(function(window) {
    watchWindow(window);
    scheduleInitialPlacement(window);
    scheduleSnapshot();
});
// 停泊档案随窗销毁清理（原写在纯函数区——测试用 "Runtime-dependent
// bridge helpers" 标记切走 workspace 依赖段，顶层 connect 在标记前会让
// window-placement 测试 ReferenceError，自停泊落地起一直红着）
workspace.windowRemoved.connect(function(window) {
    delete parkedGeometry[windowId(window)];
});
workspace.windowRemoved.connect(scheduleSnapshot);
workspace.windowActivated.connect(scheduleSnapshot);

// Virtual-desktop lifecycle signals. KWin's QtScript API does not expose every
// signal name in every version, and one missing connect aborts the whole
// script (which would also stop the window snapshots). Connect defensively;
// snapshot() republishes the desktop list as a fallback, so the overview stays
// fresh even when every signal is unavailable.
function connectDesktopSignals() {
    const hooks = {
        desktopAdded: publishDesktops,
        desktopRemoved: publishDesktops,
        desktopNameChanged: publishDesktops,
        currentDesktopChanged: publishDesktops
    };
    for (const name in hooks) {
        try {
            if (workspace[name] && workspace[name].connect)
                workspace[name].connect(hooks[name]);
            else
                print("[QuickshellWindowBridge] desktop signal unavailable: " + name);
        } catch (error) {
            print("[QuickshellWindowBridge] desktop signal connect failed: " + name);
        }
    }
}
connectDesktopSignals();

const commandTimer = new QTimer();
// Commands are UI actions, so 50 ms keeps the Dock responsive while still
// cutting idle D-Bus traffic in half versus the old 25 ms interval.
commandTimer.interval = 50;
commandTimer.singleShot = false;
let commandPollInFlight = false;
let commandPollWatchdog = 0;
commandTimer.timeout.connect(function() {
    if (commandPollInFlight) {
        // If the daemon vanished (restart) the D-Bus callback may never
        // fire; reset the flag so polling resumes instead of wedging.
        if (++commandPollWatchdog >= 40) {  // ~2 s at 50 ms
            commandPollInFlight = false;
            commandPollWatchdog = 0;
        }
        return;
    }
    commandPollWatchdog = 0;
    commandPollInFlight = true;
    callDBus(service, path, iface, "TakeCommand", function(command) {
        commandPollInFlight = false;
        if (command)
            print("[QuickshellWindowBridge] polling callback received command");
        handleCommand(command);
        // Restart the 50 ms repeating timer so the next poll starts a fresh
        // interval (commands still process one per tick; see commandTimer).
        if (command)
            commandTimer.restart();
    });
});
commandTimer.start();

snapshot();
publishDesktops();
