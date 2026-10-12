#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
build_dir=${KOS_BUILD_DIR:-"$repo/.build/kosctl"}
run_dir=${KOS_LIVE_ROOT:-"$build_dir/liquid-live"}
qtpaths=$(command -v qtpaths6 || command -v qtpaths || true)
if [[ -z $qtpaths ]]; then qtpaths=/usr/lib/qt6/bin/qtpaths; fi
plugin_dir=$("$qtpaths" --query QT_INSTALL_PLUGINS)
mkdir -p "$run_dir"

for scenario in ${KOS_LIVE_SCENARIOS:-shared-ssd shared-csd-hidpi legacy-ssd real-dock}; do
    case_dir=$(mktemp -d "$run_dir/$scenario.XXXXXX")
    mkdir -p "$case_dir/config/kos" "$case_dir/plugins/kwin/effects/plugins" "$case_dir/frames"
    install -m 755 "$build_dir/kwin/kos-bridge/kos_bridge.so" "$case_dir/plugins/kwin/effects/plugins/"
    install -m 755 "$build_dir/kwin/dock-window-animation/kos_dock_window_animation.so" "$case_dir/plugins/kwin/effects/plugins/"
    appearance=true
    scale=1
    width=1200
    height=800
    args=""
    if [[ $scenario == real-dock || $scenario == real-dock-glass ]]; then args="--real-dock"; fi
    if [[ $scenario == legacy-ssd ]]; then appearance=false; fi
    if [[ $scenario == shared-csd-hidpi ]]; then scale=1.5; width=1800; height=1200; args="--csd"; fi
    cat > "$case_dir/config/kwinrc" <<'CONFIG'
[Plugins]
kos_bridgeEnabled=true
kos_dock_window_animationEnabled=true
blurEnabled=false
[Effect-kos_dock_window_animation]
HideAnimation=liquid
CloseAnimation=none
GenieDuration=1000
RestoreDuration=800
[org.kde.kdecoration2]
library=kos_decoration
CONFIG
    if [[ $scenario == real-dock-glass ]]; then
        sed -i '/blurEnabled=false/a glassEnabled=true' "$case_dir/config/kwinrc"
    fi
    if [[ -n ${KOS_LIVE_DURATION:-} ]]; then
        sed -i "s/GenieDuration=1000/GenieDuration=$KOS_LIVE_DURATION/;s/RestoreDuration=800/RestoreDuration=$KOS_LIVE_DURATION/" "$case_dir/config/kwinrc"
    fi
    echo "{\"enabled\":$appearance,\"version\":2,\"defaults\":{\"corners\":{\"radius\":20},\"outline\":{\"activeOpacity\":0.16},\"shadow\":{\"enabled\":true}}}" > "$case_dir/config/kos/window-appearance.json"
    cat > "$case_dir/session.sh" <<'SESSION'
#!/usr/bin/env bash
set -eu
export WAYLAND_DISPLAY="$KOS_LIVE_WAYLAND"
if [[ ${KOS_LIVE_ARGS:-} == --real-dock ]]; then
    export KOS_PLATFORM_SOCKET="$KOS_LIVE_CASE/platform.sock"
    export KOS_PLATFORM_KWIN_SCRIPT="$KOS_LIVE_REPO/kwin/window-bridge.js"
    export XDG_CACHE_HOME="$KOS_LIVE_CASE/cache" XDG_DATA_HOME="$KOS_LIVE_CASE/data" XDG_STATE_HOME="$KOS_LIVE_CASE/state"
    "$KOS_LIVE_BUILD/platform/kos-platform" daemon > "$KOS_LIVE_CASE/platform.log" 2>&1 &
    platform_pid=$!
    cd "$KOS_LIVE_REPO"
    quickshell --path shell --no-color > "$KOS_LIVE_CASE/quickshell.log" 2>&1 &
    shell_pid=$!
    trap 'kill "$shell_pid" "$platform_pid" 2>/dev/null || true; wait "$shell_pid" "$platform_pid" 2>/dev/null || true' EXIT
fi
qdbus6 org.kde.KWin /KWin org.kde.KWin.supportInformation > "$KOS_LIVE_CASE/support.txt"
"$KOS_LIVE_BIN" ${KOS_LIVE_ARGS:-} > "$KOS_LIVE_CASE/test.log" 2>&1
touch "$KOS_LIVE_CASE/passed"
SESSION
    chmod +x "$case_dir/session.sh"
    socket="kos-liquid-test-$BASHPID"
    KOS_LIVE_REPO="$repo" KOS_LIVE_BUILD="$build_dir" \
    KOS_LIVE_WAYLAND="$socket" KOS_LIVE_CASE="$case_dir" KOS_LIVE_ARGS="$args" \
    KOS_LIVE_BIN="$build_dir/kwin/dock-window-animation/kos-liquid-live-test" \
    KOS_LIVE_OUTPUT="$case_dir/frames" XDG_CONFIG_HOME="$case_dir/config" \
    QT_PLUGIN_PATH="$case_dir/plugins:$plugin_dir" KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1 \
    QT_FORCE_STDERR_LOGGING=1 dbus-run-session -- kwin_wayland --virtual --socket "$socket" \
        --width "$width" --height "$height" --scale "$scale" --no-lockscreen --no-global-shortcuts \
        --no-kactivities --exit-with-session "$case_dir/session.sh" > "$case_dir/kwin.log" 2>&1
    if [[ ! -f $case_dir/passed ]]; then
        cat "$case_dir/test.log" >&2
        echo "FAIL: $scenario ($case_dir)" >&2
        exit 1
    fi
    echo "PASS: $scenario ($case_dir)"
    tail -n 1 "$case_dir/test.log"
done
