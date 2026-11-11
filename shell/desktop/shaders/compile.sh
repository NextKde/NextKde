#!/bin/bash
# Compile the QML-side shaders to Qt Shader Binary (.qsb)
# Requires: qsb (from qt6-shadertools; on Arch it is /usr/lib/qt6/bin/qsb)

set -eu
cd "$(dirname "$0")"

# qsb ships with qt6-shadertools and is not always on PATH (Arch installs it as
# /usr/lib/qt6/bin/qsb).
PATH="$PATH:/usr/lib/qt6/bin"
QSB=${QSB:-qsb}

# --qt6 == --glsl "100 es,120,150" --hlsl 50 --msl 12, the set Qt Quick bakes
# its own scene-graph shaders with. That matters because these effects are
# linked against Qt's built-in shaders: a ShaderEffect without a vertexShader
# of its own gets Qt's built-in one, which only has 100/120/150 variants.
#
# Bake a fragment shader with a wider set and on a desktop GL context the
# fragment is served as #version 440 -- where qsb carries the varying over as
# an explicit `layout(location = 0) in vec2 qt_TexCoord0` -- while the built-in
# vertex shader has no 440 variant and falls back to #version 150, where
# varyings carry no explicit location at all. Mesa refuses to link that pair:
#
#   fragment shader input `qt_TexCoord0' with explicit location has no matching
#   output
#
# and the effect renders nothing. Staying on --qt6 also means this script
# reproduces the committed .qsb byte for byte, so a diff after re-running it
# means the shader really changed.
# Bake both stages, including the sourceless card-shadow vertex shader and the
# stage plate. Wallpaper shaders stay next to their consuming QML; do not keep
# a second global copy that can drift from the module's uniform layout.
for source in *.frag *.vert ../modules/wallpaper/shaders/*.frag; do
    case "$source" in
        # Qt Quick 3D CustomMaterial reads these sources directly.
        */spatial_background.frag|*/spatial_subject.frag) continue ;;
    esac
    echo "Compiling $source..."
    case "$source" in
        # This shader samples textureSize and already ships GLSL 330/300 es.
        */layered_wallpaper.frag)
            "$QSB" --glsl "330,300 es" --hlsl 50 --msl 12 -o "$source.qsb" "$source" ;;
        *) "$QSB" --qt6 -o "$source.qsb" "$source" ;;
    esac
done

echo "Done: desktop and wallpaper ShaderEffect binaries"
