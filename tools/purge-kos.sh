#!/usr/bin/env bash
# purge-kos.sh — remove every KOS install artifact so the next
# `./tools/kosctl install` is a true clean install.
#
# Workflow:
#   1. Print the full deletion list (core + leftovers) and wait for confirm.
#   2. Stop KOS services and detached processes; remove registered shortcuts.
#      Call `./tools/kosctl uninstall` for the KWin/plugin/service layer --
#      it runs unloadEffect + blur restore BEFORE deleting the /usr .so files,
#      using the state it saved at install time. This step will ask for sudo to
#      remove /usr/lib/qt6/plugins/...
#   3. Sweep leftovers uninstall leaves behind: empty share dirs, apps-era
#      files (install-apps.sh产物, not owned by kosctl), stray systemd wants
#      links, the optional lockscreen/app surfaces, and any kwinrc keys that
#      survived.
#   4. daemon-reload, then verify every target is gone.
#
# Idempotent: safe to run multiple times. Read-only until you confirm.

set -uo pipefail

if (( EUID == 0 )); then
    echo "Run as your desktop user, not with sudo; system files request sudo separately." >&2
    exit 2
fi

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
prefix="${KOS_PREFIX:-$HOME/.local}"
apps_prefix="${KOS_INSTALL_PREFIX:-$prefix}"
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}"
runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
unit_dir="$config_dir/systemd/user"
wants_dir="$unit_dir/graphical-session.target.wants"
kwinrc="$config_dir/kwinrc"

# Never accept a root/home/source directory as a deletion root through overrides.
for root in "$prefix" "$apps_prefix" "$data_dir" "$cache_dir" "$state_dir" "$config_dir"; do
    case "$root" in
        /*) ;;
        *) echo "Paths must be absolute: $root" >&2; exit 2 ;;
    esac
    case "$root" in /|"$HOME"|"$project_dir"|*/../*|*/..)
        echo "Unsafe cleanup root: $root" >&2; exit 2 ;;
    esac
done
case "${1:-}" in
    ""|--dry-run|--yes) ;;
    *) echo "Usage: $0 [--dry-run|--yes]" >&2; exit 2 ;;
esac

# --- core targets that `kosctl uninstall` owns (fixed list, for the report) ---
core_targets=(
    "$prefix/libexec/kos-ai-worker"
    "$prefix/libexec/kos-platform"
    "$prefix/libexec/kos-data-service"
    "$prefix/bin/kos-settings"
    "$unit_dir/kos-shell.service"
    "$unit_dir/kos-platform.service"
    "$unit_dir/kos-data.service"
    "$prefix/share/applications/kos-settings.desktop"
    "$prefix/share/applications/org.kos.Platform.desktop"
    "$prefix/share/applications/kos-platform.desktop"
    "$prefix/share/kos/platform/kwin/window-bridge.js"
    "$prefix/share/kos/settings/main.qml"
    "$prefix/share/shared/qml"
    "$config_dir/quickshell/kos"
    /usr/lib/qt6/plugins/kwin/effects/plugins/glass.so
    /usr/lib/qt6/plugins/kwin/effects/plugins/kos_bridge.so
    /usr/lib/qt6/plugins/kwin/effects/plugins/kos_context_menu_input.so
    /usr/lib/qt6/plugins/kwin/effects/plugins/kos_dock_window_animation.so
    /usr/lib/qt6/plugins/kwin/effects/plugins/quickshell_context_menu_input.so
    /usr/lib/qt6/plugins/kwin/effects/configs/kwin_glass_config.so
    /usr/lib/qt6/plugins/org.kde.kdecoration3/kos_decoration.so
    /usr/lib/qt6/qml/Kos/SurfaceShape/libkos_surface_shape.so
    "$prefix/share/kos/kwin-system-files.manifest"
    "$prefix/share/kos/kwin-effect-state"
)

