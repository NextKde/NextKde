import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import { clearForApp, clearForTask, clearGroup, countForApp, countForTask, recordNotification,
         windowForNotification,
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

assert.equal(countForTask(groups, "linuxqq", "QQ", "", 2, normalize), 5,
    "grouped application icons retain the total");
assert.equal(countForTask(groups, "linuxqq", "QQ", "qq-1", 1, normalize), 5,
    "a sole window can display its application's count");
for (const windowId of ["qq-1", "qq-2"])
    assert.equal(countForTask(groups, "linuxqq", "QQ", windowId, 2, normalize), 0,
        "an application total must not be copied onto separate sibling windows");
assert.equal(countForTask(groups, "linuxqq", "QQ", "stale", 0, normalize), 0,
    "a removed task cannot inherit the application count");

const terminals = [11, 22].map((pid, i) => ({
    pid, windowId: `terminal-${i}`, handleId: `uuid-${i}`, title: "MainThread",
    identity: {desktopId: "org.kde.konsole.desktop", name: "Konsole"},
}));
const bell = {desktopEntry: "org.kde.konsole", appName: "Konsole",
              summary: "Konsole", body: '“MainThread”中的系统提示', senderPid: 22};
assert.equal(windowForNotification(bell, terminals, normalize), "terminal-1",
    "sender PID disambiguates identical terminal titles without compositor urgency");
assert.equal(windowForNotification({...bell, senderPid: 99}, terminals, normalize), "",
    "a foreign sender must not inherit an arbitrary window");
assert.equal(windowForNotification({...bell, senderPid: 0}, terminals, normalize), "",
    "application names alone cannot distinguish siblings");
assert.equal(windowForNotification(bell, [...terminals, {...terminals[1], windowId: "third"}], normalize), "",
    "multiple windows in one sender process are ambiguous");
assert.equal(windowForNotification({...bell, hints: {"x-kde-window-id": "uuid-0"}}, terminals, normalize), "terminal-0");
let scoped = recordNotification([], {...bell, windowId: "terminal-1"});
scoped = recordNotification(scoped, {...bell, windowId: "terminal-0"});
scoped = recordNotification(scoped, {...bell, windowId: "terminal-1"});
assert.equal(countForTask(scoped, bell.desktopEntry, "Konsole", "terminal-0", 2, normalize), 1);
assert.equal(countForTask(scoped, bell.desktopEntry, "Konsole", "terminal-1", 2, normalize), 2);
assert.equal(countForTask(scoped, bell.desktopEntry, "Konsole", "", 2, normalize), 3);
scoped = clearForTask(scoped, bell.desktopEntry, "Konsole", "terminal-0", 2, normalize);
assert.equal(countForTask(scoped, bell.desktopEntry, "Konsole", "terminal-0", 2, normalize), 0);
assert.equal(countForTask(scoped, bell.desktopEntry, "Konsole", "terminal-1", 2, normalize), 2,
    "reading one terminal must leave its sibling's unread count intact");

// Exercise the production model: even a NeedsAttention tray item must not
// mark both terminals urgent when only one compositor window requests it.
const source = readFileSync(new URL("../dock/DockModelService.qml", import.meta.url), "utf8");
const windows = [true, false].map((isUrgent, i) => ({
    windowId: `terminal-${i}`, pid: i + 1, isUrgent,
    identity: { desktopId: "org.kde.konsole", name: "Konsole" },
    toplevel: { activated: false, minimized: false, fullscreen: false },
}));
let items;
const config = { windowGrouping: "separate" };
const context = vm.createContext({
    ConfigService: config,
    WindowService: { records: windows, providerReady: true },
    TrayAttentionService: { needsAttention: () => true },
    svc: {
        _urgentInitDone: false, _lastUrgentIds: [], isAppPinned: () => false,
        _orderWindowItems() {}, _setWindowItems: value => { items = Array.from(value); },
    },
});
vm.runInContext(source.match(/^    function _refreshWindowItems\([^]*?^    \}/m)[0], context);
context._refreshWindowItems();
assert.deepEqual(items.map(item => item.isUrgent), [true, false]);
windows[0].isUrgent = false;
context._refreshWindowItems();
assert.ok(items.every(item => !item.isUrgent), "tray attention cannot leak to siblings");
windows.pop();
context._refreshWindowItems();
assert.equal(items[0].isUrgent, true, "a sole window retains tray attention");
windows.push({ ...windows[0], windowId: "terminal-1", pid: 2 });
config.windowGrouping = "grouped";
context._refreshWindowItems();
assert.equal(items.length, 1);
assert.equal(items[0].isUrgent, true, "grouped icons retain tray attention");

// Evaluate the production binding for separate window tasks and grouped icons.
const iconSource = readFileSync(new URL("../dock/DockIcon.qml", import.meta.url), "utf8");
const scopeBinding = iconSource.match(/readonly property string notificationWindowId:([^]*?)\n    readonly property int notificationCount:/)[1];
const countBinding = iconSource.match(/readonly property int notificationCount:([^]*?)\n    \/\//)[1];
const icon = {appId: bell.desktopEntry, displayName: "Konsole", isWindowItem: true, windowId: "terminal-0"};
let unread = recordNotification([], {...bell, windowId: "terminal-1"});
const badgeContext = vm.createContext({icon,
    WindowService: {windowsForApp: () => terminals},
    AppNotificationService: {countForTask: (...args) => countForTask(unread, ...args, normalize)}});
function badge() {
    icon.notificationWindowId = vm.runInContext(scopeBinding, badgeContext);
    return vm.runInContext(countBinding, badgeContext);
}
assert.equal(badge(), 0, "a separate task cannot inherit its sibling's count");
icon.windowId = "terminal-1";
assert.equal(badge(), 1, "the notifying sibling retains its badge");
unread = recordNotification(unread, {...bell, windowId: "terminal-0"});
assert.equal(badge(), 1, "each separate task displays only its own unread total");
icon.isWindowItem = false;
assert.equal(badge(), 2, "grouped icons still display the application total");

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
