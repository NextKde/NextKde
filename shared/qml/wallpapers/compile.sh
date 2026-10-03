#!/bin/sh
# 按主题就地烘焙 .qsb:源 .frag/.vert 与产物 .qsb 同在 themes/<id>/shaders/。
# 产物命名规则:x.frag → x.frag.qsb(x.vert → x.vert.qsb),与运行时引用一致。
# 壳级 shader(不属于任何主题)在 shell/desktop/modules/wallpaper/shaders/。
set -eu
cd "$(dirname "$0")"
QSB=${QSB:-/usr/lib/qt6/bin/qsb}

for dir in themes/*/shaders; do
    for src in "$dir"/*.frag "$dir"/*.vert; do
        [ -f "$src" ] || continue
        # decode_table 需要 GLSL 330/300 es(双精度查表),其余用 qt6 默认档。
        case "$(basename "$src")" in
            decode_table.frag)
                "$QSB" --qsbversion 64 --glsl "330,300 es" --hlsl 50 --msl 12 -o "$src.qsb" "$src" ;;
            *)
                "$QSB" --qsbversion 64 --qt6 -o "$src.qsb" "$src" ;;
        esac
    done
done
echo "baked: $(find themes -name '*.frag.qsb' -o -name '*.vert.qsb' | wc -l) qsb files"
