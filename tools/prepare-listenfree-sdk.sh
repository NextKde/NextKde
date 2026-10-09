#!/usr/bin/env bash
# Build the private patched audio/JS dependencies used by the Linux music app.
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(dirname -- "$script_dir")
sdk=${1:-"$project_dir/.build/listenfree-sdk"}
mkdir -p "$sdk"
sdk=$(cd -- "$sdk" && pwd)
if ! command -v python3 >/dev/null 2>&1; then
    echo "Missing dependency: python3 (Arch: sudo pacman -S python; Ubuntu: sudo apt install python3)" >&2
    exit 1
fi
python3 "$script_dir/check-apps-dependencies.py" --sdk-only
exec 9>"$sdk/.build.lock"
flock 9
patch_root="$project_dir/apps/listenfree/patches/qmmp"
patches=("$patch_root/2.4.1/0001-enable-https-verification.patch"
         "$patch_root/2.4.1/0003-propagate-http-end-of-stream.patch"
         "$patch_root"/00{04..20}-*.patch)
fingerprint=$({ sha256sum "$0" "${patches[@]}"; uname -m; cc --version; pkg-config --modversion Qt6Core libavcodec libavformat libavutil libswresample libcurl libpulse openssl zlib; pkg-config --modversion taglib || true; } | sha256sum | cut -d ' ' -f 1)
if [[ -f "$sdk/.ready" && $(cat "$sdk/.ready") == "$fingerprint" &&
      -f "$sdk/prefix/lib/libqmmp.so" && -f "$sdk/prefix/lib/cmake/qjs/qjsConfig.cmake" &&
      -f "$sdk/prefix/lib/qmmp-2.4/Input/libffmpeg.so" &&
      -f "$sdk/prefix/lib/qmmp-2.4/Transports/libhttp.so" &&
      -f "$sdk/prefix/lib/qmmp-2.4/Output/libpulseaudio.so" ]]; then
    echo "ListenFree dependencies are cached: $sdk"
    exit 0
fi
rm -f "$sdk/.ready"
mkdir -p "$sdk/downloads" "$sdk/vendor" "$sdk/build" "$sdk/tmp"
export TMPDIR="$sdk/tmp"
fetch() {
    local name=$1 url=$2 checksum=$3 archive="$sdk/downloads/$1"
    if [[ ! -f "$archive" ]]; then
        curl --fail --location --retry 3 --connect-timeout 20 "$url" -o "$archive.part"
        mv -- "$archive.part" "$archive"
    fi
    if ! printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check --status; then
        echo "Source checksum mismatch: $name. Remove $archive and retry." >&2
        exit 1
    fi
}
fetch quickjs-0.16.2.tar.gz https://codeload.github.com/quickjs-ng/quickjs/tar.gz/refs/tags/v0.16.2 \
    97c80625b26775a4c7ca618c004d4ea24cf99cbf867e4eba78bd927a8b23d106
fetch qmmp-2.4.1.tar.bz2 https://downloads.sourceforge.net/project/qmmp-dev/qmmp/2.4/qmmp-2.4.1.tar.bz2 \
    5a0a6f1efcefe9cc4b1ff3ae4038493168baec0b12989ca116af2454098825ed
# Re-extract pristine sources whenever versions, patches or native ABI change.
rm -rf -- "$sdk/vendor/quickjs-0.16.2" "$sdk/vendor/qmmp-2.4.1"
tar -xf "$sdk/downloads/quickjs-0.16.2.tar.gz" -C "$sdk/vendor"
tar -xf "$sdk/downloads/qmmp-2.4.1.tar.bz2" -C "$sdk/vendor"
for patch_file in "${patches[@]}"; do
    patch --batch --forward -p1 -d "$sdk/vendor/qmmp-2.4.1" < "$patch_file"
done
jobs=${CMAKE_BUILD_PARALLEL_LEVEL:-$(nproc)}
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || jobs=4
(( jobs <= 8 )) || jobs=8
cmake -S "$sdk/vendor/quickjs-0.16.2" -B "$sdk/build/quickjs" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$sdk/prefix" -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_SHARED_LIBS=OFF -DQJS_BUILD_EXAMPLES=OFF
cmake --build "$sdk/build/quickjs" --parallel "$jobs"
cmake --install "$sdk/build/quickjs"
# Ubuntu can ship an older TagLib than the app's required API. Build the
# pinned release privately instead of replacing distro libraries.
if ! pkg-config --exists 'taglib >= 2.3.1'; then
    fetch taglib-2.3.1.tar.gz https://codeload.github.com/taglib/taglib/tar.gz/refs/tags/v2.3.1 \
        72c3176432b065978dee670b674aaeae7d9a9f37c721ee578181e9231832bca1
    rm -rf -- "$sdk/vendor/taglib-2.3.1"
    tar -xf "$sdk/downloads/taglib-2.3.1.tar.gz" -C "$sdk/vendor"
    cmake -S "$sdk/vendor/taglib-2.3.1" -B "$sdk/build/taglib" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$sdk/prefix" -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_SHARED_LIBS=ON -DBUILD_TESTING=OFF \
        -DBUILD_BINDINGS=OFF -DBUILD_EXAMPLES=OFF
    cmake --build "$sdk/build/taglib" --parallel "$jobs"
    cmake --install "$sdk/build/taglib"
fi
export PKG_CONFIG_PATH="$sdk/prefix/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
# Only build the codecs, transport and outputs used by ListenFree, not Qmmp's
# separate desktop interfaces or integrations.
mapfile -t qmmp_options < <(python3 - "$sdk/vendor/qmmp-2.4.1" <<'PY'
from pathlib import Path
import re, sys
options = set()
for source in Path(sys.argv[1]).rglob('CMakeLists.txt'):
    options.update(re.findall(r'option\((USE_\w+)', source.read_text()))
needed = {'USE_FFMPEG', 'USE_CURL', 'USE_PULSE', 'USE_NULL', 'USE_CROSSFADE'}
for option in sorted(options):
    print('-D' + option + '=' + ('ON' if option in needed else 'OFF'))
PY
)
cmake -S "$sdk/vendor/qmmp-2.4.1" -B "$sdk/build/qmmp" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$sdk/prefix" -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_PREFIX_PATH="$sdk/prefix" -DCMAKE_INSTALL_RPATH='$ORIGIN' "${qmmp_options[@]}"
cmake --build "$sdk/build/qmmp" --parallel "$jobs"
cmake --install "$sdk/build/qmmp"
printf '%s\n' "$fingerprint" > "$sdk/.ready"
echo "ListenFree dependencies prepared: $sdk"
