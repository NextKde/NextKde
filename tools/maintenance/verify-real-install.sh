#!/usr/bin/env bash
# VM-only, read-only acceptance after kosctl install/start and a session restart.
# Checks the user deployment produced by kosctl, not a declarative NixOS install.
# Run only in the VM: ./tools/maintenance/verify-real-install.sh
# Uses the same KOS_PREFIX, XDG_CONFIG_HOME and KOS_BUILD_KWIN_PLUGINS as kosctl.
set -uo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
prefix="${KOS_PREFIX:-$HOME/.local}"
config="${XDG_CONFIG_HOME:-$HOME/.config}"
unit_dir="$config/systemd/user"
shell_cfg="$config/quickshell/kos"
runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
manifest="$prefix/share/kos/kwin-system-files.manifest"
ok=0; bad=0; skipped=0

ck() {
    local label=$1
    shift
    if "$@"; then
        printf '  PASS %s\n' "$label"
        ok=$((ok + 1))
    else
        printf '  FAIL %s\n' "$label" >&2
        bad=$((bad + 1))
    fi
}
hdr() { printf '\n== %s ==\n' "$1"; }
skip() { printf '  SKIP %s\n' "$1"; skipped=$((skipped + 1)); }
nonempty() { [[ -f "$1" && -s "$1" ]]; }
# ldd failing is itself a failure; missing tools/files must never pass this check.
linked() {
    local output
    output=$(ldd "$1" 2>&1) || { printf '%s\n' "$output" >&2; return 1; }
    if [[ "$output" == *'not found'* ]]; then
        printf '%s\n' "$output" >&2
        return 1
    fi
}
config_is() {
    local file=$1 group=$2 key=$3 expected=$4 value
    value=$(kreadconfig6 --file "$config/$file" --group "$group" --key "$key") || return 1
    [[ "$value" == "$expected" ]]
}
no_build_files() {
    local files
    [[ -d "$1" ]] || return 1
    files=$(find -L "$1" \( -name CMakeLists.txt -o -name 'test_*.mjs' \) -print) || return 1
    [[ -z "$files" ]]
}
manifest_files() {
    local path count=0 failed=0
    [[ -s "$manifest" ]] || return 1
    while IFS= read -r path || [[ -n "$path" ]]; do
        [[ -z "$path" ]] && continue
        # kosctl only records system files under /usr. Never execute the entries.
        case "$path" in
            /usr/*) ;;
            *) printf 'Invalid manifest path: %s\n' "$path" >&2; failed=1; continue ;;
        esac
        count=$((count + 1))
        if [[ ! -f "$path" || ! -s "$path" ]]; then
            printf 'Missing/empty system artifact: %s\n' "$path" >&2
            failed=1
        fi
    done < "$manifest"
    (( count > 0 && failed == 0 ))
}
manifest_plugin() {
    local name=$1 path found=0 failed=0
    [[ -s "$manifest" ]] || return 1
    while IFS= read -r path || [[ -n "$path" ]]; do
        case "$path" in
            /usr/*/"$name".so|/usr/*/lib"$name".so)
                found=1
                linked "$path" || failed=1
                ;;
        esac
    done < "$manifest"
    (( found == 1 && failed == 0 ))
}
effect_loaded() {
    local reply
    reply=$(qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded "$1") || return 1
    [[ "$reply" == true ]]
}

hdr 'Binaries and release identity'
ck 'kos-platform executable' test -x "$prefix/libexec/kos-platform"
ck 'kos-data-service executable' test -x "$prefix/libexec/kos-data-service"
ck 'kos-settings executable' test -x "$prefix/bin/kos-settings"
ck 'kos-platform shared libraries' linked "$prefix/libexec/kos-platform"
ck 'release record' nonempty "$prefix/share/kos/release.json"

hdr 'QML runtime'
# Reuse deployment's qmldir/import checks; no hard-coded count or source-version
# comparison, so the checkout may be newer than the installed release.
qml_runtime() {
    python3 - "$project_dir" "$prefix" "$shell_cfg" <<'PY'
import importlib.util
from pathlib import Path
import sys
root, prefix, shell = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location('deploy_shell', root / 'tools/deploy/deploy-shell-qml.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
try:
    module.check_shared(prefix / 'share/shared/qml')
    module.check_installed(shell)
except (OSError, ValueError) as error:
    print(error, file=sys.stderr)
    sys.exit(1)
PY
}
ck 'shared modules, Shell aliases and referenced files' qml_runtime
for tree in "$prefix/share/shared/qml" "$shell_cfg/shared/qml" "$shell_cfg/Kos/Ui"; do
    ck "runtime excludes build/test files: $tree" no_build_files "$tree"
done
ck 'settings main.qml' nonempty "$prefix/share/kos/settings/main.qml"
ck 'window bridge script' nonempty "$prefix/share/kos/platform/kwin/window-bridge.js"
ck 'Shell SurfaceShape qmldir' nonempty "$shell_cfg/Kos/SurfaceShape/qmldir"
ck 'Shell SurfaceShape native plugin' nonempty "$shell_cfg/Kos/SurfaceShape/libkos_surface_shape.so"
ck 'SurfaceShape shared libraries' linked "$shell_cfg/Kos/SurfaceShape/libkos_surface_shape.so"

hdr 'systemd units and services'
for service in kos-platform kos-data kos-shell; do
    ck "$service unit" nonempty "$unit_dir/$service.service"
    ck "$service running" systemctl --user is-active --quiet "$service.service"
done
ck 'platform socket' test -S "$runtime_dir/kos-platform.sock"
ck 'data socket' test -S "$runtime_dir/kos-data.sock"

hdr 'KWin system installation'
case "${KOS_BUILD_KWIN_PLUGINS:-ON}" in
    0|OFF|off|FALSE|false|NO|no)
        skip 'system plugins and effect state (KOS_BUILD_KWIN_PLUGINS=OFF)'
        ;;
    *)
        ck 'all recorded system artifacts exist' manifest_files
        for plugin in kos_bridge kos_dock_window_animation kos_context_menu_input glass kos_decoration; do
            ck "$plugin recorded and shared libraries resolved" manifest_plugin "$plugin"
        done
        for effect in kos_bridge kos_dock_window_animation kos_context_menu_input glass; do
            ck "$effect enabled" config_is kwinrc Plugins "${effect}Enabled" true
            # Missing qdbus6 or an unreachable compositor is a failed runtime gate.
            ck "$effect loaded" effect_loaded "$effect"
        done
        ck 'conflicting stock blur disabled' config_is kwinrc Plugins blurEnabled false
        ;;
esac

hdr 'Plasma desktop package'
plasma="$prefix/share/plasma/shells/org.kos.desktop"
ck 'shells metadata.json' nonempty "$plasma/metadata.json"
ck 'desktop defaults' nonempty "$plasma/contents/defaults"
ck 'wallpaper containment' grep -q '^Containment=org.kde.desktopcontainment$' "$plasma/contents/defaults"
ck 'desktop package selected' config_is plasmashellrc Shell ShellPackage org.kos.desktop
if [[ -f "$plasma/contents/lockscreen/LockScreen.qml" ]]; then
    ck 'optional lockscreen look-and-feel metadata' nonempty "$prefix/share/plasma/look-and-feel/org.kos.desktop/metadata.json"
fi
# Independent application health belongs to kosctl install apps status --app APP.
printf '\n%d passed, %d failed, %d skipped\n' "$ok" "$bad" "$skipped"
(( bad == 0 ))
