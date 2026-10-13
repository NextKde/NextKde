#!/usr/bin/env bash
set -euo pipefail
if [[ $# != 3 ]]; then
    echo "usage: build.sh CLEAN_KWIN_V6.7.5_SOURCE BUILD_DIR PRIVATE_PROTOCOL_PREFIX" >&2
    exit 2
fi
base=$(cd -- "$(dirname -- "$0")" && pwd)
source_dir=$(realpath -- "$1")
mkdir -p -- "$2"
build_dir=$(realpath -- "$2")
deps=$(realpath -- "$3")
python3 - "$source_dir" "$base/kwin-source-sha256.json" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1])
for name,digest in json.loads(pathlib.Path(sys.argv[2]).read_text()).items():
    if hashlib.sha256((root/name).read_bytes()).hexdigest()!=digest:
        raise SystemExit('Source differs from clean reviewed v6.7.5: '+name)
PY
git -C "$source_dir" apply --check "$base/kwin-v6.7.5-bootstrap.patch"
git -C "$source_dir" apply "$base/kwin-v6.7.5-bootstrap.patch"
PKG_CONFIG_PATH="$deps/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" \
cmake -S "$source_dir" -B "$build_dir" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DBUILD_TESTING=OFF -DCMAKE_PREFIX_PATH="$deps" -DCMAKE_INSTALL_PREFIX="$build_dir/stage"
cmake --build "$build_dir" --target kwin_wayland kwin_wayland_wrapper -j2
c++ -std=c++20 -fPIC -pie "$base/fixture-session.cpp" -o "$build_dir/fixture-session" $(pkg-config --cflags --libs Qt6Widgets)
# No cmake --install: built KWin and library remain in this private build tree.
