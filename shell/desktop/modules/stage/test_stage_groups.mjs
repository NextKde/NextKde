// test_stage_groups.mjs — stage-groups 纯函数回归门（分组/顺序表/模型对账）
// 运行：node shell/desktop/modules/stage/test_stage_groups.mjs
import assert from "node:assert/strict";
import {
    CARD_FIELDS,
    groupKeyOf, isOnDesktop, isSameProcess, isSameApp,
    groupRecords, pickRepresentative, decorateGroups,
    orderIndex, sortByOrder, applySwapOrder, pruneOrder, mergeOrder, moveOrderKey,
    SWAP_COMMIT_TTL_MS, commitDueSwaps,
    buildModelRows, planModelSync,
    applyMerge, splitGroup, pruneOverrides,
} from "./stage-groups.mjs";

const cases = [];
function check(name, actual, expected) {
    assert.deepEqual(actual, expected, name);
    cases.push(name);
}

// 测试窗口记录（字段形状同 WindowService.records 的消费子集）
let seq = 0;
function rec(overrides = {}) {
    seq++;
    return Object.assign({
        windowId: "w" + seq,
        handleId: "h" + seq,
        pid: 1000 + seq,
        title: "窗口" + seq,
        iconSource: "",
        onAllDesktops: false,
        desktopIds: ["desk1"],
        identity: {},
        toplevel: { minimized: false },
    }, overrides);
}

// ── groupKeyOf：desktopId > rawAppId > pid ──
check("key: desktopId wins", groupKeyOf(rec({ identity: { desktopId: "d", rawAppId: "r" } })), "d");
check("key: rawAppId fallback", groupKeyOf(rec({ identity: { rawAppId: "r" } })), "r");
check("key: pid fallback", groupKeyOf(rec({ identity: {}, pid: 42 })), "pid:42");

// ── isOnDesktop ──
check("desktop: onAllDesktops", isOnDesktop(rec({ onAllDesktops: true, desktopIds: [] }), "deskX"), true);
check("desktop: listed", isOnDesktop(rec({ desktopIds: ["a", "b"] }), "b"), true);
check("desktop: not listed", isOnDesktop(rec({ desktopIds: ["a"] }), "b"), false);
check("desktop: no desktopIds array", isOnDesktop(rec({ desktopIds: undefined }), "b"), false);

// ── 同进程 / 同应用双保险 ──
check("process: same pid", isSameProcess(rec({ pid: 7 }), rec({ pid: 7 })), true);
check("process: pid 0 never matches", isSameProcess(rec({ pid: 0 }), rec({ pid: 0 })), false);
check("process: null record", isSameProcess(rec({ pid: 7 }), null), false);
check("app: same desktopId", isSameApp(rec({ pid: 1 }), rec({ pid: 2 }), "chrome", "chrome"), true);
check("app: empty appIds not equal", isSameApp(rec({ pid: 1 }), rec({ pid: 2 }), "", ""), false);
check("app: different appIds", isSameApp(rec({ pid: 1 }), rec({ pid: 2 }), "a", "b"), false);
check("app: pid path wins", isSameApp(rec({ pid: 9 }), rec({ pid: 9 }), "a", "b"), true);

// ── groupRecords ──
const wins = [
    rec({ windowId: "active", identity: { desktopId: "chrome" } }),
    rec({ windowId: "w1", pid: 5, identity: { desktopId: "chrome" } }),
    // 身份完全缺失的窗按 pid 成组（同 pid 归同组，XWayland 弹窗场景）
    rec({ windowId: "p1", pid: 5, identity: {} }),
    rec({ windowId: "p2", pid: 5, identity: {} }),
    rec({ windowId: "w3", identity: { desktopId: "zcode" } }),
    rec({ windowId: "other-desk", identity: { desktopId: "kate" }, desktopIds: ["desk2"] }),
    rec({ windowId: "nopid", pid: 0, identity: { desktopId: "kwin-internal" } }),
];
let groups = groupRecords(wins, { desktopId: "desk1", skipWindowId: "active" });
check("group count", groups.length, 4);
check("group order preserved", groups.map(g => g.key),
    ["chrome", "pid:5", "zcode", "kwin-internal"]);
check("same pid merged (no identity)", groups[1].wins.map(w => w.windowId), ["p1", "p2"]);
check("group pid from first record", groups[0].pid, 5);

groups = groupRecords(wins, { desktopId: "desk1", skipWindowId: "active", requirePid: true });
check("requirePid drops pid=0 group", groups.map(g => g.key),
    ["chrome", "pid:5", "zcode"]);

