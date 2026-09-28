// stage-groups.mjs — 台前侧栏的纯分组/排序/对账逻辑，QML 与 node 单测共用。
// 与 stage-geometry.mjs（几何）分工：这里只管"哪些窗口归同一张卡、卡片
// 以什么顺序排、ListModel 怎么对账"。不依赖任何 QML 单例——需要外部
// 状态的地方（缩略图探测）一律由调用方注入函数。

// ── 卡片模型字段 ──
// ListModel 角色 / delegate required property 的唯一出处（appKey 是主键，
// 不进差异比较）。新增卡片字段：加这里 + buildModelRows + 两处 required。
export const CARD_FIELDS = ["targetId", "pid", "appName", "title",
    "iconSource", "count", "idsJson"]

// ── 分组 ──

// 组键：desktopId 优先（同应用堆一张卡），无身份退 rawAppId，再退 pid
// （KWin 内部表面无身份时同 pid 的窗仍归同一张卡——pid 不会骗人）。
export function groupKeyOf(r) {
    return r.identity?.desktopId || r.identity?.rawAppId
        || ("pid:" + r.pid)
}

// 窗口是否落在指定桌面上
export function isOnDesktop(r, desktopId) {
    return r.onAllDesktops
        || (Array.isArray(r.desktopIds) && r.desktopIds.indexOf(desktopId) >= 0)
}

// 同进程（pid 相同）。XWayland 弹窗的身份解析常与主窗对不上，pid 是
// "同应用豁免"的第二重保险（第一重是 desktopId）。
export function isSameProcess(a, b) {
    return a.pid > 0 && a.pid === (b?.pid || 0)
}

// 同应用豁免双保险：同进程，或 desktopId 相同（空串不算相同——两个身份
// 未解析的窗口不该因此互认）。
export function isSameApp(a, b, appIdA, appIdB) {
    if (isSameProcess(a, b))
        return true
    return !!(appIdA && appIdA === appIdB)
}

// 把 records 分组（保持首次出现顺序），返回 [{ key, pid, wins }]。
//   opts.skipWindowId — 排除的窗口（当前活动窗：它就是"主窗"，不出卡）
//   opts.desktopId    — 只留该桌面上的窗口（缺省不筛；矩形发布跨桌面）
//   opts.requirePid   — 只留 pid > 0（无 pid 的 KWin 内部表面不碰）
//   opts.excludeKey   — 排除的组（激活应用的组：它的卡将离开侧栏）
//   opts.excludeKeepMinimized — 为真时，被排除组里已最小化的窗口仍保留。
//                       侧栏是最小化窗口的家：前台应用的最小化子窗若连卡
//                       都不出，那扇窗就困在"不可见 + 无卡"里点不回来了。
export function groupRecords(records, opts = {}) {
    const groups = []
    const byKey = ({})
    for (let i = 0; i < records.length; i++) {
        const r = records[i]
        if (opts.skipWindowId && r.windowId === opts.skipWindowId)
            continue
        if (opts.requirePid && !(r.pid > 0))
            continue
        if (opts.desktopId !== undefined && !isOnDesktop(r, opts.desktopId))
            continue
        const key = groupKeyOf(r)
        if (opts.excludeKey && key === opts.excludeKey
                && !(opts.excludeKeepMinimized && r.toplevel?.minimized))
            continue
        let wins = byKey[key]
        if (!wins) {
            wins = []
            byKey[key] = wins
            groups.push({ key: key, pid: r.pid || 0, wins: wins })
        }
        wins.push(r)
    }
    return groups
}

// 代表窗口：优先第一个未最小化的（可实时截图）；全最小化时优先已有缩略
// 图的（历史上截过图的那扇——组内兄弟窗口各存各的图，选错窗口卡片就只剩
// 占位符）；都没有则最后一个（激活时解锁）。thumbnailUrlOf 由调用方注入。
export function pickRepresentative(wins, thumbnailUrlOf) {
    for (let i = 0; i < wins.length; i++)
        if (!wins[i].toplevel?.minimized)
            return wins[i]
    for (let j = 0; j < wins.length; j++)
        if (thumbnailUrlOf(wins[j].windowId) !== "")
            return wins[j]
    return wins[wins.length - 1]
}

