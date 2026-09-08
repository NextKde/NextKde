import assert from "node:assert/strict";
import { collectAttentionKeys, matchesAttention } from "./TrayAttentionMatch.mjs";

const normalize = value => String(value ?? "").replace(/\.desktop$/i, "")
    .toLowerCase().replace(/[-_\s.]/g, "");
const items = [
    { id: "com.tencent.WeChat", title: "微信", status: 2 },
    { id: "network-manager", title: "Network", status: 1 },
    { id: "org.example.Mail", title: "Mail", status: 2 },
];
const keys = collectAttentionKeys(items, 2, normalize);
assert.equal(matchesAttention(keys, "com.tencent.WeChat.desktop", "微信", normalize), true);
assert.equal(matchesAttention(keys, "org.example.Mail.desktop", "Mail", normalize), true);
assert.equal(matchesAttention(keys, "network-manager.desktop", "Network", normalize), false);
assert.equal(matchesAttention(keys, "com.tencent.WeChatBeta.desktop", "微信测试版", normalize), false);
assert.equal(matchesAttention(keys, "org.example.Other.desktop", "Other", normalize), false);
console.log("tray attention matching: passed");
