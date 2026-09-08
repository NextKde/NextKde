import assert from "node:assert/strict";
import { clearForApp, clearGroup, countForApp, recordNotification,
         reportedCount } from "./NotificationCountMatch.mjs";

const normalize = value => String(value ?? "").replace(/<\d+>$/, "")
    .replace(/\.desktop$/i, "").toLowerCase().replace(/[-_\s.]/g, "");

let groups = [];
groups = recordNotification(groups, {
    desktopEntry: "linuxqq", appName: "QQ", summary: "Alice", body: "Hello"
});
groups = recordNotification(groups, {
    desktopEntry: "linuxqq", appName: "QQ", summary: "Bob", body: "Hello"
});
assert.equal(countForApp(groups, "linuxqq.desktop", "QQ", normalize), 2,
    "replacement notifications still count as separate incoming events");

groups = recordNotification(groups, {
    desktopEntry: "linuxqq", appName: "QQ",
    summary: "QQ", body: "你有 5 条新消息"
});
assert.equal(countForApp(groups, "linuxqq.desktop", "QQ", normalize), 5,
    "an application-reported unread total overrides event accumulation");
assert.equal(reportedCount("Mail", "12 unread messages", {}), 12);
assert.equal(reportedCount("Chat", "message 42", {}), null);
assert.equal(reportedCount("Chat", "ignored", { "badge-count": 7 }), 7);

groups = recordNotification(groups, {
    desktopEntry: "org.kde.dolphin.desktop", appName: "Dolphin"
});
assert.equal(countForApp(groups, "dolphin.desktop", "文件管理器", normalize), 0,
    "short suffixes must not match vendor-qualified application ids");
groups = clearGroup(groups, "linuxqq");
assert.equal(countForApp(groups, "linuxqq.desktop", "QQ", normalize), 0);
groups = clearForApp(groups, "org.kde.dolphin", "Dolphin", normalize);
assert.equal(groups.length, 0);

console.log("notification count matching: passed");
