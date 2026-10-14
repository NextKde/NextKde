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
var colorSwatches = [
    {title:"Cyan blue", color:"#4BCDE9"}, {title:"Clear sky", color:"#70A0F5"},
    {title:"Lavender", color:"#AD8CED"}, {title:"Orchid purple", color:"#CE54E9"},
    {title:"Rose", color:"#E86C99"}, {title:"Coral", color:"#FA8D7E"},
    {title:"Peach", color:"#FFA77D"}, {title:"Cream apricot", color:"#FFCA7E"},
    {title:"Golden yellow", color:"#FFDD78"}, {title:"Lemon", color:"#FFFA8A"},
    {title:"Lime", color:"#E3EF89"}, {title:"Spring green", color:"#B1D98A"},
    {title:"Sage", color:"#B2C2A6"}, {title:"Misty blue", color:"#9EB7BF"},
    {title:"Misty purple", color:"#B4A7B8"}, {title:"Warm gray", color:"#B7AFA4"},
    {title:"Moon white", color:"#FFFFFF"}, {title:"Night", color:"#000000"}
];
function hsvHex(h, s, v) {
    h = ((h % 1) + 1) % 1;
    s = Math.max(0, Math.min(1, s)); v = Math.max(0, Math.min(1, v));
    var i = Math.floor(h * 6), f = h * 6 - i;
    var p = v * (1-s), q = v * (1-f*s), t = v * (1-(1-f)*s);
    var rgb = [[v,t,p],[q,v,p],[p,v,t],[p,q,v],[t,p,v],[v,p,q]][i % 6];
    return "#" + rgb.map(x => Math.round(x * 255).toString(16).padStart(2,"0")).join("").toUpperCase();
}
function colorGradient(base, depth) {
    var n = parseInt(base.slice(1),16);
    var r = (n >> 16 & 255)/255, g = (n >> 8 & 255)/255, b = (n & 255)/255;
    var v = Math.max(r,g,b), min = Math.min(r,g,b), d = v-min, h = 0;
    if (d) h = (((v===r ? (g-b)/d : v===g ? (b-r)/d+2 : (r-g)/d+4)/6)+1)%1;
    var sat = v ? d/v : 0, level = Math.max(0, Math.min(1, Number(depth)));
    var start, end;
    if (v < 0.08) {
        start = hsvHex(h, sat, 0.08+0.14*(1-level));
        end = hsvHex(h, sat, 0.025+0.025*(1-level));
    } else {
        // Blue shades lean gently towards lavender at the top, as on iOS.
        var topHue = h + (h > 0.48 && h < 0.78 ? 0.075 : -0.015);
        start = hsvHex(topHue, sat * (0.4+0.35*level), Math.max(0.12, v*(0.9-0.22*level)));
        end = hsvHex(h, sat*(0.3+0.7*level), Math.min(1, v+(1-v)*0.55)*(1-level*0.04));
    }
    return {base:base, start:start, end:end, angle:90};
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
