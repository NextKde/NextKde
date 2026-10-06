// stage-live 协议字段契约测试：发布端（StageSidebarWindow.publishLiveCards）
// 与消费端（vendor stageanim.cpp 的 reloadLiveCards 解析）的卡字段名
// 是两侧手抄的——任何 rename 在特效侧静默失配（toDouble(默认) 吞掉）。
// 本测试正则摄取两侧键名，双向断言：①特效解析的每个卡字段都在发布
// 载荷里；②发布载荷的每个键都被特效解析（或列入下方白名单——防止
// 死字段悄悄堆积，grabDX/grabDY 就是这么发现的）。顶层键单独核对。
import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";

const here = new URL(".", import.meta.url);
const sidebar = readFileSync(
    new URL("StageSidebarWindow.qml", here), "utf8");
// 双布局探测（上游重构后 kwin/，本地开发 vendor/）
const effectRel = ["../../../../kwin/kwin-effects-stageanim/src/stageanim.cpp",
    "../../../../vendor/kwin-effects-stageanim/src/stageanim.cpp"]
    .map(rel => new URL(rel, here));
const effectUrl = effectRel.find(u => existsSync(u));
assert(effectUrl, "stageanim.cpp not found in either layout");
const effect = readFileSync(effectUrl, "utf8");

// ── 发布端：publishLiveCards 的 out.push({...}) 对象里的顶层键 ──
// （先剥行注释再取键——行尾注释不带逗号会把下一键吞进同一段）。
// matchAll 合并全部块（v87 审查）：旧版非贪婪单块匹配停在第一个 })，
// 将来在它之前出现任何含 }) 的 out.push 会把后半字段静默截走＝死字段
// 检测变盲
const pushBlocks = [...sidebar.matchAll(/out\.push\(\{([\s\S]*?)\}\)/g)];
assert(pushBlocks.length > 0, "publishLiveCards out.push block not found");
const noComments = pushBlocks.map(m => m[1])
    .join("\n").split("\n").map(l => l.replace(/\/\/.*$/, "")).join("\n");
const published = new Set(["id", ...noComments
    .split(",")
    .map(kv => kv.trim().split(":")[0].trim())
    .filter(k => /^[A-Za-z_][A-Za-z0-9_]*$/.test(k))]);

// ── 消费端：reloadLiveCards 解析块里 o.value(QStringLiteral("...")) ──
const reloadBlock = effect.slice(
    effect.indexOf("void StageAnimEffect::reloadLiveCards"),
    effect.indexOf("bool StageAnimEffect::expireAbsentLiveCards"));
assert(reloadBlock.length > 0, "reloadLiveCards block not found");
const parsed = [...reloadBlock.matchAll(
    /o\.value\(QStringLiteral\("([A-Za-z_][A-Za-z0-9_]*)"\)\)/g)]
    .map(m => m[1]);
const parsedCard = parsed.filter(k => k !== "id" && k !== "winId");

let cases = 0;
for (const k of parsedCard) {
    cases++;
    assert(published.has(k),
        `effect parses "${k}" but publishLiveCards does not send it`);
}
assert(parsedCard.length >= 30,
    `suspiciously few parsed fields (${parsedCard.length}) — parser moved?`);
assert(published.has("winId"), "v3 winId field missing from publish");
cases += 2;

// 反向：发布侧死字段检测（白名单=发布但特效有意不读的键）
const publishWhitelist = new Set([]);
for (const k of published) {
    if (k === "id" || k === "winId")
        continue;
    cases++;
    assert(parsedCard.includes(k) || publishWhitelist.has(k),
        `publishLiveCards sends "${k}" but effect never parses it `
        + `(dead payload field — remove it or whitelist intentionally)`);
}

console.log(`stage-protocol: ${cases} checks passed `
    + `(${parsedCard.length} card fields verified)`);
