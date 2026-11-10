// Shared by Settings and the desktop preview. IDs are persisted; labels are UI only.
var transitions = [
    { id: "none", label: "No transition" }, { id: "simple", label: "Gentle fade" },
    { id: "fade", label: "Smooth crossfade" }, { id: "left", label: "Slide from left" },
    { id: "right", label: "Slide from right" }, { id: "top", label: "Slide from top" },
    { id: "bottom", label: "Slide from bottom" }, { id: "wipe", label: "Diagonal wipe" },
    { id: "wave", label: "Flowing wave" }, { id: "grow", label: "Point expansion" },
    { id: "center", label: "Expand from center" }, { id: "outer", label: "Contract inward" },
    { id: "any", label: "Random expansion" }, { id: "random", label: "Random effect" },
    { id: "cinematic", label: "Soft reveal" }
];
var intervals = [
    { minutes: 1, label: "Every minute" }, { minutes: 5, label: "Every 5 minutes" },
    { minutes: 15, label: "Every 15 minutes" }, { minutes: 30, label: "Every 30 minutes" },
    { minutes: 60, label: "Every hour" }, { minutes: 1440, label: "Every day" }
];
// Curated presets have distinct hue routes and brightness ranges. The base
// remains the picker identity; arbitrary custom colors use the adaptive recipe.
// Stops: upper, middle, lower, left accent, right accent.
var colorSwatches = [
    {title:"Cyan blue", color:"#4BCDE9", angle:105, stops:["#205A9C","#39B7D2","#8AE7CA","#5F81DA","#4EDABB"]},
    {title:"Clear sky", color:"#70A0F5", angle:90, stops:["#5143AE","#628BEE","#8FDDF6","#C68DDC","#69CFF3"]},
    {title:"Lavender", color:"#AD8CED", angle:110, stops:["#765DA6","#B99BE6","#EDDAF3","#DBA4C5","#A5BFE8"]},
    {title:"Orchid purple", color:"#CE54E9", angle:75, stops:["#45218C","#A346C5","#F392CA","#7249B9","#DE64BC"]},
    {title:"Rose", color:"#E86C99", angle:110, stops:["#8D2C61","#DE699D","#FFD0C1","#BD7C9F","#F3A38D"]},
    {title:"Coral", color:"#FA8D7E", angle:70, stops:["#BE3B45","#F67A65","#FFCD8C","#E36581","#FFB370"]},
    {title:"Peach", color:"#FFA77D", angle:90, stops:["#D59A91","#FFD1AF","#FFF0D2","#E9B8CE","#F8D596"]},
    {title:"Cream apricot", color:"#FFCA7E", angle:100, stops:["#AA7463","#EBC398","#F6E9CF","#D1AD9B","#F5D7A4"]},
    {title:"Golden yellow", color:"#FFDD78", angle:80, stops:["#A65A17","#EBA72F","#FFE4A0","#D97B25","#F5C259"]},
    {title:"Lemon", color:"#FFFA8A", angle:110, stops:["#AFB144","#F1EB77","#FAFBCB","#B6D584","#FFF099"]},
    {title:"Lime", color:"#E3EF89", angle:70, stops:["#6D9631","#B9D95D","#E8F2A9","#E1D45C","#93CE74"]},
    {title:"Spring green", color:"#B1D98A", angle:95, stops:["#1D6E4C","#4AAC76","#BAE9B5","#599469","#73C8A6"]},
    {title:"Sage", color:"#B2C2A6", angle:90, stops:["#3F675B","#85AD94","#C7DDAD","#5E9278","#B1C298"]},
    {title:"Misty blue", color:"#9EB7BF", angle:115, stops:["#4D718A","#92AEBE","#D5E3E8","#94A6C2","#94B8B9"]},
    {title:"Misty purple", color:"#B4A7B8", angle:75, stops:["#715775","#B197B3","#E8D9DF","#CAA7BC","#B1AAC8"]},
    {title:"Warm gray", color:"#B7AFA4", angle:90, stops:["#72675B","#B3A796","#E7DECF","#AC9B91","#C4BCA7"]},
    {title:"Moon white", color:"#FFFFFF"}, {title:"Night", color:"#000000"}
];
// Perceptual palette construction; Oklab matrices from Björn Ottosson:
// https://bottosson.github.io/posts/oklab/ (sRGB, D65).
function colorLch(hex) {
    var n = parseInt(hex.slice(1), 16);
    var rgb = [n >> 16 & 255, n >> 8 & 255, n & 255].map(value => {
        var c = value / 255;
        return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    });
    var r = rgb[0], g = rgb[1], b = rgb[2];
    var l = Math.cbrt(0.4122214708*r + 0.5363325363*g + 0.0514459929*b);
    var m = Math.cbrt(0.2119034982*r + 0.6806995451*g + 0.1073969566*b);
    var s = Math.cbrt(0.0883024619*r + 0.2817188376*g + 0.6299787005*b);
    var aa = 1.9779984951*l - 2.4285922050*m + 0.4505937099*s;
    var bb = 0.0259040371*l + 0.7827717662*m - 0.8086757660*s;
    return {l: 0.2104542553*l + 0.7936177850*m - 0.0040720468*s,
        c: Math.sqrt(aa*aa + bb*bb), h: (Math.atan2(bb, aa)*180/Math.PI + 360)%360};
}
function lchHex(lightness, chroma, hue) {
    var radians = hue*Math.PI/180;
    function linearRgb(scale) {
        var a = Math.cos(radians)*chroma*scale, b = Math.sin(radians)*chroma*scale;
        var l = Math.pow(lightness + 0.3963377774*a + 0.2158037573*b, 3);
        var m = Math.pow(lightness - 0.1055613458*a - 0.0638541728*b, 3);
        var s = Math.pow(lightness - 0.0894841775*a - 1.2914855480*b, 3);
        return [4.0767416621*l - 3.3077115913*m + 0.2309699292*s,
            -1.2684380046*l + 2.6097574011*m - 0.3413193965*s,
            -0.0041960863*l - 0.7034186147*m + 1.7076147010*s];
    }
    var rgb = linearRgb(1);
    if (rgb.some(c => c < -0.000001 || c > 1.000001)) {
        var low = 0, high = 1;
        for (var i = 0; i < 14; ++i) {
            var scale = (low + high)/2;
            if (linearRgb(scale).every(c => c >= -0.000001 && c <= 1.000001)) low = scale;
            else high = scale;
        }
        rgb = linearRgb(low);
    }
    return "#" + rgb.map(c => {
        c = Math.max(0, Math.min(1, c));
        c = c <= 0.0031308 ? 12.92*c : 1.055*Math.pow(c, 1/2.4) - 0.055;
        return Math.round(c*255).toString(16).padStart(2, "0");
    }).join("").toUpperCase();
}
function colorGradient(base, depth) {
    var color = colorLch(base);
    var level = Number(depth);
    level = isFinite(level) ? Math.max(0, Math.min(1, level)) : 0.5;
    var preset = colorSwatches.find(item => item.color.toUpperCase() === base.toUpperCase());
    if (preset && preset.stops) {
        var stops = preset.stops.map(hex => {
            if (level === 0.5) return hex;
            var stop = colorLch(hex);
            return lchHex(Math.max(0.15, Math.min(0.98, stop.l + (0.5-level)*0.10)),
                stop.c*(0.82+0.36*level), stop.h);
        });
        return {base: base, start: stops[0], end: stops[2], angle: preset.angle,
            colors: [stops[1], stops[3], stops[4]]};
    }
    if (color.c < 0.018 && color.l > 0.95) {
        return {base: base, start: lchHex(0.93 - 0.07*level, 0, 0),
            end: lchHex(0.995 - 0.01*level, 0, 0), angle: 90};
    }
    if (color.l < 0.18) {
        return {base: base, start: lchHex(0.25 - 0.06*level, color.c*0.5, color.h),
            end: lchHex(0.13 - 0.04*level, color.c*0.3, color.h), angle: 90};
    }
    // Different hue families need different shifts: violet-to-sky blues,
    // rose-to-peach reds, amber-to-cream yellows and teal-to-mint greens.
    // Interpolate the art direction so custom colors have no sector seams.
    var families = [[0,-36,50], [60,-40,38], [110,-38,32],
        [160,35,-32], [210,42,-35], [270,38,-42], [320,28,-40], [360,-36,50]];
    var topShift = 0, bottomShift = 0;
    for (var i = 1; i < families.length; ++i) {
        if (color.h <= families[i][0]) {
            var left = families[i-1], right = families[i];
            var t = (color.h-left[0])/(right[0]-left[0]);
            topShift = left[1] + (right[1]-left[1])*t;
            bottomShift = left[2] + (right[2]-left[2])*t;
            break;
        }
    }
    var neutral = color.c < 0.018;
    var topL = Math.max(0.30, Math.min(0.82, color.l - 0.035 - 0.13*level));
    var bottomL = Math.max(topL + 0.12, Math.min(0.97, 0.80 + color.l*0.10 - 0.035*level));
    var topC = neutral ? color.c : Math.max(0.045, color.c)*(0.94 + 0.22*level);
    var bottomC = neutral ? color.c*0.5 : Math.max(0.035, color.c)*(0.76 + 0.20*level);
    var midL = Math.max(topL + 0.07, Math.min(0.80, color.l + 0.035));
    var midC = Math.max(0.075, color.c)*(1.0 + 0.18*level);
    // Independent middle and side colors survive the bridge and cache. The
    // accents occupy broad, different regions instead of bleaching one ramp.
    var colors = neutral ? [] : [
        lchHex(midL, midC, color.h),
        lchHex(Math.min(0.84, midL + 0.07), midC*0.88, color.h + topShift*1.9),
        lchHex(Math.min(0.89, midL + 0.12), midC*0.78, color.h + bottomShift*1.7)
    ];
    return {base: base, start: lchHex(topL, topC, color.h + (neutral ? 0 : topShift)),
        end: lchHex(bottomL, bottomC, color.h + (neutral ? 0 : bottomShift)), angle: 90,
        colors: colors};
}
var palettes = colorSwatches.map(item => {
    var gradient = colorGradient(item.color, 0.5);
    gradient.title = item.title;
    return gradient;
});
function resolvedTransition(style, seed) {
    var value = Math.abs(Number(seed) || 0);
    if (style === "random") {
        var choices = ["none", "cinematic", "simple", "fade", "left", "right", "top", "bottom", "wipe", "wave", "grow", "center", "outer"];
        return choices[Math.floor(value * 997) % choices.length];
    }
    if (style === "any") return Math.floor(value * 991) % 2 ? "grow" : "outer";
    return style;
}

