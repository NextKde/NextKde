#!/usr/bin/env bash
# verify-real-install.sh - end-to-end check that `kosctl install` actually
# landed a working desktop on THIS machine. Read-only: changes nothing.
#
# Distinct from tools/verify-install-tree.sh, which checks a `cmake --install`
# staging prefix. This one checks the real ~/.local tree + /usr KWin plugins
# + running services + KWin effect state after `kosctl install` (and the
# optional `install lockscreen` / `install apps`).
#
# Run it on the real machine after install:
#   ./tools/verify-real-install.sh
set -uo pipefail

prefix="${KOS_INSTALL_PREFIX:-$HOME/.local}"
config="${XDG_CONFIG_HOME:-$HOME/.config}"
unit_dir="$config/systemd/user"
shell_cfg="$config/quickshell/kos"
kwin_plugins=/usr/lib/qt6/plugins/kwin
runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

ok=0; bad=0
g=$'\033[32m'; r=$'\033[31m'; b=$'\033[1m'; n=$'\033[0m'

ck()  { if eval "$2" >/dev/null 2>&1; then printf '  %s✓%s %s\n' "$g" "$n" "$1"; ok=$((ok+1));  else printf '  %s✗%s %s\n' "$r" "$n" "$1"; bad=$((bad+1)); fi; }
ckn() { if ! eval "$2" >/dev/null 2>&1; then printf '  %s✓%s %s\n' "$g" "$n" "$1"; ok=$((ok+1));  else printf '  %s✗%s %s\n' "$r" "$n" "$1"; bad=$((bad+1)); fi; }
hdr() { printf '\n%s== %s ==%s\n' "$b" "$1" "$n"; }

hdr "Binaries"
ck  "kos-platform binary"        "[[ -x \$prefix/libexec/kos-platform ]]"
ck  "kos-data-service binary"    "[[ -x \$prefix/libexec/kos-data-service ]]"
ck  "kos-settings binary"        "[[ -x \$prefix/bin/kos-settings ]]"
ck  "kos-platform ldd clean"     "! ldd \$prefix/libexec/kos-platform 2>/dev/null | grep -qi 'not found'"

hdr "shared/qml (the new exclusion)"
ckn "no CMakeLists.txt leaked"   "find \$prefix/share/shared/qml -name CMakeLists.txt | grep -q ."
ckn "no test_*.mjs leaked"       "find \$prefix/share/shared/qml -name 'test_*.mjs' | grep -q ."
ck  "colorize dir"               "[[ -d \$prefix/share/shared/qml/colorize ]]"
ck  "controls dir"               "[[ -d \$prefix/share/shared/qml/controls ]]"
ck  "foundation dir"             "[[ -d \$prefix/share/shared/qml/foundation ]]"
ck  "glass dir"                  "[[ -d \$prefix/share/shared/qml/glass ]]"
ck  "runtime qml count == 24"    "[[ \$(find \$prefix/share/shared/qml -name '*.qml' | wc -l) -eq 24 ]]"
ck  "settings main.qml"          "[[ -f \$prefix/share/kos/settings/main.qml ]]"
ck  "window-bridge.js"           "[[ -f \$prefix/share/kos/platform/kwin/window-bridge.js ]]"
ck  "shell config tree"          "[[ -f \$shell_cfg/shell.qml ]]"

hdr "systemd units + services"
ck  "kos-platform unit"          "[[ -f \$unit_dir/kos-platform.service ]]"
ck  "kos-data unit"              "[[ -f \$unit_dir/kos-data.service ]]"
ck  "kos-shell unit"             "[[ -f \$unit_dir/kos-shell.service ]]"
ck  "kos-platform running"       "systemctl --user is-active --quiet kos-platform.service"
ck  "kos-data running"            "systemctl --user is-active --quiet kos-data.service"
ck  "kos-shell running"           "systemctl --user is-active --quiet kos-shell.service"
# pim is D-Bus activated on demand and must NOT be resident/enabled.
ckn "kos-pim NOT enabled (D-Bus activated)" "systemctl --user is-enabled --quiet kos-pim-service.service"
ck  "kos-platform socket"        "[[ -S \$runtime_dir/kos-platform.sock ]]"
ck  "kos-data socket"            "[[ -S \$runtime_dir/kos-data.sock ]]"

