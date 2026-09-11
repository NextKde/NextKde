#!/usr/bin/env node
// Detect duplicate QML declarations inside the SAME object.
//
// Why this exists: qmllint happily accepts two `Component.onCompleted:` blocks
// in one object. The QML engine does not -- it fails the entire load with
// "Property value set multiple times". That is exactly what took down
// AppearanceTokens.qml, and no linter in this repo catches it.
//
// Method: a brace stack, not indentation. An earlier version of this tool
// grouped declarations by indentation depth, which produced ~8600 false
// positives -- sibling objects at the same indent (`Repeater { target: a }`
// next to `Repeater { target: b }`) are perfectly legal but looked like
// duplicates. Only declarations sharing one brace scope are real conflicts.
//
// Usage: node tools/qml-duplicate-handlers.mjs [path...]   (default: repo)

import { readFileSync } from "node:fs";
import { execSync } from "node:child_process";

// Strip string literals and line comments so braces/quotes inside them do not
// disturb the scope stack.
function scrub(line) {
    let out = "";
    let inStr = null;
    for (let i = 0; i < line.length; i++) {
        const c = line[i];
        if (inStr) {
            if (c === "\\") { i++; continue; }
            if (c === inStr) inStr = null;
            continue;
        }
        if (c === '"' || c === "'" || c === "`") { inStr = c; continue; }
        if (c === "/" && line[i + 1] === "/") break;
        out += c;
    }
    return out;
}

// A declaration is one of:
//   [readonly] property <type> name:      -> "name"
//   signal name(...)                      -> "name"
//   function name(...)                    -> "name"
//   name: <binding>                       -> "name"  (also onFoo: / Component.onFoo:)
// A bare `foo(...)` is a JS call, NOT a declaration -- matching those was the
// second source of false positives (ctx.lineTo / Math.max inside Canvas paint
// code are called repeatedly in one scope, which is entirely legal).
const JS_KEYWORDS = new Set([
    "case", "default", "if", "else", "for", "while", "do", "switch", "try",
    "catch", "finally", "return", "typeof", "instanceof", "in", "void",
    "break", "continue", "throw", "import", "export", "pragma", "as",
]);

function declarationOf(line) {
    let s = line.replace(/^(?:readonly|default|required|final)\s+/, "");
    let m = s.match(/^property\s+\S+\s+([A-Za-z_$][\w.$<>]*)\s*:/);
    if (m) return m[1];
    m = s.match(/^signal\s+([A-Za-z_$][\w.$<>]*)\s*[(:;]/);
    if (m) return m[1];
    m = s.match(/^function\s+([A-Za-z_$][\w.$<>]*)\s*\(/);
    if (m) return m[1];
    m = s.match(/^([A-Za-z_$][\w.$<>]*)\s*:(?!=)/);
    if (m) return m[1];
    return null;
}

function scan(text) {
    const problems = [];
    const stack = [new Map()]; // scope stack; each scope maps name -> line
    const lines = text.split("\n");
    for (let i = 0; i < lines.length; i++) {
        const line = scrub(lines[i]).trim();
        if (!line || line.startsWith("//") || line.startsWith("*")) continue;

        const name = declarationOf(line);
        if (name && !JS_KEYWORDS.has(name)
            && !/^(?:true|false|null|undefined)$/.test(name)) {
            const scope = stack[stack.length - 1];
            if (scope.has(name)) {
                problems.push({
                    line: i + 1, name,
                    first: scope.get(name), text: lines[i].trim(),
                });
            } else {
                scope.set(name, i + 1);
            }
        }

        for (const c of line) {
            if (c === "{") stack.push(new Map());
            else if (c === "}" && stack.length > 1) stack.pop();
        }
    }
    return problems;
}

const roots = process.argv.slice(2);
const files = (roots.length
    ? execSync(`find ${roots.map(r => `"${r}"`).join(" ")} -name '*.qml'`, { encoding: "utf8" })
    : execSync("find . -name '*.qml' -not -path './.build/*' -not -path './node_modules/*'", { encoding: "utf8" })
).split("\n").filter(Boolean);

let total = 0;
for (const file of files) {
    let text;
    try { text = readFileSync(file, "utf8"); } catch { continue; }
    const problems = scan(text);
    if (!problems.length) continue;
    total += problems.length;
    console.log(`${file}`);
    for (const p of problems) {
        console.log(`  ${p.line}: duplicate "${p.name}" (first at ${p.first})`);
        console.log(`      ${p.text}`);
    }
}
console.log(total === 0
    ? `无重复声明（共检查 ${files.length} 个文件）`
    : `发现 ${total} 处重复声明`);
process.exit(0);
