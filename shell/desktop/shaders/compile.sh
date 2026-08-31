#!/bin/bash
# Compile liquid glass shaders to Qt Shader Binary (.qsb)
# Requires: qsb (from qt6-shadertools)

cd "$(dirname "$0")"

echo "Compiling vertex shader..."
qsb \
  --glsl 120,150,330,400,440,450 \
  --hlsl 50 \
  --msl 12 \
  -o liquid.vert.qsb \
  liquid.vert

echo "Compiling fragment shader..."
qsb \
  --glsl 120,150,330,400,440,450 \
  --hlsl 50 \
  --msl 12 \
  -o liquid.frag.qsb \
  liquid.frag

echo "Done: liquid.vert.qsb + liquid.frag.qsb"