hdr "KWin plugins in /usr"
ck  "dock effect .so"            "[[ -f \$kwin_plugins/effects/plugins/kos_dock_window_animation.so ]]"
ck  "context-menu effect .so"    "[[ -f \$kwin_plugins/effects/plugins/kos_context_menu_input.so ]]"
ck  "glass effect .so"           "[[ -f \$kwin_plugins/effects/plugins/glass.so ]]"
ck  "SurfaceShape .so"           "[[ -f \$kwin_plugins/qml/Kos/SurfaceShape/libkos_surface_shape.so ]]"
ckn "NO legacy quickshell_context_menu_input.so" "[[ -f \$kwin_plugins/effects/plugins/quickshell_context_menu_input.so ]]"
ck  "dock effect ldd clean"      "! ldd \$kwin_plugins/effects/plugins/kos_dock_window_animation.so 2>/dev/null | grep -qi 'not found'"

hdr "kwinrc (effect enabled keys)"
ck  "dock effect enabled"         "[[ \"\$(kreadconfig6 --file kwinrc --group Plugins --key kos_dock_window_animationEnabled 2>/dev/null)\" == true ]]"
ck  "context-menu enabled"       "[[ \"\$(kreadconfig6 --file kwinrc --group Plugins --key kos_context_menu_inputEnabled 2>/dev/null)\" == true ]]"
ck  "glass enabled"              "[[ \"\$(kreadconfig6 --file kwinrc --group Plugins --key glassEnabled 2>/dev/null)\" == true ]]"
ckn "legacy quickshell_* key removed" "[[ -n \"\$(kreadconfig6 --file kwinrc --group Plugins --key quickshell_context_menu_inputEnabled 2>/dev/null)\" ]]"

if command -v qdbus6 >/dev/null 2>&1; then
    hdr "KWin effect loaded (runtime)"
    ck "dock effect loaded"      "[[ \"\$(qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded kos_dock_window_animation 2>/dev/null)\" == true ]]"
    ck "context-menu loaded"     "[[ \"\$(qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded kos_context_menu_input 2>/dev/null)\" == true ]]"
    ck "glass loaded"            "[[ \"\$(qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded glass 2>/dev/null)\" == true ]]"
else
    printf '\n  (qdbus6 unavailable; skipping runtime effect-load checks)\n'
fi

# The shells/ root ships with every core install (desktop takeover); the lock
# screen skin inside it is the optional part and is checked separately.
if [[ -f "$prefix/share/plasma/shells/org.kos.desktop/contents/defaults" ]]; then
    hdr "Plasma desktop takeover (installed)"
    ck  "shells metadata.json"   "[[ -f \$prefix/share/plasma/shells/org.kos.desktop/metadata.json ]]"
    ck  "shells contents/"       "[[ -d \$prefix/share/plasma/shells/org.kos.desktop/contents ]]"
    ck  "defaults wallpapers-only containment" "grep -q '^Containment=org.kde.desktopcontainment' \$prefix/share/plasma/shells/org.kos.desktop/contents/defaults"
    ckn "shells no tests/"       "[[ -d \$prefix/share/plasma/shells/org.kos.desktop/tests ]]"
    ckn "shells no README"       "[[ -f \$prefix/share/plasma/shells/org.kos.desktop/README.md ]]"
    ck  "ShellPackage=org.kos.desktop" "[[ \"\$(kreadconfig6 --file plasmashellrc --group Shell --key ShellPackage 2>/dev/null)\" == org.kos.desktop ]]"
    ckn "org.kos appletsrc folder-free" "grep -q '^plugin=org.kde.plasma.folder' \$config/plasma-org.kos.desktop-appletsrc 2>/dev/null"
fi
if [[ -f "$prefix/share/plasma/shells/org.kos.desktop/contents/lockscreen/LockScreen.qml" ]]; then
    hdr "lockscreen (installed)"
    ck  "laf metadata.json"      "[[ -f \$prefix/share/plasma/look-and-feel/org.kos.desktop/metadata.json ]]"
    ckn "laf no tests/"          "[[ -d \$prefix/share/plasma/look-and-feel/org.kos.desktop/tests ]]"
fi
if [[ -x "$prefix/bin/kos-calendar" ]]; then
    hdr "apps (installed)"
    for app in calendar todo weather music; do
        ck "kos-$app binary"    "[[ -x \$prefix/bin/kos-$app ]]"
        ck "kos-$app desktop"   "[[ -f \$prefix/share/applications/kos-$app.desktop ]]"
        ck "kos-$app icon"      "[[ -f \$prefix/share/icons/hicolor/scalable/apps/kos-$app.svg ]]"
    done
fi

printf '\n'
if (( bad > 0 )); then
    printf '%sFAIL:%s %d check(s) failed, %d passed\n' "$r" "$n" "$bad" "$ok" >&2
    exit 1
fi
printf '%sPASS:%s real install verified (%d checks)\n' "$g" "$n" "$ok"
