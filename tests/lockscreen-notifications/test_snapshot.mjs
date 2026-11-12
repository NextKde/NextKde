import assert from "node:assert/strict";
import {snapshot} from "../../shell/desktop/modules/notifications/LockScreenNotificationSnapshot.mjs";

const policy = {ready: true, historyEnabled: true, doNotDisturbEnabled: false,
    isKeyBlocked: key => key === "desktop:blocked"};
const row = (n, extra = {}) => ({historyKey: n, timestamp: 1700000000000 + n,
    sourceKey: "desktop:mail", appName: "Mail <b>literal</b>", appIcon: "org.kde.kmail",
    // Even touching these private fields is a bug, regardless of preview settings.
    get summary() { throw Error("private summary read"); },
    get body() { throw Error("private body read"); },
    get actions() { throw Error("private actions read"); }, ...extra});
function project(rows, overrides = {}) {
    return snapshot({count: rows.length, get: index => rows[index]}, {...policy, ...overrides});
}
assert.deepEqual(project([row(1)], {ready: false}), []);
assert.deepEqual(project([row(1)], {historyEnabled: false}), []);
assert.deepEqual(project([row(1)], {doNotDisturbEnabled: true}), []);
assert.deepEqual(project([row(1, {sourceKey: "desktop:blocked"})]), []);
const result = project([row(6, {sourceKey: "desktop:blocked"}), ...[5, 4, 3, 2, 1].map(n => row(n))]);
assert.equal(result.length, 4);
assert.deepEqual(result.map(n => n.id), ["5", "4", "3", "2"]);
assert.deepEqual(Object.keys(result[0]), ["id", "appName", "appIcon", "createdAt", "summary", "body"]);
assert.equal(result[0].summary, "");
assert.equal(result[0].body, "");
assert.equal(result[0].appName, "Mail <b>literal</b>");
for (const icon of ["file:///private.png", "/tmp/icon.svg", "https://evil.invalid/icon", "image://provider/secret", "../icon", "qrc:/x.qml"])
    assert.equal(project([row(1, {appIcon: icon})])[0].appIcon, "");
assert.equal(project([row(1, {appName: "a\nb\0c"})])[0].appName, "a b c");
assert.equal(project([row(1, {appName: "a".repeat(300)})])[0].appName.length, 256);
assert.deepEqual(project([row(1, {timestamp: NaN}), row(2, {timestamp: -1})]), []);
assert.deepEqual(project([]), []);
console.log("Privacy projection: gates, blocking, cap, field whitelist and unsafe icons passed");