groups = groupRecords(wins, { desktopId: "desk1", skipWindowId: "active", excludeKey: "chrome" });
check("excludeKey drops active app group", groups.map(g => g.key),
    ["pid:5", "zcode", "kwin-internal"]);

groups = groupRecords(wins, {});
check("no opts: everything groups", groups.length, 5);

// ── 前台应用整组排除（excludeKeepMinimized）──
// 活动窗 + 桌面兄弟 + 最小化兄弟同组：桌面兄弟不出卡，最小化兄弟保留
//（侧栏是最小化窗口的家，否则那扇窗困在"不可见+无卡"里）
const front = [
    rec({ windowId: "fa", identity: { desktopId: "app" } }),
    rec({ windowId: "fb", identity: { desktopId: "app" },
        toplevel: { minimized: true } }),
    rec({ windowId: "fc", identity: { desktopId: "app" } }),
    rec({ windowId: "bg", identity: { desktopId: "other" } }),
];
check("front app: desktop sibling cardless, minimized sibling keeps card",
    groupRecords(front, { skipWindowId: "fa", excludeKey: "app",
        excludeKeepMinimized: true })
        .map(g => g.key + ":" + g.wins.map(w => w.windowId).join(",")),
    ["app:fb", "other:bg"]);
check("front app: without keepMinimized whole group excluded",
    groupRecords(front, { skipWindowId: "fa", excludeKey: "app" })
        .map(g => g.key),
    ["other"]);

// ── 代表窗口与展示字段 ──
const thumbs = { w1: "file:///t1.png" };
const thumbOf = id => thumbs[id] || "";
check("rep: first non-minimized",
    pickRepresentative([rec({ windowId: "a", toplevel: { minimized: true } }),
        rec({ windowId: "b" }), rec({ windowId: "c" })], thumbOf).windowId, "b");
check("rep: falls back to captured thumbnail",
    pickRepresentative([rec({ windowId: "a", toplevel: { minimized: true } }),
        rec({ windowId: "w1", toplevel: { minimized: true } })], thumbOf).windowId, "w1");
check("rep: all invisible → last",
    pickRepresentative([rec({ windowId: "a", toplevel: { minimized: true } }),
        rec({ windowId: "b", toplevel: { minimized: true } })], thumbOf).windowId, "b");

const decorated = decorateGroups(groupRecords(wins, { desktopId: "desk1", skipWindowId: "active" }),
    thumbOf);
check("decorate: fields filled from representative",
    { targetId: decorated[0].targetId, count: decorated[0].count,
        ids: decorated[0].ids },
    { targetId: "w1", count: 1, ids: ["w1"] });
check("decorate: appName falls back to title then key",
    decorateGroups([groupRecords([rec({ windowId: "z", title: "终端", identity: { desktopId: "x" } })], {})[0]],
        thumbOf)[0].appName, "终端");

// ── 顺序表 ──
check("orderIndex: known", orderIndex(["a", "b"], "b"), 1);
check("orderIndex: unknown goes tail", orderIndex(["a", "b"], "z"), 2 + 1000);
check("sortByOrder: unknowns keep relative order (stable)",
    sortByOrder(["a"], [{ key: "y" }, { key: "a" }, { key: "x" }]).map(g => g.key),
    ["a", "y", "x"]);
check("sortByOrder: full reorder",
    sortByOrder(["c", "b", "a"], [{ key: "a" }, { key: "b" }, { key: "c" }]).map(g => g.key),
    ["c", "b", "a"]);

// 交换：被点组移除、退位组补到被点槽位；原表不被修改
const order = ["chrome", "zcode", "kate"];
check("swap: clicked removed, demoted already in table",
    applySwapOrder(order, "zcode", "kate"), ["chrome", "kate"]);
check("swap: new demoted fills clicked slot",
    applySwapOrder(["chrome", "zcode"], "chrome", "kate"), ["kate", "zcode"]);
check("swap: demoted already a card → stays, clicked just removed",
    applySwapOrder(["chrome", "zcode", "kate"], "chrome", "kate"),
    ["zcode", "kate"]);
check("swap: input table untouched", order, ["chrome", "zcode", "kate"]);
check("swap: demoted already in table → not duplicated",
    applySwapOrder(["a", "b", "c"], "b", "c"), ["a", "c"]);
check("swap: clicked not in table → demoted appended",
    applySwapOrder(["a", "b"], "zzz", "n"), ["a", "b", "n"]);
check("swap: no demoted → just remove",
    applySwapOrder(["a", "b", "c"], "b", ""), ["a", "c"]);

