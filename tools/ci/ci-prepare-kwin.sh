#!/bin/sh
# Arch KWin's scheduling capability is outside Docker's default bounding set.
# Virtual software rendering needs no elevated scheduling, but KWin 6.8 does
# require /dev/udmabuf to create its Mesa software render device:
# https://github.com/KDE/kwin/blob/v6.8.0/src/core/gpumanager.cpp#L73-L86
set -eu
binary=$(command -v kwin_wayland)
if [ -n "$(getcap "$binary")" ]; then
    setcap -r "$binary"
fi
test -c /dev/udmabuf
exec 9<>/dev/udmabuf
exec 9>&-
ls -l /dev/udmabuf
printf 'KWin software rendering device is accessible\n'
