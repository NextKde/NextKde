// Shared by Settings and the desktop preview. IDs are persisted; labels are UI only.
var transitions = [
    { id: "none", label: "无过渡" }, { id: "simple", label: "轻柔淡入" },
    { id: "fade", label: "平滑淡入淡出" }, { id: "left", label: "从左滑入" },
    { id: "right", label: "从右滑入" }, { id: "top", label: "从上滑入" },
    { id: "bottom", label: "从下滑入" }, { id: "wipe", label: "斜向擦除" },
    { id: "wave", label: "波浪漫入" }, { id: "grow", label: "定点扩散" },
    { id: "center", label: "中心展开" }, { id: "outer", label: "向内收拢" },
    { id: "any", label: "随机扩散" }, { id: "random", label: "随机效果" },
    { id: "cinematic", label: "柔和揭幕" }
];
var intervals = [
    { minutes: 1, label: "每分钟" }, { minutes: 5, label: "每 5 分钟" },
    { minutes: 15, label: "每 15 分钟" }, { minutes: 30, label: "每 30 分钟" },
    { minutes: 60, label: "每小时" }, { minutes: 1440, label: "每天" }
];
var colorSwatches = [
    {title:"青蓝", color:"#4BCDE9"}, {title:"晴空", color:"#70A0F5"},
    {title:"薰衣草", color:"#AD8CED"}, {title:"兰紫", color:"#CE54E9"},
    {title:"玫瑰", color:"#E86C99"}, {title:"珊瑚", color:"#FA8D7E"},
    {title:"蜜桃", color:"#FFA77D"}, {title:"奶杏", color:"#FFCA7E"},
    {title:"金黄", color:"#FFDD78"}, {title:"柠檬", color:"#FFFA8A"},
    {title:"青柠", color:"#E3EF89"}, {title:"嫩绿", color:"#B1D98A"},
    {title:"鼠尾草", color:"#B2C2A6"}, {title:"雾蓝", color:"#9EB7BF"},
    {title:"雾紫", color:"#B4A7B8"}, {title:"暖灰", color:"#B7AFA4"},
    {title:"月白", color:"#FFFFFF"}, {title:"夜色", color:"#000000"}
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
    { id: "starfield", label: "星尘引力", detail: "引力粒子、湍流星云与多尺度光晕", accent: "#729bda" },
    { id: "blackhole", label: "事件视界", detail: "光线偏折、炽热吸积盘与跨层粒子轨迹", accent: "#e5a568" },
    { id: "weather", label: "大气光场", detail: "体积散射、气流阻力与雨雾粒子", accent: "#7abbd6" },
    { id: "underwater", label: "水下光影", detail: "流动焦散、穿透水光与上浮气泡", accent: "#55c9c3" },
    { id: "forest", label: "萤火森林", detail: "月光薄雾、层叠树影与近景萤火", accent: "#b5ce75" }
];
function theme(id) { return themes.find(item => item.id === id) || null; }
