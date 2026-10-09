#pragma once
#include <QCoreApplication>
#include <QVariantList>
#include <QVariantMap>

namespace listenfree::qmlbridge {
// 31 / 62 / 125 / 250 / 500 / 1k / 2k / 4k / 8k / 16k Hz.
// Sources and adaptations: docs/research/audio-effects-2026-09-08.md.
inline QVariantList builtinEqualizerPresets() {
    QVariantList result;
    auto add=[&](const char* id,const char* name,const char* description,QVariantList gains) {
        result.append(QVariantMap{{"value",QString::fromLatin1(id)},
            {"label",QCoreApplication::translate("EqualizerPresets",name)},
            {"description",QCoreApplication::translate("EqualizerPresets",description)},
            {"gains",gains},{"preamp",0.0},{"builtin",true}});
    };
    add("flat","原声","十段归零，保持原始频响",{0,0,0,0,0,0,0,0,0,0});
    add("vocal","人声","LX 预设 · 突出人声中频",{-5,-6,-4,-3,3,4,5,4,-3,-3});
    add("classical","古典","LX 预设 · 厚实低频、柔和高频",{6,7,1,2,-1,1,-4,-6,-7,-8});
    add("acg","ACG · 清亮","ListenFree 调音 · 轻提人声与空气感",{1,2,0,-1,-1,1,2.5,2,1.5,1});
    add("acg-energy","ACG · 燃系","ListenFree 调音 · 增强节奏，保留人声",{3,3,1,-1,-1,1,2,2.5,2,1});
    add("pop","流行","LX 预设 · 明亮、有活力",{6,5,-3,-2,5,4,-4,-3,6,4});
    add("rock","摇滚","LX 预设 · 鼓点与吉他更突出",{7,6,2,1,-3,-4,2,1,4,5});
    add("dance","舞曲","LX 预设 · 节奏与高频细节",{4,3,-4,-6,0,0,3,4,4,5});
    add("electronic","电子","LX 预设 · 两端增强",{6,5,0,-5,-4,0,6,8,8,7});
    add("bass","低音增强","LX 预设 · 提升低频量感",{8,7,5,4,0,0,0,0,0,0});
    add("soft","柔和","LX 预设 · 减少低频堆积",{-5,-5,-4,-4,3,2,4,4,0,0});
    add("slow","舒缓","LX 预设 · 柔和中频与高频延伸",{5,4,2,0,-2,0,3,6,7,8});
    add("live","现场","VLC ISO 十段曲线 · 幅度减半",{-2.4,0,2,2.8,2.8,2.8,2,1.2,1.2,1.2});
    add("party","派对","VLC ISO 十段曲线 · 幅度减半",{3.6,3.6,0,0,0,0,0,0,3.6,3.6});
    return result;
}
}