# --- leftovers that uninstall does NOT cover (sweep these) ---
leftover_targets=(
    # empty share dirs (uninstall deletes contents, leaves the dirs)
    "$prefix/share/kos"
    "$prefix/share/shared/qml"
    # apps-era files (install-apps.sh产物, kosctl uninstall does not touch)
    "$prefix/lib/quickshell"
    "$prefix/bin/kos-pim-service"
    "$unit_dir/kos-pim-service.service"
    "$unit_dir/shell-data-service.service"
    # stray wants symlinks (orphans can survive service disable)
    "$wants_dir/kos-shell.service"
    "$wants_dir/kos-platform.service"
    "$wants_dir/kos-data.service"
    "$wants_dir/kos-pim-service.service"
    "$wants_dir/shell-data-service.service"
    # optional surfaces (uninstall removes them if installed; sweep to be sure)
    "$prefix/share/plasma/shells/org.kos.desktop"
    "$prefix/share/plasma/look-and-feel/org.kos.desktop"
    # appletsrc seeded by the desktop takeover; the previous shell's own
    # appletsrc was never modified, so deleting this loses nothing
    "$config_dir/plasma-org.kos.desktop-appletsrc"
    # a copy of the bridge effect that once landed in kwin/effects/ instead of
    # kwin/effects/plugins/. KWin never loads it from there and no install
    # writes it, so nothing else will ever remove it.
    /usr/lib/qt6/plugins/kwin/effects/kos_bridge.so
    "$prefix/lib/qt6/qml/Kos/Spatial3D"
    "$prefix/lib/qt6/qml/Kos/SurfaceShape"
    "$prefix/lib64/qt6/qml/Kos/Spatial3D"
    "$prefix/lib64/qt6/qml/Kos/SurfaceShape"
    /usr/lib/qt6/qml/Kos/Spatial3D
    /usr/lib/qt6/qml/Kos/SurfaceShape
    /usr/share/sddm/themes/kos
    /etc/sddm.conf.d/kos-theme.conf
    "$config_dir/Quickshell/kos-settings.conf"
    "$data_dir/kos"
    "$cache_dir/kos"
    "$cache_dir/kos-settings"
    "$cache_dir/kos-platform"
    "$cache_dir/liquid-shell"
    "$state_dir/kos"
    "$state_dir/kos-platform"
    "$state_dir/quickshell/kos"
    "$state_dir/quickshell/shell-data-service"
    "$runtime_dir/kos-platform.sock"
    "$runtime_dir/kos-data.sock"
    "$runtime_dir/kos-data.sock.lock"
    # Generated build trees include the downloaded ONNX Runtime SDK.
    "$project_dir/.build"
)

