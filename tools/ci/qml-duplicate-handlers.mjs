#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { lint, selectFiles } from './qml-lint-common.mjs';

// Qt catches duplicate properties/bindings, but currently misses repeated
// attached handlers such as Component.onCompleted. Supplement those only.
// Tokens ignore comments and quoted text; brace scopes distinguish siblings
// and JavaScript blocks from QML objects. This is not a replacement QML parser.
function handlers(source) {
    const tokens = [...source.matchAll(/\/\*[\s\S]*?\*\/|\/\/[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`|\/(?:\\.|[^\/\n\\])+\/[dgimsuvy]*|[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*|[^\s]/g)]
        .filter(match => !/^(?:\/|["'`])/.test(match[0]));
    const scopes = [{qml: false, names: new Map()}];
    const errors = [];
    for (let i = 0; i < tokens.length; i++) {
        const token = tokens[i][0];
        if (token === '{') {
            const previous = tokens[i - 1]?.[0] || '';
            scopes.push({qml: /(?:^|\.)[A-Z][\w$]*$/.test(previous), names: new Map()});
        } else if (token === '}') {
            if (scopes.length > 1) scopes.pop();
        } else if (scopes.at(-1).qml && /(?:^|\.)on[A-Z]\w*$/.test(token) && tokens[i + 1]?.[0] === ':') {
            const line = source.slice(0, tokens[i].index).split('\n').length;
            const names = scopes.at(-1).names;
            if (names.has(token)) errors.push(`${line}: duplicate ${token} (first at ${names.get(token)})`);
            else names.set(token, line);
        }
    }
    return errors;
}
const args = process.argv.slice(2);
lint(args, true);
try {
    for (const file of selectFiles(args)) {
        const errors = handlers(readFileSync(file, 'utf8'));
        if (errors.length) { console.error(`${file}:\n${errors.join('\n')}`); process.exitCode = 1; }
    }
} catch (error) { console.error(error.message); process.exitCode = 1; }
