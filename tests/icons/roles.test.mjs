import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import vm from "node:vm";
import { artworkSources, icons } from "../../shell/desktop/modules/common/ShellIconMap.mjs";

// A role value has to name bundled artwork: a font glyph, a compatible alias,
// or a key in artworkSources. A value that names nothing renders nothing, and a
// blank row is indistinguishable from a deliberate omission, so the mistake
// stays invisible in the UI.
const iconMapSource = readFileSync(
    new URL("../../shared/Icons/IconMap.js", import.meta.url), "utf8")
    .replace(/^\.pragma library\s*$/m, "");
const iconMap = vm.createContext({});
vm.runInContext(iconMapSource, iconMap);

// Artwork compiled into BundledIcons.qml instead of listed in artworkSources.
const inlineArtwork = ["nextkde", "kos-calendar", "kos-music", "kos-weather", "default-cover"];

// IconRegistry.resolve takes one alias hop, and the font then needs the glyph.
function resolves(value) {
    const glyph = iconMap.aliases[value] || value;
    return Boolean(iconMap.glyphs[glyph])
        || value === "placeholder-dot"
        || Object.hasOwn(artworkSources, value)
        || inlineArtwork.includes(value);
}

test("role values resolve to bundled artwork", () => {
    const dangling = Object.entries(icons)
        .filter(([, value]) => value !== "" && !resolves(value))
        .map(([role, value]) => `${role} -> ${value}`);
    assert.deepEqual(dangling, [],
        'a role that cannot render has to stay empty ("") instead of naming missing artwork');
});

test("dock menu roles are registered", () => {
    // Blank values are deliberate: only some Dock actions carry an icon. The
    // role name itself still has to exist, or resolve() returns it verbatim and
    // the row keeps rendering nothing after the mapping is filled in.
    const roles = new Set();
    for (const name of ["DockIcon.qml", "DockContainer.qml"]) {
        const source = readFileSync(
            new URL(`../../shell/desktop/modules/dock/${name}`, import.meta.url), "utf8");
        for (const match of source.matchAll(/"dock\.menu\.[A-Za-z0-9_.]+"/g))
            roles.add(match[0].slice(1, -1));
    }
    assert.ok(roles.size > 0, "dock menu roles must stay discoverable in the QML sources");
    for (const role of roles)
        assert.ok(Object.hasOwn(icons, role), `${role} must be registered in ShellIconMap`);
});
