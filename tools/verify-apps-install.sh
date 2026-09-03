#!/bin/sh
set -eu

prefix=${1:-${KOS_INSTALL_PREFIX:-"$HOME/.local"}}
failed=0

for app in calendar todo weather music; do
    binary="$prefix/bin/kos-$app"
    desktop="$prefix/share/applications/kos-$app.desktop"
    icon="$prefix/share/icons/hicolor/scalable/apps/kos-$app.svg"
    if test ! -x "$binary" || test ! -f "$desktop" || test ! -f "$icon"; then
        echo "Incomplete registration: kos-$app" >&2
        failed=1
        continue
    fi
    if command -v desktop-file-validate >/dev/null 2>&1; then
        desktop-file-validate "$desktop" || failed=1
    fi
    QT_QPA_PLATFORM=offscreen "$binary" --version >/dev/null || failed=1
done

for metadata in "$prefix"/share/metainfo/org.nextkde.Kos.*.metainfo.xml; do
    test -f "$metadata" || continue
    if command -v appstreamcli >/dev/null 2>&1; then
        appstreamcli validate --no-net "$metadata" || failed=1
    fi
done

for unit in shell-data-service.service kos-pim-service.service; do
    systemctl --user is-enabled "$unit" >/dev/null || failed=1
    systemctl --user is-active "$unit" >/dev/null || failed=1
done

if test "$failed" -ne 0; then
    echo "KOS application registration verification failed." >&2
    exit 1
fi
echo "Verified four desktop entries, icons, metadata, binaries, and user services."