// 就地填充每组的展示字段（targetId/appName/title/iconSource/count/ids）
export function decorateGroups(groups, thumbnailUrlOf) {
    for (let g = 0; g < groups.length; g++) {
        const grp = groups[g]
        const rep = pickRepresentative(grp.wins, thumbnailUrlOf)
        grp.targetId = rep.windowId
        grp.appName = rep.identity?.name || rep.title || grp.key
        grp.title = rep.title || ""
        grp.iconSource = rep.iconSource || ""
        grp.count = grp.wins.length
        grp.ids = grp.wins.map(w => w.windowId)
    }
    return groups
}

// ── 组顺序表 ──
// 卡片点击 = 位置交换（退位组补到被点槽位），顺序由本表决定而不是
// records 顺序。新组排尾部，消失的组由 pruneOrder 清除。

const UNSORTED_OFFSET = 1000 // 不在表中的组排尾部（远大于真实索引数）

export function orderIndex(order, key) {
    const i = order.indexOf(key)
    return i < 0 ? order.length + UNSORTED_OFFSET : i
}

// 就地按顺序表稳定排序（组数通常 < 10，插入序的稳定性比算法更重要），
// 返回同一数组便于链式书写。
export function sortByOrder(order, groups) {
    for (let i = 1; i < groups.length; i++) {
        const g = groups[i]
        let j = i - 1
        while (j >= 0 && orderIndex(order, groups[j].key)
                > orderIndex(order, g.key)) {
            groups[j + 1] = groups[j]
            j--
        }
        groups[j + 1] = g
    }
    return groups
}

// 交换后的组顺序（返回新表，不改原表）：被点组移除；退位组（若不在表中）
// 插入被点槽位。同组切换/免收编时 demotedKey 传空串则不插入。
export function applySwapOrder(order, clickedKey, demotedKey) {
    const next = order.slice()
    const clickedIdx = next.indexOf(clickedKey)
    if (clickedIdx >= 0)
        next.splice(clickedIdx, 1)
    if (demotedKey && next.indexOf(demotedKey) < 0) {
        const at = Math.min(clickedIdx < 0 ? next.length : clickedIdx,
            next.length)
        next.splice(at, 0, demotedKey)
    }
    return next
}

// 清掉已消失的组（syncCards 每次对账时调用）
export function pruneOrder(order, liveKeys) {
    return order.filter(function(k) {
        return liveKeys.indexOf(k) >= 0
    })
}

// 顺序表对账 = 剪除已消失 + **补全新出现的组**（按 live 顺序稳定追加）。
// ⚠️ 只 prune 不补会退化成空表：播种曾靠滚轮换序（滚动改版时已删），
// applySwapOrder 只在换位时零星插键，重启后顺序表永远为空 → 排序与
// 交换预测全部失效（实测：窗口收编飞错槽位 = 发布矩形与卡片各排各的）。
export function mergeOrder(order, liveKeys) {
    const next = pruneOrder(order, liveKeys)
    for (let i = 0; i < liveKeys.length; i++) {
        if (next.indexOf(liveKeys[i]) < 0)
            next.push(liveKeys[i])
    }
    return next
}

// ── 换位提交门（dispatch 与记录翻转之间隔 100-250ms）──
// 派发时把预测顺序只喂特效发布；顺序表本体若提前转正，间隙里的对账
// （派发拍的缩略图事件恰好落在这个窗口）会按"新顺序"排"旧记录"——
// 被点槽位空置、邻卡顶位（N−1 布局），真快照到达再弹回 = 换位抽动。
// 换位请求在此排队，等退位组键真正出现在 sideGroups 的那次对账才
// applySwapOrder 转正，与模型变更同拍落地。TTL 内未进场（最小化被拦/
// 窗口已关）的换位作废；急速连点各自独立排队，无单槽互踩。

