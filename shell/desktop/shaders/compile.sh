#!/bin/bash
# Compile the QML-side shaders to Qt Shader Binary (.qsb)
# Requires: qsb (from qt6-shadertools; on Arch it is /usr/lib/qt6/bin/qsb)

set -e
cd "$(dirname "$0")"

# qsb ships with qt6-shadertools and is not always on PATH (Arch installs it as
# /usr/lib/qt6/bin/qsb).
PATH="$PATH:/usr/lib/qt6/bin"

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
echo "Compiling icon tint fragment shader..."
qsb --qt6 -o icon_effect.frag.qsb icon_effect.frag

echo "Compiling squircle fragment shader..."
qsb --qt6 -o squircle.frag.qsb squircle.frag

echo "Compiling card shadow shaders..."
# Both stages are baked here: the shadow has no source item, so its vertex
# stage computes the item-local coordinate itself instead of relying on
# qt_MultiTexCoord0, which a sourceless ShaderEffect is not guaranteed to get.
qsb --qt6 -o card_shadow.vert.qsb card_shadow.vert
qsb --qt6 -o card_shadow.frag.qsb card_shadow.frag

echo "Done: icon_effect.frag.qsb + squircle.frag.qsb + card_shadow.vert.qsb + card_shadow.frag.qsb"
