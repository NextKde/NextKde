#!/bin/sh
# 就地烘焙共享 shaders/ 和可选 themes/<id>/shaders/ 中的 .qsb。
# 产物命名规则:x.frag → x.frag.qsb(x.vert → x.vert.qsb),与运行时引用一致。
# 壳级 shader(不属于任何主题)在 shell/desktop/modules/wallpaper/shaders/。
set -eu
cd "$(dirname "$0")"
QSB=${QSB:-/usr/lib/qt6/bin/qsb}

for dir in shaders themes/*/shaders; do
    for src in "$dir"/*.frag "$dir"/*.vert; do
        [ -f "$src" ] || continue
        "$QSB" --qsbversion 64 --qt6 -o "$src.qsb" "$src"
    done
done
echo "baked: $(find shaders themes -name '*.frag.qsb' -o -name '*.vert.qsb' | wc -l) qsb files"