check("pruneOrder", pruneOrder(["a", "gone", "b"], ["a", "b", "c"]), ["a", "b"]);
// mergeOrder：剪除 + 补全（空表播种——只 prune 会永远空表，排序/交换失效）
check("mergeOrder seeds empty order",
    mergeOrder([], ["a", "b", "c"]), ["a", "b", "c"]);
check("mergeOrder keeps known order, appends new",
    mergeOrder(["c", "a"], ["a", "b", "c"]), ["c", "a", "b"]);
check("mergeOrder prunes dead",
    mergeOrder(["c", "dead", "a"], ["a", "c"]), ["c", "a"]);

// commitDueSwaps：换位提交门——退位键到场才转正，未到场按 TTL 保留，
// 超时作废（dispatch 与记录翻转隔 100-250ms，提前转正会让中间对账按
// 新序排旧记录 = 邻卡顶位再弹回的换位抽动）
const t0 = 1000000;
check("commit: due swap lands in order",
    commitDueSwaps(["chrome", "zcode"],
        [{ clicked: "chrome", demoted: "kate", at: t0 }],
        ["kate", "zcode"], t0 + 500),
    { order: ["kate", "zcode"], swaps: [] });
check("commit: demoted not arrived → order untouched, swap kept",
    commitDueSwaps(["chrome", "zcode"],
        [{ clicked: "chrome", demoted: "kate", at: t0 }],
        ["zcode"], t0 + 500),
    { order: ["chrome", "zcode"],
        swaps: [{ clicked: "chrome", demoted: "kate", at: t0 }] });
check("commit: expired swap dropped",
    commitDueSwaps(["chrome", "zcode"],
        [{ clicked: "chrome", demoted: "kate", at: t0 }],
        ["zcode"], t0 + SWAP_COMMIT_TTL_MS + 1),
    { order: ["chrome", "zcode"], swaps: [] });
check("commit: pending swap survives just inside TTL",
    commitDueSwaps(["a"], [{ clicked: "a", demoted: "b", at: t0 }], [],
        t0 + SWAP_COMMIT_TTL_MS - 1),
    { order: ["a"], swaps: [{ clicked: "a", demoted: "b", at: t0 }] });
check("commit: mixed batch — first due, second pending",
    commitDueSwaps(["a", "b"],
        [{ clicked: "a", demoted: "x", at: t0 },
         { clicked: "b", demoted: "y", at: t0 + 10 }],
        ["x", "b"], t0 + 100),
    { order: ["x", "b"],
        swaps: [{ clicked: "b", demoted: "y", at: t0 + 10 }] });
check("commit: rapid alternation — both due, sequential commits",
    commitDueSwaps(["a", "b"],
        [{ clicked: "a", demoted: "x", at: t0 },
         { clicked: "b", demoted: "y", at: t0 + 10 }],
        ["x", "y"], t0 + 100),
    { order: ["x", "y"], swaps: [] });

// ── 模型对账 ──
check("CARD_FIELDS shape", CARD_FIELDS,
    ["targetId", "pid", "appName", "title", "iconSource", "count",
     "idsJson", "iconsJson", "merged"]);

function row(appKey, over = {}) {
    return Object.assign({ appKey, targetId: "t-" + appKey, pid: 1,
        appName: appKey, title: "", iconSource: "i", count: 1,
        idsJson: '["t-' + appKey + '"]' }, over);
}

// 用与 ListModel 相同的 splice 语义执行计划，验证 plan 确实把 current 变成 desired
function applyPlan(rows, plan) {
    const out = rows.slice();
    for (const r of plan.removes)
        out.splice(r, 1);
    for (const u of plan.updates)
        out[u.row] = Object.assign({}, out[u.row], u.fields);
    out.push(...plan.appends);
    for (const m of plan.moves)
        out.splice(m.to, 0, out.splice(m.from, 1)[0]);
    return out;
}

check("plan: fresh → all appends",
    planModelSync([], [row("a"), row("b")]),
    { removes: [], updates: [], appends: [row("a"), row("b")], moves: [] });

const same = [row("a"), row("b")];
check("plan: identical → no ops",
    planModelSync(same, same.slice()),
    { removes: [], updates: [], appends: [], moves: [] });

check("plan: field change → minimal update",
    planModelSync([row("a", { count: 1 })], [row("a", { count: 3 })]).updates,
    [{ row: 0, fields: { count: 3 } }]);

const withGone = planModelSync([row("a"), row("gone"), row("b")], [row("a"), row("b")]);
check("plan: removal detected", withGone.removes, [1]);
check("plan: removal applies", applyPlan([row("a"), row("gone"), row("b")], withGone),
    [row("a"), row("b")]);

const mix = planModelSync([row("a"), row("old"), row("b")],
    [row("b"), row("a"), row("new")]);
