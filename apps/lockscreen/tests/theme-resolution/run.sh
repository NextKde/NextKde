#!/usr/bin/env bash
# Does kscreenlocker actually pick this lock screen up?
#
# Runs apps/lockscreen/tests/theme-resolution/pkgprobe.cpp, which reproduces the
# greeter's own skin-selection logic (see the header of that file for the two
# conditions kscreenlocker 6.7.4 requires). It catches the two silent traps:
#
#   * the skin is loaded from a **Plasma/Shell** package named by
#     plasmashellrc [Shell] ShellPackage -- installing it as a Look-and-Feel
#     package, the obvious-looking place, has no effect on the lock screen;
#   * "X-Plasma-APIVersion" must be a TOP-LEVEL key of metadata.json, or the
#     greeter logs "Lockscreen QML outdated" and quietly loads KDE's own skin.
#
# Either mistake leaves you staring at the Breeze lock screen (its WallpaperFader
# blurs the wallpaper) while every config file says otherwise.
#
# Usage: ./run.sh [package-id]        (exit 0 = the greeter would load this theme)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
package="$(cd "$here/../.." && pwd)"
work="$here/.tmp"

id="${1:-$(python3 -c "import json,sys;print(json.load(open('$package/metadata.json'))['KPlugin']['Id'])")}"

# A throwaway HOME mirroring the real install: the package symlinked under
# plasma/shells/ (that is the structure the greeter loads) and plasmashellrc
# naming it. A symlink is fine here: KPackage resolves it.
home="$work/home"
rm -rf "$work"
mkdir -p "$home/.config" "$home/.local/share/plasma/shells" "$work/tmp"
ln -s "$package" "$home/.local/share/plasma/shells/$id"
printf '[Shell]\nShellPackage=%s\n' "$id" > "$home/.config/plasmashellrc"

cd "$work"
if command -v pkg-config >/dev/null && pkg-config --exists KF6Package KF6ConfigCore Qt6Core 2>/dev/null; then
    cflags="$(pkg-config --cflags KF6Package KF6ConfigCore Qt6Core)"
    libs="$(pkg-config --libs KF6Package KF6ConfigCore Qt6Core)"
else
    # Distros that ship the CMake config but no .pc files.
    cflags="-I/usr/include/qt6 -I/usr/include/qt6/QtCore -I/usr/include/qt6/QtGui -I/usr/include/qt6/QtXml
            -I/usr/include/KF6/KPackage -I/usr/include/KF6/KConfigCore -I/usr/include/KF6/KConfig
            -I/usr/include/KF6/KCoreAddons -I/usr/include/KF6/KArchive"
    libs="-L/usr/lib64 -lKF6Package -lKF6ConfigCore -lKF6CoreAddons -lKF6Archive -lQt6Core -lQt6Xml"
fi

# shellcheck disable=SC2086
if ! g++ -fPIC -std=c++17 -O0 -o pkgprobe "$here/pkgprobe.cpp" $cflags $libs 2>compile.log; then
    echo "skip: cannot build the probe (KF6 development headers missing?)"
    sed -n '1,5p' compile.log
    echo "      this check needs kpackage + kconfig development packages"
    rm -rf "$work"
    exit 0
fi

echo "checking package '$id' at $package"
set +e
TMPDIR="$work/tmp" HOME="$home" ./pkgprobe "$id"
status=$?
set -e

# The same probe against the live config, informational only: it answers "what
# will my next lock screen actually be", which is the question that is otherwise
# unanswerable from inside a locked session.
echo
echo "--- live session, informational ---"
TMPDIR="$work/tmp" ./pkgprobe || true

rm -rf "$work"
exit $status
