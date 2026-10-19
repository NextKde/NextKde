.pragma library

// The units the converter knows, and the arithmetic that moves a value between
// them.
//
// Every unit carries how many base units one of itself is worth — the way a
// unit table is written out loud, "1 km = 1000 m" — so a conversion is one
// multiply and one divide and there is no per-pair table to keep in step: a
// category only has to agree on its base. Temperature is the exception: its
// scales are offset from each other rather than merely scaled, so it carries a
// pair of functions instead of a number.
//
// Currency is a snapshot, not a feed. The reference's own footer names its
// source and the day it was updated, and this carries the same kind of stamp
// rather than pretending to be live (see LEDGER, 外推待确认).

var CATEGORIES = [
    {
        // Ordered the way the reference's list is: by the pinyin of the Chinese
        // name, not by the code and not with the base unit first. Read off
        // ios-unit-picker.webp, whose first eight rows run 人民币 日元 瑞典克朗
        // 瑞士法郎 塞尔维亚第纳尔 塞舌尔卢比 沙特里亚尔 圣赫勒拿群岛磅 — rén rì ruì ruì
        // sài sài shā shèng, which is pinyin and nothing else. The other twelve
        // categories have no reference for their order and keep the base unit
        // first; see LEDGER, 外推待确认.
        id: "currency", label: "货币", base: "EUR",
        updated: "2024/10/5", source: "yahoo!finance",
        // An FX table quotes the rate the other way round — units per euro —
        // and the quote is what is legible here, so each entry writes its
        // reciprocal rather than this one category turning `per` around and
        // making every other table's numbers mean the opposite. 1 EUR = 1.1150
        // USD, so 1 USD = 1 / 1.1150 EUR.
        units: [
            { code: "AUD", label: "澳元", per: 1 / 1.6128 },
            { code: "RUB", label: "俄罗斯卢布", per: 1 / 106.20 },
            { code: "HKD", label: "港币", per: 1 / 8.6680 },
            { code: "KRW", label: "韩元", per: 1 / 1498.6 },
            { code: "CAD", label: "加元", per: 1 / 1.5085 },
            { code: "USD", label: "美元", per: 1 / 1.1150 },
            { code: "EUR", label: "欧元", per: 1 },
            { code: "CNY", label: "人民币", per: 1 / 7.7524 },
            { code: "JPY", label: "日元", per: 1 / 159.87 },
            { code: "CHF", label: "瑞士法郎", per: 1 / 0.9402 },
            { code: "THB", label: "泰铢", per: 1 / 36.850 },
            { code: "SGD", label: "新加坡元", per: 1 / 1.4362 },
            { code: "TWD", label: "新台币", per: 1 / 35.680 },
            { code: "INR", label: "印度卢比", per: 1 / 93.620 },
            { code: "GBP", label: "英镑", per: 1 / 0.8372 }
        ]
    },
    {
        id: "length", label: "长度", base: "m",
        units: [
            { code: "m", label: "米", per: 1 },
            { code: "km", label: "千米", per: 1000 },
            { code: "dm", label: "分米", per: 0.1 },
            { code: "cm", label: "厘米", per: 0.01 },
            { code: "mm", label: "毫米", per: 0.001 },
            { code: "µm", label: "微米", per: 1e-6 },
            { code: "nm", label: "纳米", per: 1e-9 },
            { code: "mi", label: "英里", per: 1609.344 },
            { code: "yd", label: "码", per: 0.9144 },
            { code: "ft", label: "英尺", per: 0.3048 },
            { code: "in", label: "英寸", per: 0.0254 },
            { code: "nmi", label: "海里", per: 1852 },
            { code: "里", label: "市里", per: 500 }
        ]
    },
    {
        id: "mass", label: "质量", base: "kg",
        units: [
            { code: "kg", label: "千克", per: 1 },
            { code: "g", label: "克", per: 0.001 },
            { code: "mg", label: "毫克", per: 1e-6 },
            { code: "µg", label: "微克", per: 1e-9 },
            { code: "t", label: "吨", per: 1000 },
            { code: "lb", label: "磅", per: 0.45359237 },
            { code: "oz", label: "盎司", per: 0.028349523125 },
            { code: "ct", label: "克拉", per: 0.0002 },
            { code: "st", label: "英石", per: 6.35029318 },
            { code: "斤", label: "市斤", per: 0.5 },
            { code: "两", label: "市两", per: 0.05 }
        ]
    },
    {
        // The one affine category: a scale's zero is not the base's zero, so
        // each unit states both directions rather than a single multiplier.
        id: "temperature", label: "温度", base: "°C", affine: true,
        units: [
            { code: "°C", label: "摄氏度",
              toBase: function(v) { return v },
              fromBase: function(v) { return v } },
            { code: "°F", label: "华氏度",
              toBase: function(v) { return (v - 32) * 5 / 9 },
              fromBase: function(v) { return v * 9 / 5 + 32 } },
            { code: "K", label: "开尔文",
              toBase: function(v) { return v - 273.15 },
              fromBase: function(v) { return v + 273.15 } },
            { code: "°R", label: "兰氏度",
              toBase: function(v) { return (v - 491.67) * 5 / 9 },
              fromBase: function(v) { return (v + 273.15) * 9 / 5 } }
        ]
    },
    {
        id: "area", label: "面积", base: "m²",
        units: [
            { code: "m²", label: "平方米", per: 1 },
            { code: "km²", label: "平方千米", per: 1e6 },
            { code: "cm²", label: "平方厘米", per: 1e-4 },
            { code: "mm²", label: "平方毫米", per: 1e-6 },
            { code: "ha", label: "公顷", per: 10000 },
            { code: "acre", label: "英亩", per: 4046.8564224 },
            { code: "ft²", label: "平方英尺", per: 0.09290304 },
            { code: "in²", label: "平方英寸", per: 0.00064516 },
            { code: "mi²", label: "平方英里", per: 2589988.110336 },
            { code: "亩", label: "市亩", per: 666.6666666667 }
        ]
    },
    {
        id: "volume", label: "体积", base: "L",
        units: [
            { code: "L", label: "升", per: 1 },
            { code: "mL", label: "毫升", per: 0.001 },
            { code: "m³", label: "立方米", per: 1000 },
            { code: "cm³", label: "立方厘米", per: 0.001 },
            { code: "gal", label: "美制加仑", per: 3.785411784 },
            { code: "qt", label: "美制夸脱", per: 0.946352946 },
            { code: "pt", label: "美制品脱", per: 0.473176473 },
            { code: "cup", label: "美制杯", per: 0.2365882365 },
            { code: "fl oz", label: "液量盎司", per: 0.0295735295625 },
            { code: "tbsp", label: "汤匙", per: 0.01478676478125 },
            { code: "tsp", label: "茶匙", per: 0.00492892159375 },
            { code: "gal (英)", label: "英制加仑", per: 4.54609 }
        ]
    },
    {
        id: "speed", label: "速度", base: "m/s",
        units: [
            { code: "m/s", label: "米每秒", per: 1 },
            { code: "km/h", label: "千米每小时", per: 0.2777777777778 },
            { code: "mph", label: "英里每小时", per: 0.44704 },
            { code: "kn", label: "节", per: 0.5144444444444 },
            { code: "ft/s", label: "英尺每秒", per: 0.3048 }
        ]
    },
    {
        id: "time", label: "时间", base: "s",
        units: [
            { code: "s", label: "秒", per: 1 },
            { code: "ms", label: "毫秒", per: 0.001 },
            { code: "µs", label: "微秒", per: 1e-6 },
            { code: "min", label: "分钟", per: 60 },
            { code: "h", label: "小时", per: 3600 },
            { code: "d", label: "天", per: 86400 },
            { code: "wk", label: "周", per: 604800 },
            { code: "mo", label: "月", per: 2629800 },
            { code: "yr", label: "年", per: 31557600 }
        ]
    },
    {
        id: "energy", label: "能量", base: "J",
        units: [
            { code: "J", label: "焦耳", per: 1 },
            { code: "kJ", label: "千焦", per: 1000 },
            { code: "cal", label: "卡", per: 4.184 },
            { code: "kcal", label: "千卡", per: 4184 },
            { code: "Wh", label: "瓦时", per: 3600 },
            { code: "kWh", label: "千瓦时", per: 3.6e6 },
            { code: "eV", label: "电子伏", per: 1.602176634e-19 },
            { code: "BTU", label: "英热单位", per: 1055.05585262 }
        ]
    },
    {
        id: "power", label: "功率", base: "W",
        units: [
            { code: "W", label: "瓦", per: 1 },
            { code: "kW", label: "千瓦", per: 1000 },
            { code: "MW", label: "兆瓦", per: 1e6 },
            { code: "hp", label: "英制马力", per: 745.6998715823 },
            { code: "PS", label: "米制马力", per: 735.49875 }
        ]
    },
    {
        id: "pressure", label: "压强", base: "Pa",
        units: [
            { code: "Pa", label: "帕", per: 1 },
            { code: "hPa", label: "百帕", per: 100 },
            { code: "kPa", label: "千帕", per: 1000 },
            { code: "MPa", label: "兆帕", per: 1e6 },
            { code: "bar", label: "巴", per: 100000 },
            { code: "atm", label: "标准大气压", per: 101325 },
            { code: "mmHg", label: "毫米汞柱", per: 133.322387415 },
            { code: "psi", label: "磅每平方英寸", per: 6894.757293168 }
        ]
    },
    {
        id: "data", label: "数据", base: "B",
        units: [
            { code: "B", label: "字节", per: 1 },
            { code: "KB", label: "千字节", per: 1024 },
            { code: "MB", label: "兆字节", per: 1048576 },
            { code: "GB", label: "吉字节", per: 1073741824 },
            { code: "TB", label: "太字节", per: 1099511627776 },
            { code: "bit", label: "比特", per: 0.125 },
            { code: "Kb", label: "千比特", per: 128 },
            { code: "Mb", label: "兆比特", per: 131072 },
            { code: "Gb", label: "吉比特", per: 134217728 }
        ]
    },
    {
        id: "angle", label: "角度", base: "°",
        units: [
            { code: "°", label: "度", per: 1 },
            { code: "rad", label: "弧度", per: 57.29577951308232 },
            { code: "grad", label: "百分度", per: 0.9 },
            { code: "turn", label: "转", per: 360 },
            { code: "′", label: "分", per: 0.016666666666667 },
            { code: "″", label: "秒", per: 0.000277777777778 }
        ]
    }
]