function colorPreview(start, end, angle, width, height) {
    if (!/^#[0-9a-fA-F]{6}$/.test(start) || !/^#[0-9a-fA-F]{6}$/.test(end)) return "";
    var radians = angle * Math.PI / 180;
    var x = Math.cos(radians), y = Math.sin(radians);
    var extent = Math.abs(x) * width / 2 + Math.abs(y) * height / 2;
    var svg = '<svg xmlns="http://www.w3.org/2000/svg" width="' + width + '" height="' + height + '"><defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="'
        + (width / 2 - x * extent) + '" y1="' + (height / 2 - y * extent) + '" x2="'
        + (width / 2 + x * extent) + '" y2="' + (height / 2 + y * extent)
        + '"><stop stop-color="' + start + '"/><stop offset="1" stop-color="' + end
        + '"/></linearGradient></defs><rect width="' + width + '" height="' + height + '" rx="12" fill="url(#g)"/></svg>';
    return "data:image/svg+xml;utf8," + encodeURIComponent(svg);
}

// Each named effect is ready to use; old user-tuned values do not alter it.
function transitionPreset(style) {
    return { angle: 45, waveWidth: 0.22, waveHeight: 0.08,
        positionX: style === "grow" ? 0.28 : 0.5,
        positionY: style === "grow" ? 0.62 : 0.5 };
}

// Stable theme IDs shared by Settings and the desktop renderer.
var themes = [
    { id: "starfield", label: "Stardust Gravity", detail: "Gravitational particles, turbulent nebulae and layered halos", accent: "#729bda" },
    { id: "blackhole", label: "Event Horizon", detail: "Bent light, a glowing accretion disk and layered particle trails", accent: "#e5a568" },
    { id: "weather", label: "Atmospheric Light", detail: "Volumetric scattering, airflow and rain particles", accent: "#7abbd6" },
    { id: "underwater", label: "Underwater Light", detail: "Flowing caustics, underwater rays and rising bubbles", accent: "#55c9c3" },
    { id: "forest", label: "Firefly Forest", detail: "Moonlit mist, layered trees and foreground fireflies", accent: "#b5ce75" }
];
function theme(id) { return themes.find(item => item.id === id) || null; }
