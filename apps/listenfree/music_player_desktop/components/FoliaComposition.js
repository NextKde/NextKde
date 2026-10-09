// Generated from Folia 71c5705, AGPL-3.0. See licenses/Folia-AGPL-3.0.txt.
var factories={
"tempera/temperaCompositions":function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.drawTemperaComposition = exports.resolveTemperaComposition = void 0;
const temperaRandom_1 = require("tempera/temperaRandom");
const temperaHatch_1 = require("tempera/temperaHatch");
const temperaShapes_1 = require("tempera/temperaShapes");
const temperaSplitCompositions_1 = require("tempera/compositions/temperaSplitCompositions");
const temperaBandCompositions_1 = require("tempera/compositions/temperaBandCompositions");
const temperaFrameCompositions_1 = require("tempera/compositions/temperaFrameCompositions");
const temperaPosterCompositions_1 = require("tempera/compositions/temperaPosterCompositions");
const temperaSparseCompositions_1 = require("tempera/compositions/temperaSparseCompositions");
const temperaCinemaCompositions_1 = require("tempera/compositions/temperaCinemaCompositions");
const temperaCharmCompositions_1 = require("tempera/compositions/temperaCharmCompositions");
const temperaApertureCompositions_1 = require("tempera/compositions/temperaApertureCompositions");
const temperaSignalCompositions_1 = require("tempera/compositions/temperaSignalCompositions");
const temperaCorridorCompositions_1 = require("tempera/compositions/temperaCorridorCompositions");
const temperaMonolithCompositions_1 = require("tempera/compositions/temperaMonolithCompositions");
const temperaTerrainCompositions_1 = require("tempera/compositions/temperaTerrainCompositions");
const temperaMonogatariCompositions_1 = require("tempera/compositions/temperaMonogatariCompositions");
const temperaShotProfiles_1 = require("tempera/temperaShotProfiles");
const COMPOSITIONS = Object.assign(Object.assign(Object.assign(Object.assign(Object.assign(Object.assign(Object.assign(Object.assign(Object.assign(Object.assign(Object.assign(Object.assign(Object.assign({}, temperaSplitCompositions_1.TEMPERA_SPLIT_COMPOSITIONS), temperaBandCompositions_1.TEMPERA_BAND_COMPOSITIONS), temperaFrameCompositions_1.TEMPERA_FRAME_COMPOSITIONS), temperaPosterCompositions_1.TEMPERA_POSTER_COMPOSITIONS), temperaSparseCompositions_1.TEMPERA_SPARSE_COMPOSITIONS), temperaCinemaCompositions_1.TEMPERA_CINEMA_COMPOSITIONS), temperaCharmCompositions_1.TEMPERA_CHARM_COMPOSITIONS), temperaApertureCompositions_1.TEMPERA_APERTURE_COMPOSITIONS), temperaSignalCompositions_1.TEMPERA_SIGNAL_COMPOSITIONS), temperaCorridorCompositions_1.TEMPERA_CORRIDOR_COMPOSITIONS), temperaMonolithCompositions_1.TEMPERA_MONOLITH_COMPOSITIONS), temperaTerrainCompositions_1.TEMPERA_TERRAIN_COMPOSITIONS), temperaMonogatariCompositions_1.TEMPERA_MONOGATARI_COMPOSITIONS);
const resolveTemperaComposition = (kind) => {
    var _a;
    return ((_a = COMPOSITIONS[kind]) !== null && _a !== void 0 ? _a : COMPOSITIONS['duo-split']);
};
exports.resolveTemperaComposition = resolveTemperaComposition;
const addCrossingLines = (ctx) => {
    const lines = (0, temperaHatch_1.buildCrossingLines)(ctx.seed, 31, ctx.width, ctx.height, ctx.decor.crossCount);
    if (lines.length === 0)
        return;
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, lines, ctx.palette.tone4, 1.3, 0.6), {
        delay: 0.14,
        span: 0.6,
        enterDX: ctx.width * 0.25,
    });
};
const addMotif = (ctx) => {
    const { width, height, palette, decor } = ctx;
    const cornerX = (0, temperaRandom_1.temperaHash01)(ctx.seed, 61, 7) > 0.5 ? width * 0.14 : width * 0.86;
    const cornerY = (0, temperaRandom_1.temperaHash01)(ctx.seed, 63, 7) > 0.5 ? height * 0.18 : height * 0.82;
    switch (decor.motif) {
        case 'diamonds':
            ctx.add((0, temperaShapes_1.drawConcentricDiamonds)(ctx.pixi, cornerX, cornerY, 34, 34, 3, palette.tone4, 0.8), { delay: 0.34, drift: true });
            return;
        case 'hatch-twin': {
            const spec = Object.assign(Object.assign({}, (0, temperaHatch_1.buildHatchSpec)(ctx.seed, 67)), { angle: decor.hatchAngle });
            [0, 1].forEach(index => {
                const box = (0, temperaHatch_1.rectPolygon)(cornerX - 34 + index * 46, cornerY - 26, 38, 38);
                ctx.add((0, temperaShapes_1.drawHatchFill)(ctx.pixi, box, index === 0 ? spec : Object.assign(Object.assign({}, spec), { spacing: spec.spacing * 0.55 }), palette.tone4, 0.75), { delay: 0.34 + index * 0.05, grow: true });
                ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, box, palette.tone4, 1.2, 0.6), { delay: 0.38 + index * 0.05 });
            });
            return;
        }
        case 'band-cross':
            ctx.add((0, temperaShapes_1.drawCrossMarks)(ctx.pixi, (0, temperaHatch_1.buildCrossRow)(ctx.seed, 71, cornerX - width * 0.1, cornerY, 5, width * 0.05, 8, decor.hatchAngle * 0.4), palette.tone4, 2, 0.8), { delay: 0.34, span: 0.5 });
            return;
        case 'poster-diamond':
            ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.diamondPolygon)(cornerX < width / 2 ? -width * 0.04 : width * 1.04, cornerY, width * 0.14, height * 0.2), palette.tone3, 0.85), { delay: 0.32, span: 0.55, enterDX: (cornerX < width / 2 ? -1 : 1) * width * 0.1 });
            return;
        case 'doodle':
        default:
            ctx.add((0, temperaShapes_1.drawPolyline)(ctx.pixi, (0, temperaHatch_1.buildScribblePath)(decor.scribbleSeed, 73, cornerX, cornerY, Math.min(width, height) * 0.08, 3), palette.tone4, 1.5, 0.72), { delay: 0.34, span: 0.6 });
    }
};
const drawTemperaComposition = (ctx) => {
    (0, exports.resolveTemperaComposition)(ctx.kind)(ctx);
    if ((0, temperaShotProfiles_1.resolveTemperaShotProfile)(ctx.kind).sharedDecor === false)
        return;
    addCrossingLines(ctx);
    if (ctx.showDecor)
        addMotif(ctx);
};
exports.drawTemperaComposition = drawTemperaComposition;

},
"tempera/temperaRandom":function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.chooseWithoutRepeat = exports.temperaHash01 = exports.mixTemperaSeed = exports.hashTemperaSeed = void 0;
const hashTemperaSeed = (value) => {
    let hash = 2166136261;
    for (let index = 0; index < value.length; index += 1) {
        hash ^= value.charCodeAt(index);
        hash = Math.imul(hash, 16777619);
    }
    return hash >>> 0;
};
exports.hashTemperaSeed = hashTemperaSeed;
const mixTemperaSeed = (seed, salt) => (Math.imul((Math.trunc(seed) ^ salt) >>> 0, 2654435761) >>> 0);
exports.mixTemperaSeed = mixTemperaSeed;
const temperaHash01 = (seed, index, salt) => ((0, exports.mixTemperaSeed)(seed + Math.imul(index + 1, 97), salt) / 4294967296);
exports.temperaHash01 = temperaHash01;
const chooseWithoutRepeat = (choices, seed, previous) => {
    const start = (0, exports.hashTemperaSeed)(seed) % choices.length;
    for (let offset = 0; offset < choices.length; offset += 1) {
        const candidate = choices[(start + offset) % choices.length];
        if (candidate !== previous)
            return candidate;
    }
    return choices[start];
};
exports.chooseWithoutRepeat = chooseWithoutRepeat;

},
"tempera/temperaHatch":function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildCrossingLines = exports.buildDotGrid = exports.buildDotRow = exports.buildCrossRow = exports.buildWavyPath = exports.buildScribblePath = exports.buildHatchLines = exports.diamondPolygon = exports.circlePolygon = exports.rectPolygon = exports.buildHatchSpec = void 0;
const temperaRandom_1 = require("tempera/temperaRandom");
const TAU = Math.PI * 2;
const MAX_HATCH_LINES = 320;
const buildHatchSpec = (seed, salt, scale = 1) => {
    var _a, _b;
    const angleIndex = Math.floor((0, temperaRandom_1.temperaHash01)(seed, 1, salt) * 4);
    const angle = (_a = [-Math.PI / 4, Math.PI / 4, -Math.PI / 3, Math.PI / 6][angleIndex]) !== null && _a !== void 0 ? _a : Math.PI / 4;
    const density = Math.floor((0, temperaRandom_1.temperaHash01)(seed, 2, salt) * 3);
    const spacing = ((_b = [9, 13, 18][density]) !== null && _b !== void 0 ? _b : 13) * scale;
    const width = Math.max(0.8, spacing * (0.16 + (0, temperaRandom_1.temperaHash01)(seed, 3, salt) * 0.14));
    return { angle, spacing, width };
};
exports.buildHatchSpec = buildHatchSpec;
const rectPolygon = (x, y, width, height) => [
    x, y,
    x + width, y,
    x + width, y + height,
    x, y + height,
];
exports.rectPolygon = rectPolygon;
const circlePolygon = (cx, cy, radius, segments = 28) => {
    const points = [];
    const count = Math.max(6, Math.round(segments));
    for (let index = 0; index < count; index += 1) {
        const angle = (index / count) * TAU;
        points.push(cx + Math.cos(angle) * radius, cy + Math.sin(angle) * radius);
    }
    return points;
};
exports.circlePolygon = circlePolygon;
const diamondPolygon = (cx, cy, rx, ry) => [
    cx, cy - ry,
    cx + rx, cy,
    cx, cy + ry,
    cx - rx, cy,
];
exports.diamondPolygon = diamondPolygon;
const clipToConvex = (polygon, ax, ay, dx, dy, span) => {
    const count = polygon.length / 2;
    let cx = 0;
    let cy = 0;
    for (let index = 0; index < count; index += 1) {
        cx += polygon[index * 2];
        cy += polygon[index * 2 + 1];
    }
    cx /= count;
    cy /= count;
    let tMin = -span;
    let tMax = span;
    for (let index = 0; index < count; index += 1) {
        const x0 = polygon[index * 2];
        const y0 = polygon[index * 2 + 1];
        const x1 = polygon[((index + 1) % count) * 2];
        const y1 = polygon[((index + 1) % count) * 2 + 1];
        let nx = y1 - y0;
        let ny = -(x1 - x0);
        if (nx * (cx - x0) + ny * (cy - y0) > 0) {
            nx = -nx;
            ny = -ny;
        }
        const denominator = nx * dx + ny * dy;
        const numerator = nx * (ax - x0) + ny * (ay - y0);
        if (Math.abs(denominator) < 1e-9) {
            if (numerator > 0)
                return null;
            continue;
        }
        const t = -numerator / denominator;
        if (denominator > 0)
            tMax = Math.min(tMax, t);
        else
            tMin = Math.max(tMin, t);
        if (tMin > tMax)
            return null;
    }
    if (tMax - tMin < 0.5)
        return null;
    return {
        x1: ax + dx * tMin,
        y1: ay + dy * tMin,
        x2: ax + dx * tMax,
        y2: ay + dy * tMax,
    };
};
const buildHatchLines = (polygon, spec, coverage = 1) => {
    if (polygon.length < 6 || spec.spacing <= 0)
        return [];
    const xs = [];
    const ys = [];
    for (let index = 0; index < polygon.length; index += 2) {
        xs.push(polygon[index]);
        ys.push(polygon[index + 1]);
    }
    const minX = Math.min(...xs);
    const maxX = Math.max(...xs);
    const minY = Math.min(...ys);
    const maxY = Math.max(...ys);
    const centerX = (minX + maxX) / 2;
    const centerY = (minY + maxY) / 2;
    const diagonal = Math.hypot(maxX - minX, maxY - minY);
    if (diagonal <= 0)
        return [];
    const dx = Math.cos(spec.angle);
    const dy = Math.sin(spec.angle);
    const px = -dy;
    const py = dx;
    const steps = Math.min(MAX_HATCH_LINES / 2, Math.ceil(diagonal / (spec.spacing * 2)) + 2);
    const clampedCoverage = Math.min(1, Math.max(0, coverage));
    const lines = [];
    for (let step = -steps; step <= steps; step += 1) {
        const offset = step * spec.spacing;
        const clipped = clipToConvex(polygon, centerX + px * offset, centerY + py * offset, dx, dy, diagonal);
        if (!clipped)
            continue;
        if (clampedCoverage >= 1) {
            lines.push(clipped);
            continue;
        }
        const midX = (clipped.x1 + clipped.x2) / 2;
        const midY = (clipped.y1 + clipped.y2) / 2;
        lines.push({
            x1: midX + (clipped.x1 - midX) * clampedCoverage,
            y1: midY + (clipped.y1 - midY) * clampedCoverage,
            x2: midX + (clipped.x2 - midX) * clampedCoverage,
            y2: midY + (clipped.y2 - midY) * clampedCoverage,
        });
    }
    return lines;
};
exports.buildHatchLines = buildHatchLines;
const buildScribblePath = (seed, salt, cx, cy, radius, turns = 2) => {
    const perTurn = 13;
    const total = Math.max(perTurn, Math.round(perTurn * Math.max(1, turns)));
    const points = [];
    for (let index = 0; index <= total; index += 1) {
        const progress = index / total;
        const angle = progress * TAU * Math.max(1, turns);
        const jitterR = ((0, temperaRandom_1.temperaHash01)(seed, index, salt) - 0.5) * radius * 0.26;
        const jitterA = ((0, temperaRandom_1.temperaHash01)(seed, index, salt + 7) - 0.5) * 0.22;
        const currentRadius = radius * (0.52 + 0.48 * progress) + jitterR;
        points.push(cx + Math.cos(angle + jitterA) * currentRadius, cy + Math.sin(angle + jitterA) * currentRadius * 0.82);
    }
    return points;
};
exports.buildScribblePath = buildScribblePath;
const buildWavyPath = (seed, salt, x0, x1, y, amplitude, steps = 24) => {
    const points = [];
    const safeSteps = Math.max(2, Math.round(steps));
    for (let index = 0; index <= safeSteps; index += 1) {
        const progress = index / safeSteps;
        const wave = Math.sin(progress * TAU * 1.5 + (0, temperaRandom_1.temperaHash01)(seed, 0, salt) * TAU);
        const jitter = ((0, temperaRandom_1.temperaHash01)(seed, index, salt) - 0.5) * amplitude * 0.5;
        points.push(x0 + (x1 - x0) * progress, y + wave * amplitude + jitter);
    }
    return points;
};
exports.buildWavyPath = buildWavyPath;
const buildMarkRow = (seed, salt, x, y, count, spacing, size, angle) => {
    const marks = [];
    const total = Math.max(0, Math.round(count));
    const dx = Math.cos(angle);
    const dy = Math.sin(angle);
    for (let index = 0; index < total; index += 1) {
        const jitter = ((0, temperaRandom_1.temperaHash01)(seed, index, salt) - 0.5) * spacing * 0.16;
        const distance = index * spacing + jitter;
        marks.push({
            x: x + dx * distance,
            y: y + dy * distance,
            size: size * (0.82 + (0, temperaRandom_1.temperaHash01)(seed, index, salt + 3) * 0.36),
            rotation: ((0, temperaRandom_1.temperaHash01)(seed, index, salt + 11) - 0.5) * 0.3,
        });
    }
    return marks;
};
const buildCrossRow = (seed, salt, x, y, count, spacing, size = 9, angle = 0) => buildMarkRow(seed, salt, x, y, count, spacing, size, angle);
exports.buildCrossRow = buildCrossRow;
const buildDotRow = (seed, salt, x, y, count, spacing, size = 4, angle = Math.PI / 2) => buildMarkRow(seed, salt, x, y, count, spacing, size, angle);
exports.buildDotRow = buildDotRow;
const buildDotGrid = (width, height, spacing, size = 1.6) => {
    const marks = [];
    if (spacing <= 0 || width <= 0 || height <= 0)
        return marks;
    const columns = Math.min(200, Math.ceil(width / spacing) + 1);
    const rows = Math.min(200, Math.ceil(height / spacing) + 1);
    for (let row = 0; row < rows; row += 1) {
        for (let column = 0; column < columns; column += 1) {
            marks.push({
                x: column * spacing + (row % 2 === 0 ? 0 : spacing / 2),
                y: row * spacing,
                size,
                rotation: 0,
            });
        }
    }
    return marks;
};
exports.buildDotGrid = buildDotGrid;
const buildCrossingLines = (seed, salt, width, height, count) => {
    const total = Math.min(3, Math.max(0, Math.round(count)));
    const lines = [];
    for (let index = 0; index < total; index += 1) {
        const anchorY = height * (0.18 + (0, temperaRandom_1.temperaHash01)(seed, index, salt) * 0.64);
        const sign = (0, temperaRandom_1.temperaHash01)(seed, index, salt + 5) > 0.5 ? 1 : -1;
        const angle = sign * (0.07 + (0, temperaRandom_1.temperaHash01)(seed, index, salt + 9) * 0.11);
        const reach = width * 0.9;
        lines.push({
            x1: -width * 0.3,
            y1: anchorY - Math.tan(angle) * reach,
            x2: width * 1.3,
            y2: anchorY + Math.tan(angle) * reach,
        });
    }
    return lines;
};
exports.buildCrossingLines = buildCrossingLines;

},
"tempera/temperaShapes":function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.drawSquareMarks = exports.drawCrossMarks = exports.drawConcentricDiamonds = exports.drawPolyline = exports.drawLines = exports.drawRings = exports.drawDiscs = exports.drawHatchFill = exports.drawPolygonOutline = exports.drawPolygonFillWithHoles = exports.drawPolygonFill = exports.toPixiColor = void 0;
const colorMix_1 = require("colorMix");
const temperaHatch_1 = require("tempera/temperaHatch");
const toPixiColor = (pixi, color) => (pixi.Color.shared.setValue(color).toNumber());
exports.toPixiColor = toPixiColor;
const boundsCenter = (polygon) => {
    let minX = Number.POSITIVE_INFINITY;
    let maxX = Number.NEGATIVE_INFINITY;
    let minY = Number.POSITIVE_INFINITY;
    let maxY = Number.NEGATIVE_INFINITY;
    for (let index = 0; index < polygon.length; index += 2) {
        minX = Math.min(minX, polygon[index]);
        maxX = Math.max(maxX, polygon[index]);
        minY = Math.min(minY, polygon[index + 1]);
        maxY = Math.max(maxY, polygon[index + 1]);
    }
    return { x: (minX + maxX) / 2, y: (minY + maxY) / 2 };
};
const buildGradientFill = (pixi, gradient, color) => {
    const half = 0.5;
    const dx = Math.cos(gradient.angle) * half;
    const dy = Math.sin(gradient.angle) * half;
    const stops = gradient.colors.map((stop, index) => ({
        offset: gradient.colors.length > 1 ? index / (gradient.colors.length - 1) : 0,
        color: (0, colorMix_1.mixColors)(stop, color, 0.5),
    }));
    return new pixi.FillGradient({
        type: 'linear',
        start: { x: half - dx, y: half - dy },
        end: { x: half + dx, y: half + dy },
        colorStops: stops,
        textureSpace: 'local',
    });
};
const drawPolygonFill = (pixi, polygon, color, alpha = 1, gradient) => {
    const node = new pixi.Graphics().poly(polygon);
    return gradient && gradient.colors.length > 1
        ? node.fill({ fill: buildGradientFill(pixi, gradient, color), alpha })
        : node.fill({ color: (0, exports.toPixiColor)(pixi, color), alpha });
};
exports.drawPolygonFill = drawPolygonFill;
const drawPolygonFillWithHoles = (pixi, polygon, holes, color, alpha = 1, gradient) => {
    const node = new pixi.Graphics().poly(polygon);
    if (gradient && gradient.colors.length > 1) {
        node.fill({ fill: buildGradientFill(pixi, gradient, color), alpha });
    }
    else {
        node.fill({ color: (0, exports.toPixiColor)(pixi, color), alpha });
    }
    holes.forEach(hole => {
        if (hole.length >= 6)
            node.poly(hole).cut();
    });
    return node;
};
exports.drawPolygonFillWithHoles = drawPolygonFillWithHoles;
const drawPolygonOutline = (pixi, polygon, color, width, alpha = 1) => new pixi.Graphics()
    .poly(polygon)
    .stroke({ color: (0, exports.toPixiColor)(pixi, color), width, alpha });
