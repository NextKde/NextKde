import assert from "node:assert/strict";
import { friendlyName, isInternalId, nameFromId } from "./TrayIdentity.mjs";

const id = "chrome_status_icon_1";
const qq = {id, tooltipTitle: "", title: ""};
const buddy = {id, tooltipTitle: "WorkBuddy", title: ""};
const gpt = {id, tooltipTitle: "ChatGPT", title: ""};
const apps = [qq, buddy, gpt];
const stale = {[id]: "QQ"};
assert.equal(friendlyName(buddy, stale, {}, apps), "WorkBuddy");
assert.equal(friendlyName(gpt, stale, {}, apps), "ChatGPT");
assert.equal(friendlyName(qq, stale, {}, apps), "QQ");
for (const title of ["WorkBuddy", "OneDrive", "RustDesk", "SPlayer Next", "微信"]) {
    assert.equal(friendlyName({id, tooltipTitle: title}, stale), title);
}
assert.equal(isInternalId("WorkBuddy"), false);
assert.equal(isInternalId("2cUW32wlKy"), true);
assert.equal(nameFromId("WorkBuddy_status_icon_1"), "WorkBuddy");
assert.equal(friendlyName({id: "WorkBuddy_status_icon_1"}, {WorkBuddy_status_icon_1: "QQ"}), "WorkBuddy");
assert.equal(friendlyName({id: "workbuddy"}, {workbuddy: "QQ"}), "workbuddy");
assert.equal(friendlyName(qq, stale, {}, [qq, {...qq}]), id,
    "two anonymous shared IDs cannot inherit one application's name");
assert.equal(friendlyName(qq, {}), id, "no daemon still has a stable fallback");
assert.equal(friendlyName(null), "");
console.log("tray identity: shared Electron IDs, explicit labels and anonymous collisions passed");