# Include explicit build overrides, but never source/home/root.
for build_root in "${KOS_BUILD_DIR:-}" "${KOS_APPS_BUILD_DIR:-}"; do
    [[ -n "$build_root" ]] || continue
    case "$build_root" in
        /|"$HOME"|"$project_dir"|*/../*|*/..|*/./*|*/.|[!/]*)
            echo "Unsafe build directory: $build_root" >&2; exit 2 ;;
    esac
    build_root=$(realpath -ms -- "$build_root") || exit 2
    case "$project_dir/" in "$build_root/"*)
        echo "Build cleanup would delete the checkout: $build_root" >&2; exit 2 ;;
    esac
    case "$HOME/" in "$build_root/"*)
        echo "Build cleanup would delete your home: $build_root" >&2; exit 2 ;;
    esac
    case "$build_root" in /usr|/usr/*|/etc|/etc/*|/nix|/nix/*)
        echo "Not a user build directory: $build_root" >&2; exit 2 ;;
    esac
    case "$build_root/" in
        "$project_dir/.build/"*) ;;
        "$project_dir/"*)
            if [[ -d "$build_root" && ! -f "$build_root/CMakeCache.txt" ]]; then
                echo "Checkout directory is not a CMake build tree: $build_root" >&2; exit 2
            fi
            tracked=$(git -C "$project_dir" ls-files -- ":(literal)${build_root#"$project_dir/"}" ) || exit 2
            if [[ -n "$tracked" ]]; then
                echo "Build directory contains tracked source: $build_root" >&2; exit 2
            fi ;;
    esac
    leftover_targets+=("$build_root")
done
# Only remove checkout result links, never recursively remove a Nix store.
for result in "$project_dir/result" "$project_dir/result-kos"; do
    [[ -L "$result" ]] && leftover_targets+=("$result")
done
shopt -s nullglob
leftover_targets+=("$prefix"/lib/libonnxruntime.so* "$prefix"/lib/libonnxruntime_providers_shared.so)
for app in kos-settings kos-weather kos-calendar kos-todo kos-music kos-pim-service kos-music-lx-source-host; do
    leftover_targets+=("$apps_prefix/bin/$app"
        "$apps_prefix/share/applications/$app.desktop"
        "$apps_prefix/share/icons/hicolor/scalable/apps/$app.svg"
        "$config_dir/NextKde/$app.conf"
        "$cache_dir/$app")
done
leftover_targets+=("$config_dir/NextKde/KosApplications.conf"
    "$apps_prefix/bin/kos-music-lx-source-host.js"
    "$apps_prefix/share/dbus-1/services/org.nextkde.Kos.Pim1.service"
    "$apps_prefix"/share/metainfo/org.nextkde.Kos.*.metainfo.xml
    "$apps_prefix/lib/quickshell")
for units_root in "$unit_dir" "$prefix/share/systemd/user" "$apps_prefix/share/systemd/user"; do
    for unit in kos-shell kos-platform kos-data kos-pim-service kos-shell-init shell-data-service; do
        leftover_targets+=("$units_root/$unit.service" "$units_root/$unit.service.d")
        for link in "$units_root"/*.wants/"$unit.service" "$units_root"/*.requires/"$unit.service"; do
            leftover_targets+=("$link")
        done
    done
done
# Older Quickshell versions stored KOS state under a hash. The KOS-specific
# widget filename identifies ownership; leave other Quickshell configs alone.
if [[ -d "$state_dir/quickshell/by-shell" ]]; then
    while IFS= read -r -d '' marker; do
        leftover_targets+=("$(dirname "$marker")")
    done < <(find "$state_dir/quickshell" -mindepth 2 -maxdepth 3 \
        -type f -name deskcenter-widgets.ini -print0)
fi
shopt -u nullglob

kwinrc_keys=(
    glassEnabled
    kos_bridgeEnabled
    kos_context_menu_inputEnabled
    kos_dock_window_animationEnabled
    quickshell_context_menu_inputEnabled
)

# --- scan what is actually present ---
present_core=()
present_leftover=()
present_keys=()

for f in "${core_targets[@]}"; do
    [[ -e "$f" || -L "$f" ]] && present_core+=("$f")
done
for f in "${leftover_targets[@]}"; do
    [[ -e "$f" || -L "$f" ]] && present_leftover+=("$f")
done
if [[ -f "$kwinrc" ]]; then
    for k in "${kwinrc_keys[@]}"; do
        grep -q "^${k}=" "$kwinrc" 2>/dev/null && present_keys+=("$k")
    done
fi

total=$(( ${#present_core[@]} + ${#present_leftover[@]} + ${#present_keys[@]} ))
if (( total == 0 )); then
    echo "Nothing to purge — the machine is already clean."
    echo "Run './tools/kosctl install' for a fresh install."
    exit 0
fi

# --- report ---
echo "=== KOS purge — the following will be deleted ==="
echo
echo "[1] Core (removed by 'kosctl uninstall'; includes KWin unloadEffect + blur restore"
echo "    and the /usr .so files, which needs sudo):"
if (( ${#present_core[@]} == 0 )); then
    echo "    (nothing — core already removed)"
fi
for f in "${present_core[@]}"; do echo "    $f"; done
echo
echo "[2] Full reset (includes imported gallery copies, settings, caches, models and builds):"
if (( ${#present_leftover[@]} == 0 )); then
    echo "    (none)"
fi
for f in "${present_leftover[@]}"; do echo "    $f"; done
echo
echo "[3] kwinrc keys (cleared via kwriteconfig6):"
if (( ${#present_keys[@]} == 0 )); then
    echo "    (none)"
fi
for k in "${present_keys[@]}"; do echo "    $k"; done
echo
echo "Full reset: imported gallery copies, app data (including calendar/tasks), settings, models, caches and builds are deleted."
echo "Original pictures outside KOS directories and shared OS packages (Qt/OpenCV/etc.) are preserved."
echo "NixOS declarative services must first be disabled in configuration and rebuilt."
[[ "${1:-}" == --dry-run ]] && exit 0
echo
confirm=y
if [[ "${1:-}" != --yes ]]; then
    read -rp "Proceed with deletion? [y/N] " confirm
fi
[[ "$confirm" == y || "$confirm" == Y ]] || { echo "Aborted — nothing was deleted."; exit 0; }

# Stop services first; detached development workers and Settings can otherwise
# recreate models/thumbnail caches while the deletion sweep is running.
if command -v systemctl >/dev/null 2>&1; then
    systemctl --user disable --now kos-shell.service kos-platform.service \
        kos-data.service kos-pim-service.service shell-data-service.service \
        kos-shell-init.service 2>/dev/null || true
fi
pids=()
for proc in /proc/[0-9]*; do
    [[ -O "$proc" ]] || continue
    exe=$(readlink "$proc/exe" 2>/dev/null) || continue
    name=${exe##*/}
    name=${name% (deleted)}
    case "$name" in
        kos-platform|kos-ai-worker|kos-data-service|kos-pim-service|kos-settings|kos-weather|kos-calendar|kos-todo|kos-music|kos-music-lx-source-host)
            pids+=("${proc##*/}") ;;
        qs|quickshell)
            mapfile -d '' -t args < "$proc/cmdline" 2>/dev/null || continue
            for ((i=1; i<${#args[@]}-1; i++)); do
                case "${args[i]}:${args[i+1]}" in
                    -c:kos|--config:kos|-p:"$project_dir/shell"|--path:"$project_dir/shell"|-p:"$config_dir/quickshell/kos"|--path:"$config_dir/quickshell/kos")
                        pids+=("${proc##*/}"); break ;;
                esac
            done ;;
    esac
done
if (( ${#pids[@]} )); then
    kill -TERM "${pids[@]}" 2>/dev/null || true
    for ((attempt=0; attempt<30; attempt++)); do
        remaining=()
        for pid in "${pids[@]}"; do
            kill -0 "$pid" 2>/dev/null && remaining+=("$pid")
        done
        (( ${#remaining[@]} )) || break
        sleep 0.1
    done
    if (( ${#remaining[@]} )); then
        kill -KILL "${remaining[@]}" 2>/dev/null || true
    fi
fi

# Shortcut cleanup uses KGlobalAccel, not a CLI the daemon does not expose.
# Stop owners first so cleanUp can remove their inactive shortcut registration.
qdbus_bin=$(command -v qdbus6 || command -v qdbus || true)
if [[ -n "$qdbus_bin" ]]; then
    "$qdbus_bin" org.kde.kglobalaccel /component/kos_platform \
        org.kde.kglobalaccel.Component.cleanUp >/dev/null 2>&1 || true
fi
# Legacy one-file-per-shortcut registrations are scoped to KOS names.
shopt -s nullglob
for shortcut in "$prefix"/share/applications/net.local.kos*.desktop; do
    rm -f -- "$shortcut" || exit 1
done
shopt -u nullglob

# Restore a selected KOS decoration before removing its plugin.
if command -v kreadconfig6 >/dev/null 2>&1 &&
    [[ "$(kreadconfig6 --file kwinrc --group org.kde.kdecoration2 --key library)" == kos_decoration ]]; then
    kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.kde.breeze || exit 1
fi

# Earlier Nix deployments copied read-only directories into the user prefix.
# Make only the known installed trees writable so uninstall can remove them.
for tree in "$config_dir/quickshell/kos" "$prefix/share/shared/qml" "$prefix/share/kos/settings"; do
    if [[ -d "$tree" && ! -L "$tree" ]]; then
        find "$tree" -type d -exec chmod u+w {} + || exit 1
    fi
done

# --- step 1: kosctl uninstall (KWin interactions + blur restore + /usr + core) ---
cd "$project_dir"
if [[ -x ./tools/kosctl ]]; then
    echo
    echo "=== Running 'kosctl uninstall' (sudo will be needed for /usr) ==="
    if ! ./tools/kosctl uninstall; then
        echo "kosctl uninstall failed; stopping to preserve restoration state. Re-run after fixing the error." >&2
        exit 1
    fi
fi

# --- step 2: delete leftover dirs/files ---
echo
echo "=== Sweeping leftovers ==="
# Do not delete a Plasma package still selected after restoration failed.
if command -v kreadconfig6 >/dev/null 2>&1 &&
    [[ "$(kreadconfig6 --file plasmashellrc --group Shell --key ShellPackage 2>/dev/null)" == org.kos.desktop ]]; then
    echo "Plasma shell restoration failed; leaving its package and saved state intact." >&2
    exit 1
fi
# Legacy plugin installs can predate the manifest. Unload them as well before
# the fixed-path fallback sweep; do not touch unrelated KWin effects.
qdbus_bin=$(command -v qdbus6 || command -v qdbus || true)
if [[ -n "$qdbus_bin" ]]; then
    for effect in glass kos_bridge kos_context_menu_input kos_dock_window_animation quickshell_context_menu_input; do
        "$qdbus_bin" org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect "$effect" >/dev/null 2>&1 || true
    done
fi
# Keep any legacy files inactive if the following administrator cleanup fails.
if command -v kwriteconfig6 >/dev/null 2>&1; then
    for effect in glass kos_bridge kos_context_menu_input kos_dock_window_animation quickshell_context_menu_input; do
        kwriteconfig6 --file kwinrc --group Plugins --key "${effect}Enabled" false --type bool --notify || exit 1
    done
fi
system_targets=()
for f in "${core_targets[@]}" "${leftover_targets[@]}"; do
    [[ -e "$f" || -L "$f" ]] || continue
    case "$f" in
        /usr/*|/etc/sddm.conf.d/kos-theme.conf) system_targets+=("$f") ;;
        *)
            if [[ -d "$f" && ! -L "$f" ]]; then
                find "$f" -type d -exec chmod u+w {} +
            fi
            rm -rf -- "$f" || { echo "Failed to remove: $f" >&2; exit 1; } ;;
    esac
done
if (( ${#system_targets[@]} )); then
    sudo rm -rf -- "${system_targets[@]}" || exit 1
fi

# --- step 3: clear kwinrc keys (kwriteconfig6 mirrors what kosctl does) ---
if command -v kwriteconfig6 >/dev/null 2>&1; then
    echo
    echo "=== Clearing kwinrc keys ==="
    for k in "${kwinrc_keys[@]}"; do
        kwriteconfig6 --file kwinrc --group Plugins --key "$k" --delete 2>/dev/null || true
    done
fi

# --- step 4: daemon-reload ---
if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user reset-failed kos-shell.service kos-platform.service kos-data.service \
        kos-pim-service.service shell-data-service.service 2>/dev/null || true
fi

if command -v busctl >/dev/null 2>&1; then
    busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus ReloadConfig >/dev/null 2>&1 || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$prefix/share/applications" >/dev/null 2>&1 || true
fi
# --- step 5: verify ---
echo
echo "=== Remaining install artifacts ==="
fail=0
for f in "${core_targets[@]}" "${leftover_targets[@]}"; do
    if [[ -e "$f" || -L "$f" ]]; then
        echo "  STILL EXISTS: $f"
        fail=1
    fi
done
if [[ -f "$kwinrc" ]]; then
    for k in "${kwinrc_keys[@]}"; do
        if grep -q "^${k}=" "$kwinrc" 2>/dev/null; then
            echo "  STILL SET: kwinrc:$k"
            fail=1
        fi
    done
fi
# plasmashell exits at startup ("starting invalid corona") if ShellPackage
# names a package that is no longer there, and a swept install leaves exactly
# that if `kosctl uninstall` could not write the key back. Surface it loudly:
# it is the difference between a working login and no wallpaper or panel.
if command -v kreadconfig6 >/dev/null 2>&1 &&
    [[ "$(kreadconfig6 --file plasmashellrc --group Shell --key ShellPackage 2>/dev/null)" == org.kos.desktop ]]; then
    echo
    echo "  WARNING: plasmashellrc still names org.kos.desktop, which was just deleted."
    echo "  plasmashell will not start until it is reverted — run:"
    echo "    kwriteconfig6 --file plasmashellrc --group Shell --key ShellPackage org.kde.plasma.desktop"
    fail=1
fi
if (( fail == 0 )); then
    echo "  all targets gone ✓"
    echo
    echo "Purge complete. Reboot now, then run './tools/kosctl install' for a clean install."
    echo "Then run './tools/kosctl start' and check the desktop and first model download manually."
else
    echo
    echo "Some targets remain — check the messages above."
    echo "Check permissions and any service that is recreating files, then re-run the script."
    exit 1
fi
