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

# apps/settings/main.qml runs as its own process and resolves
# `import "../../shared/qml/<dir>"` against its installed location
# ($prefix/share/kos/settings), so every import target has to exist under
# $prefix/share/shared/qml. controls/ once shipped alone, and the binary --
# installed, executable, and passing every check above -- exited 1 inside
# QQmlApplicationEngine before a window existed, which nothing else here saw.
settings_qml="$prefix/share/kos/settings/main.qml"
if test -f "$settings_qml"; then
    for target in $(sed -n 's/.*import "\.\.\/\.\.\/shared\/qml\/\([^"]*\)".*/\1/p' "$settings_qml"); do
        if test ! -e "$prefix/share/shared/qml/$target"; then
            echo "Settings import target is not installed: shared/qml/$target" >&2
            failed=1
        fi
    done
fi

for metadata in "$prefix"/share/metainfo/org.nextkde.Kos.*.metainfo.xml; do
    test -f "$metadata" || continue
    if command -v appstreamcli >/dev/null 2>&1; then
        appstreamcli validate --no-net "$metadata" || failed=1
    fi
done

systemctl --user is-enabled kos-data.service >/dev/null || failed=1
systemctl --user is-active kos-data.service >/dev/null || failed=1
test -f "$prefix/share/dbus-1/services/org.nextkde.Kos.Pim1.service" || failed=1
test -f "$prefix/share/systemd/user/kos-pim-service.service" || failed=1

if test "$failed" -ne 0; then
    echo "KOS application registration verification failed." >&2
    exit 1
fi
echo "Verified four desktop entries, icons, metadata, binaries, and service registration."