export const SWAP_COMMIT_TTL_MS = 2000

// 提交到期的换位（纯核，由 syncCards 每次对账调用）：demoted 已到场
// （arrivedKeys 含它）的换位逐个转正进 order；未到场的按 TTL 保留，
// 超时的作废。返回 { order, swaps } 由调用方写回。
export function commitDueSwaps(order, swaps, arrivedKeys, now) {
    let next = order
    const kept = []
    for (let i = 0; i < swaps.length; i++) {
        const swap = swaps[i]
        if (arrivedKeys.indexOf(swap.demoted) >= 0)
            next = applySwapOrder(next, swap.clicked, swap.demoted)
        else if (now - swap.at < SWAP_COMMIT_TTL_MS)
            kept.push(swap)
    }
    return { order: next, swaps: kept }
}

// ── ListModel 对账 ──

// 组数组 → 模型期望行（idsJson 序列化；同 key 去重保首个）。
export function buildModelRows(groups) {
    const rows = []
    const seen = ({})
    for (let i = 0; i < groups.length; i++) {
        const g = groups[i]
        if (seen[g.key])
            continue
        seen[g.key] = true
        rows.push({
            appKey: g.key,
            targetId: g.targetId,
            pid: g.pid || 0,
            appName: g.appName || "",
            title: g.title || "",
            iconSource: g.iconSource || "",
            count: g.count || 1,
            idsJson: JSON.stringify(g.ids || []),
        })
    }
    return rows
}

// 对账计划（syncCards 的纯核）：算出把 current 变成 desired 的最小操作表，
// QML 侧只负责执行。执行顺序有约定：
//   ① removes（行号基于 current，已降序，从尾往头删不打乱后续行号）
//   ② updates（row 基于删除后的模型；只含变化过的字段）
//   ③ appends（依次追加到尾部）
//   ④ moves（from/to 基于追加后的模型，按序执行；语义同 ListModel.move）
export function planModelSync(current, desired) {
    const desiredKeys = ({})
    for (let i = 0; i < desired.length; i++)
        desiredKeys[desired[i].appKey] = true
    const removes = []
    const kept = []
    for (let row = 0; row < current.length; row++) {
        if (desiredKeys[current[row].appKey])
            kept.push(current[row])
        else
            removes.push(row)
    }
    removes.reverse() // 降序
    const updates = []
    const appends = []
    const keptIndexByKey = ({})
    for (let k = 0; k < kept.length; k++)
        keptIndexByKey[kept[k].appKey] = k
    for (let j = 0; j < desired.length; j++) {
        const d = desired[j]
        const found = keptIndexByKey[d.appKey]
        if (found === undefined) {
            appends.push(d)
            continue
        }
        const fields = ({})
        for (let f = 0; f < CARD_FIELDS.length; f++) {
            const field = CARD_FIELDS[f]
            if (kept[found][field] !== d[field])
                fields[field] = d[field]
        }
        if (Object.keys(fields).length > 0)
            updates.push({ row: found, fields: fields })
    }
    // 行序对齐 desired 顺序（位置交换在此落地为真实卡位）——在与执行侧
    // 相同的"删除+追加后"的排列上仿真扫描，产出 moves 序列
    const arranged = kept.concat(appends)
    const moves = []
    for (let target = 0; target < desired.length
            && target < arranged.length; target++) {
        let row = -1
        for (let k = target; k < arranged.length; k++) {
            if (arranged[k].appKey === desired[target].appKey) {
                row = k
                break
            }
        }
        if (row !== target && row >= 0) {
            moves.push({ from: row, to: target })
            arranged.splice(target, 0, arranged.splice(row, 1)[0])
        }
    }
    return { removes: removes, updates: updates, appends: appends,
        moves: moves }
}
