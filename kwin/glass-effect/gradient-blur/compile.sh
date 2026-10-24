#!/bin/bash
# 重新烘焙渐变羽化模糊的 QML 侧着色器。
# 与 shell/desktop/shaders/compile.sh 同一套参数：--qt6 才会同时产出 Qt 内置
# 顶点着色器能链接的那些变体（细节见那个脚本的注释）。
set -e
cd "$(dirname "$0")"
PATH="$PATH:/usr/lib/qt6/bin"
qsb --qt6 -o gradient_blur.frag.qsb gradient_blur.frag
echo "Done: gradient_blur.frag.qsb"