exports.drawPolygonOutline = drawPolygonOutline;
const drawHatchFill = (pixi, polygon, spec, color, alpha = 1) => {
    const node = new pixi.Graphics();
    const lines = (0, temperaHatch_1.buildHatchLines)(polygon, spec);
    lines.forEach(line => {
        node.moveTo(line.x1, line.y1).lineTo(line.x2, line.y2);
    });
    if (lines.length > 0) {
        node.stroke({ color: (0, exports.toPixiColor)(pixi, color), width: spec.width, alpha });
    }
    const center = boundsCenter(polygon);
    node.pivot.set(center.x, center.y);
    node.position.set(center.x, center.y);
    return node;
};
exports.drawHatchFill = drawHatchFill;
const discsCenter = (discs) => {
    if (discs.length === 0)
        return { x: 0, y: 0 };
    let minX = Number.POSITIVE_INFINITY;
    let maxX = Number.NEGATIVE_INFINITY;
    let minY = Number.POSITIVE_INFINITY;
    let maxY = Number.NEGATIVE_INFINITY;
    discs.forEach(disc => {
        minX = Math.min(minX, disc.x - disc.radius);
        maxX = Math.max(maxX, disc.x + disc.radius);
        minY = Math.min(minY, disc.y - disc.radius);
        maxY = Math.max(maxY, disc.y + disc.radius);
    });
    return { x: (minX + maxX) / 2, y: (minY + maxY) / 2 };
};
const buildDiscNode = (pixi, discs) => {
    const node = new pixi.Graphics();
    discs.forEach(disc => {
        node.circle(disc.x, disc.y, Math.max(0.5, disc.radius));
    });
    return node;
};
const pivotOnSelf = (node, center) => {
    node.pivot.set(center.x, center.y);
    node.position.set(center.x, center.y);
    return node;
};
const drawDiscs = (pixi, discs, color, alpha = 1, gradient) => {
    const node = buildDiscNode(pixi, discs);
    if (discs.length > 0) {
        node.fill(gradient && gradient.colors.length > 1
            ? { fill: buildGradientFill(pixi, gradient, color), alpha }
            : { color: (0, exports.toPixiColor)(pixi, color), alpha });
    }
    return pivotOnSelf(node, discsCenter(discs));
};
exports.drawDiscs = drawDiscs;
const drawRings = (pixi, discs, color, width, alpha = 1) => {
    const node = buildDiscNode(pixi, discs);
    if (discs.length > 0) {
        node.stroke({ color: (0, exports.toPixiColor)(pixi, color), width, alpha });
    }
    return pivotOnSelf(node, discsCenter(discs));
};
exports.drawRings = drawRings;
const drawLines = (pixi, lines, color, width, alpha = 1) => {
    const node = new pixi.Graphics();
    lines.forEach(line => {
        node.moveTo(line.x1, line.y1).lineTo(line.x2, line.y2);
    });
    if (lines.length > 0) {
        node.stroke({ color: (0, exports.toPixiColor)(pixi, color), width, alpha });
    }
    return node;
};
exports.drawLines = drawLines;
const drawPolyline = (pixi, points, color, width, alpha = 1) => {
    const node = new pixi.Graphics();
    if (points.length < 4)
        return node;
    node.moveTo(points[0], points[1]);
    for (let index = 2; index < points.length; index += 2) {
        node.lineTo(points[index], points[index + 1]);
    }
    return node.stroke({ color: (0, exports.toPixiColor)(pixi, color), width, alpha });
};
exports.drawPolyline = drawPolyline;
const drawConcentricDiamonds = (pixi, cx, cy, rx, ry, rings, color, alpha = 1) => {
    const node = new pixi.Graphics();
    const stroke = (0, exports.toPixiColor)(pixi, color);
    for (let ring = 0; ring < Math.max(1, rings); ring += 1) {
        const shrink = 1 - ring * 0.22;
        node
            .poly([cx, cy - ry * shrink, cx + rx * shrink, cy, cx, cy + ry * shrink, cx - rx * shrink, cy])
            .stroke({ color: stroke, width: ring % 2 === 0 ? 3.5 : 1.4, alpha });
    }
    node.pivot.set(cx, cy);
    node.position.set(cx, cy);
    return node;
};
exports.drawConcentricDiamonds = drawConcentricDiamonds;
const drawCrossMarks = (pixi, marks, color, width, alpha = 1) => {
    const node = new pixi.Graphics();
    marks.forEach(mark => {
        const cos = Math.cos(mark.rotation + Math.PI / 4) * mark.size;
        const sin = Math.sin(mark.rotation + Math.PI / 4) * mark.size;
        node.moveTo(mark.x - cos, mark.y - sin).lineTo(mark.x + cos, mark.y + sin);
        node.moveTo(mark.x - sin, mark.y + cos).lineTo(mark.x + sin, mark.y - cos);
    });
    if (marks.length > 0) {
        node.stroke({ color: (0, exports.toPixiColor)(pixi, color), width, alpha });
    }
    return node;
};
exports.drawCrossMarks = drawCrossMarks;
const drawSquareMarks = (pixi, marks, color, alpha = 1) => {
    const node = new pixi.Graphics();
    marks.forEach(mark => {
        node.rect(mark.x - mark.size / 2, mark.y - mark.size / 2, mark.size, mark.size);
    });
    if (marks.length > 0) {
        node.fill({ color: (0, exports.toPixiColor)(pixi, color), alpha });
    }
    return node;
};
exports.drawSquareMarks = drawSquareMarks;

},
"colorMix":function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.mixColors = exports.parseColorChannels = exports.colorWithAlpha = void 0;
const clamp = (value, min, max) => Math.max(min, Math.min(max, value));
const mix = (from, to, amount) => from + (to - from) * amount;
const FALLBACK_RGB = { r: 255, g: 255, b: 255 };
const isFiniteChannel = (value) => Number.isFinite(value);
const formatRgba = (channels, alpha) => (`rgba(${Math.round(clamp(channels.r, 0, 255))}, ${Math.round(clamp(channels.g, 0, 255))}, ${Math.round(clamp(channels.b, 0, 255))}, ${alpha})`);
const colorWithAlpha = (color, alpha) => {
    const normalizedAlpha = clamp(alpha, 0, 1);
    const normalizedColor = typeof color === 'string' ? color.trim() : '';
    if (!normalizedColor) {
        return formatRgba(FALLBACK_RGB, normalizedAlpha);
    }
    if (normalizedColor.startsWith('#')) {
        const hex = normalizedColor.slice(1);
        const parse = (value) => Number.parseInt(value, 16);
        if (/^[0-9a-fA-F]{3}$/.test(hex)) {
            const r = parse(hex[0] + hex[0]);
            const g = parse(hex[1] + hex[1]);
            const b = parse(hex[2] + hex[2]);
            return formatRgba({ r, g, b }, normalizedAlpha);
        }
        if (/^[0-9a-fA-F]{6}$/.test(hex)) {
            const r = parse(hex.slice(0, 2));
            const g = parse(hex.slice(2, 4));
            const b = parse(hex.slice(4, 6));
            return formatRgba({ r, g, b }, normalizedAlpha);
        }
        return formatRgba(FALLBACK_RGB, normalizedAlpha);
    }
    const rgbMatch = normalizedColor.match(/^rgba?\(([^)]+)\)$/);
    if (rgbMatch) {
        const [r, g, b] = rgbMatch[1].split(',').slice(0, 3).map(part => Number.parseFloat(part.trim()));
        if ([r, g, b].every(isFiniteChannel)) {
            return formatRgba({ r, g, b }, normalizedAlpha);
        }
        return formatRgba(FALLBACK_RGB, normalizedAlpha);
    }
    return normalizedColor;
};
exports.colorWithAlpha = colorWithAlpha;
const parseColorChannels = (color) => {
    const normalizedColor = typeof color === 'string' ? color.trim() : '';
    if (!normalizedColor) {
        return null;
    }
    if (normalizedColor.startsWith('#')) {
        const hex = normalizedColor.slice(1);
        const parse = (value) => Number.parseInt(value, 16);
        if (/^[0-9a-fA-F]{3}$/.test(hex)) {
            return {
                r: parse(hex[0] + hex[0]),
                g: parse(hex[1] + hex[1]),
                b: parse(hex[2] + hex[2]),
            };
        }
        if (/^[0-9a-fA-F]{6}$/.test(hex)) {
            return {
                r: parse(hex.slice(0, 2)),
                g: parse(hex.slice(2, 4)),
                b: parse(hex.slice(4, 6)),
            };
        }
    }
    const rgbMatch = normalizedColor.match(/^rgba?\(([^)]+)\)$/);
    if (rgbMatch) {
        const [r, g, b] = rgbMatch[1].split(',').slice(0, 3).map(part => Number.parseFloat(part.trim()));
        if ([r, g, b].every(isFiniteChannel)) {
            return { r, g, b };
        }
    }
    return null;
};
exports.parseColorChannels = parseColorChannels;
const mixColors = (from, to, amount, alpha = 1) => {
    const normalizedAmount = clamp(amount, 0, 1);
    const fromChannels = (0, exports.parseColorChannels)(from);
    const toChannels = (0, exports.parseColorChannels)(to);
    if (!fromChannels || !toChannels) {
        return (0, exports.colorWithAlpha)(normalizedAmount >= 0.5 ? to : from, alpha);
    }
    return `rgba(${Math.round(mix(fromChannels.r, toChannels.r, normalizedAmount))}, ${Math.round(mix(fromChannels.g, toChannels.g, normalizedAmount))}, ${Math.round(mix(fromChannels.b, toChannels.b, normalizedAmount))}, ${clamp(alpha, 0, 1)})`;
};
exports.mixColors = mixColors;

},
"tempera/compositions/temperaSplitCompositions":function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.TEMPERA_SPLIT_COMPOSITIONS = void 0;
const temperaRandom_1 = require("tempera/temperaRandom");
const temperaHatch_1 = require("tempera/temperaHatch");
const temperaShapes_1 = require("tempera/temperaShapes");
const addPanels = (ctx, panels, hatchIndex) => {
    const hatch = (0, temperaHatch_1.buildHatchSpec)(ctx.seed, 5);
    panels.forEach((panel, index) => {
        ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, panel.polygon, panel.tone, 0.96, ctx.gradient), {
            delay: index * 0.05,
            span: 0.5,
            enterDX: panel.enterDX,
            enterDY: panel.enterDY,
        });
        if (index !== hatchIndex)
            return;
        ctx.add((0, temperaShapes_1.drawHatchFill)(ctx.pixi, panel.polygon, hatch, ctx.palette.tone4, 0.5), {
            delay: index * 0.05 + 0.06,
            span: 0.5,
            grow: true,
        });
    });
};
const addSeam = (ctx, polygon, delay) => {
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, polygon, ctx.palette.ink, 0.85, ctx.gradient), { delay, span: 0.5 });
};
const duoSplit = ctx => {
    const { width, height, palette, bleed } = ctx;
    const horizontal = (0, temperaRandom_1.temperaHash01)(ctx.seed, 1, 3) > 0.5;
    addPanels(ctx, horizontal
        ? [
            { polygon: (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height * 0.52 + bleed), tone: palette.tone1, enterDX: 0, enterDY: -height * 0.55 },
            { polygon: (0, temperaHatch_1.rectPolygon)(-bleed, height * 0.52, width + bleed * 2, height * 0.48 + bleed), tone: palette.tone3, enterDX: 0, enterDY: height * 0.55 },
        ]
        : [
            { polygon: (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width * 0.5 + bleed, height + bleed * 2), tone: palette.tone1, enterDX: -width * 0.5, enterDY: 0 },
            { polygon: (0, temperaHatch_1.rectPolygon)(width * 0.5, -bleed, width * 0.5 + bleed, height + bleed * 2), tone: palette.tone3, enterDX: width * 0.5, enterDY: 0 },
        ], 0);
    addSeam(ctx, horizontal
        ? (0, temperaHatch_1.rectPolygon)(-bleed, height * 0.52 - 1.5, width + bleed * 2, 3)
        : (0, temperaHatch_1.rectPolygon)(width * 0.5 - 1.5, -bleed, 3, height + bleed * 2), 0.16);
};
const quadSplit = ctx => {
    const { width, height, palette, bleed } = ctx;
    const splitX = width * (0.42 + (0, temperaRandom_1.temperaHash01)(ctx.seed, 2, 7) * 0.16);
    const splitY = height * (0.42 + (0, temperaRandom_1.temperaHash01)(ctx.seed, 3, 11) * 0.16);
    addPanels(ctx, [
        { polygon: (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, splitX + bleed, splitY + bleed), tone: palette.tone1, enterDX: -width * 0.3, enterDY: -height * 0.3 },
        { polygon: (0, temperaHatch_1.rectPolygon)(splitX, -bleed, width - splitX + bleed, splitY + bleed), tone: palette.tone4, enterDX: width * 0.3, enterDY: -height * 0.3 },
        { polygon: (0, temperaHatch_1.rectPolygon)(-bleed, splitY, splitX + bleed, height - splitY + bleed), tone: palette.tone3, enterDX: -width * 0.3, enterDY: height * 0.3 },
        { polygon: (0, temperaHatch_1.rectPolygon)(splitX, splitY, width - splitX + bleed, height - splitY + bleed), tone: palette.tone2, enterDX: width * 0.3, enterDY: height * 0.3 },
    ], 3);
    addSeam(ctx, (0, temperaHatch_1.rectPolygon)(splitX - 1.5, -bleed, 3, height + bleed * 2), 0.2);
    addSeam(ctx, (0, temperaHatch_1.rectPolygon)(-bleed, splitY - 1.5, width + bleed * 2, 3), 0.24);
};
const triColumn = ctx => {
    const { width, height, palette, bleed } = ctx;
    const edge = width * (0.26 + (0, temperaRandom_1.temperaHash01)(ctx.seed, 4, 13) * 0.06);
    addPanels(ctx, [
        { polygon: (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, edge + bleed, height + bleed * 2), tone: palette.tone1, enterDX: -width * 0.25, enterDY: 0 },
        { polygon: (0, temperaHatch_1.rectPolygon)(edge, -bleed, width - edge * 2, height + bleed * 2), tone: palette.tone4, enterDX: 0, enterDY: -height * 0.3 },
        { polygon: (0, temperaHatch_1.rectPolygon)(width - edge, -bleed, edge + bleed, height + bleed * 2), tone: palette.tone1, enterDX: width * 0.25, enterDY: 0 },
    ], 0);
};
const thirdsStack = ctx => {
    const { width, height, palette, bleed } = ctx;
    const band = height * 0.34;
    addPanels(ctx, [
        { polygon: (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, band + bleed), tone: palette.tone2, enterDX: -width * 0.2, enterDY: 0 },
        { polygon: (0, temperaHatch_1.rectPolygon)(-bleed, band, width + bleed * 2, band), tone: palette.tone4, enterDX: width * 0.2, enterDY: 0 },
        { polygon: (0, temperaHatch_1.rectPolygon)(-bleed, band * 2, width + bleed * 2, height - band * 2 + bleed), tone: palette.tone1, enterDX: -width * 0.2, enterDY: 0 },
    ], 0);
};
const checkerQuad = ctx => {
    const { width, height, palette, bleed } = ctx;
    const splitX = width * 0.5;
    const splitY = height * 0.5;
    addPanels(ctx, [
        { polygon: (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, splitX + bleed, splitY + bleed), tone: palette.tone4, enterDX: 0, enterDY: -height * 0.35 },
        { polygon: (0, temperaHatch_1.rectPolygon)(splitX, -bleed, width - splitX + bleed, splitY + bleed), tone: palette.tone1, enterDX: 0, enterDY: -height * 0.35 },
        { polygon: (0, temperaHatch_1.rectPolygon)(-bleed, splitY, splitX + bleed, height - splitY + bleed), tone: palette.tone1, enterDX: 0, enterDY: height * 0.35 },
        { polygon: (0, temperaHatch_1.rectPolygon)(splitX, splitY, width - splitX + bleed, height - splitY + bleed), tone: palette.tone4, enterDX: 0, enterDY: height * 0.35 },
    ], 1);
};
const cornerWedge = ctx => {
    const { width, height, palette, bleed } = ctx;
    const fromLeft = (0, temperaRandom_1.temperaHash01)(ctx.seed, 5, 17) > 0.5;
    const apexX = fromLeft ? width * 0.78 : width * 0.22;
    addPanels(ctx, [
        { polygon: (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), tone: palette.tone1, enterDX: 0, enterDY: 0 },
        {
            polygon: fromLeft
                ? [-bleed, -bleed, apexX, -bleed, -bleed, height + bleed]
                : [width + bleed, -bleed, apexX, -bleed, width + bleed, height + bleed],
            tone: palette.tone4,
            enterDX: fromLeft ? -width * 0.4 : width * 0.4,
            enterDY: 0,
        },
    ], 1);
};
const diagonalHalves = ctx => {
    const { width, height, palette, bleed } = ctx;
    const lean = height * (0.2 + (0, temperaRandom_1.temperaHash01)(ctx.seed, 6, 19) * 0.3);
    addPanels(ctx, [
        { polygon: [-bleed, -bleed, width + bleed, -bleed, width + bleed, lean, -bleed, height - lean], tone: palette.tone2, enterDX: 0, enterDY: -height * 0.4 },
        { polygon: [-bleed, height - lean, width + bleed, lean, width + bleed, height + bleed, -bleed, height + bleed], tone: palette.tone4, enterDX: 0, enterDY: height * 0.4 },
    ], 1);
};
const crossAxis = ctx => {
    const { width, height, palette, bleed } = ctx;
    const barX = width * 0.11;
    const barY = height * 0.13;
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), palette.tone1, 0.9, ctx.gradient), { span: 0.5 });
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)((width - barX) / 2, -bleed, barX, height + bleed * 2), palette.tone4, 0.95), { delay: 0.06, span: 0.5, enterDY: -height * 0.5 });
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, (height - barY) / 2, width + bleed * 2, barY), palette.tone3, 0.95), { delay: 0.12, span: 0.5, enterDX: width * 0.5 });
};
const offsetHalves = ctx => {
    const { width, height, palette, bleed } = ctx;
    const step = height * (0.06 + (0, temperaRandom_1.temperaHash01)(ctx.seed, 7, 23) * 0.06);
    const seam = width * 0.48;
    addPanels(ctx, [
        { polygon: (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, seam + bleed, height * 0.5 + step + bleed), tone: palette.tone1, enterDX: -width * 0.3, enterDY: 0 },
        { polygon: (0, temperaHatch_1.rectPolygon)(seam, -bleed, width - seam + bleed, height * 0.5 - step + bleed), tone: palette.tone3, enterDX: width * 0.3, enterDY: 0 },
        { polygon: (0, temperaHatch_1.rectPolygon)(-bleed, height * 0.5 + step, seam + bleed, height * 0.5 - step + bleed), tone: palette.tone4, enterDX: -width * 0.2, enterDY: 0 },
        { polygon: (0, temperaHatch_1.rectPolygon)(seam, height * 0.5 - step, width - seam + bleed, height * 0.5 + step + bleed), tone: palette.tone2, enterDX: width * 0.2, enterDY: 0 },
    ], 2);
};
const stairBlocks = ctx => {
    const { width, height, palette, bleed } = ctx;
    const tones = [palette.tone1, palette.tone2, palette.tone3, palette.tone4];
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), palette.tone1, 0.9, ctx.gradient), { span: 0.5 });
    tones.forEach((tone, index) => {
        const left = width * (0.06 + index * 0.2);
        const top = height * (0.1 + index * 0.16);
        ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(left, top, width * 0.3, height * 0.34), tone, 0.94, ctx.gradient), { delay: index * 0.06, span: 0.5, enterDX: -width * 0.2, enterDY: height * 0.12 });
    });
};
const pillarGap = ctx => {
    const { width, height, palette, bleed } = ctx;
    const gap = width * (0.26 + (0, temperaRandom_1.temperaHash01)(ctx.seed, 8, 29) * 0.08);
    const side = (width - gap) / 2;
    addPanels(ctx, [
        { polygon: (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, side + bleed, height + bleed * 2), tone: palette.tone4, enterDX: -width * 0.3, enterDY: 0 },
        { polygon: (0, temperaHatch_1.rectPolygon)(width - side, -bleed, side + bleed, height + bleed * 2), tone: palette.tone4, enterDX: width * 0.3, enterDY: 0 },
    ], 1);
};
const cornerQuad = ctx => {
    const { width, height, palette, bleed } = ctx;
    const splitX = width * (0.6 + (0, temperaRandom_1.temperaHash01)(ctx.seed, 9, 31) * 0.12);
    const splitY = height * (0.62 + (0, temperaRandom_1.temperaHash01)(ctx.seed, 10, 37) * 0.1);
    addPanels(ctx, [
        { polygon: (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, splitX + bleed, splitY + bleed), tone: palette.tone2, enterDX: 0, enterDY: -height * 0.25 },
        { polygon: (0, temperaHatch_1.rectPolygon)(splitX, -bleed, width - splitX + bleed, splitY + bleed), tone: palette.tone4, enterDX: width * 0.25, enterDY: 0 },
        { polygon: (0, temperaHatch_1.rectPolygon)(-bleed, splitY, splitX + bleed, height - splitY + bleed), tone: palette.tone1, enterDX: -width * 0.25, enterDY: 0 },
        { polygon: (0, temperaHatch_1.rectPolygon)(splitX, splitY, width - splitX + bleed, height - splitY + bleed), tone: palette.tone3, enterDX: 0, enterDY: height * 0.25 },
    ], 0);
};
const sliverStack = ctx => {
    const { width, height, palette, bleed } = ctx;
    const fromLeft = (0, temperaRandom_1.temperaHash01)(ctx.seed, 11, 41) > 0.5;
    const slabWidth = width * 0.46;
    const left = fromLeft ? -bleed : width - slabWidth;
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), palette.tone1, 0.9, ctx.gradient), { span: 0.5 });
    const count = 9;
    const sliver = (height + bleed * 2) / count;
    for (let index = 0; index < count; index += 1) {
        if (index % 2 === 1)
            continue;
        ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(left, -bleed + sliver * index, slabWidth + bleed, sliver), palette.tone4, 0.92, ctx.gradient), { delay: index * 0.02, span: 0.5, enterDX: (fromLeft ? -1 : 1) * width * 0.2 });
    }
};
exports.TEMPERA_SPLIT_COMPOSITIONS = {
    'duo-split': duoSplit,
    'quad-split': quadSplit,
    'tri-column': triColumn,
    'thirds-stack': thirdsStack,
    'checker-quad': checkerQuad,
    'corner-wedge': cornerWedge,
    'diagonal-halves': diagonalHalves,
    'cross-axis': crossAxis,
    'offset-halves': offsetHalves,
    'stair-blocks': stairBlocks,
    'pillar-gap': pillarGap,
    'corner-quad': cornerQuad,
    'sliver-stack': sliverStack,
};

},
"tempera/compositions/temperaBandCompositions":function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.TEMPERA_BAND_COMPOSITIONS = void 0;
const temperaRandom_1 = require("tempera/temperaRandom");
const temperaHatch_1 = require("tempera/temperaHatch");
const temperaShapes_1 = require("tempera/temperaShapes");
const bandStrip = ctx => {
    const { width, height, palette, bleed } = ctx;
    const bandY = height * 0.37;
    const bandHeight = height * 0.3;
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, bandY, width + bleed * 2, bandHeight), palette.tone3, 0.96, ctx.gradient), { span: 0.55, enterDX: -width * 0.5 });
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, [
        { x1: -bleed, y1: bandY - 10, x2: width + bleed, y2: bandY - 22 },
        { x1: -bleed, y1: bandY + bandHeight + 22, x2: width + bleed, y2: bandY + bandHeight + 10 },
    ], palette.tone4, 1.4, 0.75), { delay: 0.12, enterDX: width * 0.25 });
    if (!ctx.showDecor)
        return;
    ctx.add((0, temperaShapes_1.drawCrossMarks)(ctx.pixi, (0, temperaHatch_1.buildCrossRow)(ctx.seed, 17, width * 0.06, bandY - height * 0.16, 4, width * 0.055, 9), palette.ink, 2, 0.8), { delay: 0.2, span: 0.5 });
    ctx.add((0, temperaShapes_1.drawSquareMarks)(ctx.pixi, (0, temperaHatch_1.buildDotRow)(ctx.seed, 19, width * 0.94, bandY + bandHeight + height * 0.06, 3, height * 0.05, 6), palette.ink, 0.75), { delay: 0.26, drift: true });
};
const horizonBand = ctx => {
    const { width, height, palette, bleed } = ctx;
    const waterline = height * (0.5 + (0, temperaRandom_1.temperaHash01)(ctx.seed, 1, 23) * 0.12);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, waterline + bleed), palette.tone1, 0.94, ctx.gradient), { span: 0.55, enterDY: -height * 0.3 });
    const water = (0, temperaHatch_1.rectPolygon)(-bleed, waterline, width + bleed * 2, height - waterline + bleed);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, water, palette.tone3, 0.95, ctx.gradient), { delay: 0.05, span: 0.55, enterDY: height * 0.3 });
    ctx.add((0, temperaShapes_1.drawHatchFill)(ctx.pixi, water, Object.assign(Object.assign({}, (0, temperaHatch_1.buildHatchSpec)(ctx.seed, 29)), { angle: 0 }), palette.tone4, 0.55), { delay: 0.1, span: 0.55, grow: true });
    ctx.add((0, temperaShapes_1.drawPolyline)(ctx.pixi, (0, temperaHatch_1.buildWavyPath)(ctx.seed, 31, -bleed, width + bleed, waterline, height * 0.012, 30), palette.ink, 2.2, 0.85), { delay: 0.16, span: 0.5 });
};
const deepDive = ctx => {
    const { width, height, palette, bleed } = ctx;
    const tones = [palette.tone1, palette.tone2, palette.tone3, palette.tone4];
    const bandHeight = (height + bleed * 2) / tones.length;
    tones.forEach((tone, index) => {
        const top = -bleed + bandHeight * index;
        ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, top, width + bleed * 2, bandHeight + 1), tone, 0.95, ctx.gradient), { delay: index * 0.06, span: 0.55, enterDY: height * 0.3 });
        if (index === 0)
            return;
        ctx.add((0, temperaShapes_1.drawPolyline)(ctx.pixi, (0, temperaHatch_1.buildWavyPath)(ctx.seed, 37 + index, -bleed, width + bleed, top, height * 0.008, 24), palette.paper, 1.6, 0.5), { delay: index * 0.06 + 0.05, span: 0.5 });
    });
};
const toneRamp = ctx => {
    const { width, height, palette, bleed } = ctx;
    const spec = (0, temperaHatch_1.buildHatchSpec)(ctx.seed, 41);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), palette.tone1, 0.92, ctx.gradient), { span: 0.5 });
    const steps = 4;
    for (let index = 0; index < steps; index += 1) {
        const columnWidth = (width + bleed * 2) / steps;
        const column = (0, temperaHatch_1.rectPolygon)(-bleed + columnWidth * index, -bleed, columnWidth, height + bleed * 2);
        ctx.add((0, temperaShapes_1.drawHatchFill)(ctx.pixi, column, Object.assign(Object.assign({}, spec), { spacing: spec.spacing * (1.6 - index * 0.32) }), palette.tone4, 0.6), { delay: index * 0.06, span: 0.55, grow: true });
    }
};
const doubleBand = ctx => {
    const { width, height, palette, bleed } = ctx;
    const slot = height * (0.2 + (0, temperaRandom_1.temperaHash01)(ctx.seed, 51, 43) * 0.08);
    const rail = height * 0.3;
    const top = (height - slot) / 2 - rail;
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, top, width + bleed * 2, rail), palette.tone3, 0.95, ctx.gradient), { span: 0.55, enterDX: -width * 0.4 });
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, top + rail + slot, width + bleed * 2, rail), palette.tone4, 0.95, ctx.gradient), { delay: 0.07, span: 0.55, enterDX: width * 0.4 });
};
const tiltBand = ctx => {
    const { width, height, palette, bleed } = ctx;
    const lean = height * (0.14 + (0, temperaRandom_1.temperaHash01)(ctx.seed, 53, 47) * 0.14);
    const half = height * 0.17;
    const band = [
        -bleed, height / 2 + lean - half,
        width + bleed, height / 2 - lean - half,
        width + bleed, height / 2 - lean + half,
        -bleed, height / 2 + lean + half,
    ];
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), palette.tone1, 0.9, ctx.gradient), { span: 0.5 });
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, band, palette.tone4, 0.95, ctx.gradient), { delay: 0.06, span: 0.55, enterDX: -width * 0.35 });
    ctx.add((0, temperaShapes_1.drawHatchFill)(ctx.pixi, band, Object.assign(Object.assign({}, (0, temperaHatch_1.buildHatchSpec)(ctx.seed, 59)), { angle: Math.PI / 2 }), palette.paper, 0.3), { delay: 0.12, span: 0.55, grow: true });
};
const edgeRails = ctx => {
    const { width, height, palette, bleed } = ctx;
    const rail = height * (0.16 + (0, temperaRandom_1.temperaHash01)(ctx.seed, 61, 53) * 0.06);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, rail + bleed), palette.tone3, 0.94, ctx.gradient), { span: 0.55, enterDY: -height * 0.2 });
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, height - rail, width + bleed * 2, rail + bleed), palette.tone3, 0.94, ctx.gradient), { delay: 0.06, span: 0.55, enterDY: height * 0.2 });
    if (!ctx.showDecor)
        return;
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, [
        { x1: -bleed, y1: rail + 8, x2: width + bleed, y2: rail + 8 },
        { x1: -bleed, y1: height - rail - 8, x2: width + bleed, y2: height - rail - 8 },
    ], palette.tone4, 1.2, 0.6), { delay: 0.16, span: 0.5, enterDX: width * 0.2 });
};
const gradientWall = ctx => {
    const { width, height, palette, bleed } = ctx;
    const spec = (0, temperaHatch_1.buildHatchSpec)(ctx.seed, 67);
    const downward = (0, temperaRandom_1.temperaHash01)(ctx.seed, 71, 59) > 0.5;
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), palette.tone2, 0.94, ctx.gradient), { span: 0.5 });
    const steps = 5;
    const bandHeight = height / steps;
    for (let index = 0; index < steps; index += 1) {
        const rank = downward ? index : steps - 1 - index;
        const top = bandHeight * index - (index === 0 ? bleed : 0);
        const bottom = bandHeight * (index + 1) + (index === steps - 1 ? bleed : 0);
        ctx.add((0, temperaShapes_1.drawHatchFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, top, width + bleed * 2, bottom - top), Object.assign(Object.assign({}, spec), { spacing: spec.spacing * (1.9 - rank * 0.34) }), palette.tone4, 0.55), { delay: index * 0.05, span: 0.55, grow: true });
    }
};
const terrace = ctx => {
    const { width, height, palette, bleed } = ctx;
    const tones = [palette.tone1, palette.tone2, palette.tone3, palette.tone4];
    const bandHeight = height / tones.length;
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), palette.tone1, 0.9, ctx.gradient), { span: 0.5 });
    tones.forEach((tone, index) => {
        const left = width * index * 0.14 - bleed;
        const top = bandHeight * index - (index === 0 ? bleed : 0);
        const bottom = bandHeight * (index + 1) + (index === tones.length - 1 ? bleed : 1);
        ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(left, top, width + bleed * 2 - left - bleed, bottom - top), tone, 0.94, ctx.gradient), { delay: index * 0.06, span: 0.55, enterDX: -width * 0.25 });
    });
};
exports.TEMPERA_BAND_COMPOSITIONS = {
    'band-strip': bandStrip,
    'horizon-band': horizonBand,
    'deep-dive': deepDive,
    'tone-ramp': toneRamp,
    'double-band': doubleBand,
    'tilt-band': tiltBand,
    'edge-rails': edgeRails,
    'gradient-wall': gradientWall,
    'terrace': terrace,
};

},
"tempera/compositions/temperaFrameCompositions":function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.TEMPERA_FRAME_COMPOSITIONS = void 0;
const temperaRandom_1 = require("tempera/temperaRandom");
const temperaHatch_1 = require("tempera/temperaHatch");
const temperaShapes_1 = require("tempera/temperaShapes");
const frameWindow = ctx => {
    const { width, height, palette } = ctx;
    const cx = width / 2;
    const cy = height / 2;
    const rx = width * 0.42;
    const ry = height * 0.44;
    ctx.add((0, temperaShapes_1.drawHatchFill)(ctx.pixi, (0, temperaHatch_1.diamondPolygon)(cx, cy, rx * 0.78, ry * 0.78), (0, temperaHatch_1.buildHatchSpec)(ctx.seed, 23, 1.4), palette.tone2, 0.45), { grow: true, span: 0.6 });
    ctx.add((0, temperaShapes_1.drawConcentricDiamonds)(ctx.pixi, cx, cy, rx, ry, 3, palette.ink, 0.9), { delay: 0.08, enterDY: height * 0.06, span: 0.55 });
    if (!ctx.showDecor)
        return;
    ctx.add((0, temperaShapes_1.drawCrossMarks)(ctx.pixi, (0, temperaHatch_1.buildCrossRow)(ctx.seed, 29, width * 0.08, height * 0.14, 3, width * 0.045, 8), palette.tone4, 1.8, 0.85), { delay: 0.22 });
    ctx.add((0, temperaShapes_1.drawSquareMarks)(ctx.pixi, (0, temperaHatch_1.buildDotRow)(ctx.seed, 37, width * 0.92, height * 0.62, 4, height * 0.06, 7), palette.tone4, 0.8), { delay: 0.28 });
};
const doubleFrame = ctx => {
    const { width, height, palette, bleed } = ctx;
    const offset = width * 0.05;
    const box = (0, temperaHatch_1.rectPolygon)(width * 0.16, height * 0.2, width * 0.68, height * 0.6);
    const shifted = (0, temperaHatch_1.rectPolygon)(width * 0.16 + offset, height * 0.2 + offset * 0.6, width * 0.68, height * 0.6);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), palette.tone1, 0.9, ctx.gradient), { span: 0.5 });
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, shifted, palette.tone3, 0.8, ctx.gradient), { delay: 0.06, span: 0.55, enterDX: offset * 3 });
    ctx.add((0, temperaShapes_1.drawHatchFill)(ctx.pixi, shifted, (0, temperaHatch_1.buildHatchSpec)(ctx.seed, 43), palette.tone4, 0.4), { delay: 0.1, span: 0.55, grow: true });
    ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, box, palette.ink, 3.5, 0.9), { delay: 0.14, span: 0.5, enterDY: -height * 0.08 });
};
const circleWindow = ctx => {
    const { width, height, palette, bleed } = ctx;
    const radius = Math.min(width, height) * 0.34;
    const circle = (0, temperaHatch_1.circlePolygon)(width / 2, height / 2, radius);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), palette.tone3, 0.92, ctx.gradient), { span: 0.5 });
    ctx.add((0, temperaShapes_1.drawHatchFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), (0, temperaHatch_1.buildHatchSpec)(ctx.seed, 47), palette.tone4, 0.4), { delay: 0.04, span: 0.6, grow: true });
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, circle, palette.paper, 0.95, ctx.gradient), { delay: 0.08, span: 0.55 });
    ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, circle, palette.ink, 3, 0.9), { delay: 0.14, span: 0.5 });
    if (!ctx.showDecor)
        return;
    ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, (0, temperaHatch_1.circlePolygon)(width / 2, height / 2, radius * 1.12), palette.ink, 1.2, 0.55), { delay: 0.2, drift: true });
};
const ladderFrame = ctx => {
    const { width, height, palette, bleed } = ctx;
    const left = width * 0.14;
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), palette.tone1, 0.9, ctx.gradient), { span: 0.5 });
    const steps = 5;
    for (let index = 0; index < steps; index += 1) {
        const y = height * (0.18 + index * 0.14);
        const run = width * (0.06 + index * 0.03);
        ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, [
            { x1: left, y1: y, x2: left + run, y2: y },
            { x1: left, y1: y, x2: left, y2: y + height * 0.14 },
        ], palette.tone4, index % 2 === 0 ? 3 : 1.4, 0.85), { delay: index * 0.05, span: 0.5, enterDX: -width * 0.1 });
    }
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, [{ x1: width * 0.9, y1: -bleed, x2: width * 0.9, y2: height + bleed }], palette.tone4, 1.4, 0.6), { delay: 0.28, span: 0.5, enterDY: height * 0.2 });
};
const cornerBrackets = ctx => {
    const { width, height, palette, bleed } = ctx;
    const inset = Math.min(width, height) * 0.12;
    const arm = Math.min(width, height) * 0.16;
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), palette.tone2, 0.9, ctx.gradient), { span: 0.5 });
    const corners = [
        [inset, inset, 1, 1],
        [width - inset, inset, -1, 1],
        [inset, height - inset, 1, -1],
        [width - inset, height - inset, -1, -1],
    ];
    corners.forEach(([x, y, sx, sy], index) => {
        ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, [
            { x1: x, y1: y, x2: x + sx * arm, y2: y },
            { x1: x, y1: y, x2: x, y2: y + sy * arm },
        ], palette.ink, 3.5, 0.9), { delay: index * 0.05, span: 0.5, enterDX: sx * width * 0.06, enterDY: sy * height * 0.06 });
    });
    if (!ctx.showDecor)
        return;
    const dotted = (0, temperaRandom_1.temperaHash01)(ctx.seed, 2, 53) > 0.5;
    ctx.add(dotted
        ? (0, temperaShapes_1.drawSquareMarks)(ctx.pixi, (0, temperaHatch_1.buildDotRow)(ctx.seed, 59, width * 0.5, height * 0.16, 3, width * 0.03, 6, 0), palette.tone4, 0.8)
        : (0, temperaShapes_1.drawCrossMarks)(ctx.pixi, (0, temperaHatch_1.buildCrossRow)(ctx.seed, 61, width * 0.44, height * 0.84, 3, width * 0.04, 7), palette.tone4, 1.8, 0.8), { delay: 0.24, drift: true });
};
const insetBox = ctx => {
    const { width, height, palette, bleed } = ctx;
    const box = (0, temperaHatch_1.rectPolygon)(width * 0.14, height * 0.2, width * 0.72, height * 0.6);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), palette.tone1, 0.9, ctx.gradient), { span: 0.5 });
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, box, palette.tone3, 0.55, ctx.gradient), { delay: 0.05, span: 0.55, enterDY: height * 0.06 });
    ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, box, palette.ink, 2.4, 0.85), { delay: 0.1, span: 0.5 });
};
const bracketPair = ctx => {
    const { width, height, palette, bleed } = ctx;
    const inset = width * 0.16;
    const arm = width * 0.09;
    const top = height * 0.26;
    const bottom = height * 0.74;
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), palette.tone2, 0.9, ctx.gradient), { span: 0.5 });
    [1, -1].forEach((side, index) => {
        const x = side === 1 ? inset : width - inset;
        ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, [
            { x1: x, y1: top, x2: x + side * arm, y2: top },
            { x1: x, y1: top, x2: x, y2: bottom },
            { x1: x, y1: bottom, x2: x + side * arm, y2: bottom },
        ], palette.ink, 4, 0.9), { delay: index * 0.07, span: 0.5, enterDX: side * width * 0.08 });
    });
};
const archWindow = ctx => {
    const { width, height, palette, bleed } = ctx;
    const radius = width * 0.24;
    const cx = width / 2;
    const shoulder = height * 0.42;
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), palette.tone3, 0.92, ctx.gradient), { span: 0.5 });
    const arch = (0, temperaHatch_1.circlePolygon)(cx, shoulder, radius, 48);
    const body = (0, temperaHatch_1.rectPolygon)(cx - radius, shoulder, radius * 2, height * 0.4);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, arch, palette.paper, 0.95, ctx.gradient), { delay: 0.05, span: 0.55, enterDY: -height * 0.08 });
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, body, palette.paper, 0.95, ctx.gradient), { delay: 0.05, span: 0.55, enterDY: height * 0.08 });
    ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, arch, palette.ink, 2.4, 0.8), { delay: 0.12, span: 0.5 });
    ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, body, palette.ink, 2.4, 0.8), { delay: 0.12, span: 0.5 });
};
const gridCells = ctx => {
    const { width, height, palette, bleed } = ctx;
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), palette.tone1, 0.9, ctx.gradient), { span: 0.5 });
    const left = width * 0.12;
    const top = height * 0.18;
    const cellWidth = (width * 0.76) / 3;
    const cellHeight = (height * 0.64) / 3;
    for (let row = 0; row < 3; row += 1) {
        for (let column = 0; column < 3; column += 1) {
            const cell = (0, temperaHatch_1.rectPolygon)(left + cellWidth * column, top + cellHeight * row, cellWidth, cellHeight);
            const index = row * 3 + column;
            if (row === 1 && column === 1) {
                ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, cell, palette.tone4, 0.75, ctx.gradient), { delay: index * 0.03, span: 0.5 });
            }
            ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, cell, palette.tone4, 1.2, 0.6), { delay: index * 0.03, span: 0.5 });
        }
    }
};
const keyhole = ctx => {
    const { width, height, palette, bleed } = ctx;
    const radius = Math.min(width, height) * 0.19;
    const cx = width / 2;
    const cy = height * 0.36;
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), palette.tone4, 0.94, ctx.gradient), { span: 0.5 });
    const head = (0, temperaHatch_1.circlePolygon)(cx, cy, radius, 48);
    const shaft = (0, temperaHatch_1.rectPolygon)(cx - radius * 0.55, cy, radius * 1.1, height * 0.46);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, head, palette.paper, 0.96, ctx.gradient), { delay: 0.05, span: 0.55 });
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, shaft, palette.paper, 0.96, ctx.gradient), { delay: 0.08, span: 0.55, enterDY: height * 0.1 });
    ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, head, palette.ink, 2, 0.7), { delay: 0.14, span: 0.5 });
};
exports.TEMPERA_FRAME_COMPOSITIONS = {
    'frame-window': frameWindow,
    'double-frame': doubleFrame,
    'circle-window': circleWindow,
    'ladder-frame': ladderFrame,
    'corner-brackets': cornerBrackets,
    'inset-box': insetBox,
    'bracket-pair': bracketPair,
    'arch-window': archWindow,
    'grid-cells': gridCells,
    'keyhole': keyhole,
};

},
"tempera/compositions/temperaPosterCompositions":function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.TEMPERA_POSTER_COMPOSITIONS = void 0;
const temperaRandom_1 = require("tempera/temperaRandom");
const temperaHatch_1 = require("tempera/temperaHatch");
const temperaShapes_1 = require("tempera/temperaShapes");
const posterPanel = ctx => {
    const { width, height, palette } = ctx;
    const poster = ctx.createGroup(-0.06, width / 2, height / 2);
    const solid = (0, temperaHatch_1.diamondPolygon)(-width * 0.12, 0, width * 0.42, height * 0.66);
    const hatched = (0, temperaHatch_1.diamondPolygon)(width * 0.2, -height * 0.06, width * 0.3, height * 0.48);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, solid, palette.ink, 0.92, ctx.gradient), { enterDX: -width * 0.6, span: 0.55 }, poster);
    ctx.add((0, temperaShapes_1.drawHatchFill)(ctx.pixi, hatched, (0, temperaHatch_1.buildHatchSpec)(ctx.seed, 41), palette.tone4, 0.7), { delay: 0.08, grow: true, span: 0.55 }, poster);
    ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, hatched, palette.ink, 2, 0.8), { delay: 0.12, span: 0.55 }, poster);
    ctx.add((0, temperaShapes_1.drawPolyline)(ctx.pixi, (0, temperaHatch_1.buildWavyPath)(ctx.seed, 43, -width * 0.6, width * 0.6, height * 0.42, height * 0.02), palette.tone4, 2, 0.7), { delay: 0.2, enterDY: height * 0.1 }, poster);
};
const diamondStack = ctx => {
    const { width, height, palette, bleed } = ctx;
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), palette.tone1, 0.9, ctx.gradient), { span: 0.5 });
    const tones = [palette.ink, palette.tone4, palette.tone3];
    tones.forEach((tone, index) => {
        const scale = 1 - index * 0.28;
        const cx = width * (0.34 + index * 0.24);
        const cy = height * (0.52 - index * 0.14);
        ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.diamondPolygon)(cx, cy, width * 0.3 * scale, height * 0.46 * scale), tone, 0.93, ctx.gradient), { delay: index * 0.07, span: 0.55, enterDX: width * 0.25, enterDY: -height * 0.12 });
    });
};
const slashPoster = ctx => {
    const { width, height, palette, bleed } = ctx;
    const lean = height * 0.34;
    const band = [
        -bleed, height * 0.24 + lean,
        width + bleed, height * 0.24 - lean,
        width + bleed, height * 0.72 - lean,
        -bleed, height * 0.72 + lean,
    ];
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), palette.tone1, 0.9, ctx.gradient), { span: 0.5 });
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, band, palette.tone4, 0.94, ctx.gradient), { delay: 0.05, span: 0.55, enterDX: -width * 0.4 });
    ctx.add((0, temperaShapes_1.drawHatchFill)(ctx.pixi, band, Object.assign(Object.assign({}, (0, temperaHatch_1.buildHatchSpec)(ctx.seed, 67)), { angle: Math.PI / 3 }), palette.paper, 0.3), { delay: 0.1, span: 0.55, grow: true });
    ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, band, palette.ink, 2.2, 0.8), { delay: 0.14, span: 0.5 });
};
const arrowWedge = ctx => {
    const { width, height, palette, bleed } = ctx;
    const apex = height * (0.24 + (0, temperaRandom_1.temperaHash01)(ctx.seed, 3, 71) * 0.14);
    const thickness = height * 0.2;
    const chevron = [
        -bleed, height + bleed,
        width * 0.5, apex,
        width + bleed, height + bleed,
        width + bleed, height + bleed,
        width * 0.5, apex + thickness,
        -bleed, height + bleed,
    ];
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), palette.tone1, 0.9, ctx.gradient), { span: 0.5 });
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, [-bleed, height + bleed, width * 0.5, apex, width + bleed, height + bleed], palette.tone4, 0.94, ctx.gradient), { delay: 0.05, span: 0.55, enterDY: height * 0.3 });
    ctx.add((0, temperaShapes_1.drawHatchFill)(ctx.pixi, chevron, Object.assign(Object.assign({}, (0, temperaHatch_1.buildHatchSpec)(ctx.seed, 73)), { angle: -Math.PI / 4 }), palette.paper, 0.35), { delay: 0.1, span: 0.55, grow: true });
    ctx.add((0, temperaShapes_1.drawPolyline)(ctx.pixi, [-bleed, height * 0.9, width * 0.5, apex - thickness * 0.4, width + bleed, height * 0.9], palette.ink, 2, 0.7), { delay: 0.16, span: 0.5, enterDY: -height * 0.1 });
};
const edgeBleed = ctx => {
    const { width, height, palette, bleed } = ctx;
    const fromLeft = (0, temperaRandom_1.temperaHash01)(ctx.seed, 4, 79) > 0.5;
    const cover = width * 0.42;
    const mass = fromLeft
        ? (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, cover + bleed, height + bleed * 2)
        : (0, temperaHatch_1.rectPolygon)(width - cover, -bleed, cover + bleed, height + bleed * 2);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), palette.tone1, 0.9, ctx.gradient), { span: 0.5 });
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, mass, palette.ink, 0.93, ctx.gradient), { delay: 0.05, span: 0.55, enterDX: (fromLeft ? -1 : 1) * width * 0.4 });
    ctx.add((0, temperaShapes_1.drawHatchFill)(ctx.pixi, mass, (0, temperaHatch_1.buildHatchSpec)(ctx.seed, 83), palette.paper, 0.22), { delay: 0.12, span: 0.55, grow: true });
};
const triangleMass = ctx => {
    const { width, height, palette, bleed } = ctx;
    const fromLeft = (0, temperaRandom_1.temperaHash01)(ctx.seed, 91, 89) > 0.5;
    const apexX = fromLeft ? width * 1.02 : -width * 0.02;
    const triangle = [
        fromLeft ? -bleed : width + bleed, -bleed,
        fromLeft ? -bleed : width + bleed, height + bleed,
        apexX, height * (0.3 + (0, temperaRandom_1.temperaHash01)(ctx.seed, 93, 97) * 0.3),
    ];
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), palette.tone1, 0.9, ctx.gradient), { span: 0.5 });
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, triangle, palette.tone4, 0.94, ctx.gradient), { delay: 0.05, span: 0.55, enterDX: (fromLeft ? -1 : 1) * width * 0.35 });
    ctx.add((0, temperaShapes_1.drawHatchFill)(ctx.pixi, triangle, (0, temperaHatch_1.buildHatchSpec)(ctx.seed, 101), palette.paper, 0.24), { delay: 0.12, span: 0.55, grow: true });
};
const ribbonCross = ctx => {
    const { width, height, palette, bleed } = ctx;
    const half = height * 0.14;
    const lean = height * 0.3;
    const ribbon = (sign) => [
        -bleed, height / 2 + sign * lean - half,
        width + bleed, height / 2 - sign * lean - half,
        width + bleed, height / 2 - sign * lean + half,
        -bleed, height / 2 + sign * lean + half,
    ];
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), palette.tone1, 0.9, ctx.gradient), { span: 0.5 });
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, ribbon(1), palette.tone3, 0.8, ctx.gradient), { delay: 0.05, span: 0.55, enterDX: -width * 0.3 });
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, ribbon(-1), palette.tone4, 0.8, ctx.gradient), { delay: 0.11, span: 0.55, enterDX: width * 0.3 });
};
const halfDisc = ctx => {
    const { width, height, palette, bleed } = ctx;
    const fromRight = (0, temperaRandom_1.temperaHash01)(ctx.seed, 103, 107) > 0.5;
    const radius = Math.hypot(width, height) * 0.62;
    const disc = (0, temperaHatch_1.circlePolygon)(fromRight ? width + radius * 0.55 : -radius * 0.55, height * 0.5, radius, 64);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), palette.tone1, 0.9, ctx.gradient), { span: 0.5 });
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, disc, palette.tone4, 0.94, ctx.gradient), { delay: 0.05, span: 0.55, enterDX: (fromRight ? 1 : -1) * width * 0.3 });
    ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, disc, palette.ink, 2, 0.6), { delay: 0.12, span: 0.5 });
};
const stackedSlabs = ctx => {
    const { width, height, palette, bleed } = ctx;
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), palette.tone1, 0.9, ctx.gradient), { span: 0.5 });
    const tones = [palette.tone2, palette.tone3, palette.tone4];
    tones.forEach((tone, index) => {
        const group = ctx.createGroup(-0.09 + index * 0.08, width / 2, height / 2);
        const slab = (0, temperaHatch_1.rectPolygon)(-width * (0.42 - index * 0.05), -height * (0.3 - index * 0.03), width * (0.84 - index * 0.1), height * (0.6 - index * 0.06));
        ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, slab, tone, 0.93, ctx.gradient), { delay: index * 0.07, span: 0.55, enterDX: width * 0.2, enterDY: height * 0.12 }, group);
    });
};
const wedgePair = ctx => {
    const { width, height, palette, bleed } = ctx;
    const waist = width * (0.2 + (0, temperaRandom_1.temperaHash01)(ctx.seed, 109, 113) * 0.1);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), palette.tone1, 0.9, ctx.gradient), { span: 0.5 });
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, [
        -bleed, -bleed, (width - waist) / 2, height / 2, -bleed, height + bleed,
    ], palette.tone4, 0.94, ctx.gradient), { delay: 0.05, span: 0.55, enterDX: -width * 0.25 });
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, [
        width + bleed, -bleed, (width + waist) / 2, height / 2, width + bleed, height + bleed,
    ], palette.tone4, 0.94, ctx.gradient), { delay: 0.11, span: 0.55, enterDX: width * 0.25 });
};
exports.TEMPERA_POSTER_COMPOSITIONS = {
    'poster-panel': posterPanel,
    'diamond-stack': diamondStack,
    'slash-poster': slashPoster,
    'arrow-wedge': arrowWedge,
    'edge-bleed': edgeBleed,
    'triangle-mass': triangleMass,
    'ribbon-cross': ribbonCross,
    'half-disc': halfDisc,
    'stacked-slabs': stackedSlabs,
    'wedge-pair': wedgePair,
};

},
"tempera/compositions/temperaSparseCompositions":function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.TEMPERA_SPARSE_COMPOSITIONS = void 0;
const temperaRandom_1 = require("tempera/temperaRandom");
const temperaHatch_1 = require("tempera/temperaHatch");
const temperaShapes_1 = require("tempera/temperaShapes");
const quietLine = ctx => {
    const { width, height, palette } = ctx;
    const gridWidth = width * 0.7;
    const gridX = (width - gridWidth) / 2;
    [0.38, 0.5, 0.62].forEach((ratio, index) => {
        ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(gridX, height * ratio, gridWidth, 1), palette.line, 1, ctx.gradient), { delay: index * 0.08, span: 0.6, enterDX: (index % 2 === 0 ? -1 : 1) * width * 0.2 });
    });
    if (!ctx.showDecor)
        return;
    ctx.add((0, temperaShapes_1.drawPolyline)(ctx.pixi, (0, temperaHatch_1.buildScribblePath)(ctx.decor.scribbleSeed, 47, width * 0.2, height * 0.26, Math.min(width, height) * 0.09, 2), palette.tone4, 1.6, 0.7), { delay: 0.24, span: 0.6 });
    const tuftX = width * 0.82;
    const tuftY = height * 0.74;
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, Array.from({ length: 6 }, (_, index) => {
        const lean = ((0, temperaRandom_1.temperaHash01)(ctx.decor.scribbleSeed, index, 59) - 0.5) * 34;
        return { x1: tuftX + index * 7, y1: tuftY, x2: tuftX + index * 7 + lean, y2: tuftY - 24 - index * 3 };
    }), palette.tone4, 1.4, 0.7), { delay: 0.3, span: 0.55 });
};
const starfieldDots = ctx => {
    const { width, height, palette, bleed } = ctx;
    const spacing = Math.max(24, Math.sqrt((width * height) / 900));
    const marks = (0, temperaHatch_1.buildDotGrid)(width + bleed, height + bleed, spacing, 2.6);
    const dense = marks.filter(mark => mark.y > height * 0.45);
    const sparse = marks.filter(mark => mark.y <= height * 0.45 && (mark.x + mark.y) % 3 < 1);
    ctx.add((0, temperaShapes_1.drawSquareMarks)(ctx.pixi, dense, palette.tone4, 0.45), { span: 0.6, enterDY: height * 0.2 });
    ctx.add((0, temperaShapes_1.drawSquareMarks)(ctx.pixi, sparse, palette.tone4, 0.25), { delay: 0.08, span: 0.6, enterDY: -height * 0.15 });
    if (!ctx.showDecor)
        return;
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, [{ x1: -bleed, y1: height * 0.45, x2: width + bleed, y2: height * 0.45 }], palette.tone4, 1.2, 0.5), { delay: 0.2, span: 0.5, enterDX: width * 0.2 });
};
const rippleLines = ctx => {
    const { width, height, palette, bleed } = ctx;
    const count = 7;
    for (let index = 0; index < count; index += 1) {
        const y = height * (0.16 + index * 0.11);
        const amplitude = height * (0.006 + index * 0.004);
        ctx.add((0, temperaShapes_1.drawPolyline)(ctx.pixi, (0, temperaHatch_1.buildWavyPath)(ctx.seed, 89 + index, -bleed, width + bleed, y, amplitude, 26), palette.tone4, index % 3 === 0 ? 2 : 1.1, 0.55), { delay: index * 0.045, span: 0.6, enterDX: (index % 2 === 0 ? -1 : 1) * width * 0.15 });
    }
};
const hairGrid = ctx => {
    const { width, height, palette, bleed } = ctx;
    const columns = 6;
    const rows = 4;
    const vertical = Array.from({ length: columns + 1 }, (_, index) => ({
        x1: (width / columns) * index, y1: -bleed, x2: (width / columns) * index, y2: height + bleed,
    }));
    const horizontal = Array.from({ length: rows + 1 }, (_, index) => ({
        x1: -bleed, y1: (height / rows) * index, x2: width + bleed, y2: (height / rows) * index,
    }));
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, vertical, palette.line, 1, 0.8), { span: 0.6, enterDY: -height * 0.1 });
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, horizontal, palette.line, 1, 0.8), { delay: 0.08, span: 0.6, enterDX: width * 0.1 });
};
const marginRule = ctx => {
    const { width, height, palette, bleed } = ctx;
    const fromLeft = (0, temperaRandom_1.temperaHash01)(ctx.seed, 121, 127) > 0.5;
    const x = fromLeft ? width * 0.12 : width * 0.88;
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(x - 3, -bleed, 6, height + bleed * 2), palette.tone4, 0.9, ctx.gradient), { span: 0.6, enterDY: height * 0.15 });
    if (!ctx.showDecor)
        return;
    ctx.add((0, temperaShapes_1.drawSquareMarks)(ctx.pixi, [0, 1, 2].map(index => ({ x: x + (fromLeft ? 22 : -22), y: height * (0.32 + index * 0.18), size: 7, rotation: 0 })), palette.tone4, 0.8), { delay: 0.22, drift: true });
};
const dotDrift = ctx => {
    const { width, height, palette, bleed } = ctx;
    const spacing = Math.max(22, Math.sqrt((width * height) / 1200));
    const marks = (0, temperaHatch_1.buildDotGrid)(width + bleed, height + bleed, spacing, 2.4);
    const span = width + height;
    const near = marks.filter(mark => mark.x + mark.y > span * 0.5);
    const far = marks.filter(mark => mark.x + mark.y <= span * 0.5 && (mark.x + mark.y) % 2 < 1);
    ctx.add((0, temperaShapes_1.drawSquareMarks)(ctx.pixi, near, palette.tone4, 0.5), { span: 0.6, enterDX: width * 0.12 });
    ctx.add((0, temperaShapes_1.drawSquareMarks)(ctx.pixi, far, palette.tone4, 0.24), { delay: 0.08, span: 0.6, enterDX: -width * 0.12 });
};
const arcSweep = ctx => {
    const { width, height, palette } = ctx;
    const cx = width * ((0, temperaRandom_1.temperaHash01)(ctx.seed, 131, 137) > 0.5 ? 1.15 : -0.15);
    const cy = height * 1.05;
    const base = Math.hypot(width, height) * 0.42;
    for (let index = 0; index < 5; index += 1) {
        ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, (0, temperaHatch_1.circlePolygon)(cx, cy, base + index * base * 0.22, 72), palette.tone4, index % 2 === 0 ? 1.8 : 1, 0.55), { delay: index * 0.05, span: 0.6, enterDY: height * 0.08 });
    }
};
const blankPage = ctx => {
    const { width, height, palette } = ctx;
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, [
        { x1: width * 0.18, y1: height * 0.7, x2: width * 0.36, y2: height * 0.7 },
    ], palette.line, 1.4, 0.8), { span: 0.6, enterDX: -width * 0.12 });
    if (!ctx.showDecor)
        return;
    ctx.add((0, temperaShapes_1.drawPolyline)(ctx.pixi, (0, temperaHatch_1.buildScribblePath)(ctx.decor.scribbleSeed, 139, width * 0.82, height * 0.26, Math.min(width, height) * 0.06, 2), palette.tone4, 1.4, 0.6), { delay: 0.28, span: 0.6 });
};
exports.TEMPERA_SPARSE_COMPOSITIONS = {
    'quiet-line': quietLine,
    'starfield-dots': starfieldDots,
    'ripple-lines': rippleLines,
    'hair-grid': hairGrid,
    'margin-rule': marginRule,
    'dot-drift': dotDrift,
    'arc-sweep': arcSweep,
    'blank-page': blankPage,
};

},
"tempera/compositions/temperaCinemaCompositions":function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.TEMPERA_CINEMA_COMPOSITIONS = void 0;
const temperaRandom_1 = require("tempera/temperaRandom");
const temperaHatch_1 = require("tempera/temperaHatch");
const temperaShapes_1 = require("tempera/temperaShapes");
const fitWindow = (width, height, aspect, fill) => {
    const maxWidth = width * fill;
    const maxHeight = height * fill;
    const windowWidth = Math.min(maxWidth, maxHeight * aspect);
    const windowHeight = windowWidth / aspect;
    return {
        x: (width - windowWidth) / 2,
        y: (height - windowHeight) / 2,
        width: windowWidth,
        height: windowHeight,
    };
};
const addMatte = (ctx, hole, tone) => {
    const { width, height, bleed } = ctx;
    const bars = [
        { polygon: (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, hole.y + bleed), enterDX: 0, enterDY: -height * 0.2 },
        { polygon: (0, temperaHatch_1.rectPolygon)(-bleed, hole.y + hole.height, width + bleed * 2, height - hole.y - hole.height + bleed), enterDX: 0, enterDY: height * 0.2 },
        { polygon: (0, temperaHatch_1.rectPolygon)(-bleed, hole.y, hole.x + bleed, hole.height), enterDX: -width * 0.2, enterDY: 0 },
        { polygon: (0, temperaHatch_1.rectPolygon)(hole.x + hole.width, hole.y, width - hole.x - hole.width + bleed, hole.height), enterDX: width * 0.2, enterDY: 0 },
    ];
    bars.forEach((bar, index) => {
        ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, bar.polygon, tone, 0.96, ctx.gradient), {
            delay: index * 0.04,
            span: 0.5,
            enterDX: bar.enterDX,
            enterDY: bar.enterDY,
        });
    });
    ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(hole.x, hole.y, hole.width, hole.height), ctx.palette.ink, 1.6, 0.5), { delay: 0.2, span: 0.5 });
};
const addWindowWash = (ctx, hole, alpha) => {
    const polygon = (0, temperaHatch_1.rectPolygon)(hole.x, hole.y, hole.width, hole.height);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, polygon, ctx.palette.tone1, alpha, ctx.gradient), { span: 0.55 });
    ctx.add((0, temperaShapes_1.drawHatchFill)(ctx.pixi, polygon, (0, temperaHatch_1.buildHatchSpec)(ctx.seed, 149, 1.5), ctx.palette.tone4, 0.2), { delay: 0.1, span: 0.6, grow: true });
};
const matte = (aspect, fill, washAlpha = 0.35) => ctx => {
    const hole = fitWindow(ctx.width, ctx.height, aspect, fill);
    addWindowWash(ctx, hole, washAlpha);
    addMatte(ctx, hole, ctx.palette.tone4);
    if (!ctx.showDecor)
        return;
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, [
        { x1: hole.x, y1: hole.y - ctx.height * 0.05, x2: hole.x, y2: hole.y - ctx.height * 0.02 },
        { x1: hole.x + hole.width, y1: hole.y + hole.height + ctx.height * 0.02, x2: hole.x + hole.width, y2: hole.y + hole.height + ctx.height * 0.05 },
    ], ctx.palette.paper, 2, 0.6), { delay: 0.26, span: 0.5 });
};
const cinemaTwin = ctx => {
    const { width, height, palette, bleed } = ctx;
    const inset = height * 0.16;
    const gutter = width * 0.04;
    const left = { x: width * 0.08, y: inset, width: width * 0.5, height: height - inset * 2 };
    const right = {
        x: left.x + left.width + gutter,
        y: inset + height * 0.1,
        width: width * 0.28,
        height: height - inset * 2 - height * 0.2,
    };
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), palette.tone4, 0.96, ctx.gradient), { span: 0.5 });
    [left, right].forEach((hole, index) => {
        const polygon = (0, temperaHatch_1.rectPolygon)(hole.x, hole.y, hole.width, hole.height);
        ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, polygon, palette.tone1, index === 0 ? 0.4 : 0.85, ctx.gradient), { delay: index * 0.08, span: 0.55, enterDX: (index === 0 ? -1 : 1) * width * 0.14 });
        ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, polygon, palette.ink, 1.6, 0.5), { delay: 0.16 + index * 0.05, span: 0.5 });
    });
    if (!ctx.showDecor)
        return;
    ctx.add((0, temperaShapes_1.drawHatchFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(right.x, right.y, right.width, right.height), (0, temperaHatch_1.buildHatchSpec)(ctx.seed, 151), palette.tone4, 0.35), { delay: 0.24, span: 0.6, grow: true });
};
const jitteredFill = (ctx, base) => (base + ((0, temperaRandom_1.temperaHash01)(ctx.seed, 157, 163) - 0.5) * 0.06);
exports.TEMPERA_CINEMA_COMPOSITIONS = {
    'cinema-scope': ctx => matte(2.39, jitteredFill(ctx, 0.88))(ctx),
    'cinema-wide': ctx => matte(1.85, jitteredFill(ctx, 0.84))(ctx),
    'cinema-academy': ctx => matte(1.33, jitteredFill(ctx, 0.78))(ctx),
    'cinema-square': ctx => matte(1, jitteredFill(ctx, 0.72))(ctx),
    'cinema-portrait': ctx => matte(0.75, jitteredFill(ctx, 0.72))(ctx),
    'cinema-tall': ctx => matte(0.5625, jitteredFill(ctx, 0.72))(ctx),
    'cinema-twin': cinemaTwin,
};

},
"tempera/compositions/temperaCharmCompositions":function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.TEMPERA_CHARM_COMPOSITIONS = void 0;
const temperaRandom_1 = require("tempera/temperaRandom");
const temperaHatch_1 = require("tempera/temperaHatch");
const temperaCurves_1 = require("tempera/temperaCurves");
const temperaShapes_1 = require("tempera/temperaShapes");
const addField = (ctx, color, alpha = 0.92) => {
    const { width, height, bleed } = ctx;
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), color, alpha, ctx.gradient), { span: 0.5 });
};
const bubbleDrift = ctx => {
    const { width, height, palette } = ctx;
    const unit = Math.min(width, height);
    addField(ctx, palette.tone1);
    const big = (0, temperaCurves_1.buildDiscField)(ctx.seed, 11, width, height, 8, unit * 0.115);
    const small = (0, temperaCurves_1.buildDiscField)(ctx.seed, 17, width, height, 13, unit * 0.042);
    ctx.add((0, temperaShapes_1.drawDiscs)(ctx.pixi, big, palette.tone3, 0.88, ctx.gradient), { delay: 0.05, span: 0.6, enterDY: height * 0.16, drift: true });
    ctx.add((0, temperaShapes_1.drawRings)(ctx.pixi, big, palette.ink, 2, 0.55), { delay: 0.12, span: 0.55, enterDY: height * 0.12 });
    ctx.add((0, temperaShapes_1.drawDiscs)(ctx.pixi, small, palette.tone4, 0.7), { delay: 0.18, span: 0.6, enterDY: height * 0.22, drift: true });
    if (!ctx.showDecor)
        return;
    ctx.add((0, temperaShapes_1.drawDiscs)(ctx.pixi, big.slice(0, 2).map(disc => ({
        x: disc.x - disc.radius * 0.36,
        y: disc.y - disc.radius * 0.36,
        radius: disc.radius * 0.16,
    })), palette.paper, 0.85), { delay: 0.28, drift: true });
};
const cloudWindow = ctx => {
    const { width, height, palette } = ctx;
    const unit = Math.min(width, height);
    const cx = width / 2;
    const cy = height * 0.52;
    const rx = width * 0.3;
    const ry = height * 0.3;
    addField(ctx, palette.tone3);
    const cloud = (0, temperaCurves_1.lobedPolygon)(cx, cy, rx, ry, 9, 0.1);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaCurves_1.lobedPolygon)(cx, cy + height * 0.025, rx * 1.05, ry * 1.05, 9, 0.1), palette.tone4, 0.5), { delay: 0.04, span: 0.6 });
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, cloud, palette.paper, 0.96, ctx.gradient), { delay: 0.08, span: 0.55 });
    ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, cloud, palette.ink, 2.4, 0.85), { delay: 0.12, span: 0.5 });
    if (!ctx.showDecor)
        return;
    ctx.add((0, temperaShapes_1.drawDiscs)(ctx.pixi, [
        { x: cx - rx * 1.16, y: cy + ry * 0.66, radius: unit * 0.035 },
        { x: cx - rx * 1.32, y: cy + ry * 0.9, radius: unit * 0.02 },
    ], palette.paper, 0.92, ctx.gradient), { delay: 0.22, drift: true });
};
const heartBurst = ctx => {
    const { width, height, palette } = ctx;
    const lean = (0, temperaRandom_1.temperaHash01)(ctx.seed, 3, 83) > 0.5 ? 1 : -1;
    const cx = width * 0.5;
    const cy = height * 0.52;
    const rx = width * 0.32;
    const ry = height * 0.4;
    addField(ctx, palette.tone4, 0.94);
    const main = (0, temperaCurves_1.rotatePolygon)((0, temperaCurves_1.heartPolygon)(cx, cy, rx, ry), cx, cy, lean * 0.06);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaCurves_1.rotatePolygon)((0, temperaCurves_1.heartPolygon)(cx + lean * width * 0.022, cy + height * 0.025, rx, ry), cx, cy, lean * 0.06), palette.tone2, 0.6), { delay: 0.04, span: 0.6 });
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, main, palette.paper, 0.95, ctx.gradient), { delay: 0.08, span: 0.55, enterDY: height * 0.1 });
    ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, main, palette.ink, 3, 0.9), { delay: 0.14, span: 0.5, enterDY: height * 0.08 });
    [0.4, 0.24].forEach((scale, index) => {
        const x = lean > 0 ? width * (0.88 + index * 0.08) : width * (0.12 - index * 0.08);
        const y = height * (0.24 + index * 0.42);
        const group = ctx.createGroup(0, x, y);
        ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaCurves_1.rotatePolygon)((0, temperaCurves_1.heartPolygon)(0, 0, rx * scale, ry * scale), 0, 0, -lean * 0.22), palette.tone2, 0.9, ctx.gradient), { delay: 0.2 + index * 0.06, span: 0.5, enterDX: lean * width * 0.12, drift: true }, group);
    });
};
const sparkleField = ctx => {
    const { width, height, palette } = ctx;
    const unit = Math.min(width, height);
    addField(ctx, palette.tone1, 0.88);
    const seeds = (0, temperaCurves_1.buildDiscField)(ctx.seed, 23, width, height, 9, unit * 0.07);
    seeds.slice(0, 5).forEach((disc, index) => {
        const star = (0, temperaCurves_1.starPolygon)(0, 0, disc.radius, disc.radius * 0.16, 4, (0, temperaRandom_1.temperaHash01)(ctx.seed, index, 29) * 0.9);
        const group = ctx.createGroup(0, disc.x, disc.y);
        ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, star, palette.tone4, 0.9, ctx.gradient), { delay: 0.06 + index * 0.05, span: 0.5, drift: true }, group);
    });
    ctx.add((0, temperaShapes_1.drawDiscs)(ctx.pixi, seeds.slice(5).map(disc => (Object.assign(Object.assign({}, disc), { radius: disc.radius * 0.22 }))), palette.tone4, 0.7), { delay: 0.24, span: 0.55, drift: true });
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, [{ x1: width * 0.08, y1: height * 0.74, x2: width * 0.92, y2: height * 0.72 }], palette.tone4, 1.2, 0.5), { delay: 0.3, span: 0.5, enterDX: -width * 0.12 });
};
const petalArc = ctx => {
    const { width, height, palette } = ctx;
    const fromLeft = (0, temperaRandom_1.temperaHash01)(ctx.seed, 5, 89) > 0.5;
    const hubX = fromLeft ? -width * 0.1 : width * 1.1;
    const hubY = height * 0.12;
    const rx = width * 0.26;
    const ry = height * 0.085;
    addField(ctx, palette.tone2);
    for (let index = 0; index < 5; index += 1) {
        const base = (0, temperaCurves_1.ellipsePolygon)(hubX + (fromLeft ? rx : -rx), hubY, rx, ry, 28);
        const petal = (0, temperaCurves_1.rotatePolygon)(base, hubX, hubY, (fromLeft ? 1 : -1) * (0.18 + index * 0.3));
        ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, petal, index % 2 === 0 ? palette.tone3 : palette.tone1, 0.9, ctx.gradient), { delay: index * 0.05, span: 0.55, enterDY: -height * 0.1 });
        ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, petal, palette.ink, 1.6, 0.5), { delay: 0.06 + index * 0.05, span: 0.5 });
    }
    const hub = ctx.createGroup(0, hubX, hubY);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaCurves_1.lobedPolygon)(0, 0, width * 0.11, width * 0.11, 6, 0.34), palette.tone4, 0.9, ctx.gradient), { delay: 0.28, span: 0.5, drift: true }, hub);
    if (!ctx.showDecor)
        return;
    ctx.add((0, temperaShapes_1.drawDiscs)(ctx.pixi, [0, 1, 2].map(index => ({
        x: fromLeft ? width * (0.78 + index * 0.07) : width * (0.22 - index * 0.07),
        y: height * (0.7 + index * 0.1),
        radius: height * (0.03 - index * 0.006),
    })), palette.tone4, 0.75, ctx.gradient), { delay: 0.32, span: 0.5, drift: true });
};
const scallopBand = ctx => {
    const { width, height, palette, bleed } = ctx;
    addField(ctx, palette.tone1, 0.9);
    const top = (0, temperaCurves_1.scallopBandPolygon)(-bleed, width + bleed, -bleed, height * 0.28, 9);
    const bottom = (0, temperaCurves_1.scallopBandPolygon)(-bleed, width + bleed, height + bleed, height * 0.72, 9);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, top, palette.tone3, 0.92, ctx.gradient), { delay: 0.04, span: 0.55, enterDY: -height * 0.18 });
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, bottom, palette.tone4, 0.92, ctx.gradient), { delay: 0.1, span: 0.55, enterDY: height * 0.18 });
    ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, top, palette.ink, 2, 0.75), { delay: 0.14, span: 0.5, enterDY: -height * 0.12 });
    ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, bottom, palette.ink, 2, 0.75), { delay: 0.18, span: 0.5, enterDY: height * 0.12 });
    if (!ctx.showDecor)
        return;
    const pitch = (width + bleed * 2) / 9;
    const beads = Array.from({ length: 5 }, (_, index) => ({
        x: -bleed + pitch * (index + 2),
        y: height * 0.28,
        radius: Math.min(width, height) * 0.018,
    }));
    ctx.add((0, temperaShapes_1.drawDiscs)(ctx.pixi, beads, palette.ink, 0.7), { delay: 0.26, drift: true });
};
const ribbonLoop = ctx => {
    const { width, height, palette, bleed } = ctx;
    const sag = height * (0.06 + (0, temperaRandom_1.temperaHash01)(ctx.seed, 7, 97) * 0.05) * ((0, temperaRandom_1.temperaHash01)(ctx.seed, 9, 97) > 0.5 ? 1 : -1);
    addField(ctx, palette.tone2);
    const band = (0, temperaCurves_1.arcRibbonPolygon)(-bleed, width + bleed, height * 0.5, height * 0.3, sag);
    const echo = (0, temperaCurves_1.arcRibbonPolygon)(-bleed, width + bleed, height * 0.68, height * 0.06, -sag);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, echo, palette.tone4, 0.7, ctx.gradient), { delay: 0.04, span: 0.6, enterDX: -width * 0.16 });
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, band, palette.paper, 0.95, ctx.gradient), { delay: 0.08, span: 0.55, enterDX: width * 0.18 });
    ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, band, palette.ink, 2.6, 0.85), { delay: 0.14, span: 0.5, enterDX: width * 0.14 });
    const knotX = width * ((0, temperaRandom_1.temperaHash01)(ctx.seed, 11, 97) > 0.5 ? 0.24 : 0.76);
    const knotY = height * 0.5 + Math.sin((knotX + bleed) / (width + bleed * 2) * Math.PI) * sag;
    const bow = ctx.createGroup(0, knotX, knotY);
    [-1, 1].forEach((side, index) => {
        const loop = (0, temperaCurves_1.rotatePolygon)((0, temperaCurves_1.ellipsePolygon)(side * width * 0.055, 0, width * 0.05, height * 0.07, 26), 0, 0, side * 0.3);
        ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, loop, palette.tone4, 0.92, ctx.gradient), { delay: 0.2 + index * 0.04, span: 0.5, enterDX: side * width * 0.06 }, bow);
        ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, loop, palette.ink, 2, 0.8), { delay: 0.24 + index * 0.04, span: 0.5 }, bow);
    });
    const knot = (0, temperaCurves_1.roundedRectPolygon)(-width * 0.018, -height * 0.035, width * 0.036, height * 0.07, height * 0.02);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, knot, palette.tone4, 0.95, ctx.gradient), { delay: 0.28, span: 0.5 }, bow);
    ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, knot, palette.ink, 2, 0.85), { delay: 0.3, span: 0.5 }, bow);
};
const roundPlate = ctx => {
    const { width, height, palette } = ctx;
    const unit = Math.min(width, height);
    addField(ctx, palette.tone3);
    const plate = (0, temperaCurves_1.roundedRectPolygon)(width * 0.16, height * 0.24, width * 0.68, height * 0.52, unit * 0.11);
    const inner = (0, temperaCurves_1.roundedRectPolygon)(width * 0.19, height * 0.29, width * 0.62, height * 0.42, unit * 0.08);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, plate, palette.paper, 0.95, ctx.gradient), { delay: 0.05, span: 0.55, enterDY: height * 0.06 });
    ctx.add((0, temperaShapes_1.drawHatchFill)(ctx.pixi, inner, (0, temperaHatch_1.buildHatchSpec)(ctx.seed, 101, 1.3), palette.tone2, 0.35), { delay: 0.1, span: 0.6, grow: true });
    ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, plate, palette.ink, 3, 0.9), { delay: 0.12, span: 0.5 });
    ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, inner, palette.tone4, 1.2, 0.55), { delay: 0.16, span: 0.5 });
    if (!ctx.showDecor)
        return;
    ctx.add((0, temperaShapes_1.drawDiscs)(ctx.pixi, [
        { x: width * 0.22, y: height * 0.3, radius: unit * 0.016 },
        { x: width * 0.78, y: height * 0.3, radius: unit * 0.016 },
        { x: width * 0.22, y: height * 0.7, radius: unit * 0.016 },
        { x: width * 0.78, y: height * 0.7, radius: unit * 0.016 },
    ], palette.ink, 0.75), { delay: 0.22, span: 0.5 });
};
const haloBurst = ctx => {
    const { width, height, palette } = ctx;
    const unit = Math.min(width, height);
    const cx = width * (0.44 + (0, temperaRandom_1.temperaHash01)(ctx.seed, 13, 103) * 0.12);
    const cy = height * 0.5;
    const reach = Math.hypot(width, height) * 0.7;
    const wedges = 14;
    addField(ctx, palette.tone1);
    for (let index = 0; index < wedges; index += 2) {
        const angle = (index / wedges) * Math.PI * 2 + (0, temperaRandom_1.temperaHash01)(ctx.seed, index, 107) * 0.09;
        const spread = 0.11;
        ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, [
            cx, cy,
            cx + Math.cos(angle - spread) * reach, cy + Math.sin(angle - spread) * reach,
            cx + Math.cos(angle + spread) * reach, cy + Math.sin(angle + spread) * reach,
        ], palette.tone3, 0.55, ctx.gradient), { delay: 0.04 + index * 0.012, span: 0.6 });
    }
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaCurves_1.ellipsePolygon)(cx, cy, unit * 0.34, unit * 0.34, 48), palette.paper, 0.94, ctx.gradient), { delay: 0.14, span: 0.55 });
    [[0.34, 3], [0.44, 1.4]].forEach(([scale, stroke], index) => {
        ctx.add((0, temperaShapes_1.drawRings)(ctx.pixi, [{ x: cx, y: cy, radius: unit * scale }], palette.ink, stroke, 0.75), { delay: 0.2 + index * 0.06, span: 0.5, drift: true });
    });
};
exports.TEMPERA_CHARM_COMPOSITIONS = {
    'bubble-drift': bubbleDrift,
    'cloud-window': cloudWindow,
    'heart-burst': heartBurst,
    'sparkle-field': sparkleField,
    'petal-arc': petalArc,
    'scallop-band': scallopBand,
    'ribbon-loop': ribbonLoop,
    'round-plate': roundPlate,
    'halo-burst': haloBurst,
};

},
"tempera/temperaCurves":function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildDiscField = exports.arcRibbonPolygon = exports.starPolygon = exports.annularSectorPolygon = exports.heartPolygon = exports.scallopBandPolygon = exports.lobedPolygon = exports.rotatePolygon = exports.roundedRectPolygon = exports.ellipsePolygon = void 0;
const temperaRandom_1 = require("tempera/temperaRandom");
const TAU = Math.PI * 2;
const ellipsePolygon = (cx, cy, rx, ry, segments = 32) => {
    const count = Math.max(8, Math.round(segments));
    const points = [];
    for (let index = 0; index < count; index += 1) {
        const angle = (index / count) * TAU;
        points.push(cx + Math.cos(angle) * rx, cy + Math.sin(angle) * ry);
    }
    return points;
};
exports.ellipsePolygon = ellipsePolygon;
const roundedRectPolygon = (x, y, width, height, radius, cornerSegments = 6) => {
    const limit = Math.max(0, Math.min(radius, Math.min(width, height) / 2));
    const steps = Math.max(1, Math.round(cornerSegments));
    const corners = [
        [x + width - limit, y + limit, -Math.PI / 2],
        [x + width - limit, y + height - limit, 0],
        [x + limit, y + height - limit, Math.PI / 2],
        [x + limit, y + limit, Math.PI],
    ];
    const points = [];
    corners.forEach(([ccx, ccy, start]) => {
        for (let step = 0; step <= steps; step += 1) {
            const angle = start + (step / steps) * (Math.PI / 2);
            points.push(ccx + Math.cos(angle) * limit, ccy + Math.sin(angle) * limit);
        }
    });
    return points;
};
exports.roundedRectPolygon = roundedRectPolygon;
const rotatePolygon = (polygon, cx, cy, angle) => {
    const cos = Math.cos(angle);
    const sin = Math.sin(angle);
    const points = [];
    for (let index = 0; index < polygon.length; index += 2) {
        const dx = polygon[index] - cx;
        const dy = polygon[index + 1] - cy;
        points.push(cx + dx * cos - dy * sin, cy + dx * sin + dy * cos);
    }
    return points;
};
exports.rotatePolygon = rotatePolygon;
const lobedPolygon = (cx, cy, rx, ry, lobes, amplitude, segments = 96) => {
    const count = Math.max(24, Math.round(segments));
    const petals = Math.max(1, Math.round(lobes));
    const swell = Math.max(0, amplitude);
    const points = [];
    for (let index = 0; index < count; index += 1) {
        const angle = (index / count) * TAU;
        const scale = (1 + Math.cos(angle * petals) * swell) / (1 + swell);
        points.push(cx + Math.cos(angle) * rx * scale, cy + Math.sin(angle) * ry * scale);
    }
    return points;
};
exports.lobedPolygon = lobedPolygon;
const scallopBandPolygon = (x0, x1, flatY, baseY, bumps, segmentsPerBump = 10) => {
    const count = Math.max(1, Math.round(bumps));
    const steps = Math.max(3, Math.round(segmentsPerBump));
    const span = (x1 - x0) / count;
    const radius = Math.abs(span) / 2;
    const direction = baseY >= flatY ? 1 : -1;
    const points = [x0, flatY, x1, flatY];
    for (let bump = count - 1; bump >= 0; bump -= 1) {
        const cx = x0 + span * (bump + 0.5);
        for (let step = 0; step <= steps; step += 1) {
            const angle = (step / steps) * Math.PI;
            points.push(cx + Math.cos(angle) * (span / 2), baseY + direction * Math.sin(angle) * radius);
        }
    }
    return points;
};
exports.scallopBandPolygon = scallopBandPolygon;
const heartPolygon = (cx, cy, rx, ry, segments = 64) => {
    const count = Math.max(16, Math.round(segments));
    const raw = [];
    let minX = Number.POSITIVE_INFINITY;
    let maxX = Number.NEGATIVE_INFINITY;
    let minY = Number.POSITIVE_INFINITY;
    let maxY = Number.NEGATIVE_INFINITY;
    for (let index = 0; index < count; index += 1) {
        const t = (index / count) * TAU;
        const x = Math.pow(Math.sin(t), 3) * 16;
        const y = -(13 * Math.cos(t) - 5 * Math.cos(2 * t) - 2 * Math.cos(3 * t) - Math.cos(4 * t));
        raw.push(x, y);
        minX = Math.min(minX, x);
        maxX = Math.max(maxX, x);
        minY = Math.min(minY, y);
        maxY = Math.max(maxY, y);
    }
    const halfWidth = Math.max(1e-6, (maxX - minX) / 2);
    const halfHeight = Math.max(1e-6, (maxY - minY) / 2);
    const midX = (minX + maxX) / 2;
    const midY = (minY + maxY) / 2;
    const points = [];
    for (let index = 0; index < raw.length; index += 2) {
        points.push(cx + ((raw[index] - midX) / halfWidth) * rx, cy + ((raw[index + 1] - midY) / halfHeight) * ry);
    }
    return points;
};
exports.heartPolygon = heartPolygon;
const annularSectorPolygon = (cx, cy, innerRadius, outerRadius, startAngle, endAngle, segments = 10) => {
    const steps = Math.max(2, Math.round(segments));
    const points = [];
    for (let step = 0; step <= steps; step += 1) {
        const angle = startAngle + ((endAngle - startAngle) * step) / steps;
        points.push(cx + Math.cos(angle) * outerRadius, cy + Math.sin(angle) * outerRadius);
    }
    for (let step = steps; step >= 0; step -= 1) {
        const angle = startAngle + ((endAngle - startAngle) * step) / steps;
        points.push(cx + Math.cos(angle) * innerRadius, cy + Math.sin(angle) * innerRadius);
    }
    return points;
};
exports.annularSectorPolygon = annularSectorPolygon;
const starPolygon = (cx, cy, outerRadius, innerRadius, points, rotation = 0) => {
    const tips = Math.max(3, Math.round(points));
    const polygon = [];
    for (let index = 0; index < tips * 2; index += 1) {
        const radius = index % 2 === 0 ? outerRadius : innerRadius;
        const angle = rotation - Math.PI / 2 + (index / (tips * 2)) * TAU;
        polygon.push(cx + Math.cos(angle) * radius, cy + Math.sin(angle) * radius);
    }
    return polygon;
};
exports.starPolygon = starPolygon;
const arcRibbonPolygon = (x0, x1, y, thickness, sag, steps = 28) => {
    const count = Math.max(4, Math.round(steps));
    const half = thickness / 2;
    const top = [];
    const bottom = [];
    for (let index = 0; index <= count; index += 1) {
        const progress = index / count;
        const x = x0 + (x1 - x0) * progress;
        const centre = y + Math.sin(progress * Math.PI) * sag;
        top.push(x, centre - half);
        bottom.push(x, centre + half);
    }
    const points = [...top];
    for (let index = bottom.length - 2; index >= 0; index -= 2) {
        points.push(bottom[index], bottom[index + 1]);
    }
    return points;
};
exports.arcRibbonPolygon = arcRibbonPolygon;
const buildDiscField = (seed, salt, width, height, count, radius) => {
    const total = Math.max(0, Math.round(count));
    if (total === 0 || width <= 0 || height <= 0)
        return [];
    const columns = Math.max(1, Math.round(Math.sqrt(total * (width / height))));
    const rows = Math.max(1, Math.ceil(total / columns));
    const cellWidth = width / columns;
    const cellHeight = height / rows;
    const discs = [];
    for (let index = 0; index < total; index += 1) {
        const column = index % columns;
        const row = Math.floor(index / columns);
        discs.push({
            x: cellWidth * (column + 0.15 + (0, temperaRandom_1.temperaHash01)(seed, index, salt) * 0.7),
            y: cellHeight * (row + 0.15 + (0, temperaRandom_1.temperaHash01)(seed, index, salt + 3) * 0.7),
            radius: radius * (0.55 + (0, temperaRandom_1.temperaHash01)(seed, index, salt + 7) * 0.75),
        });
    }
    return discs;
};
exports.buildDiscField = buildDiscField;

},
"tempera/compositions/temperaApertureCompositions":function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.TEMPERA_APERTURE_COMPOSITIONS = void 0;
const temperaRandom_1 = require("tempera/temperaRandom");
const temperaHatch_1 = require("tempera/temperaHatch");
const temperaShapes_1 = require("tempera/temperaShapes");
const temperaCurves_1 = require("tempera/temperaCurves");
const temperaCutout_1 = require("tempera/compositions/temperaCutout");
const irisHole = ctx => {
    const { width, height, palette } = ctx;
    const unit = Math.min(width, height);
    const cx = width * 0.68;
    const cy = height * 0.42;
    const radius = unit * 0.3;
    const hole = (0, temperaHatch_1.circlePolygon)(cx, cy, radius, 56);
    (0, temperaCutout_1.addCutField)(ctx, palette.tone3, [hole]);
    (0, temperaCutout_1.addHoleLip)(ctx, hole, 3, 0.9, 0.08);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-ctx.bleed, cy - unit * 0.035, cx - radius * 0.7 + ctx.bleed, unit * 0.07), palette.tone4, 0.9, ctx.gradient), { delay: 0.14, span: 0.55, enterDX: -width * 0.12 });
    if (!ctx.showDecor)
        return;
    ctx.add((0, temperaShapes_1.drawRings)(ctx.pixi, [{ x: cx, y: cy, radius: radius * 1.14 }], palette.tone4, 1.4, 0.6), { delay: 0.2, span: 0.5, drift: true });
};
const slotRail = ctx => {
    const { width, height, palette, bleed } = ctx;
    const top = height * 0.22;
    const slot = (0, temperaHatch_1.rectPolygon)(-bleed, top, width + bleed * 2, height * 0.16);
    (0, temperaCutout_1.addCutField)(ctx, palette.tone4, [slot]);
    (0, temperaCutout_1.addHoleLip)(ctx, slot, 2.4, 0.8, 0.1);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(width * 0.66, top - height * 0.06, width * 0.12, height * 0.28), palette.tone2, 0.95, ctx.gradient), { delay: 0.16, span: 0.55, enterDY: -height * 0.1 });
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, [{ x1: -bleed, y1: top + height * 0.22, x2: width + bleed, y2: top + height * 0.22 }], palette.tone2, 1.4, 0.55), { delay: 0.22, span: 0.5, enterDX: width * 0.14 });
};
const punchRow = ctx => {
    const { width, height, palette } = ctx;
    const unit = Math.min(width, height);
    const radius = unit * 0.028;
    const holes = [];
    for (let index = 0; index < 9; index += 1) {
        const x = width * (0.08 + index * 0.105);
        holes.push((0, temperaHatch_1.circlePolygon)(x, height * 0.14, radius, 20));
        holes.push((0, temperaHatch_1.circlePolygon)(x, height * 0.86, radius, 20));
    }
    (0, temperaCutout_1.addCutField)(ctx, palette.tone3, holes);
    [0.22, 0.78].forEach((y, index) => {
        ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, [{ x1: 0, y1: height * y, x2: width, y2: height * y }], palette.tone4, 1.6, 0.6), { delay: 0.12 + index * 0.04, span: 0.5, enterDX: (index === 0 ? 1 : -1) * width * 0.12 });
    });
};
const filmGate = ctx => {
    const { width, height, palette } = ctx;
    const unit = Math.min(width, height);
    const gate = (0, temperaHatch_1.rectPolygon)(width * 0.2, height * 0.1, width * 0.6, height * 0.52);
    const holes = [gate];
    for (let index = 0; index < 4; index += 1) {
        const y = height * (0.14 + index * 0.13);
        holes.push((0, temperaHatch_1.rectPolygon)(width * 0.08, y, width * 0.05, height * 0.06));
        holes.push((0, temperaHatch_1.rectPolygon)(width * 0.87, y, width * 0.05, height * 0.06));
    }
    (0, temperaCutout_1.addCutField)(ctx, palette.tone4, holes);
    (0, temperaCutout_1.addHoleLip)(ctx, gate, 3, 0.9, 0.08);
    ctx.add((0, temperaShapes_1.drawHatchFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(width * 0.2, height * 0.68, width * 0.6, height * 0.1), (0, temperaHatch_1.buildHatchSpec)(ctx.seed, 131, 1.2), palette.tone2, 0.5), { delay: 0.18, span: 0.6, grow: true });
};
const crossVent = ctx => {
    const { width, height, palette } = ctx;
    const cx = width * 0.5;
    const cy = height * 0.38;
    const arm = Math.min(width, height) * 0.3;
    const bar = Math.min(width, height) * 0.1;
    const cross = [
        cx - bar, cy - arm, cx + bar, cy - arm, cx + bar, cy - bar,
        cx + arm, cy - bar, cx + arm, cy + bar, cx + bar, cy + bar,
        cx + bar, cy + arm, cx - bar, cy + arm, cx - bar, cy + bar,
        cx - arm, cy + bar, cx - arm, cy - bar, cx - bar, cy - bar,
    ];
    (0, temperaCutout_1.addCutField)(ctx, palette.tone3, [cross]);
    (0, temperaCutout_1.addHoleLip)(ctx, cross, 2.6, 0.85, 0.1);
    if (!ctx.showDecor)
        return;
    ctx.add((0, temperaShapes_1.drawRings)(ctx.pixi, [{ x: cx, y: cy, radius: arm * 1.24 }], palette.tone4, 1.2, 0.5), { delay: 0.2, span: 0.5 });
};
const louvre = ctx => {
    const { width, height, palette, bleed } = ctx;
    const holes = [];
    for (let index = 0; index < 6; index += 1) {
        const y = height * (0.08 + index * 0.1);
        const lean = height * 0.03;
        const thickness = height * (0.05 - index * 0.004);
        holes.push([
            -bleed, y, width + bleed, y - lean,
            width + bleed, y - lean + thickness, -bleed, y + thickness,
        ]);
    }
    (0, temperaCutout_1.addCutField)(ctx, palette.tone4, holes);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(width * 0.1, height * 0.72, width * 0.08, height * 0.2), palette.tone2, 0.9, ctx.gradient), { delay: 0.2, span: 0.55, enterDY: height * 0.1 });
};
const ringEye = ctx => {
    const { width, height, palette } = ctx;
    const unit = Math.min(width, height);
    const cx = width * 0.5;
    const cy = height * 0.5;
    const inner = unit * 0.31;
    const outer = unit * 0.44;
    const segments = 12;
    const gap = 0.03;
    const holes = Array.from({ length: segments }, (_, index) => {
        const start = (index / segments) * Math.PI * 2 + gap;
        const end = ((index + 1) / segments) * Math.PI * 2 - gap;
        return (0, temperaCurves_1.annularSectorPolygon)(cx, cy, inner, outer, start, end, 8);
    });
    (0, temperaCutout_1.addCutField)(ctx, palette.tone3, holes);
    ctx.add((0, temperaShapes_1.drawRings)(ctx.pixi, [
        { x: cx, y: cy, radius: inner },
        { x: cx, y: cy, radius: outer },
    ], palette.ink, 2.4, 0.85), { delay: 0.12, span: 0.5 });
};
const notchStack = ctx => {
    const { width, height, palette } = ctx;
    const unit = Math.min(width, height);
    const holes = [];
    for (let index = 0; index < 4; index += 1) {
        const size = unit * (0.26 - index * 0.05);
        holes.push((0, temperaHatch_1.rectPolygon)(width * (0.6 + index * 0.06), height * (0.1 + index * 0.19), size, size));
    }
    (0, temperaCutout_1.addCutField)(ctx, palette.tone4, holes);
    holes.forEach((hole, index) => (0, temperaCutout_1.addHoleLip)(ctx, hole, 2, 0.75, 0.1 + index * 0.04));
};
const wedgeGap = ctx => {
    const { width, height, palette, bleed } = ctx;
    const apexX = width * (0.4 + (0, temperaRandom_1.temperaHash01)(ctx.seed, 3, 137) * 0.2);
    const wedge = [width * 0.1, -bleed, width * 0.92, -bleed, apexX, height * 0.56];
    (0, temperaCutout_1.addCutField)(ctx, palette.tone3, [wedge]);
    (0, temperaCutout_1.addHoleLip)(ctx, wedge, 3, 0.9, 0.08);
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, [{ x1: apexX, y1: height * 0.58, x2: apexX, y2: height + bleed }], palette.tone4, 1.6, 0.6), { delay: 0.18, span: 0.5, enterDY: height * 0.12 });
};
const dotSieve = ctx => {
    const { width, height, palette } = ctx;
    const unit = Math.min(width, height);
    const holes = [];
    for (let row = 0; row < 6; row += 1) {
        for (let column = 0; column < 5; column += 1) {
            const density = 1 - column / 4.5;
            if ((0, temperaRandom_1.temperaHash01)(ctx.seed, row * 9 + column, 139) > density)
                continue;
            const x = width * (0.06 + column * 0.105) + (row % 2 === 0 ? 0 : width * 0.05);
            holes.push((0, temperaHatch_1.circlePolygon)(x, height * (0.1 + row * 0.16), unit * 0.045 * density + unit * 0.012, 18));
        }
    }
    (0, temperaCutout_1.addCutField)(ctx, palette.tone2, holes, { alpha: 0.92 });
};
exports.TEMPERA_APERTURE_COMPOSITIONS = {
    'iris-hole': irisHole,
    'slot-rail': slotRail,
    'punch-row': punchRow,
    'film-gate': filmGate,
    'cross-vent': crossVent,
    'louvre-slats': louvre,
    'ring-eye': ringEye,
    'notch-stack': notchStack,
    'wedge-gap': wedgeGap,
    'dot-sieve': dotSieve,
};

},
"tempera/compositions/temperaCutout":function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.flowSpan = exports.flowPoint = exports.acrossPoint = exports.acrossFlow = exports.channelAxis = exports.axisRect = exports.addHoleLip = exports.addCutField = exports.fieldPolygon = void 0;
const temperaHatch_1 = require("tempera/temperaHatch");
const temperaCurves_1 = require("tempera/temperaCurves");
const temperaShapes_1 = require("tempera/temperaShapes");
const fieldPolygon = (ctx) => (0, temperaHatch_1.rectPolygon)(-ctx.bleed, -ctx.bleed, ctx.width + ctx.bleed * 2, ctx.height + ctx.bleed * 2);
exports.fieldPolygon = fieldPolygon;
const addCutField = (ctx, color, holes, options = {}) => {
    var _a, _b, _c;
    ctx.add((0, temperaShapes_1.drawPolygonFillWithHoles)(ctx.pixi, (0, exports.fieldPolygon)(ctx), holes, color, (_a = options.alpha) !== null && _a !== void 0 ? _a : 0.94, ctx.gradient), { delay: (_b = options.delay) !== null && _b !== void 0 ? _b : 0, span: (_c = options.span) !== null && _c !== void 0 ? _c : 0.5 });
};
exports.addCutField = addCutField;
const addHoleLip = (ctx, hole, width = 2.4, alpha = 0.85, delay = 0.1) => {
    ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, hole, ctx.palette.ink, width, alpha), { delay, span: 0.5 });
};
exports.addHoleLip = addHoleLip;
const axisRect = (cx, cy, length, width, angle) => (0, temperaCurves_1.rotatePolygon)((0, temperaHatch_1.rectPolygon)(cx - length / 2, cy - width / 2, length, width), cx, cy, angle);
exports.axisRect = axisRect;
const channelAxis = (ctx) => {
    const axis = (Math.sin(ctx.flowAngle) >= 0 ? 1 : -1) * Math.PI / 2;
    return axis + (ctx.flowAngle - axis) * 0.5;
};
exports.channelAxis = channelAxis;
const acrossFlow = (angle) => {
    const across = angle + Math.PI / 2;
    const sign = Math.cos(across) >= 0 ? 1 : -1;
    return { x: Math.cos(across) * sign, y: Math.sin(across) * sign };
};
exports.acrossFlow = acrossFlow;
const acrossPoint = (ctx, offset) => {
    const across = (0, exports.acrossFlow)((0, exports.channelAxis)(ctx));
    return { x: ctx.width / 2 + across.x * offset, y: ctx.height / 2 + across.y * offset };
};
exports.acrossPoint = acrossPoint;
const flowPoint = (ctx, distance, offset) => {
    const base = (0, exports.acrossPoint)(ctx, offset);
    const angle = (0, exports.channelAxis)(ctx);
    return {
        x: base.x + Math.cos(angle) * distance,
        y: base.y + Math.sin(angle) * distance,
    };
};
exports.flowPoint = flowPoint;
const flowSpan = (ctx) => Math.hypot(ctx.width, ctx.height) * 1.6;
exports.flowSpan = flowSpan;

},
"tempera/compositions/temperaSignalCompositions":function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.TEMPERA_SIGNAL_COMPOSITIONS = void 0;
const temperaRandom_1 = require("tempera/temperaRandom");
const temperaHatch_1 = require("tempera/temperaHatch");
const temperaCurves_1 = require("tempera/temperaCurves");
const temperaShapes_1 = require("tempera/temperaShapes");
const temperaCutout_1 = require("tempera/compositions/temperaCutout");
const addField = (ctx, color, alpha = 0.92) => {
    const { width, height, bleed } = ctx;
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), color, alpha, ctx.gradient), { span: 0.5 });
};
const sightMark = ctx => {
    const { width, height, palette, bleed } = ctx;
    const cx = width * 0.5;
    const cy = height * 0.5;
    addField(ctx, palette.tone1);
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, [
        { x1: -bleed, y1: cy, x2: width + bleed, y2: cy },
        { x1: cx, y1: -bleed, x2: cx, y2: height + bleed },
    ], palette.tone4, 1.4, 0.6), { delay: 0.04, span: 0.55, enterDX: width * 0.1 });
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(width * 0.24, height * 0.36, width * 0.52, height * 0.28), palette.tone3, 0.94, ctx.gradient), { delay: 0.1, span: 0.55, enterDY: height * 0.06 });
    ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(width * 0.2, height * 0.32, width * 0.6, height * 0.36), palette.ink, 2.4, 0.85), { delay: 0.16, span: 0.5 });
    if (!ctx.showDecor)
        return;
    [[0.2, 0.32, 1, 1], [0.8, 0.32, -1, 1], [0.2, 0.68, 1, -1], [0.8, 0.68, -1, -1]].forEach(([fx, fy, sx, sy], index) => {
        const x = width * fx;
        const y = height * fy;
        ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, [
            { x1: x, y1: y, x2: x + sx * width * 0.04, y2: y },
            { x1: x, y1: y, x2: x, y2: y + sy * height * 0.05 },
        ], palette.ink, 3, 0.8), { delay: 0.2 + index * 0.03, span: 0.5 });
    });
};
const dialScale = ctx => {
    const { width, height, palette } = ctx;
    const unit = Math.min(width, height);
    const cx = width * 0.5;
    const cy = height * 0.5;
    addField(ctx, palette.tone2);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaCurves_1.annularSectorPolygon)(cx, cy, unit * 0.34, unit * 0.44, 0, Math.PI * 2 - 0.006, 60), palette.tone4, 0.92, ctx.gradient), { delay: 0.05, span: 0.6 });
    const ticks = Array.from({ length: 24 }, (_, index) => {
        const angle = (index / 24) * Math.PI * 2;
        const inner = unit * (index % 6 === 0 ? 0.46 : 0.475);
        return {
            x1: cx + Math.cos(angle) * inner,
            y1: cy + Math.sin(angle) * inner,
            x2: cx + Math.cos(angle) * unit * 0.5,
            y2: cy + Math.sin(angle) * unit * 0.5,
        };
    });
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, ticks, palette.ink, 1.6, 0.7), { delay: 0.14, span: 0.55 });
    const pointer = 0.4 + (0, temperaRandom_1.temperaHash01)(ctx.seed, 5, 149) * 0.5;
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaCutout_1.axisRect)(cx + Math.cos(pointer * Math.PI * 2) * unit * 0.2, cy + Math.sin(pointer * Math.PI * 2) * unit * 0.2, unit * 0.4, unit * 0.035, pointer * Math.PI * 2), palette.ink, 0.9), { delay: 0.2, span: 0.5 });
};
const chevronRun = ctx => {
    const { width, height, palette, bleed } = ctx;
    const focus = 2;
    addField(ctx, palette.tone1);
    for (let index = 0; index < 5; index += 1) {
        const y = height * (0.02 + index * 0.24);
        const rise = height * 0.12;
        const thickness = height * 0.07;
        const chevron = [
            -bleed, y, width * 0.5, y - rise, width + bleed, y,
            width + bleed, y + thickness, width * 0.5, y - rise + thickness, -bleed, y + thickness,
        ];
        ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, chevron, index === focus ? palette.tone4 : palette.tone3, index === focus ? 0.95 : 0.7, ctx.gradient), { delay: index * 0.04, span: 0.55, enterDY: -height * 0.12 });
    }
};
const tallyColumn = ctx => {
    const { width, height, palette } = ctx;
    const x = width * 0.82;
    addField(ctx, palette.tone1);
    const marks = Array.from({ length: 11 }, (_, index) => {
        const long = index % 4 === 0;
        return {
            x1: x,
            y1: height * (0.1 + index * 0.075),
            x2: x + width * (long ? 0.12 : 0.06),
            y2: height * (0.1 + index * 0.075),
        };
    });
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, marks, palette.tone4, 2.4, 0.75), { delay: 0.06, span: 0.6, enterDX: width * 0.1 });
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(x - width * 0.02, height * 0.4, width * 0.16, height * 0.12), palette.tone4, 0.95, ctx.gradient), { delay: 0.16, span: 0.55, enterDX: width * 0.14 });
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, [{ x1: x, y1: height * 0.06, x2: x, y2: height * 0.92 }], palette.ink, 1.6, 0.6), { delay: 0.2, span: 0.5 });
};
const gridFocus = ctx => {
    const { width, height, palette } = ctx;
    const left = width * 0.08;
    const top = height * 0.12;
    const cellWidth = (width * 0.84) / 4;
    const cellHeight = (height * 0.76) / 3;
    const cell = (column, row) => (0, temperaHatch_1.rectPolygon)(left + cellWidth * column, top + cellHeight * row, cellWidth, cellHeight);
    (0, temperaCutout_1.addCutField)(ctx, palette.tone2, [cell(0, 0), cell(3, 2)]);
    (0, temperaCutout_1.addHoleLip)(ctx, cell(0, 0), 2, 0.7, 0.1);
    (0, temperaCutout_1.addHoleLip)(ctx, cell(3, 2), 2, 0.7, 0.14);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, cell(3, 0), palette.tone4, 0.95, ctx.gradient), { delay: 0.08, span: 0.55, enterDX: width * 0.08 });
    const lines = [];
    for (let column = 0; column <= 4; column += 1) {
        lines.push({ x1: left + cellWidth * column, y1: top, x2: left + cellWidth * column, y2: top + cellHeight * 3 });
    }
    for (let row = 0; row <= 3; row += 1) {
        lines.push({ x1: left, y1: top + cellHeight * row, x2: left + cellWidth * 4, y2: top + cellHeight * row });
    }
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, lines, palette.tone4, 1.2, 0.6), { delay: 0.16, span: 0.55 });
};
const axisCaps = ctx => {
    const { width, height, palette } = ctx;
    const unit = Math.min(width, height);
    const cx = width * 0.5;
    const cy = height * 0.42;
    const bar = (0, temperaCutout_1.axisRect)(cx, cy, (0, temperaCutout_1.flowSpan)(ctx), unit * 0.22, ctx.flowAngle);
    const port = (0, temperaHatch_1.circlePolygon)(cx, cy, unit * 0.08, 32);
    (0, temperaCutout_1.addCutField)(ctx, palette.tone1, [port], { alpha: 0.92 });
    ctx.add((0, temperaShapes_1.drawPolygonFillWithHoles)(ctx.pixi, bar, [port], palette.tone4, 0.94, ctx.gradient), { delay: 0.05, span: 0.6 });
    ctx.add((0, temperaShapes_1.drawRings)(ctx.pixi, [{ x: cx, y: cy, radius: unit * 0.08 }], palette.ink, 2.4, 0.85), { delay: 0.12, span: 0.5 });
    [1, -1].forEach((side, index) => {
        const distance = unit * 0.46;
        const capX = cx + Math.cos(ctx.flowAngle) * distance * side;
        const capY = cy + Math.sin(ctx.flowAngle) * distance * side;
        ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaCutout_1.axisRect)(capX, capY, unit * 0.1, unit * 0.34, ctx.flowAngle), palette.ink, 0.85), { delay: 0.16 + index * 0.04, span: 0.5 });
    });
};
const strobeSlats = ctx => {
    const { width, height, palette, bleed } = ctx;
    addField(ctx, palette.tone1);
    const widths = [0.06, 0.03, 0.09, 0.04, 0.34, 0.04, 0.08, 0.03, 0.06];
    let cursor = width * 0.03;
    widths.forEach((fraction, index) => {
        const slat = (0, temperaHatch_1.rectPolygon)(cursor, -bleed, width * fraction, height + bleed * 2);
        const wide = fraction > 0.2;
        ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, slat, wide ? palette.tone2 : palette.tone4, wide ? 0.9 : 0.85, ctx.gradient), { delay: index * 0.03, span: 0.55, enterDY: (index % 2 === 0 ? 1 : -1) * height * 0.14 });
        cursor += width * (fraction + 0.02);
    });
};
const offsetPlate = ctx => {
    const { width, height, palette } = ctx;
    const unit = Math.min(width, height);
    const step = unit * 0.06;
    const holeX = width * 0.72;
    const holeY = height * 0.36;
    const hole = (0, temperaHatch_1.circlePolygon)(holeX, holeY, unit * 0.05, 28);
    (0, temperaCutout_1.addCutField)(ctx, palette.tone1, [hole], { alpha: 0.9 });
    [palette.tone2, palette.tone3, palette.tone4].forEach((tone, index) => {
        const plate = (0, temperaHatch_1.rectPolygon)(width * 0.2 + step * index, height * 0.2 + step * index, width * 0.5, height * 0.5);
        ctx.add((0, temperaShapes_1.drawPolygonFillWithHoles)(ctx.pixi, plate, [hole], tone, index === 2 ? 0.95 : 0.8, ctx.gradient), { delay: index * 0.06, span: 0.55, enterDX: -step * 2, enterDY: -step });
    });
    ctx.add((0, temperaShapes_1.drawRings)(ctx.pixi, [{ x: holeX, y: holeY, radius: unit * 0.05 }], palette.ink, 2, 0.8), { delay: 0.22, span: 0.5 });
};
const radialComb = ctx => {
    const { width, height, palette } = ctx;
    const hubX = width * 1.06;
    const hubY = height * 1.1;
    const reach = Math.hypot(width, height) * 1.3;
    addField(ctx, palette.tone2);
    const rays = Array.from({ length: 11 }, (_, index) => {
        const angle = Math.PI + 0.16 + index * 0.062;
        return {
            x1: hubX,
            y1: hubY,
            x2: hubX + Math.cos(angle) * reach,
            y2: hubY + Math.sin(angle) * reach,
        };
    });
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, rays, palette.tone4, 2.6, 0.8), { delay: 0.06, span: 0.6 });
    const start = Math.PI + 0.44;
    const end = Math.PI + 0.56;
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, [
        hubX, hubY,
        hubX + Math.cos(start) * reach, hubY + Math.sin(start) * reach,
        hubX + Math.cos(end) * reach, hubY + Math.sin(end) * reach,
    ], palette.tone4, 0.95, ctx.gradient), { delay: 0.14, span: 0.6 });
    if (!ctx.showDecor)
        return;
    ctx.add((0, temperaShapes_1.drawHatchFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(width * 0.06, height * 0.08, width * 0.2, height * 0.14), (0, temperaHatch_1.buildHatchSpec)(ctx.seed, 151), palette.tone4, 0.4), { delay: 0.24, span: 0.6, grow: true });
};
const bracketTarget = ctx => {
    const { width, height, palette } = ctx;
    const box = (0, temperaHatch_1.rectPolygon)(width * 0.28, height * 0.54, width * 0.44, height * 0.34);
    (0, temperaCutout_1.addCutField)(ctx, palette.tone3, [box]);
    (0, temperaCutout_1.addHoleLip)(ctx, box, 2.4, 0.85, 0.08);
    const arm = Math.min(width, height) * 0.08;
    [[0.28, 0.54, 1, 1], [0.72, 0.54, -1, 1], [0.28, 0.88, 1, -1], [0.72, 0.88, -1, -1]].forEach(([fx, fy, sx, sy], index) => {
        const x = width * fx + sx * width * 0.03;
        const y = height * fy + sy * height * 0.04;
        ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, [
            { x1: x, y1: y, x2: x + sx * arm, y2: y },
            { x1: x, y1: y, x2: x, y2: y + sy * arm },
        ], palette.ink, 3.5, 0.9), { delay: 0.12 + index * 0.04, span: 0.5, enterDX: sx * width * 0.05 });
    });
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, [{ x1: width * 0.1, y1: height * 0.44, x2: width * 0.9, y2: height * 0.44 }], palette.tone4, 1.6, 0.6), { delay: 0.24, span: 0.5, enterDX: -width * 0.1 });
};
exports.TEMPERA_SIGNAL_COMPOSITIONS = {
    'sight-mark': sightMark,
    'dial-scale': dialScale,
    'chevron-run': chevronRun,
    'tally-column': tallyColumn,
    'grid-focus': gridFocus,
    'axis-caps': axisCaps,
    'strobe-slats': strobeSlats,
    'offset-plate': offsetPlate,
    'radial-comb': radialComb,
    'bracket-target': bracketTarget,
};

},
"tempera/compositions/temperaCorridorCompositions":function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.TEMPERA_CORRIDOR_COMPOSITIONS = void 0;
const temperaHatch_1 = require("tempera/temperaHatch");
const temperaCurves_1 = require("tempera/temperaCurves");
const temperaShapes_1 = require("tempera/temperaShapes");
const temperaCutout_1 = require("tempera/compositions/temperaCutout");
const channel = (ctx, offset, width) => {
    const centre = (0, temperaCutout_1.acrossPoint)(ctx, offset);
    return (0, temperaCutout_1.axisRect)(centre.x, centre.y, (0, temperaCutout_1.flowSpan)(ctx), width, (0, temperaCutout_1.channelAxis)(ctx));
};
const addRails = (ctx, offset, width, alpha = 0.55) => {
    const angle = (0, temperaCutout_1.channelAxis)(ctx);
    const half = (0, temperaCutout_1.flowSpan)(ctx) / 2;
    [-1, 1].forEach((side, index) => {
        const start = (0, temperaCutout_1.flowPoint)(ctx, -half, offset + side * width);
        const end = (0, temperaCutout_1.flowPoint)(ctx, half, offset + side * width);
        ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, [{ x1: start.x, y1: start.y, x2: end.x, y2: end.y }], ctx.palette.tone4, 1.4, alpha), {
            delay: 0.18 + index * 0.03,
            span: 0.5,
            enterDX: Math.cos(angle) * ctx.width * 0.08,
            enterDY: Math.sin(angle) * ctx.height * 0.08,
        });
    });
};
const flowChannel = ctx => {
    const { width, palette } = ctx;
    const unit = Math.min(width, ctx.height);
    const slot = channel(ctx, width * 0.26, unit * 0.3);
    (0, temperaCutout_1.addCutField)(ctx, palette.tone3, [slot]);
    (0, temperaCutout_1.addHoleLip)(ctx, slot, 2.6, 0.85, 0.08);
    addRails(ctx, width * 0.26, unit * 0.19);
};
const twinChannel = ctx => {
    const { width, palette } = ctx;
    const unit = Math.min(width, ctx.height);
    const slots = [channel(ctx, -width * 0.34, unit * 0.16), channel(ctx, width * 0.34, unit * 0.16)];
    (0, temperaCutout_1.addCutField)(ctx, palette.tone4, slots);
    slots.forEach((slot, index) => (0, temperaCutout_1.addHoleLip)(ctx, slot, 2.4, 0.8, 0.1 + index * 0.04));
};
const reedRun = ctx => {
    const { width, palette } = ctx;
    const unit = Math.min(width, ctx.height);
    const slots = [];
    [-1, 1].forEach(side => {
        for (let index = 0; index < 4; index += 1) {
            slots.push(channel(ctx, side * width * (0.22 + index * 0.08), unit * 0.035));
        }
    });
    (0, temperaCutout_1.addCutField)(ctx, palette.tone2, slots, { alpha: 0.9 });
    addRails(ctx, 0, width * 0.17, 0.4);
};
const taperChannel = ctx => {
    const { width, palette } = ctx;
    const unit = Math.min(width, ctx.height);
    const half = (0, temperaCutout_1.flowSpan)(ctx) / 2;
    const wide = unit * 0.24;
    const narrow = unit * 0.06;
    const offset = width * 0.24;
    const corners = [
        (0, temperaCutout_1.flowPoint)(ctx, -half, offset - wide),
        (0, temperaCutout_1.flowPoint)(ctx, -half, offset + wide),
        (0, temperaCutout_1.flowPoint)(ctx, half, offset + narrow),
        (0, temperaCutout_1.flowPoint)(ctx, half, offset - narrow),
    ];
    const slot = corners.flatMap(point => [point.x, point.y]);
    (0, temperaCutout_1.addCutField)(ctx, palette.tone3, [slot]);
    (0, temperaCutout_1.addHoleLip)(ctx, slot, 2.6, 0.85, 0.08);
};
const chainPorts = ctx => {
    const { width, height, palette } = ctx;
    const unit = Math.min(width, height);
    const offset = width * 0.28;
    const spacing = height * 0.26;
    const ports = [-1.5, -0.5, 0.5, 1.5].map(step => (0, temperaCutout_1.flowPoint)(ctx, step * spacing, offset));
    (0, temperaCutout_1.addCutField)(ctx, palette.tone4, ports.map(port => (0, temperaHatch_1.circlePolygon)(port.x, port.y, unit * 0.11, 40)));
    ctx.add((0, temperaShapes_1.drawRings)(ctx.pixi, ports.map(port => ({ x: port.x, y: port.y, radius: unit * 0.11 })), palette.ink, 2.4, 0.85), { delay: 0.1, span: 0.55 });
    const head = (0, temperaCutout_1.flowPoint)(ctx, -spacing * 2.4, offset);
    const tail = (0, temperaCutout_1.flowPoint)(ctx, spacing * 2.4, offset);
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, [{ x1: head.x, y1: head.y, x2: tail.x, y2: tail.y }], palette.tone2, 1.6, 0.6), { delay: 0.18, span: 0.5 });
};
const dashChannel = ctx => {
    const { width, height, palette } = ctx;
    const unit = Math.min(width, height);
    const offset = width * 0.24;
    const step = height * 0.32;
    const angle = (0, temperaCutout_1.channelAxis)(ctx);
    const slots = [-1.5, -0.5, 0.5, 1.5].map(index => {
        const centre = (0, temperaCutout_1.flowPoint)(ctx, index * step, offset);
        return (0, temperaCutout_1.axisRect)(centre.x, centre.y, step * 0.72, unit * 0.22, angle);
    });
    (0, temperaCutout_1.addCutField)(ctx, palette.tone3, slots);
    slots.forEach((slot, index) => (0, temperaCutout_1.addHoleLip)(ctx, slot, 2.2, 0.8, 0.08 + index * 0.03));
};
const windowRun = ctx => {
    const { width, height, palette } = ctx;
    const unit = Math.min(width, height);
    const offset = width * 0.27;
    const step = height * 0.36;
    const angle = (0, temperaCutout_1.channelAxis)(ctx);
    const slots = [-1.5, -0.5, 0.5, 1.5].map(index => {
        const centre = (0, temperaCutout_1.flowPoint)(ctx, index * step, offset);
        const size = unit * 0.2;
        return (0, temperaCurves_1.rotatePolygon)((0, temperaCurves_1.roundedRectPolygon)(centre.x - size, centre.y - size * 0.62, size * 2, size * 1.24, size * 0.3), centre.x, centre.y, angle + Math.PI / 2);
    });
    (0, temperaCutout_1.addCutField)(ctx, palette.tone4, slots);
    slots.forEach((slot, index) => (0, temperaCutout_1.addHoleLip)(ctx, slot, 2.4, 0.85, 0.08 + index * 0.03));
};
const bridgeSpan = ctx => {
    const { width, height, palette } = ctx;
    const unit = Math.min(width, height);
    const slot = channel(ctx, 0, unit * 0.62);
    (0, temperaCutout_1.addCutField)(ctx, palette.tone4, [slot]);
    (0, temperaCutout_1.addHoleLip)(ctx, slot, 2.6, 0.8, 0.08);
    const band = (0, temperaCutout_1.axisRect)(width / 2, height / 2, (0, temperaCutout_1.flowSpan)(ctx), height * 0.46, (0, temperaCutout_1.channelAxis)(ctx) + Math.PI / 2);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, band, palette.tone3, 0.95, ctx.gradient), { delay: 0.12, span: 0.6, enterDX: -width * 0.16 });
    ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, band, palette.ink, 2, 0.7), { delay: 0.2, span: 0.5, enterDX: width * 0.1 });
};
const braidChannel = ctx => {
    const { width, height, palette } = ctx;
    const unit = Math.min(width, height);
    const angle = (0, temperaCutout_1.channelAxis)(ctx);
    const pitch = height * 0.42;
    const slots = [];
    [-1, 1].forEach(side => {
        for (let index = -1; index <= 1; index += 1) {
            const centre = (0, temperaCutout_1.flowPoint)(ctx, index * pitch + side * pitch * 0.5, side * width * 0.32);
            slots.push((0, temperaCutout_1.axisRect)(centre.x, centre.y, pitch * 0.78, unit * 0.16, angle));
        }
    });
    (0, temperaCutout_1.addCutField)(ctx, palette.tone3, slots);
    slots.forEach((slot, index) => (0, temperaCutout_1.addHoleLip)(ctx, slot, 2.2, 0.8, 0.08 + index * 0.025));
};
const portLadder = ctx => {
    const { width, height, palette } = ctx;
    const unit = Math.min(width, height);
    const offset = width * 0.3;
    const slot = channel(ctx, offset, unit * 0.14);
    (0, temperaCutout_1.addCutField)(ctx, palette.tone2, [slot]);
    (0, temperaCutout_1.addHoleLip)(ctx, slot, 2.2, 0.8, 0.08);
    const rungs = Array.from({ length: 9 }, (_, index) => {
        const distance = (index - 4) * height * 0.13;
        const long = index % 3 === 0;
        const inner = (0, temperaCutout_1.flowPoint)(ctx, distance, offset - unit * 0.09);
        const outer = (0, temperaCutout_1.flowPoint)(ctx, distance, offset - unit * (long ? 0.22 : 0.15));
        return { x1: inner.x, y1: inner.y, x2: outer.x, y2: outer.y };
    });
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, rungs, palette.tone4, 2, 0.7), { delay: 0.14, span: 0.6 });
};
exports.TEMPERA_CORRIDOR_COMPOSITIONS = {
    'flow-channel': flowChannel,
    'twin-channel': twinChannel,
    'reed-run': reedRun,
    'taper-channel': taperChannel,
    'chain-ports': chainPorts,
    'dash-channel': dashChannel,
    'window-run': windowRun,
    'bridge-span': bridgeSpan,
    'braid-channel': braidChannel,
    'port-ladder': portLadder,
};

},
"tempera/compositions/temperaMonolithCompositions":function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.TEMPERA_MONOLITH_COMPOSITIONS = void 0;
const temperaRandom_1 = require("tempera/temperaRandom");
const temperaHatch_1 = require("tempera/temperaHatch");
const temperaShapes_1 = require("tempera/temperaShapes");
const temperaCutout_1 = require("tempera/compositions/temperaCutout");
const temperaMonolithKit_1 = require("tempera/compositions/temperaMonolithKit");
const apexMass = ctx => {
    const { width, height, palette, bleed } = ctx;
    const apexX = width * (0.46 + (0, temperaRandom_1.temperaHash01)(ctx.seed, 3, 227) * 0.12);
    const apexY = height * 0.38;
    (0, temperaMonolithKit_1.addGround)(ctx, palette.tone1);
    const mass = [-bleed, height + bleed, apexX, apexY, width + bleed, height + bleed];
    (0, temperaMonolithKit_1.addMass)(ctx, mass, palette.tone3, { enterDY: height * 0.1 });
    (0, temperaMonolithKit_1.addFaceRuling)(ctx, [apexX, apexY, width + bleed, height + bleed, apexX + width * 0.24, height + bleed], 229);
    (0, temperaMonolithKit_1.addSurveyLines)(ctx, 3);
    if (!ctx.showDecor)
        return;
    (0, temperaMonolithKit_1.addCornerTicks)(ctx);
    (0, temperaMonolithKit_1.addWireTrace)(ctx, width * 0.12, height * 0.84, Math.min(width, height) * 0.09);
};
const ziggurat = ctx => {
    const { width, height, palette, bleed } = ctx;
    (0, temperaMonolithKit_1.addGround)(ctx, palette.tone1);
    const tones = [palette.tone4, palette.tone3, palette.tone3, palette.tone2];
    for (let course = 0; course < 4; course += 1) {
        const half = width * (0.44 - course * 0.09);
        const top = height * (0.9 - course * 0.13) - height * 0.13;
        (0, temperaMonolithKit_1.addMass)(ctx, (0, temperaHatch_1.rectPolygon)(width / 2 - half, top, half * 2, height * 0.13 + bleed), tones[course], {
            delay: 0.04 + course * 0.05,
            enterDY: height * 0.08,
            edgeWidth: 2,
        });
    }
    (0, temperaMonolithKit_1.addSurveyLines)(ctx, 2);
    if (!ctx.showDecor)
        return;
    (0, temperaMonolithKit_1.addCornerTicks)(ctx);
};
const slabWall = ctx => {
    const { width, height, palette, bleed } = ctx;
    const edge = width * 0.36;
    (0, temperaMonolithKit_1.addGround)(ctx, palette.tone1);
    (0, temperaMonolithKit_1.addMass)(ctx, (0, temperaHatch_1.rectPolygon)(edge, -bleed, width - edge + bleed, height + bleed * 2), palette.tone3, { edge: false });
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, [{ x1: edge, y1: -bleed, x2: edge, y2: height + bleed }], palette.ink, 3.5, 0.9), { delay: 0.1, span: 0.55, enterDX: width * 0.06 });
    (0, temperaMonolithKit_1.addFaceRuling)(ctx, (0, temperaHatch_1.rectPolygon)(width * 0.62, height * 0.1, width * 0.3, height * 0.8), 233);
    (0, temperaMonolithKit_1.addSurveyLines)(ctx, 3);
    if (!ctx.showDecor)
        return;
    (0, temperaMonolithKit_1.addWireTrace)(ctx, width * 0.16, height * 0.24, Math.min(width, height) * 0.08);
};
const cantilever = ctx => {
    const { width, height, palette, bleed } = ctx;
    (0, temperaMonolithKit_1.addGround)(ctx, palette.tone1);
    (0, temperaMonolithKit_1.addMass)(ctx, (0, temperaHatch_1.rectPolygon)(0.16 * width, height * 0.5, width * 0.1, height * 0.5 + bleed), palette.tone4, {
        delay: 0.02,
        enterDY: height * 0.1,
        edge: false,
    });
    (0, temperaMonolithKit_1.addMass)(ctx, (0, temperaHatch_1.rectPolygon)(-bleed, height * 0.34, width * 0.78 + bleed, height * 0.16), palette.tone3, {
        delay: 0.08,
        enterDX: -width * 0.14,
    });
    (0, temperaMonolithKit_1.addFaceRuling)(ctx, (0, temperaHatch_1.rectPolygon)(width * 0.3, height * 0.36, width * 0.44, height * 0.12), 239, palette.paper, 0.35);
    (0, temperaMonolithKit_1.addSurveyLines)(ctx, 2);
    if (!ctx.showDecor)
        return;
    (0, temperaMonolithKit_1.addCornerTicks)(ctx);
};
const pylonPair = ctx => {
    const { width, height, palette, bleed } = ctx;
    const bay = (0, temperaHatch_1.rectPolygon)(width * 0.26, height * 0.3, width * 0.48, height * 0.7 + bleed);
    (0, temperaCutout_1.addCutField)(ctx, palette.tone1, [bay], { alpha: 0.94 });
    (0, temperaCutout_1.addHoleLip)(ctx, bay, 2, 0.6, 0.12);
    [0.1, 0.74].forEach((x, index) => {
        (0, temperaMonolithKit_1.addMass)(ctx, (0, temperaHatch_1.rectPolygon)(width * x, height * 0.28, width * 0.16, height * 0.72 + bleed), palette.tone4, {
            delay: 0.04 + index * 0.05,
            enterDY: height * 0.08,
            edgeWidth: 2,
        });
    });
    (0, temperaMonolithKit_1.addMass)(ctx, (0, temperaHatch_1.rectPolygon)(width * 0.04, height * 0.14, width * 0.92, height * 0.16), palette.tone3, {
        delay: 0.14,
        enterDY: -height * 0.1,
    });
    (0, temperaMonolithKit_1.addSurveyLines)(ctx, 2);
};
const bunkerSlit = ctx => {
    const { width, height, palette, bleed } = ctx;
    const slit = (0, temperaHatch_1.rectPolygon)(-bleed, height * 0.62, width + bleed * 2, height * 0.06);
    (0, temperaCutout_1.addCutField)(ctx, palette.tone1, [slit], { alpha: 0.94 });
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, height * 0.34, width + bleed * 2, height * 0.28), palette.tone4, 0.95, ctx.gradient), { delay: 0.05, span: 0.6, enterDY: -height * 0.08 });
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, height * 0.68, width + bleed * 2, height * 0.32 + bleed), palette.tone4, 0.95, ctx.gradient), { delay: 0.08, span: 0.6, enterDY: height * 0.1 });
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, [
        { x1: -bleed, y1: height * 0.34, x2: width + bleed, y2: height * 0.34 },
    ], palette.ink, 3, 0.85), { delay: 0.14, span: 0.5 });
    (0, temperaMonolithKit_1.addFaceRuling)(ctx, (0, temperaHatch_1.rectPolygon)(width * 0.08, height * 0.72, width * 0.36, height * 0.2), 241, palette.paper, 0.3);
    (0, temperaMonolithKit_1.addSurveyLines)(ctx, 2);
};
const plinthStack = ctx => {
    const { width, height, palette, bleed } = ctx;
    (0, temperaMonolithKit_1.addGround)(ctx, palette.tone1);
    (0, temperaMonolithKit_1.addMass)(ctx, (0, temperaHatch_1.rectPolygon)(width * 0.06, height * 0.72, width * 0.88, height * 0.28 + bleed), palette.tone4, { edgeWidth: 2 });
    (0, temperaMonolithKit_1.addMass)(ctx, (0, temperaHatch_1.rectPolygon)(width * 0.16, height * 0.52, width * 0.68, height * 0.2), palette.tone3, { delay: 0.08, edgeWidth: 2 });
    (0, temperaMonolithKit_1.addMass)(ctx, (0, temperaHatch_1.rectPolygon)(width * 0.28, height * 0.34, width * 0.44, height * 0.18), palette.tone2, { delay: 0.14, enterDY: height * 0.06 });
    (0, temperaMonolithKit_1.addFaceRuling)(ctx, (0, temperaHatch_1.rectPolygon)(width * 0.2, height * 0.76, width * 0.6, height * 0.16), 243);
    (0, temperaMonolithKit_1.addSurveyLines)(ctx, 3);
    if (!ctx.showDecor)
        return;
    (0, temperaMonolithKit_1.addCornerTicks)(ctx);
};
const buttressRun = ctx => {
    const { width, height, palette, bleed } = ctx;
    const band = (0, temperaHatch_1.rectPolygon)(-bleed, height * 0.42, width + bleed * 2, height * 0.58 + bleed);
    (0, temperaCutout_1.addCutField)(ctx, palette.tone1, [band], { alpha: 0.94 });
    for (let index = 0; index < 5; index += 1) {
        const left = width * (index * 0.2 + 0.01);
        (0, temperaMonolithKit_1.addMass)(ctx, [
            left, height + bleed,
            left + width * 0.09, height * 0.42,
            left + width * 0.17, height + bleed,
        ], index % 2 === 0 ? palette.tone4 : palette.tone3, {
            delay: 0.04 + index * 0.04,
            enterDY: height * 0.12,
            edgeWidth: 2,
        });
    }
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, [{ x1: -bleed, y1: height * 0.42, x2: width + bleed, y2: height * 0.42 }], palette.ink, 2.4, 0.8), { delay: 0.2, span: 0.5, enterDX: -width * 0.1 });
    (0, temperaMonolithKit_1.addSurveyLines)(ctx, 2);
};
const voidCore = ctx => {
    const { width, height, palette } = ctx;
    const core = (0, temperaHatch_1.rectPolygon)(width * 0.22, height * 0.34, width * 0.56, height * 0.46);
    (0, temperaCutout_1.addCutField)(ctx, palette.tone3, [core], { alpha: 0.95 });
    (0, temperaCutout_1.addHoleLip)(ctx, core, 3.5, 0.9, 0.08);
    (0, temperaMonolithKit_1.addFaceRuling)(ctx, (0, temperaHatch_1.rectPolygon)(width * 0.04, height * 0.36, width * 0.14, height * 0.42), 247, palette.tone4, 0.45);
    (0, temperaMonolithKit_1.addSurveyLines)(ctx, 3);
    if (!ctx.showDecor)
        return;
    (0, temperaMonolithKit_1.addCornerTicks)(ctx);
    (0, temperaMonolithKit_1.addWireTrace)(ctx, width * 0.86, height * 0.86, Math.min(width, height) * 0.08);
};
const shearBlock = ctx => {
    const { width, height, palette } = ctx;
    const left = width * 0.14;
    const right = width * 0.86;
    const top = height * 0.2;
    const bottom = height * 0.8;
    const cutTop = width * 0.56;
    const cutBottom = width * 0.44;
    (0, temperaMonolithKit_1.addGround)(ctx, palette.tone1);
    (0, temperaMonolithKit_1.addMass)(ctx, [left, top, cutTop, top, cutBottom, bottom, left, bottom], palette.tone3, {
        enterDX: -width * 0.08,
        enterDY: -height * 0.03,
        edgeWidth: 2,
    });
    (0, temperaMonolithKit_1.addMass)(ctx, [cutTop + width * 0.03, top + height * 0.04, right, top + height * 0.04, right, bottom + height * 0.04, cutBottom + width * 0.03, bottom + height * 0.04], palette.tone4, {
        delay: 0.1,
        enterDX: width * 0.08,
        enterDY: height * 0.03,
        edgeWidth: 2,
    });
    (0, temperaMonolithKit_1.addSurveyLines)(ctx, 2);
    if (!ctx.showDecor)
        return;
    ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(width * 0.1, height * 0.16, width * 0.8, height * 0.68), palette.paper, 1.2, 0.35), { delay: 0.28, span: 0.55 });
};
exports.TEMPERA_MONOLITH_COMPOSITIONS = {
    'apex-mass': apexMass,
    'ziggurat': ziggurat,
    'slab-wall': slabWall,
    'cantilever': cantilever,
    'pylon-pair': pylonPair,
    'bunker-slit': bunkerSlit,
    'plinth-stack': plinthStack,
    'buttress-run': buttressRun,
    'void-core': voidCore,
    'shear-block': shearBlock,
};

},
"tempera/compositions/temperaMonolithKit":function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.addWireTrace = exports.addCornerTicks = exports.addSurveyLines = exports.addFaceRuling = exports.addGround = exports.addMass = void 0;
const temperaHatch_1 = require("tempera/temperaHatch");
const temperaShapes_1 = require("tempera/temperaShapes");
const addMass = (ctx, polygon, color, options = {}) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j;
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, polygon, color, (_a = options.alpha) !== null && _a !== void 0 ? _a : 0.95, ctx.gradient), {
        delay: (_b = options.delay) !== null && _b !== void 0 ? _b : 0.04,
        span: (_c = options.span) !== null && _c !== void 0 ? _c : 0.6,
        enterDX: (_d = options.enterDX) !== null && _d !== void 0 ? _d : 0,
        enterDY: (_e = options.enterDY) !== null && _e !== void 0 ? _e : 0,
    });
    if (options.edge === false)
        return;
    ctx.add((0, temperaShapes_1.drawPolygonOutline)(ctx.pixi, polygon, ctx.palette.ink, (_f = options.edgeWidth) !== null && _f !== void 0 ? _f : 2.4, 0.8), {
        delay: ((_g = options.delay) !== null && _g !== void 0 ? _g : 0.04) + 0.06,
        span: 0.5,
        enterDX: ((_h = options.enterDX) !== null && _h !== void 0 ? _h : 0) * 0.6,
        enterDY: ((_j = options.enterDY) !== null && _j !== void 0 ? _j : 0) * 0.6,
    });
};
exports.addMass = addMass;
const addGround = (ctx, color, alpha = 0.94) => {
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-ctx.bleed, -ctx.bleed, ctx.width + ctx.bleed * 2, ctx.height + ctx.bleed * 2), color, alpha, ctx.gradient), { span: 0.5 });
};
exports.addGround = addGround;
const addFaceRuling = (ctx, face, salt, color = ctx.palette.tone4, alpha = 0.5) => {
    ctx.add((0, temperaShapes_1.drawHatchFill)(ctx.pixi, face, (0, temperaHatch_1.buildHatchSpec)(ctx.seed, salt, 0.7), color, alpha), {
        delay: 0.16,
        span: 0.65,
        grow: true,
    });
};
exports.addFaceRuling = addFaceRuling;
const addSurveyLines = (ctx, count = 3, salt = 211) => {
    const { width, height, bleed } = ctx;
    const lines = Array.from({ length: Math.max(1, count) }, (_, index) => {
        const anchor = height * (0.16 + ((index * 0.31 + (ctx.seed % 7) * 0.04) % 0.7));
        const lean = height * (index % 2 === 0 ? 0.22 : -0.16);
        return {
            x1: -bleed,
            y1: anchor - lean,
            x2: width + bleed,
            y2: anchor + lean,
        };
    });
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, lines, ctx.palette.paper, 1, 0.45), {
        delay: 0.2 + (salt % 3) * 0.02,
        span: 0.7,
        enterDX: width * 0.2,
    });
};
exports.addSurveyLines = addSurveyLines;
const addCornerTicks = (ctx) => {
    const { width, height, palette } = ctx;
    const inset = Math.min(width, height) * 0.06;
    const arm = Math.min(width, height) * 0.05;
    [[1, 1], [-1, -1]].forEach(([sx, sy], index) => {
        const x = sx > 0 ? inset : width - inset;
        const y = sy > 0 ? inset : height - inset;
        ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, [
            { x1: x, y1: y, x2: x + sx * arm, y2: y },
            { x1: x, y1: y, x2: x, y2: y + sy * arm },
        ], palette.paper, 1.6, 0.6), { delay: 0.26 + index * 0.04, span: 0.5 });
    });
};
exports.addCornerTicks = addCornerTicks;
const addWireTrace = (ctx, cx, cy, radius) => {
    const group = ctx.createGroup(0, cx, cy);
    ctx.add((0, temperaShapes_1.drawPolyline)(ctx.pixi, (0, temperaHatch_1.buildScribblePath)(ctx.decor.scribbleSeed, 199, 0, 0, radius, 1), ctx.palette.paper, 1.2, 0.4), {
        delay: 0.3,
        span: 0.6,
        drift: true,
    }, group);
};
exports.addWireTrace = addWireTrace;

},
"tempera/compositions/temperaTerrainCompositions":function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.TEMPERA_TERRAIN_COMPOSITIONS = void 0;
const temperaRandom_1 = require("tempera/temperaRandom");
const temperaHatch_1 = require("tempera/temperaHatch");
const temperaCurves_1 = require("tempera/temperaCurves");
const temperaShapes_1 = require("tempera/temperaShapes");
const temperaCutout_1 = require("tempera/compositions/temperaCutout");
const temperaMonolithKit_1 = require("tempera/compositions/temperaMonolithKit");
const ridgeLine = ctx => {
    const { width, height, palette, bleed } = ctx;
    const lift = (0, temperaRandom_1.temperaHash01)(ctx.seed, 5, 251) * 0.06;
    (0, temperaMonolithKit_1.addGround)(ctx, palette.tone1);
    (0, temperaMonolithKit_1.addMass)(ctx, [
        -bleed, height * (0.68 + lift),
        width * 0.34, height * (0.4 + lift),
        width * 0.62, height * (0.58 + lift),
        width + bleed, height * (0.34 + lift),
        width + bleed, height + bleed,
        -bleed, height + bleed,
    ], palette.tone3, { enterDY: height * 0.08 });
    (0, temperaMonolithKit_1.addFaceRuling)(ctx, [
        width * 0.34, height * (0.42 + lift),
        width * 0.62, height * (0.6 + lift),
        width * 0.62, height + bleed,
        width * 0.34, height + bleed,
    ], 253, palette.tone4, 0.45);
    (0, temperaMonolithKit_1.addSurveyLines)(ctx, 3);
    if (!ctx.showDecor)
        return;
    (0, temperaMonolithKit_1.addCornerTicks)(ctx);
    (0, temperaMonolithKit_1.addWireTrace)(ctx, width * 0.1, height * 0.86, Math.min(width, height) * 0.08);
};
const chasm = ctx => {
    const { width, height, palette, bleed } = ctx;
    const gap = (0, temperaHatch_1.rectPolygon)(width * 0.46, -bleed, width * 0.1, height + bleed * 2);
    (0, temperaCutout_1.addCutField)(ctx, palette.tone1, [gap], { alpha: 0.94 });
    (0, temperaMonolithKit_1.addMass)(ctx, (0, temperaHatch_1.rectPolygon)(-bleed, height * 0.3, width * 0.46 + bleed, height * 0.7 + bleed), palette.tone3, {
        enterDX: -width * 0.1,
        edgeWidth: 2,
    });
    (0, temperaMonolithKit_1.addMass)(ctx, (0, temperaHatch_1.rectPolygon)(width * 0.56, height * 0.2, width * 0.44 + bleed, height * 0.8 + bleed), palette.tone4, {
        delay: 0.08,
        enterDX: width * 0.1,
        edgeWidth: 2,
    });
    (0, temperaMonolithKit_1.addSurveyLines)(ctx, 2);
};
const overhang = ctx => {
    const { width, height, palette, bleed } = ctx;
    (0, temperaMonolithKit_1.addGround)(ctx, palette.tone1);
    (0, temperaMonolithKit_1.addMass)(ctx, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height * 0.34 + bleed), palette.tone4, {
        enterDY: -height * 0.1,
        edgeWidth: 3,
    });
    (0, temperaMonolithKit_1.addMass)(ctx, (0, temperaHatch_1.rectPolygon)(width * 0.72, height * 0.34, width * 0.28 + bleed, height * 0.66 + bleed), palette.tone3, {
        delay: 0.08,
        enterDX: width * 0.1,
        edge: false,
    });
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, height * 0.34, width + bleed * 2, height * 0.14), palette.tone2, 0.5, ctx.gradient), { delay: 0.16, span: 0.6 });
    (0, temperaMonolithKit_1.addSurveyLines)(ctx, 3);
    if (!ctx.showDecor)
        return;
    (0, temperaMonolithKit_1.addCornerTicks)(ctx);
};
const stepWell = ctx => {
    const { width, height, palette, bleed } = ctx;
    const shaft = (0, temperaHatch_1.rectPolygon)(width * 0.36, height * 0.6, width * 0.28, height * 0.4 + bleed);
    (0, temperaCutout_1.addCutField)(ctx, palette.tone2, [shaft], { alpha: 0.94 });
    [[0.14, 0.3, 0.72, palette.tone3], [0.24, 0.44, 0.52, palette.tone4]].forEach(([x, y, w, tone], index) => {
        ctx.add((0, temperaShapes_1.drawPolygonFillWithHoles)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(width * x, height * y, width * w, height * (1 - y) + bleed), [shaft], tone, 0.95, ctx.gradient), { delay: 0.06 + index * 0.06, span: 0.6, enterDY: height * 0.06 });
    });
    (0, temperaCutout_1.addHoleLip)(ctx, shaft, 3, 0.85, 0.18);
    (0, temperaMonolithKit_1.addSurveyLines)(ctx, 2);
};
const pierRow = ctx => {
    const { width, height, palette, bleed } = ctx;
    const water = (0, temperaHatch_1.rectPolygon)(-bleed, height * 0.46, width + bleed * 2, height * 0.54 + bleed);
    (0, temperaCutout_1.addCutField)(ctx, palette.tone1, [water], { alpha: 0.94 });
    [0.04, 0.28, 0.52, 0.76].forEach((x, index) => {
        (0, temperaMonolithKit_1.addMass)(ctx, (0, temperaHatch_1.rectPolygon)(width * x, height * 0.46, width * 0.14, height * 0.54 + bleed), palette.tone4, {
            delay: 0.06 + index * 0.04,
            enterDY: height * 0.1,
            edge: false,
        });
    });
    (0, temperaMonolithKit_1.addMass)(ctx, (0, temperaHatch_1.rectPolygon)(-bleed, height * 0.32, width + bleed * 2, height * 0.16), palette.tone3, {
        delay: 0.02,
        enterDX: -width * 0.12,
        edgeWidth: 2,
    });
    (0, temperaMonolithKit_1.addSurveyLines)(ctx, 2);
};
const revetment = ctx => {
    const { width, height, palette, bleed } = ctx;
    (0, temperaMonolithKit_1.addGround)(ctx, palette.tone1);
    const slope = [
        -bleed, height * 0.72,
        width * 0.62, height * 0.3,
        width + bleed, height * 0.34,
        width + bleed, height + bleed,
        -bleed, height + bleed,
    ];
    (0, temperaMonolithKit_1.addMass)(ctx, slope, palette.tone3, { enterDY: height * 0.1 });
    const ribs = Array.from({ length: 9 }, (_, index) => {
        const x = width * (0.04 + index * 0.11);
        const top = height * (0.72 - (x / (width * 0.62)) * 0.42);
        return { x1: x, y1: Math.max(top, height * 0.3) + height * 0.03, x2: x - width * 0.03, y2: height + bleed };
    });
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, ribs, palette.tone4, 2.4, 0.5), { delay: 0.16, span: 0.65 });
    (0, temperaMonolithKit_1.addSurveyLines)(ctx, 3);
    if (!ctx.showDecor)
        return;
    (0, temperaMonolithKit_1.addCornerTicks)(ctx);
};
const towerCrop = ctx => {
    const { width, height, palette, bleed } = ctx;
    (0, temperaMonolithKit_1.addGround)(ctx, palette.tone1);
    (0, temperaMonolithKit_1.addMass)(ctx, (0, temperaHatch_1.rectPolygon)(width * 0.58, height * 0.18, width * 0.42 + bleed, height * 0.82 + bleed), palette.tone4, {
        enterDX: width * 0.08,
        enterDY: height * 0.06,
        edgeWidth: 3,
    });
    (0, temperaMonolithKit_1.addFaceRuling)(ctx, (0, temperaHatch_1.rectPolygon)(width * 0.62, height * 0.26, width * 0.12, height * 0.6), 257, palette.paper, 0.3);
    (0, temperaMonolithKit_1.addSurveyLines)(ctx, 2);
    if (!ctx.showDecor)
        return;
    (0, temperaMonolithKit_1.addWireTrace)(ctx, width * 0.2, height * 0.7, Math.min(width, height) * 0.1);
    (0, temperaMonolithKit_1.addCornerTicks)(ctx);
};
const lintel = ctx => {
    const { width, height, palette, bleed } = ctx;
    (0, temperaMonolithKit_1.addGround)(ctx, palette.tone1);
    (0, temperaMonolithKit_1.addMass)(ctx, (0, temperaHatch_1.rectPolygon)(-bleed, height * 0.4, width + bleed * 2, height * 0.2), palette.tone3, {
        enterDX: -width * 0.16,
        edgeWidth: 3,
    });
    [0.18, 0.66].forEach((x, index) => {
        (0, temperaMonolithKit_1.addMass)(ctx, (0, temperaHatch_1.rectPolygon)(width * x, height * 0.6, width * 0.16, height * 0.12), palette.tone4, {
            delay: 0.12 + index * 0.04,
            enterDY: height * 0.06,
            edge: false,
        });
    });
    (0, temperaMonolithKit_1.addSurveyLines)(ctx, 3);
    if (!ctx.showDecor)
        return;
    (0, temperaMonolithKit_1.addCornerTicks)(ctx);
};
const rubbleFan = ctx => {
    const { width, height, palette } = ctx;
    const hubX = -width * 0.12;
    const hubY = height * 1.12;
    (0, temperaMonolithKit_1.addGround)(ctx, palette.tone1);
    for (let index = 0; index < 5; index += 1) {
        const angle = -1.24 + index * 0.19 + (0, temperaRandom_1.temperaHash01)(ctx.seed, index, 259) * 0.05;
        const reach = Math.hypot(width, height) * (0.5 + index * 0.09);
        const slab = (0, temperaHatch_1.rectPolygon)(hubX + reach * 0.34, hubY - height * 0.06, reach * 0.5, height * 0.12 + index * 8);
        (0, temperaMonolithKit_1.addMass)(ctx, (0, temperaCurves_1.rotatePolygon)(slab, hubX, hubY, angle), index % 2 === 0 ? palette.tone3 : palette.tone4, {
            delay: 0.04 + index * 0.05,
            enterDX: -width * 0.06,
            enterDY: height * 0.06,
            edgeWidth: 2,
        });
    }
    (0, temperaMonolithKit_1.addSurveyLines)(ctx, 2);
};
const gnomon = ctx => {
    const { width, height, palette, bleed } = ctx;
    (0, temperaMonolithKit_1.addGround)(ctx, palette.tone1);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, [
        width * 0.42, height * 0.86,
        width + bleed, height * 0.6,
        width + bleed, height * 0.78,
        width * 0.46, height * 0.94,
    ], palette.tone2, 0.6, ctx.gradient), { delay: 0.1, span: 0.65, enterDX: width * 0.1 });
    (0, temperaMonolithKit_1.addMass)(ctx, [
        width * 0.3, height + bleed,
        width * 0.36, height * 0.16,
        width * 0.42, height * 0.16,
        width * 0.46, height + bleed,
    ], palette.tone4, { delay: 0.04, enterDY: height * 0.08, edgeWidth: 2 });
    (0, temperaMonolithKit_1.addSurveyLines)(ctx, 3);
    if (!ctx.showDecor)
        return;
    (0, temperaMonolithKit_1.addCornerTicks)(ctx);
    (0, temperaMonolithKit_1.addWireTrace)(ctx, width * 0.8, height * 0.82, Math.min(width, height) * 0.08);
};
exports.TEMPERA_TERRAIN_COMPOSITIONS = {
    'ridge-line': ridgeLine,
    'chasm': chasm,
    'overhang': overhang,
    'step-well': stepWell,
    'pier-row': pierRow,
    'revetment': revetment,
    'tower-crop': towerCrop,
    'lintel': lintel,
    'rubble-fan': rubbleFan,
    'gnomon': gnomon,
};

},
"tempera/compositions/temperaMonogatariCompositions":function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.TEMPERA_MONOGATARI_COMPOSITIONS = void 0;
const temperaRandom_1 = require("tempera/temperaRandom");
const temperaHatch_1 = require("tempera/temperaHatch");
const temperaShapes_1 = require("tempera/temperaShapes");
const addField = (ctx, tone) => {
    const { width, height, bleed } = ctx;
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, -bleed, width + bleed * 2, height + bleed * 2), tone, 1, ctx.gradient), { span: 0.45 });
};
const pickField = (ctx) => ((0, temperaRandom_1.temperaHash01)(ctx.seed, 167, 173) > 0.5 ? ctx.palette.tone4 : ctx.palette.tone1);
const monogatariCard = ctx => {
    addField(ctx, pickField(ctx));
    if (!ctx.showDecor)
        return;
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, [
        { x1: ctx.width * 0.12, y1: ctx.height * 0.9, x2: ctx.width * 0.88, y2: ctx.height * 0.9 },
    ], ctx.palette.paper, 1.2, 0.45), { delay: 0.22, span: 0.6, enterDX: ctx.width * 0.15 });
};
const monogatariRule = ctx => {
    const { width, height, palette, bleed } = ctx;
    addField(ctx, pickField(ctx));
    const y = height * (0.62 + (0, temperaRandom_1.temperaHash01)(ctx.seed, 179, 181) * 0.08);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, (0, temperaHatch_1.rectPolygon)(-bleed, y, width + bleed * 2, height * 0.012), palette.paper, 0.85, ctx.gradient), { delay: 0.12, span: 0.55, enterDX: -width * 0.3 });
    if (!ctx.showDecor)
        return;
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, [
        { x1: -bleed, y1: y + height * 0.05, x2: width + bleed, y2: y + height * 0.05 },
    ], palette.paper, 1, 0.35), { delay: 0.2, span: 0.6, enterDX: width * 0.2 });
};
const monogatariEdge = ctx => {
    const { width, height, palette, bleed } = ctx;
    const field = pickField(ctx);
    addField(ctx, field);
    const band = width * (0.1 + (0, temperaRandom_1.temperaHash01)(ctx.seed, 191, 193) * 0.05);
    const fromLeft = (0, temperaRandom_1.temperaHash01)(ctx.seed, 197, 199) > 0.5;
    const spine = (0, temperaHatch_1.rectPolygon)(fromLeft ? -bleed : width - band, -bleed, band + bleed, height + bleed * 2);
    ctx.add((0, temperaShapes_1.drawPolygonFill)(ctx.pixi, spine, field === palette.tone4 ? palette.tone1 : palette.tone4, 0.95, ctx.gradient), { delay: 0.1, span: 0.55, enterDX: (fromLeft ? -1 : 1) * width * 0.2 });
    if (!ctx.showDecor)
        return;
    ctx.add((0, temperaShapes_1.drawHatchFill)(ctx.pixi, spine, (0, temperaHatch_1.buildHatchSpec)(ctx.seed, 211), palette.paper, 0.2), { delay: 0.18, span: 0.6, grow: true });
};
const monogatariStack = ctx => {
    const { width, height, palette, bleed } = ctx;
    addField(ctx, pickField(ctx));
    const column = width * 0.5;
    ctx.add((0, temperaShapes_1.drawLines)(ctx.pixi, [
        { x1: (width - column) / 2, y1: -bleed, x2: (width - column) / 2, y2: height + bleed },
        { x1: (width + column) / 2, y1: -bleed, x2: (width + column) / 2, y2: height + bleed },
    ], palette.paper, 1.1, 0.4), { delay: 0.14, span: 0.6, enterDY: height * 0.12 });
};
const monogatariFlash = ctx => {
    const { width, height, palette } = ctx;
    addField(ctx, palette.tone4);
    if (!ctx.showDecor)
        return;
    ctx.add((0, temperaShapes_1.drawCrossMarks)(ctx.pixi, (0, temperaHatch_1.buildCrossRow)(ctx.seed, 223, width * 0.1, height * 0.18, 4, width * 0.05, 10), palette.paper, 2.4, 0.6), { delay: 0.2, span: 0.5, enterDX: -width * 0.1 });
};
exports.TEMPERA_MONOGATARI_COMPOSITIONS = {
    'monogatari-card': monogatariCard,
    'monogatari-rule': monogatariRule,
    'monogatari-edge': monogatariEdge,
    'monogatari-stack': monogatariStack,
    'monogatari-flash': monogatariFlash,
};

},
"tempera/temperaShotProfiles":function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.resolveTemperaShotCandidates = exports.resolveTemperaShotProfile = exports.TEMPERA_SHOT_PROFILES = void 0;
const types_1 = require("tempera/types");
const region = (cx, cy, w, h, options = {}) => {
    var _a, _b, _c;
    return ({
        cx,
        cy,
        w,
        h,
        align: (_a = options.align) !== null && _a !== void 0 ? _a : 'center',
        rotation: (_b = options.rotation) !== null && _b !== void 0 ? _b : 0,
        fontScale: (_c = options.fontScale) !== null && _c !== void 0 ? _c : 1,
    });
};
exports.TEMPERA_SHOT_PROFILES = {
    'duo-split': {
        region: region(0.5, 0.52, 0.86, 0.46),
        enter: { x: 0, y: 1.3 },
        camera: { travel: 0.11, zoomStart: 1.06, zoomEnd: 1.13 },
        mood: 'neutral',
    },
    'quad-split': {
        region: region(0.5, 0.5, 0.82, 0.4),
        enter: { x: 0.9, y: 0.9 },
        camera: { travel: 0.09, zoomStart: 1.08, zoomEnd: 1.16 },
        mood: 'loud',
    },
    'tri-column': {
        region: region(0.5, 0.5, 0.7, 0.5, { fontScale: 0.95 }),
        enter: { x: -1.2, y: 0 },
        camera: { travel: 0.12, zoomStart: 1.04, zoomEnd: 1.12 },
        mood: 'neutral',
    },
    'thirds-stack': {
        region: region(0.5, 0.5, 0.8, 0.28),
        enter: { x: 0, y: 1.1 },
        camera: { travel: 0.13, zoomStart: 1.03, zoomEnd: 1.11 },
        mood: 'neutral',
    },
    'checker-quad': {
        region: region(0.5, 0.5, 0.76, 0.36),
        enter: { x: 0.8, y: -0.8 },
        camera: { travel: 0.1, zoomStart: 1.1, zoomEnd: 1.02 },
        mood: 'loud',
    },
    'corner-wedge': {
        region: region(0.44, 0.56, 0.68, 0.4, { align: 'left', rotation: -0.03 }),
        enter: { x: -1.4, y: 0.5 },
        camera: { travel: 0.1, zoomStart: 1.05, zoomEnd: 1.14 },
        mood: 'loud',
    },
    'diagonal-halves': {
        region: region(0.5, 0.5, 0.78, 0.4, { rotation: -0.075 }),
        enter: { x: 1.1, y: 1.1 },
        camera: { travel: 0.12, zoomStart: 1.06, zoomEnd: 1.14 },
        mood: 'neutral',
    },
    'cross-axis': {
        region: region(0.5, 0.5, 0.66, 0.3),
        enter: { x: 0, y: 1.2 },
        camera: { travel: 0.08, zoomStart: 1.12, zoomEnd: 1.03 },
        mood: 'loud',
    },
    'offset-halves': {
        region: region(0.5, 0.5, 0.8, 0.4),
        enter: { x: 0.9, y: 0.6 },
        camera: { travel: 0.11, zoomStart: 1.05, zoomEnd: 1.13 },
        mood: 'neutral',
    },
    'stair-blocks': {
        region: region(0.5, 0.5, 0.72, 0.38, { rotation: -0.03 }),
        enter: { x: -1, y: 0.8 },
        camera: { travel: 0.12, zoomStart: 1.06, zoomEnd: 1.14 },
        mood: 'loud',
    },
    'pillar-gap': {
        region: region(0.5, 0.5, 0.34, 0.62, { fontScale: 0.8 }),
        enter: { x: 0, y: 1.2 },
        camera: { travel: 0.07, zoomStart: 1.1, zoomEnd: 1.02 },
        mood: 'loud',
    },
    'corner-quad': {
        region: region(0.46, 0.46, 0.68, 0.36),
        enter: { x: -0.9, y: -0.9 },
        camera: { travel: 0.1, zoomStart: 1.07, zoomEnd: 1.15 },
        mood: 'neutral',
    },
    'sliver-stack': {
        region: region(0.5, 0.5, 0.76, 0.3),
        enter: { x: 1.2, y: 0 },
        camera: { travel: 0.13, zoomStart: 1.04, zoomEnd: 1.12 },
        mood: 'neutral',
    },
    'band-strip': {
        region: region(0.5, 0.52, 0.78, 0.26, { fontScale: 0.92 }),
        enter: { x: 0.5, y: 1.05 },
        camera: { travel: 0.12, zoomStart: 1.03, zoomEnd: 1.1 },
        mood: 'neutral',
    },
    'horizon-band': {
        region: region(0.5, 0.36, 0.8, 0.3),
        enter: { x: 0, y: -1.1 },
        camera: { travel: 0.14, zoomStart: 1.02, zoomEnd: 1.1 },
        mood: 'neutral',
    },
    'deep-dive': {
        region: region(0.5, 0.58, 0.76, 0.34),
        enter: { x: 0, y: 1.6 },
        camera: { travel: 0.16, zoomStart: 1.04, zoomEnd: 1.14 },
        mood: 'neutral',
    },
    'tone-ramp': {
        region: region(0.5, 0.5, 0.82, 0.38),
        enter: { x: 1.2, y: 0.4 },
        camera: { travel: 0.11, zoomStart: 1.05, zoomEnd: 1.12 },
        mood: 'neutral',
    },
    'double-band': {
        region: region(0.5, 0.5, 0.78, 0.22, { fontScale: 0.88 }),
        enter: { x: 0.8, y: 0 },
        camera: { travel: 0.12, zoomStart: 1.03, zoomEnd: 1.11 },
        mood: 'neutral',
    },
    'tilt-band': {
        region: region(0.5, 0.5, 0.8, 0.26, { rotation: -0.1 }),
        enter: { x: -1.1, y: 0.5 },
        camera: { travel: 0.13, zoomStart: 1.05, zoomEnd: 1.13 },
        mood: 'neutral',
    },
    'edge-rails': {
        region: region(0.5, 0.5, 0.74, 0.4),
        enter: { x: 0, y: 1 },
        camera: { travel: 0.09, zoomStart: 1.02, zoomEnd: 1.09 },
        mood: 'quiet',
    },
    'gradient-wall': {
        region: region(0.5, 0.44, 0.82, 0.36),
        enter: { x: 0.5, y: -0.9 },
        camera: { travel: 0.15, zoomStart: 1.04, zoomEnd: 1.13 },
        mood: 'neutral',
    },
    'terrace': {
        region: region(0.46, 0.52, 0.72, 0.34, { align: 'left' }),
        enter: { x: -1.2, y: 0.4 },
        camera: { travel: 0.14, zoomStart: 1.05, zoomEnd: 1.12 },
        mood: 'neutral',
    },
    'frame-window': {
        region: region(0.5, 0.5, 0.64, 0.5, { fontScale: 0.95 }),
        enter: { x: 0, y: 0.95 },
        camera: { travel: 0.05, zoomStart: 1.14, zoomEnd: 1.03 },
        mood: 'neutral',
    },
    'double-frame': {
        region: region(0.5, 0.5, 0.58, 0.4, { fontScale: 0.9 }),
        enter: { x: 0.6, y: 0.6 },
        camera: { travel: 0.06, zoomStart: 1.12, zoomEnd: 1.02 },
        mood: 'neutral',
    },
    'circle-window': {
        region: region(0.5, 0.5, 0.5, 0.34, { fontScale: 0.88 }),
        enter: { x: 0, y: 0.8 },
        camera: { travel: 0.05, zoomStart: 1.16, zoomEnd: 1.04 },
        mood: 'quiet',
    },
    'ladder-frame': {
        region: region(0.52, 0.5, 0.6, 0.4, { align: 'left', fontScale: 0.9 }),
        enter: { x: -0.9, y: 0.6 },
        camera: { travel: 0.07, zoomStart: 1.1, zoomEnd: 1.02 },
        mood: 'quiet',
    },
    'corner-brackets': {
        region: region(0.5, 0.5, 0.56, 0.3, { fontScale: 0.85 }),
        enter: { x: 0, y: 0.6 },
        camera: { travel: 0.04, zoomStart: 1.06, zoomEnd: 1.01 },
        mood: 'quiet',
    },
    'inset-box': {
        region: region(0.5, 0.5, 0.6, 0.42, { fontScale: 0.92 }),
        enter: { x: 0, y: 0.8 },
        camera: { travel: 0.06, zoomStart: 1.1, zoomEnd: 1.02 },
        mood: 'quiet',
    },
    'bracket-pair': {
        region: region(0.5, 0.5, 0.54, 0.34, { fontScale: 0.88 }),
        enter: { x: 1, y: 0 },
        camera: { travel: 0.05, zoomStart: 1.08, zoomEnd: 1.01 },
        mood: 'quiet',
    },
    'arch-window': {
        region: region(0.5, 0.54, 0.5, 0.34, { fontScale: 0.86 }),
        enter: { x: 0, y: 0.9 },
        camera: { travel: 0.06, zoomStart: 1.14, zoomEnd: 1.03 },
        mood: 'quiet',
    },
    'grid-cells': {
        region: region(0.5, 0.5, 0.72, 0.22, { fontScale: 0.8 }),
        enter: { x: 0.7, y: 0.7 },
        camera: { travel: 0.07, zoomStart: 1.06, zoomEnd: 1.13 },
        mood: 'neutral',
    },
    'keyhole': {
        region: region(0.5, 0.6, 0.42, 0.3, { fontScale: 0.78 }),
        enter: { x: 0, y: 1 },
        camera: { travel: 0.05, zoomStart: 1.12, zoomEnd: 1.02 },
        mood: 'quiet',
    },
    'poster-panel': {
        region: region(0.4, 0.5, 0.58, 0.62, { align: 'left', rotation: -0.045 }),
        enter: { x: -1.5, y: 0.35 },
        camera: { travel: 0.08, zoomStart: 1.05, zoomEnd: 1.12 },
        mood: 'loud',
    },
    'diamond-stack': {
        region: region(0.54, 0.5, 0.6, 0.42, { align: 'right', rotation: 0.035 }),
        enter: { x: 1.3, y: -0.5 },
        camera: { travel: 0.09, zoomStart: 1.07, zoomEnd: 1.15 },
        mood: 'loud',
    },
    'slash-poster': {
        region: region(0.46, 0.5, 0.66, 0.44, { align: 'left', rotation: -0.09 }),
        enter: { x: -1.2, y: 1 },
        camera: { travel: 0.11, zoomStart: 1.06, zoomEnd: 1.14 },
        mood: 'loud',
    },
    'arrow-wedge': {
        region: region(0.5, 0.34, 0.72, 0.26),
        enter: { x: 0, y: -1.2 },
        camera: { travel: 0.13, zoomStart: 1.04, zoomEnd: 1.13 },
        mood: 'loud',
    },
    'edge-bleed': {
        region: region(0.56, 0.5, 0.6, 0.44, { align: 'left' }),
        enter: { x: 1.4, y: 0.3 },
        camera: { travel: 0.1, zoomStart: 1.05, zoomEnd: 1.13 },
        mood: 'neutral',
    },
    'triangle-mass': {
        region: region(0.5, 0.42, 0.68, 0.3),
        enter: { x: 0.8, y: -1 },
        camera: { travel: 0.12, zoomStart: 1.05, zoomEnd: 1.14 },
        mood: 'loud',
    },
    'ribbon-cross': {
        region: region(0.5, 0.5, 0.62, 0.3, { rotation: 0.05 }),
        enter: { x: -1, y: -0.8 },
        camera: { travel: 0.11, zoomStart: 1.08, zoomEnd: 1.16 },
        mood: 'loud',
    },
    'half-disc': {
        region: region(0.44, 0.44, 0.6, 0.34, { align: 'left' }),
        enter: { x: -1.3, y: 0.4 },
        camera: { travel: 0.1, zoomStart: 1.06, zoomEnd: 1.14 },
        mood: 'loud',
    },
    'stacked-slabs': {
        region: region(0.52, 0.5, 0.62, 0.4, { rotation: -0.05 }),
        enter: { x: 1.1, y: 0.6 },
        camera: { travel: 0.1, zoomStart: 1.07, zoomEnd: 1.15 },
        mood: 'loud',
    },
    'wedge-pair': {
        region: region(0.5, 0.5, 0.44, 0.44, { fontScale: 0.82 }),
        enter: { x: 0, y: 1.1 },
        camera: { travel: 0.09, zoomStart: 1.1, zoomEnd: 1.02 },
        mood: 'loud',
    },
    'quiet-line': {
        region: region(0.5, 0.5, 0.6, 0.28, { fontScale: 0.58 }),
        enter: { x: 0, y: 0.7 },
        camera: { travel: 0.03, zoomStart: 1, zoomEnd: 1.04 },
        mood: 'quiet',
    },
    'starfield-dots': {
        region: region(0.5, 0.5, 0.62, 0.26, { fontScale: 0.66 }),
        enter: { x: 0.4, y: 0.5 },
        camera: { travel: 0.04, zoomStart: 1.02, zoomEnd: 1.08 },
        mood: 'quiet',
    },
    'ripple-lines': {
        region: region(0.5, 0.46, 0.66, 0.28, { fontScale: 0.72 }),
        enter: { x: 0, y: 0.9 },
        camera: { travel: 0.06, zoomStart: 1.03, zoomEnd: 1.1 },
        mood: 'quiet',
    },
    'hair-grid': {
        region: region(0.5, 0.5, 0.64, 0.26, { fontScale: 0.62 }),
        enter: { x: 0.4, y: 0.6 },
        camera: { travel: 0.04, zoomStart: 1.01, zoomEnd: 1.06 },
        mood: 'quiet',
    },
    'margin-rule': {
        region: region(0.54, 0.5, 0.62, 0.26, { align: 'left', fontScale: 0.66 }),
        enter: { x: -0.8, y: 0.3 },
        camera: { travel: 0.05, zoomStart: 1.02, zoomEnd: 1.07 },
        mood: 'quiet',
    },
    'dot-drift': {
        region: region(0.5, 0.48, 0.6, 0.26, { fontScale: 0.68 }),
        enter: { x: 0.6, y: 0.6 },
        camera: { travel: 0.05, zoomStart: 1.03, zoomEnd: 1.09 },
        mood: 'quiet',
    },
    'arc-sweep': {
        region: region(0.5, 0.5, 0.6, 0.26, { fontScale: 0.7 }),
        enter: { x: 0, y: 0.8 },
        camera: { travel: 0.06, zoomStart: 1.04, zoomEnd: 1.1 },
        mood: 'quiet',
    },
    'blank-page': {
        region: region(0.5, 0.5, 0.56, 0.24, { fontScale: 0.6 }),
        enter: { x: 0, y: 0.5 },
        camera: { travel: 0.03, zoomStart: 1, zoomEnd: 1.03 },
        mood: 'quiet',
    },
    'cinema-scope': {
        region: region(0.5, 0.5, 0.74, 0.22, { fontScale: 0.86 }),
        enter: { x: 0.9, y: 0 },
        camera: { travel: 0.09, zoomStart: 1.04, zoomEnd: 1.11 },
        mood: 'neutral',
    },
    'cinema-wide': {
        region: region(0.5, 0.5, 0.7, 0.3, { fontScale: 0.9 }),
        enter: { x: 0, y: 0.9 },
        camera: { travel: 0.08, zoomStart: 1.06, zoomEnd: 1.13 },
        mood: 'neutral',
    },
    'cinema-academy': {
        region: region(0.5, 0.5, 0.5, 0.4, { fontScale: 0.88 }),
        enter: { x: 0, y: 0.8 },
        camera: { travel: 0.06, zoomStart: 1.1, zoomEnd: 1.02 },
        mood: 'quiet',
    },
    'cinema-square': {
        region: region(0.5, 0.5, 0.42, 0.4, { fontScale: 0.84 }),
        enter: { x: 0.7, y: 0.7 },
        camera: { travel: 0.05, zoomStart: 1.12, zoomEnd: 1.03 },
        mood: 'quiet',
    },
    'cinema-portrait': {
        region: region(0.5, 0.5, 0.32, 0.46, { fontScale: 0.8 }),
        enter: { x: 0, y: 1 },
        camera: { travel: 0.06, zoomStart: 1.08, zoomEnd: 1.16 },
        mood: 'neutral',
    },
    'cinema-tall': {
        region: region(0.5, 0.5, 0.24, 0.5, { fontScale: 0.72 }),
        enter: { x: 0.8, y: 0.4 },
        camera: { travel: 0.07, zoomStart: 1.05, zoomEnd: 1.14 },
        mood: 'neutral',
    },
    'cinema-twin': {
        region: region(0.33, 0.5, 0.3, 0.32, { fontScale: 0.76 }),
        enter: { x: -0.9, y: 0.3 },
        camera: { travel: 0.08, zoomStart: 1.06, zoomEnd: 1.13 },
        mood: 'neutral',
    },
    'bubble-drift': {
        region: region(0.5, 0.5, 0.72, 0.36, { fontScale: 0.92 }),
        enter: { x: 0.5, y: 1 },
        camera: { travel: 0.09, zoomStart: 1.05, zoomEnd: 1.12 },
        mood: 'neutral',
    },
    'cloud-window': {
        region: region(0.5, 0.52, 0.46, 0.3, { fontScale: 0.84 }),
        enter: { x: 0, y: 0.8 },
        camera: { travel: 0.05, zoomStart: 1.14, zoomEnd: 1.03 },
        mood: 'quiet',
    },
    'heart-burst': {
        region: region(0.5, 0.52, 0.5, 0.3, { fontScale: 0.95 }),
        enter: { x: 0.8, y: 0.8 },
        camera: { travel: 0.1, zoomStart: 1.08, zoomEnd: 1.16 },
        mood: 'loud',
    },
    'sparkle-field': {
        region: region(0.5, 0.48, 0.64, 0.26, { fontScale: 0.7 }),
        enter: { x: 0.4, y: 0.6 },
        camera: { travel: 0.04, zoomStart: 1.02, zoomEnd: 1.08 },
        mood: 'quiet',
    },
    'petal-arc': {
        region: region(0.5, 0.6, 0.7, 0.3, { fontScale: 0.9 }),
        enter: { x: 0, y: 1.1 },
        camera: { travel: 0.1, zoomStart: 1.04, zoomEnd: 1.12 },
        mood: 'neutral',
    },
    'scallop-band': {
        region: region(0.5, 0.5, 0.76, 0.24, { fontScale: 0.88 }),
        enter: { x: 0.7, y: 0 },
        camera: { travel: 0.12, zoomStart: 1.03, zoomEnd: 1.1 },
        mood: 'neutral',
    },
    'ribbon-loop': {
        region: region(0.5, 0.5, 0.68, 0.22, { rotation: 0.04, fontScale: 0.86 }),
        enter: { x: -1.1, y: 0.6 },
        camera: { travel: 0.11, zoomStart: 1.07, zoomEnd: 1.15 },
        mood: 'loud',
    },
    'round-plate': {
        region: region(0.5, 0.5, 0.56, 0.36, { fontScale: 0.86 }),
        enter: { x: 0, y: 0.7 },
        camera: { travel: 0.05, zoomStart: 1.1, zoomEnd: 1.02 },
        mood: 'quiet',
    },
    'halo-burst': {
        region: region(0.5, 0.5, 0.46, 0.3, { fontScale: 0.95 }),
        enter: { x: 0, y: 0.9 },
        camera: { travel: 0.08, zoomStart: 1.12, zoomEnd: 1.02 },
        mood: 'loud',
    },
    'iris-hole': {
        region: region(0.28, 0.68, 0.44, 0.28, { fontScale: 0.78 }),
        enter: { x: -1, y: 0.6 },
        camera: { travel: 0.09, zoomStart: 1.06, zoomEnd: 1.14 },
        mood: 'loud',
    },
    'slot-rail': {
        region: region(0.5, 0.66, 0.72, 0.3, { fontScale: 0.9 }),
        enter: { x: 0.6, y: 0.9 },
        camera: { travel: 0.12, zoomStart: 1.04, zoomEnd: 1.11 },
        mood: 'neutral',
    },
    'punch-row': {
        region: region(0.5, 0.5, 0.76, 0.34, { fontScale: 0.92 }),
        enter: { x: 1.1, y: 0 },
        camera: { travel: 0.13, zoomStart: 1.03, zoomEnd: 1.1 },
        mood: 'neutral',
    },
    'film-gate': {
        region: region(0.5, 0.82, 0.66, 0.2, { fontScale: 0.8 }),
        enter: { x: 0, y: 1.1 },
        camera: { travel: 0.08, zoomStart: 1.08, zoomEnd: 1.02 },
        mood: 'loud',
    },
    'cross-vent': {
        region: region(0.5, 0.82, 0.66, 0.2, { fontScale: 0.8 }),
        enter: { x: 0, y: 1 },
        camera: { travel: 0.07, zoomStart: 1.1, zoomEnd: 1.02 },
        mood: 'loud',
    },
    'louvre-slats': {
        region: region(0.5, 0.8, 0.7, 0.22, { fontScale: 0.82 }),
        enter: { x: 0.8, y: 0.7 },
        camera: { travel: 0.11, zoomStart: 1.05, zoomEnd: 1.13 },
        mood: 'neutral',
    },
    'ring-eye': {
        region: region(0.5, 0.5, 0.26, 0.18, { fontScale: 0.62 }),
        enter: { x: 0, y: 0.7 },
        camera: { travel: 0.05, zoomStart: 1.14, zoomEnd: 1.03 },
        mood: 'quiet',
    },
    'notch-stack': {
        region: region(0.32, 0.5, 0.5, 0.34, { fontScale: 0.84 }),
        enter: { x: -1.1, y: 0.5 },
        camera: { travel: 0.1, zoomStart: 1.05, zoomEnd: 1.13 },
        mood: 'neutral',
    },
    'wedge-gap': {
        region: region(0.5, 0.78, 0.7, 0.24, { fontScale: 0.82 }),
        enter: { x: 0, y: 1.2 },
        camera: { travel: 0.12, zoomStart: 1.06, zoomEnd: 1.14 },
        mood: 'loud',
    },
    'dot-sieve': {
        region: region(0.75, 0.5, 0.38, 0.3, { fontScale: 0.78 }),
        enter: { x: 0.9, y: 0.4 },
        camera: { travel: 0.06, zoomStart: 1.03, zoomEnd: 1.09 },
        mood: 'quiet',
    },
    'sight-mark': {
        region: region(0.5, 0.5, 0.46, 0.2, { fontScale: 0.85 }),
        enter: { x: 0, y: 0.8 },
        camera: { travel: 0.06, zoomStart: 1.12, zoomEnd: 1.02 },
        mood: 'loud',
    },
    'dial-scale': {
        region: region(0.5, 0.5, 0.36, 0.2, { fontScale: 0.8 }),
        enter: { x: 0.7, y: 0.5 },
        camera: { travel: 0.05, zoomStart: 1.1, zoomEnd: 1.02 },
        mood: 'neutral',
    },
    'chevron-run': {
        region: region(0.5, 0.52, 0.72, 0.3, { fontScale: 0.9 }),
        enter: { x: 0, y: -1.1 },
        camera: { travel: 0.14, zoomStart: 1.04, zoomEnd: 1.12 },
        mood: 'neutral',
    },
    'tally-column': {
        region: region(0.38, 0.5, 0.6, 0.32, { align: 'left', fontScale: 0.76 }),
        enter: { x: -0.9, y: 0.3 },
        camera: { travel: 0.05, zoomStart: 1.02, zoomEnd: 1.08 },
        mood: 'quiet',
    },
    'grid-focus': {
        region: region(0.5, 0.5, 0.62, 0.22, { fontScale: 0.85 }),
        enter: { x: 0.8, y: 0.6 },
        camera: { travel: 0.09, zoomStart: 1.05, zoomEnd: 1.13 },
        mood: 'neutral',
    },
    'axis-caps': {
        region: region(0.5, 0.72, 0.66, 0.24, { fontScale: 0.82 }),
        enter: { x: 0, y: 1.2 },
        camera: { travel: 0.13, zoomStart: 1.06, zoomEnd: 1.15 },
        mood: 'loud',
    },
    'strobe-slats': {
        region: region(0.5, 0.5, 0.3, 0.36, { fontScale: 0.8 }),
        enter: { x: 1, y: 0 },
        camera: { travel: 0.1, zoomStart: 1.08, zoomEnd: 1.16 },
        mood: 'loud',
    },
    'offset-plate': {
        region: region(0.48, 0.62, 0.4, 0.2, { fontScale: 0.85 }),
        enter: { x: -0.9, y: -0.6 },
        camera: { travel: 0.09, zoomStart: 1.07, zoomEnd: 1.15 },
        mood: 'loud',
    },
    'radial-comb': {
        region: region(0.42, 0.4, 0.62, 0.3, { fontScale: 0.88 }),
        enter: { x: -1.2, y: -0.4 },
        camera: { travel: 0.11, zoomStart: 1.05, zoomEnd: 1.13 },
        mood: 'neutral',
    },
    'bracket-target': {
        region: region(0.5, 0.28, 0.66, 0.24, { fontScale: 0.85 }),
        enter: { x: 0, y: -0.9 },
        camera: { travel: 0.06, zoomStart: 1.04, zoomEnd: 1.1 },
        mood: 'quiet',
    },
    'flow-channel': {
        region: region(0.32, 0.5, 0.5, 0.3, { fontScale: 0.85 }),
        enter: { x: -1, y: 0.5 },
        camera: { travel: 0.13, zoomStart: 1.04, zoomEnd: 1.12 },
        mood: 'neutral',
    },
    'twin-channel': {
        region: region(0.5, 0.5, 0.4, 0.3, { fontScale: 0.85 }),
        enter: { x: 0, y: 1.2 },
        camera: { travel: 0.14, zoomStart: 1.03, zoomEnd: 1.11 },
        mood: 'neutral',
    },
    'reed-run': {
        region: region(0.5, 0.5, 0.3, 0.3, { fontScale: 0.72 }),
        enter: { x: 0, y: 0.9 },
        camera: { travel: 0.1, zoomStart: 1.02, zoomEnd: 1.09 },
        mood: 'quiet',
    },
    'taper-channel': {
        region: region(0.28, 0.5, 0.42, 0.3, { fontScale: 0.82 }),
        enter: { x: -1.1, y: 0.6 },
        camera: { travel: 0.12, zoomStart: 1.05, zoomEnd: 1.14 },
        mood: 'neutral',
    },
    'chain-ports': {
        region: region(0.32, 0.5, 0.5, 0.32, { fontScale: 0.8 }),
        enter: { x: -0.8, y: 0.7 },
        camera: { travel: 0.11, zoomStart: 1.03, zoomEnd: 1.1 },
        mood: 'quiet',
    },
    'dash-channel': {
        region: region(0.3, 0.5, 0.46, 0.3, { fontScale: 0.84 }),
        enter: { x: 0, y: 1.3 },
        camera: { travel: 0.15, zoomStart: 1.04, zoomEnd: 1.13 },
        mood: 'neutral',
    },
    'window-run': {
        region: region(0.28, 0.5, 0.42, 0.3, { fontScale: 0.82 }),
        enter: { x: 0, y: 1.2 },
        camera: { travel: 0.14, zoomStart: 1.04, zoomEnd: 1.12 },
        mood: 'neutral',
    },
    'bridge-span': {
        region: region(0.5, 0.5, 0.72, 0.16, { fontScale: 0.85 }),
        enter: { x: 1.2, y: 0 },
        camera: { travel: 0.12, zoomStart: 1.08, zoomEnd: 1.16 },
        mood: 'loud',
    },
    'braid-channel': {
        region: region(0.5, 0.5, 0.34, 0.3, { fontScale: 0.8 }),
        enter: { x: 0, y: 1.1 },
        camera: { travel: 0.13, zoomStart: 1.06, zoomEnd: 1.15 },
        mood: 'loud',
    },
    'port-ladder': {
        region: region(0.3, 0.5, 0.46, 0.3, { fontScale: 0.78 }),
        enter: { x: -0.9, y: 0.4 },
        camera: { travel: 0.09, zoomStart: 1.02, zoomEnd: 1.09 },
        mood: 'quiet',
    },
    'apex-mass': {
        region: region(0.5, 0.3, 0.62, 0.2, { fontScale: 0.9 }),
        enter: { x: 0, y: -1 },
        camera: { travel: 0.12, zoomStart: 1.04, zoomEnd: 1.13 },
        mood: 'loud',
    },
    'ziggurat': {
        region: region(0.5, 0.32, 0.5, 0.18, { fontScale: 0.85 }),
        enter: { x: 0, y: -0.9 },
        camera: { travel: 0.1, zoomStart: 1.06, zoomEnd: 1.15 },
        mood: 'loud',
    },
    'slab-wall': {
        region: region(0.36, 0.5, 0.5, 0.24, { fontScale: 0.88 }),
        enter: { x: 1.2, y: 0 },
        camera: { travel: 0.11, zoomStart: 1.05, zoomEnd: 1.12 },
        mood: 'neutral',
    },
    'cantilever': {
        region: region(0.42, 0.42, 0.6, 0.14, { fontScale: 0.8 }),
        enter: { x: -1.3, y: 0 },
        camera: { travel: 0.13, zoomStart: 1.04, zoomEnd: 1.12 },
        mood: 'loud',
    },
    'pylon-pair': {
        region: region(0.5, 0.22, 0.7, 0.12, { fontScale: 0.75 }),
        enter: { x: 0, y: -0.8 },
        camera: { travel: 0.09, zoomStart: 1.08, zoomEnd: 1.02 },
        mood: 'loud',
    },
    'bunker-slit': {
        region: region(0.5, 0.48, 0.72, 0.2, { fontScale: 0.86 }),
        enter: { x: 0.9, y: 0.4 },
        camera: { travel: 0.08, zoomStart: 1.06, zoomEnd: 1.13 },
        mood: 'neutral',
    },
    'plinth-stack': {
        region: region(0.5, 0.32, 0.44, 0.16, { fontScale: 0.82 }),
        enter: { x: 0, y: -0.8 },
        camera: { travel: 0.1, zoomStart: 1.05, zoomEnd: 1.13 },
        mood: 'neutral',
    },
    'buttress-run': {
        region: region(0.5, 0.26, 0.7, 0.2, { fontScale: 0.86 }),
        enter: { x: 0.8, y: -0.8 },
        camera: { travel: 0.12, zoomStart: 1.03, zoomEnd: 1.11 },
        mood: 'loud',
    },
    'void-core': {
        region: region(0.5, 0.2, 0.66, 0.18, { fontScale: 0.84 }),
        enter: { x: 0, y: -1.1 },
        camera: { travel: 0.11, zoomStart: 1.07, zoomEnd: 1.15 },
        mood: 'loud',
    },
    'shear-block': {
        region: region(0.5, 0.5, 0.56, 0.2, { fontScale: 0.88 }),
        enter: { x: 1, y: 0.5 },
        camera: { travel: 0.12, zoomStart: 1.06, zoomEnd: 1.14 },
        mood: 'neutral',
    },
    'ridge-line': {
        region: region(0.5, 0.42, 0.72, 0.2, { fontScale: 0.9 }),
        enter: { x: 0, y: -1 },
        camera: { travel: 0.14, zoomStart: 1.03, zoomEnd: 1.12 },
        mood: 'neutral',
    },
    'chasm': {
        region: region(0.25, 0.5, 0.38, 0.24, { fontScale: 0.82 }),
        enter: { x: -1.2, y: 0.4 },
        camera: { travel: 0.1, zoomStart: 1.06, zoomEnd: 1.14 },
        mood: 'loud',
    },
    'overhang': {
        region: region(0.44, 0.58, 0.6, 0.22, { fontScale: 0.88 }),
        enter: { x: 0, y: 1.1 },
        camera: { travel: 0.11, zoomStart: 1.08, zoomEnd: 1.02 },
        mood: 'loud',
    },
    'step-well': {
        region: region(0.5, 0.26, 0.66, 0.2, { fontScale: 0.85 }),
        enter: { x: 0, y: -0.9 },
        camera: { travel: 0.09, zoomStart: 1.04, zoomEnd: 1.12 },
        mood: 'neutral',
    },
    'pier-row': {
        region: region(0.5, 0.4, 0.76, 0.14, { fontScale: 0.82 }),
        enter: { x: 1.1, y: 0 },
        camera: { travel: 0.13, zoomStart: 1.03, zoomEnd: 1.1 },
        mood: 'neutral',
    },
    'revetment': {
        region: region(0.46, 0.3, 0.6, 0.2, { fontScale: 0.86 }),
        enter: { x: -1, y: -0.6 },
        camera: { travel: 0.12, zoomStart: 1.05, zoomEnd: 1.13 },
        mood: 'neutral',
    },
    'tower-crop': {
        region: region(0.28, 0.5, 0.44, 0.24, { align: 'left', fontScale: 0.74 }),
        enter: { x: -0.8, y: 0.3 },
        camera: { travel: 0.06, zoomStart: 1.02, zoomEnd: 1.09 },
        mood: 'quiet',
    },
    'lintel': {
        region: region(0.5, 0.5, 0.76, 0.16, { fontScale: 0.9 }),
        enter: { x: -1.1, y: 0 },
        camera: { travel: 0.1, zoomStart: 1.02, zoomEnd: 1.08 },
        mood: 'quiet',
    },
    'rubble-fan': {
        region: region(0.56, 0.4, 0.5, 0.22, { fontScale: 0.84 }),
        enter: { x: 1.2, y: -0.5 },
        camera: { travel: 0.13, zoomStart: 1.07, zoomEnd: 1.16 },
        mood: 'loud',
    },
    'gnomon': {
        region: region(0.66, 0.34, 0.46, 0.2, { fontScale: 0.78 }),
        enter: { x: 0.9, y: -0.4 },
        camera: { travel: 0.07, zoomStart: 1.03, zoomEnd: 1.1 },
        mood: 'quiet',
    },
    'monogatari-card': {
        region: region(0.5, 0.5, 0.78, 0.5, { fontScale: 1.15 }),
        enter: { x: 0, y: 0.7 },
        camera: { travel: 0.03, zoomStart: 1.02, zoomEnd: 1.07 },
        mood: 'quiet',
        sharedDecor: false,
    },
    'monogatari-rule': {
        region: region(0.5, 0.46, 0.76, 0.4, { fontScale: 1.05 }),
        enter: { x: 0.6, y: 0 },
        camera: { travel: 0.04, zoomStart: 1.03, zoomEnd: 1.09 },
        mood: 'quiet',
        sharedDecor: false,
    },
    'monogatari-edge': {
        region: region(0.52, 0.5, 0.72, 0.46, { align: 'left', fontScale: 1.05 }),
        enter: { x: -0.8, y: 0 },
        camera: { travel: 0.05, zoomStart: 1.02, zoomEnd: 1.08 },
        mood: 'neutral',
        sharedDecor: false,
    },
    'monogatari-stack': {
        region: region(0.5, 0.5, 0.44, 0.62, { fontScale: 1 }),
        enter: { x: 0, y: 0.9 },
        camera: { travel: 0.04, zoomStart: 1.05, zoomEnd: 1.12 },
        mood: 'quiet',
        sharedDecor: false,
    },
    'monogatari-flash': {
        region: region(0.5, 0.5, 0.82, 0.44, { fontScale: 1.3 }),
        enter: { x: 0, y: 0.5 },
        camera: { travel: 0.02, zoomStart: 1.08, zoomEnd: 1.01 },
        mood: 'loud',
        sharedDecor: false,
    },
};
const resolveTemperaShotProfile = (kind) => {
    var _a;
    return ((_a = exports.TEMPERA_SHOT_PROFILES[kind]) !== null && _a !== void 0 ? _a : exports.TEMPERA_SHOT_PROFILES['duo-split']);
};
exports.resolveTemperaShotProfile = resolveTemperaShotProfile;
const resolveTemperaShotCandidates = (moods) => {
    const candidates = types_1.TEMPERA_SHOT_KINDS.filter(kind => moods.includes((0, exports.resolveTemperaShotProfile)(kind).mood));
    return candidates.length > 0 ? candidates : types_1.TEMPERA_SHOT_KINDS;
};
exports.resolveTemperaShotCandidates = resolveTemperaShotCandidates;

},
"tempera/types":function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.TEMPERA_DECOR_MOTIFS = exports.TEMPERA_TRANSITION_KINDS = exports.TEMPERA_SHOT_KINDS = void 0;
exports.TEMPERA_SHOT_KINDS = [
    'duo-split',
    'quad-split',
    'tri-column',
    'thirds-stack',
    'checker-quad',
    'corner-wedge',
    'diagonal-halves',
    'cross-axis',
    'offset-halves',
    'stair-blocks',
    'pillar-gap',
    'corner-quad',
    'sliver-stack',
    'band-strip',
    'horizon-band',
    'deep-dive',
    'tone-ramp',
    'double-band',
    'tilt-band',
    'edge-rails',
    'gradient-wall',
    'terrace',
    'frame-window',
    'double-frame',
    'circle-window',
    'ladder-frame',
    'corner-brackets',
    'inset-box',
    'bracket-pair',
    'arch-window',
    'grid-cells',
    'keyhole',
    'poster-panel',
    'diamond-stack',
    'slash-poster',
    'arrow-wedge',
    'edge-bleed',
    'triangle-mass',
    'ribbon-cross',
    'half-disc',
    'stacked-slabs',
    'wedge-pair',
    'quiet-line',
    'starfield-dots',
    'ripple-lines',
    'hair-grid',
    'margin-rule',
    'dot-drift',
    'arc-sweep',
    'blank-page',
    'cinema-scope',
    'cinema-wide',
    'cinema-academy',
    'cinema-square',
    'cinema-portrait',
    'cinema-tall',
    'cinema-twin',
    'bubble-drift',
    'cloud-window',
    'heart-burst',
    'sparkle-field',
    'petal-arc',
    'scallop-band',
    'ribbon-loop',
    'round-plate',
    'halo-burst',
    'iris-hole',
    'slot-rail',
    'punch-row',
    'film-gate',
    'cross-vent',
    'louvre-slats',
    'ring-eye',
    'notch-stack',
    'wedge-gap',
    'dot-sieve',
    'sight-mark',
    'dial-scale',
    'chevron-run',
    'tally-column',
    'grid-focus',
    'axis-caps',
    'strobe-slats',
    'offset-plate',
    'radial-comb',
    'bracket-target',
    'flow-channel',
    'twin-channel',
    'reed-run',
    'taper-channel',
    'chain-ports',
    'dash-channel',
    'window-run',
    'bridge-span',
    'braid-channel',
    'port-ladder',
    'apex-mass',
    'ziggurat',
    'slab-wall',
    'cantilever',
    'pylon-pair',
    'bunker-slit',
    'plinth-stack',
    'buttress-run',
    'void-core',
    'shear-block',
    'ridge-line',
    'chasm',
    'overhang',
    'step-well',
    'pier-row',
    'revetment',
    'tower-crop',
    'lintel',
    'rubble-fan',
    'gnomon',
    'monogatari-card',
    'monogatari-rule',
    'monogatari-edge',
    'monogatari-stack',
    'monogatari-flash',
];
exports.TEMPERA_TRANSITION_KINDS = [
    'block-wipe',
    'camera-pan',
    'shape-carry',
];
exports.TEMPERA_DECOR_MOTIFS = [
    'diamonds',
    'hatch-twin',
    'band-cross',
    'poster-diamond',
    'doodle',
];

},
"tempera/temperaBlocks":function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildTemperaBlocks = void 0;
const temperaMotion_1 = require("tempera/temperaMotion");
const temperaRandom_1 = require("tempera/temperaRandom");
const temperaCompositions_1 = require("tempera/temperaCompositions");
const buildTemperaBlocks = (pixi, options) => {
    const container = new pixi.Container();
    const items = [];
    const flowX = Math.cos(options.flowAngle);
    const flowY = Math.sin(options.flowAngle);
    const carry = Math.max(options.width, options.height) * 0.09;
    const add = (node, blockOptions = {}, parent) => {
        var _a, _b, _c, _d, _e, _f, _g;
        items.push({
            node,
            baseX: node.x,
            baseY: node.y,
            baseAlpha: (_a = blockOptions.alpha) !== null && _a !== void 0 ? _a : 1,
            enterDX: (_b = blockOptions.enterDX) !== null && _b !== void 0 ? _b : 0,
            enterDY: (_c = blockOptions.enterDY) !== null && _c !== void 0 ? _c : 0,
            delayFraction: (_d = blockOptions.delay) !== null && _d !== void 0 ? _d : 0,
            spanFraction: (_e = blockOptions.span) !== null && _e !== void 0 ? _e : 0.45,
            drift: (_f = blockOptions.drift) !== null && _f !== void 0 ? _f : false,
            driftPhase: (0, temperaRandom_1.temperaHash01)(options.seed, items.length, 173) * Math.PI * 2,
            grow: (_g = blockOptions.grow) !== null && _g !== void 0 ? _g : false,
        });
        (parent !== null && parent !== void 0 ? parent : container).addChild(node);
    };
    const createGroup = (rotation, x, y) => {
        const group = new pixi.Container();
        group.rotation = rotation;
        group.position.set(x, y);
        container.addChild(group);
        return group;
    };
    const context = {
        pixi,
        kind: options.kind,
        palette: options.palette,
        decor: options.decor,
        width: options.width,
        height: options.height,
        seed: options.seed,
        showDecor: options.showDecor,
        flowAngle: options.flowAngle,
        bleed: carry + Math.max(options.width, options.height) * 0.08,
        gradient: options.palette.gradient
            ? { colors: options.palette.gradient, angle: (0, temperaRandom_1.temperaHash01)(options.seed, 3, 197) * Math.PI * 2 }
            : null,
        add,
        createGroup,
    };
    (0, temperaCompositions_1.drawTemperaComposition)(context);
    const updateTime = (time, shotStart, shotEnd, lyricEnd) => {
        const duration = Math.max(shotEnd - shotStart, 0.2);
        const paceDuration = Math.max((lyricEnd !== null && lyricEnd !== void 0 ? lyricEnd : shotEnd) - shotStart, 0.2);
        const progress = (0, temperaMotion_1.clamp01)((time - shotStart) / duration);
        const creep = (0, temperaMotion_1.easeTemperaInOut)(progress) * carry * 0.35;
        const budget = Math.max(0.5, paceDuration);
        for (const item of items) {
            const rawDelay = (0, temperaMotion_1.resolveShotPacedDuration)(paceDuration, item.delayFraction, 0, 1.4);
            const rawSpan = (0, temperaMotion_1.resolveShotPacedDuration)(paceDuration, item.spanFraction, 0.7, 2.6);
            const compress = Math.min(1, budget / (rawDelay + rawSpan));
            const enter = (0, temperaMotion_1.easeTemperaEnter)((time - shotStart - rawDelay * compress) / (rawSpan * compress));
            item.node.alpha = item.baseAlpha * enter;
            item.node.visible = enter > 0.001;
            const behind = (1 - enter) * carry - creep;
            item.node.position.set(item.baseX + item.enterDX * (1 - enter) - flowX * behind, item.baseY + item.enterDY * (1 - enter) - flowY * behind);
            if (item.drift || item.grow) {
                const float = item.drift ? 1 + Math.sin(time * 0.5 + item.driftPhase) * 0.02 : 1;
                item.node.scale.set(item.grow ? Math.max(0.0001, enter) * float : float, float);
                if (item.drift)
                    item.node.rotation = Math.sin(time * 0.33 + item.driftPhase) * 0.012;
            }
        }
    };
    return { container, updateTime };
};
exports.buildTemperaBlocks = buildTemperaBlocks;

},
"tempera/temperaMotion":function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.resolveShotPacedDuration = exports.resolveTemperaGlyphMotion = exports.resolveCubicBezier = exports.easeTemperaSoftBack = exports.easeTemperaInOut = exports.easeTemperaEnter = exports.clamp01 = void 0;
const temperaMotionEasing_1 = require("tempera/temperaMotionEasing");
Object.defineProperty(exports, "clamp01", { enumerable: true, get: function () { return temperaMotionEasing_1.clamp01; } });
Object.defineProperty(exports, "easeTemperaEnter", { enumerable: true, get: function () { return temperaMotionEasing_1.easeTemperaEnter; } });
Object.defineProperty(exports, "easeTemperaInOut", { enumerable: true, get: function () { return temperaMotionEasing_1.easeTemperaInOut; } });
Object.defineProperty(exports, "easeTemperaSoftBack", { enumerable: true, get: function () { return temperaMotionEasing_1.easeTemperaSoftBack; } });
Object.defineProperty(exports, "resolveCubicBezier", { enumerable: true, get: function () { return temperaMotionEasing_1.resolveCubicBezier; } });
const temperaEnterStyles_1 = require("tempera/temperaEnterStyles");
const CURRENT_EMPHASIS = 0.05;
const EMPHASIS_DECAY = 0.26;
const ECHO_ALPHA = 0.5;
const MAX_REVEAL_WINDOW = 1.35;
const RELEASE_TRACKING = 0.055;
const resolveTemperaGlyphMotion = (glyph, time, motion) => {
    const window = Math.max(glyph.settleTime - glyph.startTime, 0.08);
    const linear = (0, temperaMotionEasing_1.clamp01)((time - glyph.startTime) / window);
    const travel = 1 - (0, temperaMotionEasing_1.easeTemperaEnter)(linear);
    const entrance = (0, temperaEnterStyles_1.resolveTemperaEnterFrame)(glyph.enterStyle, glyph, travel, linear);
    const reveal = (0, temperaMotionEasing_1.clamp01)((time - glyph.startTime) / Math.min(window, MAX_REVEAL_WINDOW));
    const alpha = (0, temperaMotionEasing_1.easeTemperaInOut)((0, temperaMotionEasing_1.clamp01)(reveal * 2.4));
    const sungWindow = glyph.endTime - glyph.startTime;
    const attack = Math.min(0.12, sungWindow * 0.5);
    const emphasis = sungWindow <= 0
        ? 0
        : (0, temperaMotionEasing_1.easeTemperaInOut)((0, temperaMotionEasing_1.clamp01)((time - glyph.startTime) / Math.max(attack, 0.02)))
            * (1 - (0, temperaMotionEasing_1.easeTemperaInOut)((0, temperaMotionEasing_1.clamp01)((time - glyph.endTime) / EMPHASIS_DECAY)));
    const releaseStart = Math.max(glyph.endTime, glyph.settleTime);
    const release = (0, temperaMotionEasing_1.easeTemperaInOut)((0, temperaMotionEasing_1.clamp01)((time - releaseStart) / Math.max(glyph.releaseTime - releaseStart, 0.001)));
    const spread = release * (0, temperaMotionEasing_1.clamp01)(motion) * RELEASE_TRACKING;
    const driftX = glyph.trackingX * spread;
    const driftY = glyph.trackingY * spread;
    const amount = (0, temperaMotionEasing_1.clamp01)(motion);
    const swell = emphasis * CURRENT_EMPHASIS * amount;
    return {
        visible: time >= glyph.startTime,
        alpha,
        x: entrance.x * motion + driftX,
        y: entrance.y * motion + driftY,
        rotation: glyph.rotation + entrance.rotation * motion,
        scaleX: entrance.scaleX + (1 - entrance.scaleX) * (1 - amount) + swell,
        scaleY: entrance.scaleY + (1 - entrance.scaleY) * (1 - amount) + swell,
        echoX: entrance.x * motion,
        echoY: entrance.y * motion,
        echoAlpha: entrance.echo * (1 - (0, temperaMotionEasing_1.easeTemperaEnter)(reveal)) * ECHO_ALPHA * amount,
    };
};
exports.resolveTemperaGlyphMotion = resolveTemperaGlyphMotion;
const resolveShotPacedDuration = (shotDuration, fraction, minSeconds, maxSeconds) => Math.min(maxSeconds, Math.max(minSeconds, shotDuration * fraction));
exports.resolveShotPacedDuration = resolveShotPacedDuration;

},
"tempera/temperaMotionEasing":function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.easeTemperaSoftBack = exports.easeTemperaInOut = exports.easeTemperaEnter = exports.resolveCubicBezier = exports.clamp01 = void 0;
const clamp01 = (value) => Math.min(1, Math.max(0, value));
exports.clamp01 = clamp01;
const cubicCoordinate = (point1, point2, time) => {
    const inverse = 1 - time;
    return 3 * inverse * inverse * time * point1
        + 3 * inverse * time * time * point2
        + time * time * time;
};
const resolveCubicBezier = (x1, y1, x2, y2, value) => {
    const target = (0, exports.clamp01)(value);
    if (target === 0 || target === 1)
        return target;
    let low = 0;
    let high = 1;
    let parameter = target;
    for (let iteration = 0; iteration < 12; iteration += 1) {
        const x = cubicCoordinate(x1, x2, parameter);
        if (x < target)
            low = parameter;
        else
            high = parameter;
        parameter = (low + high) / 2;
    }
    return cubicCoordinate(y1, y2, parameter);
};
exports.resolveCubicBezier = resolveCubicBezier;
const easeTemperaEnter = (value) => (0, exports.resolveCubicBezier)(0.22, 1, 0.36, 1, value);
exports.easeTemperaEnter = easeTemperaEnter;
const easeTemperaInOut = (value) => (0, exports.resolveCubicBezier)(0.62, 0, 0.32, 1, value);
exports.easeTemperaInOut = easeTemperaInOut;
const easeTemperaSoftBack = (value) => {
    const t = (0, exports.clamp01)(value);
    const c = 1.42;
    return 1 + (c + 1) * Math.pow(t - 1, 3) + c * Math.pow(t - 1, 2);
};
exports.easeTemperaSoftBack = easeTemperaSoftBack;

},
"tempera/temperaEnterStyles":function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.resolveTemperaEnterFrame = exports.TEMPERA_ENTER_STYLES = void 0;
const temperaMotionEasing_1 = require("tempera/temperaMotionEasing");
exports.TEMPERA_ENTER_STYLES = [
    'slide',
    'from-left',
    'from-right',
    'from-above',
    'from-below',
    'swing',
    'stamp',
];
const directional = (input, travel, uniform, dirX, dirY, rotationScale) => {
    const magnitude = Math.hypot(input.enterX, input.enterY);
    const length = Math.hypot(dirX, dirY) || 1;
    return {
        x: (dirX / length) * magnitude * travel,
        y: (dirY / length) * magnitude * travel,
        rotation: input.enterRotation * rotationScale * travel,
        scaleX: uniform,
        scaleY: uniform,
        echo: travel,
    };
};
const resolveTemperaEnterFrame = (style, input, travel, linear) => {
    const settle = (0, temperaMotionEasing_1.easeTemperaSoftBack)(linear);
    const uniform = input.enterScale + (1 - input.enterScale) * settle;
    switch (style) {
        case 'from-left':
            return directional(input, travel, uniform, -1, 0.12, 0.4);
        case 'from-right':
            return directional(input, travel, uniform, 1, -0.12, 0.4);
        case 'from-above':
            return directional(input, travel, uniform, 0.12, -1, 0.4);
        case 'from-below':
            return directional(input, travel, uniform, -0.12, 1, 0.4);
        case 'swing':
            return {
                x: input.enterX * 0.6 * travel,
                y: input.enterY * 0.6 * travel,
                rotation: (input.enterRotation + Math.sign(input.enterRotation || 1) * 0.95) * travel,
                scaleX: uniform,
                scaleY: uniform,
                echo: travel * 0.8,
            };
        case 'stamp':
            return {
                x: 0,
                y: 0,
                rotation: input.enterRotation * 0.6 * travel,
                scaleX: 1 + travel * 0.7,
                scaleY: 1 + travel * 0.7,
                echo: 0,
            };
        case 'slide':
        default:
            return {
                x: input.enterX * travel,
                y: input.enterY * travel,
                rotation: input.enterRotation * travel,
                scaleX: uniform,
                scaleY: uniform,
                echo: travel,
            };
    }
};
exports.resolveTemperaEnterFrame = resolveTemperaEnterFrame;

},
"sonnet/sonnetShotFlowLayouts":function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.layoutCrossStack = exports.layoutFragmentCollage = exports.layoutEditorialColumn = exports.layoutTrackingRibbon = exports.layoutQuietTableau = exports.placeWithGlobalFit = exports.resolveSonnetFlowGaps = void 0;
const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
const resolveSonnetFlowGaps = (baseFontSize) => {
    const flowGap = clamp(baseFontSize * 0.35, 16, 40);
    return { flowGap, stackGap: Math.max(24, flowGap * 1.35) };
};
exports.resolveSonnetFlowGaps = resolveSonnetFlowGaps;
const placeWithGlobalFit = (ctx, place) => {
    const snapshot = ctx.boxes.map(box => ({
        fontScale: box.fontScale,
        measuredWidth: box.measuredWidth,
        measuredHeight: box.measuredHeight,
    }));
    const safeHalfW = ctx.width * 0.48;
    const safeHalfH = ctx.height * 0.46;
    for (const globalScale of [1, 0.92, 0.84, 0.76, 0.68, 0.6, 0.52]) {
        ctx.boxes.forEach((box, index) => {
            box.fontScale = snapshot[index].fontScale * globalScale;
            box.measuredWidth = snapshot[index].measuredWidth * globalScale;
            box.measuredHeight = snapshot[index].measuredHeight * globalScale;
        });
        place(globalScale);
        const fits = ctx.boxes.every(box => (Math.abs(box.x) + box.measuredWidth / 2 <= safeHalfW + 0.5
            && Math.abs(box.y) + box.measuredHeight / 2 <= safeHalfH + 0.5));
        if (fits)
            return;
    }
};
exports.placeWithGlobalFit = placeWithGlobalFit;
const layoutQuietTableau = (ctx, variant) => {
    const { boxes, heroIndex, height, stackGap } = ctx;
    const heroBox = boxes[heroIndex];
    const horizontalCard = variant === 2 || variant === 3;
    boxes.forEach(box => { box.layoutDirection = horizontalCard ? 'horizontal' : 'vertical'; });
    const safeHalfH = height * 0.46;
    (0, exports.placeWithGlobalFit)(ctx, () => {
        heroBox.x = 0;
        heroBox.y = horizontalCard ? 0 : -height * 0.1;
        const stagger = variant === 3 ? 70 : 0;
        const columnStep = Math.max(...boxes.map(box => box.measuredWidth)) + stackGap + stagger;
        const xFor = (box, index) => {
            if (variant === 1)
                return heroBox.x - heroBox.measuredWidth / 2 + box.measuredWidth / 2;
            if (variant === 3)
                return heroBox.x + ((index % 2 === 0) ? 1 : -1) * 35;
            return heroBox.x;
        };
        let column = 0;
        let currentY = heroBox.y - heroBox.measuredHeight / 2 - stackGap;
        for (let i = heroIndex - 1; i >= 0; i--) {
            const box = boxes[i];
            if (currentY - box.measuredHeight < -safeHalfH) {
                column += 1;
                currentY = safeHalfH;
            }
            box.x = xFor(box, i) + column * columnStep;
            box.y = currentY - box.measuredHeight / 2;
            currentY -= box.measuredHeight + stackGap;
            if (variant === 1) {
                box.enterX = 20;
                box.enterY = 0;
            }
            else if (variant === 3) {
                box.enterX = box.x > heroBox.x ? 30 : -30;
                box.enterY = 0;
            }
            else {
                box.enterX = 0;
                box.enterY = 20;
            }
        }
        column = 0;
        currentY = heroBox.y + heroBox.measuredHeight / 2 + stackGap;
        for (let i = heroIndex + 1; i < boxes.length; i++) {
            const box = boxes[i];
            if (currentY + box.measuredHeight > safeHalfH) {
                column += 1;
                currentY = -safeHalfH;
            }
            box.x = xFor(box, i) - column * columnStep;
            box.y = currentY + box.measuredHeight / 2;
            currentY += box.measuredHeight + stackGap;
            if (variant === 1) {
                box.enterX = -20;
                box.enterY = 0;
            }
            else if (variant === 3) {
                box.enterX = box.x > heroBox.x ? 30 : -30;
                box.enterY = 0;
            }
            else {
                box.enterX = 0;
                box.enterY = -20;
            }
        }
    });
};
exports.layoutQuietTableau = layoutQuietTableau;
const layoutTrackingRibbon = (ctx, variant) => {
    const { boxes, heroIndex, flowGap } = ctx;
    const heroBox = boxes[heroIndex];
    boxes.forEach(box => { box.layoutDirection = 'horizontal'; });
    (0, exports.placeWithGlobalFit)(ctx, () => {
        heroBox.x = 0;
        heroBox.y = 0;
        const alignY = (box, index) => (variant === 1
            ? heroBox.y + heroBox.measuredHeight / 2 - box.measuredHeight / 2
            : variant === 2
                ? heroBox.y - heroBox.measuredHeight / 2 + box.measuredHeight / 2
                : heroBox.y + (index % 2 === 0 ? 10 : -10));
        const enter = variant === 2 ? 20 : 30;
        let currentX = heroBox.x - heroBox.measuredWidth / 2 - flowGap;
        for (let i = heroIndex - 1; i >= 0; i--) {
            const box = boxes[i];
            box.x = currentX - box.measuredWidth / 2;
            box.y = alignY(box, i);
            currentX -= box.measuredWidth + flowGap;
            box.enterX = enter;
            box.enterY = 0;
        }
        currentX = heroBox.x + heroBox.measuredWidth / 2 + flowGap;
        for (let i = heroIndex + 1; i < boxes.length; i++) {
            const box = boxes[i];
            box.x = currentX + box.measuredWidth / 2;
            box.y = alignY(box, i);
            currentX += box.measuredWidth + flowGap;
            box.enterX = -enter;
            box.enterY = 0;
        }
    });
};
exports.layoutTrackingRibbon = layoutTrackingRibbon;
const layoutEditorialColumn = (ctx, variant, secondaryHeroIndex) => {
    const { boxes, heroIndex, width, height, flowGap, stackGap } = ctx;
    const heroBox = boxes[heroIndex];
    if (variant === 0) {
        boxes.forEach(box => { box.layoutDirection = 'vertical'; });
        (0, exports.placeWithGlobalFit)(ctx, () => {
            heroBox.x = -width * 0.15;
            heroBox.y = 0;
            let currentY = heroBox.y - heroBox.measuredHeight / 2 + stackGap * 0.5;
            for (let i = 0; i < heroIndex; i++) {
                const box = boxes[i];
                box.x = heroBox.x + heroBox.measuredWidth / 2 + flowGap + box.measuredWidth / 2;
                box.y = currentY + box.measuredHeight / 2;
                currentY += box.measuredHeight + stackGap;
                box.enterX = -20;
                box.enterY = 0;
            }
            currentY = heroBox.y - heroBox.measuredHeight / 2 + stackGap * 0.5;
            for (let i = heroIndex + 1; i < boxes.length; i++) {
                const box = boxes[i];
                box.x = heroBox.x - heroBox.measuredWidth / 2 - flowGap - box.measuredWidth / 2;
                box.y = currentY + box.measuredHeight / 2;
                currentY += box.measuredHeight + stackGap;
                box.enterX = 20;
                box.enterY = 0;
            }
        });
    }
    else if (variant === 1) {
        boxes.forEach(box => { box.layoutDirection = 'vertical'; });
        (0, exports.placeWithGlobalFit)(ctx, () => {
            const rightEdge = width * 0.28;
            const safeHalfH = height * 0.46;
            const railStep = Math.max(...boxes.map(box => box.measuredWidth)) + stackGap;
            const totalHeight = boxes.reduce((sum, box) => sum + box.measuredHeight, 0)
                + stackGap * (boxes.length - 1);
            const fitsSingleRail = boxes.reduce((sum, box) => sum + box.measuredHeight, 0) * 0.52
                + stackGap * (boxes.length - 1) <= safeHalfH * 2;
            if (fitsSingleRail) {
                let currentY = -totalHeight / 2;
                boxes.forEach(box => {
                    box.x = rightEdge - box.measuredWidth / 2;
                    box.y = currentY + box.measuredHeight / 2;
                    currentY += box.measuredHeight + stackGap;
                    box.enterX = 20;
                    box.enterY = 0;
                });
                return;
            }
            let rail = 0;
            let currentY = -safeHalfH;
            boxes.forEach(box => {
                if (currentY + box.measuredHeight > safeHalfH) {
                    rail += 1;
                    currentY = -safeHalfH;
                }
                box.x = (rightEdge - rail * railStep) - box.measuredWidth / 2;
                box.y = currentY + box.measuredHeight / 2;
                currentY += box.measuredHeight + stackGap;
                box.enterX = 20;
                box.enterY = 0;
            });
        });
    }
    else if (variant === 2) {
        boxes.forEach(box => { box.layoutDirection = 'horizontal'; });
        (0, exports.placeWithGlobalFit)(ctx, () => {
            var _a;
            heroBox.x = 0;
            heroBox.y = -height * 0.25;
            const before = boxes.slice(0, heroIndex);
            const after = boxes.slice(heroIndex + 1);
            if (before.length > 0) {
                const kickerHeight = Math.max(...before.map(box => box.measuredHeight));
                const kickerWidth = before.reduce((sum, box) => sum + box.measuredWidth, 0)
                    + flowGap * (before.length - 1);
                const kickerY = heroBox.y - heroBox.measuredHeight / 2 - stackGap - kickerHeight / 2;
                let currentX = heroBox.x - kickerWidth / 2;
                before.forEach(box => {
                    box.x = currentX + box.measuredWidth / 2;
                    box.y = kickerY;
                    currentX += box.measuredWidth + flowGap;
                    box.enterX = 0;
                    box.enterY = -20;
                });
            }
            const leftAnchor = heroBox.x - heroBox.measuredWidth * 0.25 - flowGap;
            const rightAnchor = heroBox.x + heroBox.measuredWidth * 0.25 + flowGap;
            let currentY = heroBox.y + heroBox.measuredHeight / 2 + stackGap;
            for (let pair = 0; pair < after.length; pair += 2) {
                const left = after[pair];
                const right = after[pair + 1];
                const rowHeight = Math.max(left.measuredHeight, (_a = right === null || right === void 0 ? void 0 : right.measuredHeight) !== null && _a !== void 0 ? _a : 0);
                left.x = leftAnchor - left.measuredWidth / 2;
                left.y = currentY + left.measuredHeight / 2;
                left.enterX = -20;
                left.enterY = 0;
                if (right) {
                    right.x = rightAnchor + right.measuredWidth / 2;
                    right.y = currentY + right.measuredHeight / 2;
                    right.enterX = 20;
                    right.enterY = 0;
                }
                currentY += rowHeight + stackGap;
            }
        });
    }
    else if (variant === 3) {
        boxes.forEach(box => { box.layoutDirection = 'horizontal'; });
        (0, exports.placeWithGlobalFit)(ctx, () => {
            heroBox.x = 0;
            heroBox.y = 0;
            const firstHero = Math.min(heroIndex, secondaryHeroIndex);
            const line1 = boxes.slice(0, firstHero + 1);
            const line2 = boxes.slice(firstHero + 1);
            const line1Height = Math.max(...line1.map(box => box.measuredHeight));
            const line2Height = Math.max(...line2.map(box => box.measuredHeight));
            const totalHeight = line1Height + stackGap + line2Height;
            const line1Y = heroBox.y - totalHeight / 2 + line1Height / 2;
            const line2Y = line1Y + line1Height / 2 + stackGap + line2Height / 2;
            const layLine = (line, lineY, enterX) => {
                const lineWidth = line.reduce((sum, box) => sum + box.measuredWidth, 0)
                    + flowGap * (line.length - 1);
                let currentX = -lineWidth / 2;
                line.forEach(box => {
                    box.x = currentX + box.measuredWidth / 2;
                    box.y = lineY;
                    currentX += box.measuredWidth + flowGap;
                    box.enterX = enterX;
                    box.enterY = 0;
                });
                return lineWidth;
            };
            const line1Width = layLine(line1, line1Y, 30);
            const line2Width = layLine(line2, line2Y, -30);
            const offsetAmount = Math.max(line1Width, line2Width) * 0.12;
            line1.forEach(box => { box.x -= offsetAmount; });
            line2.forEach(box => { box.x += offsetAmount; });
        });
    }
    else if (variant === 4) {
        boxes.forEach((box, index) => {
            box.layoutDirection = index === heroIndex ? 'vertical' : 'horizontal';
        });
        (0, exports.placeWithGlobalFit)(ctx, () => {
            const heroOnRight = heroIndex === boxes.length - 1;
            const blockLeft = -width * 0.40;
            const blockRight = width * 0.40;
            let currentY = -height * 0.34;
            const flowWords = (indices, regionFor) => {
                let [left, right] = regionFor(currentY);
                let currentX = left;
                let rowHeight = 0;
                indices.forEach(index => {
                    const box = boxes[index];
                    if (currentX > left && currentX + box.measuredWidth > right) {
                        currentY += rowHeight + stackGap;
                        [left, right] = regionFor(currentY);
                        currentX = left;
                        rowHeight = 0;
                    }
                    box.x = currentX + box.measuredWidth / 2;
                    box.y = currentY + box.measuredHeight / 2;
                    box.enterX = heroOnRight ? -25 : 25;
                    box.enterY = 0;
                    currentX += box.measuredWidth + flowGap;
                    rowHeight = Math.max(rowHeight, box.measuredHeight);
                });
                if (indices.length > 0)
                    currentY += rowHeight;
            };
            const beforeIndices = boxes.slice(0, heroIndex).map(box => box.index);
            const afterIndices = boxes.slice(heroIndex + 1).map(box => box.index);
            flowWords(beforeIndices, () => [blockLeft, blockRight]);
            currentY += stackGap;
            const pillarLeft = heroOnRight ? blockRight - heroBox.measuredWidth : blockLeft;
            heroBox.x = pillarLeft + heroBox.measuredWidth / 2;
            heroBox.y = currentY + heroBox.measuredHeight / 2;
            const pillarBottom = currentY + heroBox.measuredHeight + stackGap;
            const besideLeft = heroOnRight ? blockLeft : pillarLeft + heroBox.measuredWidth + flowGap;
            const besideRight = heroOnRight ? pillarLeft - flowGap : blockRight;
            flowWords(afterIndices, rowTop => (rowTop < pillarBottom - 0.5 ? [besideLeft, besideRight] : [blockLeft, blockRight]));
        });
    }
};
exports.layoutEditorialColumn = layoutEditorialColumn;
const layoutFragmentCollage = (ctx, variant) => {
    const { boxes, heroIndex, flowGap, stackGap } = ctx;
    const heroBox = boxes[heroIndex];
    const rectSeparation = (a, b) => Math.max(Math.max(a.left - b.right, b.left - a.right), Math.max(a.top - b.bottom, b.top - a.bottom));
    boxes.forEach((box, index) => {
        if (index === heroIndex)
            return;
        if (Math.abs(Math.round(box.rotation / (Math.PI / 2)) % 2) === 1) {
            const rotatedWidth = box.measuredHeight;
            box.measuredHeight = box.measuredWidth;
            box.measuredWidth = rotatedWidth;
        }
        box.rotation = 0;
    });
    (0, exports.placeWithGlobalFit)(ctx, (globalScale) => {
        heroBox.x = 0;
        heroBox.y = 0;
        const baseRadius = Math.hypot(heroBox.measuredWidth, heroBox.measuredHeight) / 2 + stackGap;
        const count = Math.max(1, boxes.length - 1);
        const squash = 0.65;
        const placed = [{
                left: heroBox.x - heroBox.measuredWidth / 2,
                right: heroBox.x + heroBox.measuredWidth / 2,
                top: heroBox.y - heroBox.measuredHeight / 2,
                bottom: heroBox.y + heroBox.measuredHeight / 2,
            }];
        let angle = Math.PI / 4;
        let supportIndex = 0;
        for (let i = 0; i < boxes.length; i++) {
            if (i === heroIndex)
                continue;
            const box = boxes[i];
            let radius = baseRadius;
            if (variant === 1) {
                radius += (35 + (supportIndex / count) * 150) * globalScale;
            }
            else if (variant === 2) {
                radius += ((supportIndex % 2 === 1) ? 140 : 50) * globalScale;
            }
            else {
                radius += (45 + ((supportIndex * 23) % 90)) * globalScale;
            }
            supportIndex += 1;
            let candidate = angle;
            let rect = { left: 0, right: 0, top: 0, bottom: 0 };
            let resolvedRadius = radius;
            let placedClear = false;
            for (let ring = 0; ring < 14 && !placedClear; ring += 1) {
                for (let attempt = 0; attempt < 400; attempt++) {
                    rect = {
                        left: Math.cos(candidate) * resolvedRadius - box.measuredWidth / 2,
                        right: Math.cos(candidate) * resolvedRadius + box.measuredWidth / 2,
                        top: Math.sin(candidate) * resolvedRadius * squash - box.measuredHeight / 2,
                        bottom: Math.sin(candidate) * resolvedRadius * squash + box.measuredHeight / 2,
                    };
                    if (placed.every(entry => rectSeparation(entry, rect) >= flowGap)) {
                        placedClear = true;
                        break;
                    }
                    candidate += 0.07;
                }
                if (!placedClear)
                    resolvedRadius += (36 + ring * 12) * globalScale;
            }
            angle = candidate + 0.02;
            placed.push(rect);
            box.x = heroBox.x + Math.cos(candidate) * resolvedRadius;
            box.y = heroBox.y + Math.sin(candidate) * resolvedRadius * squash;
            box.layoutDirection = Math.abs(Math.cos(candidate)) >= Math.abs(Math.sin(candidate))
                ? 'vertical'
                : 'horizontal';
            box.enterX = Math.cos(candidate) * -60;
            box.enterY = Math.sin(candidate) * -60;
        }
    });
};
exports.layoutFragmentCollage = layoutFragmentCollage;
const layoutCrossStack = (ctx) => {
    const { boxes, heroIndex, height, flowGap, stackGap } = ctx;
    const heroBox = boxes[heroIndex];
    const beforeCount = heroIndex;
    const topCount = Math.floor(beforeCount / 2);
    const afterCount = boxes.length - 1 - heroIndex;
    const rightCount = Math.ceil(afterCount / 2);
    const fillColumn = (column) => {
        if (column.length === 0)
            return 0;
        const available = Math.max(0, height * 0.46 - heroBox.measuredHeight / 2 - stackGap);
        if (available <= 0)
            return 0;
        const gaps = stackGap * (column.length - 1);
        const contentHeight = column.reduce((sum, box) => sum + box.measuredHeight, 0);
        const target = available * 0.72;
        if (contentHeight + gaps < target) {
            const boost = Math.min(2.2, (target - gaps) / Math.max(1, contentHeight));
            column.forEach(box => {
                const capped = Math.min(boost, (heroBox.fontScale * 0.6) / box.fontScale);
                if (capped > 1.05) {
                    box.fontScale *= capped;
                    box.measuredWidth *= capped;
                    box.measuredHeight *= capped;
                }
            });
        }
        if (column.length < 2)
            return 0;
        const grown = column.reduce((sum, box) => sum + box.measuredHeight, 0);
        const pitch = (available * 0.95 - grown) / (column.length - 1);
        return Math.max(0, Math.min(stackGap * 2, pitch - stackGap));
    };
    (0, exports.placeWithGlobalFit)(ctx, () => {
        heroBox.x = 0;
        heroBox.y = 0;
        const topStretch = fillColumn(boxes.slice(0, topCount));
        const bottomStretch = fillColumn(boxes.slice(heroIndex + rightCount + 1));
        let currentX = heroBox.x - heroBox.measuredWidth / 2 - stackGap;
        for (let i = heroIndex - 1; i >= topCount; i--) {
            const box = boxes[i];
            box.layoutDirection = 'horizontal';
            box.x = currentX - box.measuredWidth / 2;
            box.y = heroBox.y + (i % 2 === 0 ? 10 : -10);
            currentX -= box.measuredWidth + flowGap;
            box.enterX = -30;
            box.enterY = 0;
        }
        let currentY = heroBox.y - heroBox.measuredHeight / 2 - stackGap;
        for (let i = topCount - 1; i >= 0; i--) {
            const box = boxes[i];
            box.layoutDirection = 'vertical';
            box.x = heroBox.x + (i % 2 === 0 ? 15 : -15);
            box.y = currentY - box.measuredHeight / 2;
            currentY -= box.measuredHeight + stackGap + topStretch;
            box.enterX = 0;
            box.enterY = -30;
        }
        currentX = heroBox.x + heroBox.measuredWidth / 2 + stackGap;
        for (let i = heroIndex + 1; i <= heroIndex + rightCount; i++) {
            const box = boxes[i];
            box.layoutDirection = 'horizontal';
            box.x = currentX + box.measuredWidth / 2;
            box.y = heroBox.y + (i % 2 === 0 ? 10 : -10);
            currentX += box.measuredWidth + flowGap;
            box.enterX = 30;
            box.enterY = 0;
        }
        currentY = heroBox.y + heroBox.measuredHeight / 2 + stackGap;
        for (let i = heroIndex + rightCount + 1; i < boxes.length; i++) {
            const box = boxes[i];
            box.layoutDirection = 'vertical';
            box.x = heroBox.x + (i % 2 === 0 ? 15 : -15);
            box.y = currentY + box.measuredHeight / 2;
            currentY += box.measuredHeight + stackGap + bottomStretch;
            box.enterX = 0;
            box.enterY = 30;
        }
    });
};
exports.layoutCrossStack = layoutCrossStack;

},
"sonnet/sonnetPosterBlocksLayout":function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.layoutSonnetPosterBlocks = void 0;
const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
const partitionFlowItems = (boxes) => {
    const items = [];
    let group = [];
    boxes.forEach(box => {
        if (box.isHero || box.isSemiHero) {
            if (group.length > 0)
                items.push({ kind: 'group', group });
            group = [];
            items.push({ kind: 'zone', zone: box });
        }
        else {
            group.push(box);
        }
    });
    if (group.length > 0)
        items.push({ kind: 'group', group });
    return items;
};
const flowToScreen = (space, rect, canvas) => {
    if (space.orientation === 'horizontal') {
        return {
            x: canvas.x + rect.u,
            y: canvas.y + rect.v,
            width: rect.uSize,
            height: rect.vSize,
        };
    }
    return {
        x: canvas.x + canvas.width - rect.v - rect.vSize,
        y: canvas.y + rect.u,
        width: rect.vSize,
        height: rect.uSize,
    };
};
const attemptFlowLayout = (boxes, space, globalScale, chipGap, lineGap, seed) => {
    const items = partitionFlowItems(boxes);
    const placements = [];
    const floats = [];
    let vCursor = 0;
    let ownBandOnEndSide = ((seed >> 1) & 1) === 1;
    const measure = (box) => {
        const useVertical = space.orientation === 'vertical'
            && typeof box.verticalMeasuredWidth === 'number'
            && typeof box.verticalMeasuredHeight === 'number'
            && typeof box.verticalFontScale === 'number';
        const baseScale = useVertical ? box.verticalFontScale : box.fontScale;
        const width = (useVertical ? box.verticalMeasuredWidth : box.measuredWidth) * globalScale;
        const height = (useVertical ? box.verticalMeasuredHeight : box.measuredHeight) * globalScale;
        return { useVertical, baseScale, width, height };
    };
    const toFlowSize = (width, height) => (space.orientation === 'horizontal'
        ? { uSize: width, vSize: height }
        : { uSize: height, vSize: width });
    const pruneFloats = () => {
        for (let index = floats.length - 1; index >= 0; index--) {
            if (floats[index].vBottom <= vCursor)
                floats.splice(index, 1);
        }
    };
    items.forEach((item, itemIndex) => {
        var _a;
        pruneFloats();
        if (item.kind === 'group') {
            const reservedU = floats.reduce((sum, entry) => sum + entry.extent, 0);
            const capacity = Math.max(chipGap * 2, space.u - reservedU);
            const uStart = reservedU;
            const chips = item.group.map(box => {
                const dims = measure(box);
                const flow = toFlowSize(dims.width, dims.height);
                return { box, dims, uSize: flow.uSize, vSize: flow.vSize, shrink: 1 };
            });
            let line = [];
            let lineUsedU = 0;
            const flushLine = () => {
                if (line.length === 0)
                    return;
                const lineV = Math.max(...line.map(chip => chip.vSize * chip.shrink));
                const leftover = capacity - lineUsedU;
                const spread = line.length > 1 && leftover > 0
                    ? Math.min(leftover / (line.length - 1), chipGap * 2.5)
                    : 0;
                let uCursor = uStart;
                line.forEach(chip => {
                    const finalScale = chip.dims.baseScale * globalScale * chip.shrink;
                    placements.push({
                        box: chip.box,
                        rect: {
                            u: uCursor,
                            v: vCursor,
                            uSize: chip.uSize * chip.shrink,
                            vSize: chip.vSize * chip.shrink,
                        },
                        scale: finalScale,
                        vertical: chip.dims.useVertical,
                    });
                    uCursor += chip.uSize * chip.shrink + chipGap + spread;
                });
                vCursor += lineV + lineGap;
                pruneFloats();
                line = [];
                lineUsedU = 0;
            };
            chips.forEach(chip => {
                const needed = lineUsedU + (line.length > 0 ? chipGap : 0) + chip.uSize;
                if (needed > capacity && line.length > 0)
                    flushLine();
                if (chip.uSize > capacity) {
                    chip.shrink = Math.max(0.5, capacity / chip.uSize);
                    lineUsedU = 0;
                    line.push(chip);
                    flushLine();
                    return;
                }
                lineUsedU += (line.length > 0 ? chipGap : 0) + chip.uSize;
                line.push(chip);
            });
            flushLine();
            return;
        }
        const zone = item.zone;
        vCursor = Math.max(vCursor, ...floats.map(entry => entry.vBottom), 0);
        floats.length = 0;
        const dims = measure(zone);
        const flow = toFlowSize(dims.width, dims.height);
        const followedByGroup = ((_a = items[itemIndex + 1]) === null || _a === void 0 ? void 0 : _a.kind) === 'group';
        const zoneShrink = Math.min(1, (space.u * (followedByGroup ? 0.62 : 0.9)) / flow.uSize, (space.v * 0.66) / flow.vSize);
        const uSize = flow.uSize * zoneShrink;
        const vSize = flow.vSize * zoneShrink;
        const onlyZone = items.length === 1;
        const u = onlyZone
            ? (space.u - uSize) / 2
            : followedByGroup
                ? 0
                : ownBandOnEndSide
                    ? space.u - uSize
                    : 0;
        placements.push({
            box: zone,
            rect: { u, v: vCursor, uSize, vSize },
            scale: dims.baseScale * globalScale * zoneShrink,
            vertical: dims.useVertical,
        });
        if (followedByGroup) {
            floats.push({ extent: uSize + chipGap, vBottom: vCursor + vSize + lineGap });
        }
        else {
            vCursor += vSize + lineGap;
            ownBandOnEndSide = !ownBandOnEndSide;
        }
    });
    const vTotal = placements.reduce((max, placement) => (Math.max(max, placement.rect.v + placement.rect.vSize)), 0);
    return { placements, vTotal };
};
const layoutSonnetPosterBlocks = (boxes, width, height, baseFontSize, seed = 0) => {
    if (boxes.length === 0)
        return { placements: [], width: 0, height: 0, gap: 0 };
    const gap = clamp(baseFontSize * 0.35, 16, 40);
    const chipGap = gap;
    const lineGap = gap * 1.15;
    const canvas = {
        x: -width * 0.42,
        y: -height * 0.40,
        width: width * 0.84,
        height: height * 0.80,
    };
    const orientation = (seed % 2 === 0) ? 'horizontal' : 'vertical';
    const space = orientation === 'horizontal'
        ? { orientation, u: canvas.width, v: canvas.height }
        : { orientation, u: canvas.height, v: canvas.width };
    let attempt = attemptFlowLayout(boxes, space, 1, chipGap, lineGap, seed);
    for (const globalScale of [0.92, 0.84, 0.76, 0.68, 0.6, 0.52]) {
        if (attempt.vTotal <= space.v + 0.5)
            break;
        attempt = attemptFlowLayout(boxes, space, globalScale, chipGap, lineGap, seed);
    }
    if (attempt.vTotal > space.v) {
        const fitScale = space.v / attempt.vTotal;
        attempt.placements.forEach(placement => {
            placement.rect.u *= fitScale;
            placement.rect.v *= fitScale;
            placement.rect.uSize *= fitScale;
            placement.rect.vSize *= fitScale;
            placement.scale *= fitScale;
        });
        attempt.vTotal = space.v;
    }
    const vShift = Math.max(0, (space.v - attempt.vTotal) / 2);
    attempt.placements.forEach(placement => {
        const { box } = placement;
        const rect = Object.assign(Object.assign({}, placement.rect), { v: placement.rect.v + vShift });
        const screen = flowToScreen(space, rect, canvas);
        box.fontScale = placement.scale;
        box.measuredWidth = screen.width;
        box.measuredHeight = screen.height;
        box.x = screen.x + screen.width / 2;
        box.y = screen.y + screen.height / 2;
        box.rotation = 0;
        box.vertical = placement.vertical;
        if (placement.vertical && box.verticalDisplayText)
            box.displayText = box.verticalDisplayText;
        box.layoutDirection = orientation === 'vertical' ? 'vertical' : 'horizontal';
        if (orientation === 'horizontal') {
            box.enterX = (screen.x + screen.width / 2 < 0 ? -1 : 1) * Math.min(28, baseFontSize * 0.45);
            box.enterY = Math.min(18, baseFontSize * 0.25);
        }
        else {
            box.enterX = Math.min(18, baseFontSize * 0.25);
            box.enterY = (screen.y + screen.height / 2 < 0 ? -1 : 1) * Math.min(28, baseFontSize * 0.45);
        }
    });
    return { placements: boxes, width: canvas.width, height: canvas.height, gap };
};
exports.layoutSonnetPosterBlocks = layoutSonnetPosterBlocks;

}
};
var cache={};
function require(id){if(cache[id])return cache[id].exports;var m={exports:{}};cache[id]=m;factories[id](require,m,m.exports);return m.exports;}
// Graphics command recorder: original procedural functions -> Qt Quick Shapes.
// Kept separate from the generated bundle so re-imports are reproducible.
function vec(owner,xKey,yKey){return {set:function(x,y){owner[xKey]=x;owner[yKey]=y===undefined?x:y}}}
function Graphics(){this.paths=[];this.pending='';this.x=0;this.y=0;this.px=0;this.py=0;this.sx=1;this.sy=1;this.rotation=0;this.alpha=1;this.visible=true;this.parent=null;this.position=vec(this,'x','y');this.pivot=vec(this,'px','py');this.scale=vec(this,'sx','sy');}
Graphics.prototype.moveTo=function(x,y){this.pending+='M'+x+' '+y;return this;};
Graphics.prototype.lineTo=function(x,y){this.pending+='L'+x+' '+y;return this;};
Graphics.prototype.poly=function(p){if(p.length){this.moveTo(p[0],p[1]);for(var i=2;i<p.length;i+=2)this.lineTo(p[i],p[i+1]);this.pending+='Z';}return this;};
Graphics.prototype.rect=function(x,y,w,h){return this.poly([x,y,x+w,y,x+w,y+h,x,y+h]);};
Graphics.prototype.circle=function(x,y,r){this.pending+='M'+(x-r)+' '+y+'a'+r+' '+r+' 0 1 0 '+(2*r)+' 0a'+r+' '+r+' 0 1 0 '+(-2*r)+' 0Z';return this;};
Graphics.prototype.fill=function(spec){this.paths.push({path:this.pending,fill:spec.color,alpha:spec.alpha===undefined?1:spec.alpha,stroke:'transparent',strokeWidth:0});this.pending='';return this;};
Graphics.prototype.stroke=function(spec){this.paths.push({path:this.pending,fill:'transparent',alpha:spec.alpha===undefined?1:spec.alpha,stroke:spec.color,strokeWidth:spec.width||1});this.pending='';return this;};
Graphics.prototype.cut=function(){if(this.paths.length)this.paths[this.paths.length-1].path+=this.pending;this.pending='';return this;};
function Container(){Graphics.call(this);this.children=[];}
Container.prototype.addChild=function(child){child.parent=this;this.children.push(child);return child;};
function colorString(value){if(typeof value==='number')return '#'+value.toString(16).padStart(6,'0');var match=String(value).match(/^rgba?\(([^)]+)\)$/);if(match){var parts=match[1].split(',').map(Number);return '#'+Math.round((parts.length>3?parts[3]:1)*255).toString(16).padStart(2,'0')+parts.slice(0,3).map(function(n){return Math.round(n).toString(16).padStart(2,'0');}).join('');}return value||'#ffffff';}
var nativeGraphics={Graphics:Graphics,Container:Container,Color:{shared:{value:'#fff',setValue:function(c){this.value=c;return this;},toNumber:function(){return this.value;}}}};
function kinds(){return Object.keys(require('tempera/temperaShotProfiles').TEMPERA_SHOT_PROFILES);}
function hash(text){var h=2166136261;for(var i=0;i<text.length;i++){h^=text.charCodeAt(i);h=Math.imul(h,16777619);}return h>>>0;}
function build(seedText,line,width,height){
    var seed=hash(seedText+':'+line),keys=kinds(),kind=keys[seed%keys.length];
    var palette={paper:'#202a32',ink:'#ebdac4',tone1:'#2f4651',tone2:'#5b6971',tone3:'#877565',tone4:'#d4bc9d',accent:'#c39578'};
    var profile=require('tempera/temperaShotProfiles').TEMPERA_SHOT_PROFILES[kind];
    var view=require('tempera/temperaBlocks').buildTemperaBlocks(nativeGraphics,{kind:kind,seed:seed,palette:palette,width:width,height:height,flowAngle:Math.PI/2+.12,showDecor:true,decor:{motif:'diamonds',hatchAngle:.6,scribbleSeed:seed}});
    var records=[];function walk(item){if(item.paths)for(var i=0;i<item.paths.length;i++){var p=item.paths[i];records.push({owner:item,path:p.path,fill:colorString(p.fill),stroke:colorString(p.stroke),strokeWidth:p.strokeWidth,alpha:p.alpha});}if(item.children)item.children.forEach(walk);}
    walk(view.container);
    return {kind:kind,profile:profile,records:records,update:view.updateTime};
}
function frame(record){var n=record.owner,angle=n.rotation,scaleX=n.sx,scaleY=n.sy,c=Math.cos(angle),s=Math.sin(angle),x=n.x-n.px*scaleX*c+n.py*scaleY*s,y=n.y-n.px*scaleX*s-n.py*scaleY*c,alpha=n.alpha*record.alpha;var p=n.parent;while(p){c=Math.cos(p.rotation);s=Math.sin(p.rotation);var nx=(x-p.px)*p.sx,ny=(y-p.py)*p.sy;x=nx*c-ny*s+p.x;y=nx*s+ny*c+p.y;angle+=p.rotation;scaleX*=p.sx;scaleY*=p.sy;alpha*=p.alpha;p=p.parent;}return {x:x,y:y,rotation:angle*180/Math.PI,sx:scaleX,sy:scaleY,alpha:alpha};}
function sonnetLayout(units,kind,seedText,width,height){
    if(!units.length)return [];
    var boxes=units.map(function(unit,i){var box=Object.assign({},unit);box.index=i;box.isHero=i===Math.floor(units.length/2);box.isSemiHero=units.length>3&&i===0;box.fontScale=box.isHero?1.65:box.isSemiHero?1.12:.85;box.measuredWidth*=box.fontScale;box.measuredHeight*=box.fontScale;box.vertical=false;box.layoutDirection='horizontal';box.rotation=0;box.x=0;box.y=0;box.enterX=0;box.enterY=0;return box;});
    var lib=require('sonnet/sonnetShotFlowLayouts'),gaps=lib.resolveSonnetFlowGaps(units[0].fontSize),variant=hash(seedText+units[0].displayText)%4;
    var ctx={boxes:boxes,heroIndex:Math.floor(boxes.length/2),width:width*.88,height:height*.7,flowGap:gaps.flowGap,stackGap:gaps.stackGap};
    if(kind==='editorial-column')lib.layoutEditorialColumn(ctx,boxes.length===1?0:hash(seedText+units[0].displayText)%5,0);
    else if(kind==='tracking-ribbon')lib.layoutTrackingRibbon(ctx,variant%3);
    else if(kind==='fragment-collage')lib.layoutFragmentCollage(ctx,variant%3);
    else if(kind==='type-impact'||kind==='mask-reveal')lib.layoutCrossStack(ctx);
    else if(kind==='poster-blocks')boxes=require('sonnet/sonnetPosterBlocksLayout').layoutSonnetPosterBlocks(boxes,ctx.width,ctx.height,units[0].fontSize,variant).placements;
    else lib.layoutQuietTableau(ctx,variant);
    return boxes;
}
