export const VALID_SHAPES = [
    "roundedRect",
    "pill",
    "circle",
    "flower",
    "cookie",
    "clover",
    "slantedOval",
    "arch",
];

const POLYGON_SET = {
    flower: true,
    cookie: true,
    clover: true,
    slantedOval: true,
    arch: true,
};

export function normalizeShape(raw) {
    const trimmed = String(raw ?? "").trim();
    if (!trimmed) return "roundedRect";
    const lower = trimmed.toLowerCase();
    if (lower === "slanted-oval" || lower === "slantedoval") return "slantedOval";
    if (lower === "rounded-rect" || lower === "roundedrect") return "roundedRect";
    for (let i = 0; i < VALID_SHAPES.length; ++i) {
        if (VALID_SHAPES[i] === trimmed) return trimmed;
        if (VALID_SHAPES[i].toLowerCase() === lower) return VALID_SHAPES[i];
    }
    return "roundedRect";
}

export function isPolygonShape(shape) {
    return Boolean(POLYGON_SET[normalizeShape(shape)]);
}

function polarRipplePoints(cx, cy, r, lobes, amp, phaseShift, useCos, count) {
    const pts = [];
    for (let i = 0; i <= count; ++i) {
        const a = (i / count) * Math.PI * 2;
        const trig = useCos
            ? Math.cos(lobes * (a + phaseShift))
            : Math.sin(lobes * (a + phaseShift));
        const d = r * (1 - amp + amp * trig);
        pts.push({
            x: cx + Math.cos(a) * d,
            y: cy + Math.sin(a) * d,
        });
    }
    return pts;
}

function slantedOvalPoints(cx, cy, w, h, inset) {
    const theta = (-35 * Math.PI) / 180;
    const cosT = Math.cos(theta);
    const sinT = Math.sin(theta);
    const bRatio = 0.68;
    const halfWUnit = Math.hypot(cosT, bRatio * sinT);
    const halfHUnit = Math.hypot(sinT, bRatio * cosT);
    const maxRx = halfWUnit > 0 ? Math.max(0, w / 2 - inset) / halfWUnit : 0;
    const maxRy = halfHUnit > 0 ? Math.max(0, h / 2 - inset) / halfHUnit : 0;
    const scale = Math.max(0, Math.min(maxRx, maxRy));
    const rx = scale;
    const ry = bRatio * scale;
    const count = 180;
    const pts = [];
    for (let i = 0; i <= count; ++i) {
        const t = (i / count) * Math.PI * 2;
        const lx = rx * Math.cos(t);
        const ly = ry * Math.sin(t);
        pts.push({
            x: cx + lx * cosT - ly * sinT,
            y: cy + lx * sinT + ly * cosT,
        });
    }
    return pts;
}

function archPoints(ox, oy, w, h, inset) {
    const x0 = ox + inset;
    const y0 = oy + inset;
    const aw = w - inset * 2;
    const ah = h - inset * 2;
    if (aw <= 2 || ah <= 2) return [];

    const topRx = aw / 2;
    const topRy = Math.min(topRx, ah * 0.55);
    const botR = Math.min(22, aw * 0.16, Math.max(0, ah - topRy));
    const pts = [];

    // Top semi-ellipse / semicircle arc: PI -> 2*PI in screen coords (top dome)
    const topCx = x0 + topRx;
    const topCy = y0 + topRy;
    const topSteps = 64;
    for (let i = 0; i <= topSteps; ++i) {
        const a = Math.PI + (i / topSteps) * Math.PI;
        pts.push({
            x: topCx + Math.cos(a) * topRx,
            y: topCy + Math.sin(a) * topRy,
        });
    }

    // Bottom-right quarter arc: 0 -> PI/2
    const brCx = x0 + aw - botR;
    const brCy = y0 + ah - botR;
    const cornerSteps = 16;
    for (let i = 0; i <= cornerSteps; ++i) {
        const a = (i / cornerSteps) * (Math.PI / 2);
        pts.push({
            x: brCx + Math.cos(a) * botR,
            y: brCy + Math.sin(a) * botR,
        });
    }

    // Bottom-left quarter arc: PI/2 -> PI
    const blCx = x0 + botR;
    const blCy = y0 + ah - botR;
    for (let i = 0; i <= cornerSteps; ++i) {
        const a = Math.PI / 2 + (i / cornerSteps) * (Math.PI / 2);
        pts.push({
            x: blCx + Math.cos(a) * botR,
            y: blCy + Math.sin(a) * botR,
        });
    }

    if (pts.length > 0) {
        pts.push({ x: pts[0].x, y: pts[0].y });
    }
    return pts;
}

export function outlinePoints(shape, ox, oy, w, h, inset = 1) {
    if (w <= inset * 2 + 2 || h <= inset * 2 + 2) return [];
    const canonical = normalizeShape(shape);
    const cx = ox + w / 2;
    const cy = oy + h / 2;
    const r = Math.max(0, Math.min(w, h) / 2 - inset);

    if (canonical === "flower") {
        return polarRipplePoints(cx, cy, r, 12, 0.075, 0, false, 240);
    }
    if (canonical === "cookie") {
        return polarRipplePoints(cx, cy, r, 8, 0.085, 0, false, 240);
    }
    if (canonical === "clover") {
        return polarRipplePoints(cx, cy, r, 4, 0.095, -Math.PI / 4, true, 240);
    }
    if (canonical === "slantedOval") {
        return slantedOvalPoints(cx, cy, w, h, inset);
    }
    if (canonical === "arch") {
        return archPoints(ox, oy, w, h, inset);
    }
    return [];
}

export function scanlineBands(points, rows) {
    if (!points || points.length < 3 || rows <= 0) return [];
    let minY = Infinity;
    let maxY = -Infinity;
    for (let i = 0; i < points.length; ++i) {
        const py = points[i].y;
        if (py < minY) minY = py;
        if (py > maxY) maxY = py;
    }
    const spanY = maxY - minY;
    if (!Number.isFinite(spanY) || spanY <= 1) return [];

    const step = spanY / rows;
    const out = [];
    for (let row = 0; row < rows; ++row) {
        const rowTop = Math.round(minY + row * step);
        const rowBot = Math.round(minY + (row + 1) * step);
        const rowH = Math.max(1, rowBot - rowTop);
        const scanY = minY + (row + 0.5) * step;

        const crossings = [];
        for (let index = 0; index < points.length - 1; ++index) {
            const a = points[index];
            const b = points[index + 1];
            if ((a.y <= scanY) !== (b.y <= scanY)) {
                const t = (scanY - a.y) / (b.y - a.y);
                crossings.push(a.x + t * (b.x - a.x));
            }
        }
        crossings.sort((left, right) => left - right);

        for (let slotIndex = 0; slotIndex < 2; ++slotIndex) {
            const left = crossings[slotIndex * 2];
            const right = crossings[slotIndex * 2 + 1];
            if (left === undefined || right === undefined) {
                out.push(null);
            } else {
                const x1 = Math.round(left);
                const x2 = Math.round(right);
                const bandW = x2 - x1;
                out.push(bandW > 0 ? { x: x1, y: rowTop, width: bandW, height: rowH } : null);
            }
        }
    }
    return out;
}