// The picker's chip row, as plain rows. The order is not the table's own: the
// reference's row opens on 角度 面积 货币 数据 能量 …, and the chips are what the
// eye lands on first, so its sequence is copied rather than the order the
// categories happen to be declared in. The ones the reference does not show are
// appended in table order.
//
// The rows are flattened rather than handed over as the category objects
// themselves because a category carries functions — temperature's two scales
// are functions, not multipliers — and a function value crossing out of a
// .pragma library into a QML property is not something the engine promises to
// carry. The picker only needs the two labels.
var ORDER = ["angle", "area", "currency", "data", "energy", "power",
             "length", "mass", "temperature", "volume", "speed", "time",
             "pressure"]

function chipList() {
    var list = []
    for (var i = 0; i < ORDER.length; i++) {
        var group = category(ORDER[i])
        if (group)
            list.push({ id: group.id, label: group.label })
    }
    return list
}

function unitRows(categoryId) {
    var group = category(categoryId)
    if (!group)
        return []
    var list = []
    for (var i = 0; i < group.units.length; i++)
        list.push({ categoryId: group.id, code: group.units[i].code,
                    label: group.units[i].label })
    return list
}

function category(id) {
    for (var i = 0; i < CATEGORIES.length; i++)
        if (CATEGORIES[i].id === id)
            return CATEGORIES[i]
    return null
}

