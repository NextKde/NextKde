import assert from "node:assert/strict";
import { localizedField } from "./WidgetLocalization.mjs";

const entry = {
    name: "数字时钟",
    description: "显示本地时间",
    categoryName: "时钟",
    i18n: {
        en: {
            name: "Digital Clock",
            description: "Shows local time",
            categoryName: "Clock"
        },
        "zh-CN": {
            name: "数字时钟（简体）",
            description: "显示本地时间与日期"
        },
        zh: {
            name: "數字時鐘",
            categoryName: "時鐘"
        }
    }
};

// Exact match (case-insensitive, underscore variant).
assert.equal(localizedField(entry, "name", "en"), "Digital Clock");
assert.equal(localizedField(entry, "name", "zh-CN"), "数字时钟（简体）");
assert.equal(localizedField(entry, "name", "zh_cn"), "数字时钟（简体）");

// Base language fallback when region tag does not match.
assert.equal(localizedField(entry, "name", "zh-TW"), "數字時鐘");
assert.equal(localizedField(entry, "name", "en-US"), "Digital Clock");

// Falls back to top-level field when locale or field is absent in i18n.
assert.equal(localizedField(entry, "categoryName", "zh-CN"), "時鐘");
assert.equal(localizedField(entry, "name", "fr-FR"), "数字时钟");
assert.equal(localizedField({ name: "Plain" }, "name", "en"), "Plain");
assert.equal(localizedField(null, "name", "en"), "");
assert.equal(localizedField(entry, "missingField", "en"), "");

console.log("DeskCenter widget localization tests passed");