check("plan: mixed ops land on desired", applyPlan(
    [row("a"), row("old"), row("b")], mix), [row("b"), row("a"), row("new")]);

const reorder = planModelSync([row("a"), row("b"), row("c")],
    [row("c"), row("a"), row("b")]);
check("plan: reorder moves", applyPlan([row("a"), row("b"), row("c")], reorder),
    [row("c"), row("a"), row("b")]);
check("plan: identity → no moves", planModelSync([row("b"), row("a")], [row("b"), row("a")]).moves, []);

// 组数组 → 模型行：idsJson 序列化、同 key 去重
check("buildModelRows: fields + dedup",
    buildModelRows([
        { key: "a", pid: 5, targetId: "t1", appName: "A", title: "x",
            iconSource: "i", count: 2, ids: ["t1", "t2"] },
        { key: "a", pid: 6, targetId: "t3", appName: "A", title: "y",
            iconSource: "i", count: 1, ids: ["t3"] },
    ]),
    [{ appKey: "a", targetId: "t1", pid: 5, appName: "A", title: "x",
        iconSource: "i", count: 2, idsJson: '["t1","t2"]',
        iconsJson: '[]', merged: false }]);

// moveOrderKey：拖拽换位
check("move 前移尾→头", moveOrderKey(["a", "b", "c"], "c", 0), ["c", "a", "b"]);
check("move 后移头→尾", moveOrderKey(["a", "b", "c"], "a", 2), ["b", "c", "a"]);
check("move 中移一位", moveOrderKey(["a", "b", "c"], "b", 2), ["a", "c", "b"]);
check("move 原地不动", moveOrderKey(["a", "b"], "a", 0), ["a", "b"]);
check("move 索引越界原样", moveOrderKey(["a", "b"], "a", 5), ["a", "b"]);
check("move 键缺失原样", moveOrderKey(["a", "b"], "z", 0), ["a", "b"]);


// ── 自由组合（覆盖键层）──
{
    const mk = (id, h, did) => ({ windowId: id, handleId: h, pid: 10,
        toplevel: {}, identity: { desktopId: did },
        iconSource: "icon-" + did });
    const recs = [mk("w1", "h1", "a"), mk("w2", "h2", "b"),
        mk("w3", "h3", "a")];

    // 覆盖键优先于自然键
    check("override key wins", groupKeyOf(recs[0], { h1: "b" }), "b");
    check("override miss falls back", groupKeyOf(recs[1], { h1: "b" }), "b");

    // 合并：fromKey 组全部并进 toKey；无变化返回**原引用**（消费端
    // `next === root._mergeOverrides` 据此跳过保存/syncCards——引用回归
    // 改成返回副本会让 no-op 检测全部失效，锁引用而非值相等）
    let ov = applyMerge({}, recs, "a", "b");
    check("merge writes both windows", ov, { h1: "b", h3: "b" });
    assert.equal(applyMerge(ov, recs, "b", "b"), ov, "merge self no-op ref");
    cases.push("merge self is no-op (ref)");
    // fromKey 已无任何 record（260ms 动画窗口内窗口消失）同样原引用——
    // 合并动画 no-op 分支的承重契约（2026-09-30 审计补）
    assert.equal(applyMerge(ov, [], "ghost", "b"), ov, "no-record no-op ref");
    cases.push("merge no-record is no-op (ref)");

    // 分组：合成一张 merged 卡，每窗图标齐全
    const groups = groupRecords(recs, { overrides: ov });
    check("merged into one group", groups.length, 1);
    check("group key is target", groups[0].key, "b");
    check("group merged flag", groups[0].merged, true);
    const rows = buildModelRows(decorateGroups(groups, () => ""));
    check("row icons per window", JSON.parse(rows[0].iconsJson),
        ["icon-a", "icon-b", "icon-a"]);

    // 拆散：组内覆盖全部清除
    ov = splitGroup(ov, recs, "b");
    check("split clears overrides", ov, {});
    const regrouped = groupRecords(recs, { overrides: ov });
    check("split restores natural groups", regrouped.length, 2);

    // 剪枝：死窗口的覆盖项清掉；全活 = 原引用（同上锁引用：返回入参本身）
    check("prune drops dead handles",
        pruneOverrides({ h1: "b", h9: "x" }, { h1: 1 }), { h1: "b" });
    const allLive = { h1: "b" };
    assert.equal(pruneOverrides(allLive, { h1: 1 }), allLive,
        "prune all-live no-op ref");
    cases.push("prune all-live is no-op (ref)");
}

console.log(`stage-groups: ${cases.length} checks passed`);
