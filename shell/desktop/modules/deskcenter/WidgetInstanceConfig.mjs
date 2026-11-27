export const MAX_INSTANCE_CONFIG_BYTES = 64 * 1024;

export function utf8ByteLength(str) {
    let bytes = 0;
    for (let i = 0; i < str.length; i++) {
        const code = str.charCodeAt(i);
        if (code < 0x80) {
            bytes += 1;
        } else if (code < 0x800) {
            bytes += 2;
        } else if (code >= 0xD800 && code <= 0xDBFF && i + 1 < str.length) {
            const next = str.charCodeAt(i + 1);
            if (next >= 0xDC00 && next <= 0xDFFF) {
                bytes += 4;
                i++;
            } else {
                bytes += 3;
            }
        } else {
            bytes += 3;
        }
    }
    return bytes;
}

function isPlainObject(value) {
    return !!value && typeof value === "object" && !Array.isArray(value);
}

export function parseConfigMap(json) {
    try {
        const parsed = JSON.parse(String(json ?? "{}"));
        if (!isPlainObject(parsed)) return {};
        const clean = {};
        for (const key of Object.keys(parsed)) {
            if (key.length > 0 && isPlainObject(parsed[key]))
                clean[key] = parsed[key];
        }
        return clean;
    } catch (_) {
        return {};
    }
}

export function getInstanceConfig(map, instanceId) {
    const id = String(instanceId ?? "");
    if (id.length === 0 || !isPlainObject(map) || !Object.prototype.hasOwnProperty.call(map, id))
        return null;
    const entry = map[id];
    if (!isPlainObject(entry)) return null;
    return JSON.parse(JSON.stringify(entry));
}

export function setInstanceConfig(map, instanceId, next, maxBytes = MAX_INSTANCE_CONFIG_BYTES) {
    const id = String(instanceId ?? "");
    if (id.length === 0 || !isPlainObject(next))
        return { ok: false, map: isPlainObject(map) ? map : {}, value: null };
    let serialized;
    try {
        serialized = JSON.stringify(next);
    } catch (_) {
        return { ok: false, map: isPlainObject(map) ? map : {}, value: null };
    }
    if (typeof serialized !== "string" || utf8ByteLength(serialized) > maxBytes)
        return { ok: false, map: isPlainObject(map) ? map : {}, value: null };
    const value = JSON.parse(serialized);
    if (!isPlainObject(value))
        return { ok: false, map: isPlainObject(map) ? map : {}, value: null };
    const nextMap = Object.assign({}, isPlainObject(map) ? map : {});
    nextMap[id] = value;
    return { ok: true, map: nextMap, value: JSON.parse(serialized) };
}

export function removeInstanceConfig(map, instanceId) {
    const id = String(instanceId ?? "");
    if (id.length === 0 || !isPlainObject(map) || !Object.prototype.hasOwnProperty.call(map, id))
        return { map: isPlainObject(map) ? map : {}, changed: false };
    const nextMap = Object.assign({}, map);
    delete nextMap[id];
    return { map: nextMap, changed: true };
}
