#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
probe_dir="$repo_dir/.build/glass-scrim-check"
mkdir -p "$probe_dir"
c++ -std=c++17 -fPIC "$repo_dir/tests/glass-scrim/run.cpp" -o "$probe_dir/run" \
    $(pkg-config --cflags --libs Qt6Core Qt6Gui Qt6OpenGL)
"$probe_dir/run" "$repo_dir"