function unit(categoryId, code) {
    var group = category(categoryId)
    if (!group)
        return null
    for (var i = 0; i < group.units.length; i++)
        if (group.units[i].code === code)
            return group.units[i]
    return null
}

// The pair a category opens on. Currency's is the reference's own — EUR on the
// input row and CNY on the result row — and it is named here rather than read
// off the top of the list, because the list is now in the picker's order and no
// longer leads with the base unit. Every other category has no reference for an
// opening pair and takes its base unit and the one below it, which is the same
// rule the reference's own pair follows.
var DEFAULTS = { currency: ["EUR", "CNY"] }

function defaultFrom(categoryId) {
    var group = category(categoryId)
    if (!group)
        return ""
    var pair = DEFAULTS[categoryId]
    return pair ? pair[0] : group.units[0].code
}

function defaultTo(categoryId) {
    var group = category(categoryId)
    if (!group)
        return ""
    var pair = DEFAULTS[categoryId]
    return pair ? pair[1] : group.units[Math.min(1, group.units.length - 1)].code
}

function convert(value, categoryId, fromCode, toCode) {
    var group = category(categoryId)
    var from = unit(categoryId, fromCode)
    var to = unit(categoryId, toCode)
    if (!group || !from || !to)
        return value
    if (group.affine)
        return to.fromBase(from.toBase(value))
    // Into the base and back out: `per` is base units per unit, so the value
    // goes up by how big the unit it is in happens to be and comes back down by
    // how big the unit it is going to is.
    return value * from.per / to.per
}

// Everything the picker's search field matches, across every category rather
// than within the open one — the reference's placeholder reads "search all
// units", and a search that stayed inside the current category would make the
// chip row above it the real control. Each hit carries the category it came
// from so the row can say where it lives.
function search(text) {
    var needle = text.toLowerCase()
    var found = []
    for (var i = 0; i < CATEGORIES.length; i++) {
        var group = CATEGORIES[i]
        for (var j = 0; j < group.units.length; j++) {
            var entry = group.units[j]
            if (entry.code.toLowerCase().indexOf(needle) >= 0
                    || entry.label.indexOf(text) >= 0
                    || group.label.indexOf(text) >= 0)
                found.push({ categoryId: group.id, categoryLabel: group.label,
                             code: entry.code, label: entry.label })
        }
    }
    return found
}
