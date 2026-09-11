#!/bin/bash
set -euo pipefail

# Compile the QML fallback glass shader to Qt Shader Binary (.qsb)
# Requires: qsb (from qt6-shadertools)

cd "$(dirname "$0")"

qsb_bin="$(command -v qsb || true)"
if [[ -z "$qsb_bin" && -x /usr/lib/qt6/bin/qsb ]]; then
  qsb_bin=/usr/lib/qt6/bin/qsb
fi
if [[ -z "$qsb_bin" ]]; then
  echo "qsb not found (install qt6-shadertools)" >&2
  exit 1
fi

echo "Compiling static glass highlight shader..."
"$qsb_bin" \
  --glsl 120,150,330,400,440,450 \
  --hlsl 50 \
  --msl 12 \
  -o glass_highlight.vert.qsb \
  glass_highlight.vert

"$qsb_bin" \
  --glsl 120,150,330,400,440,450 \
  --hlsl 50 \
  --msl 12 \
  -o glass_highlight.frag.qsb \
  glass_highlight.frag

echo "Done: glass_highlight.vert.qsb + glass_highlight.frag.qsb"
