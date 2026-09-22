#!/usr/bin/env bash
# purge-kos.sh — remove every KOS install artifact so the next
# `./tools/kosctl install` is a true clean install.
#
# Workflow:
#   1. Print the full deletion list (core + leftovers) and wait for confirm.
#   2. Call `./tools/kosctl uninstall` for the KWin/plugin/service layer --
#      it runs unloadEffect + blur/decoration restore BEFORE deleting the
#      /usr .so files, using the state it saved at install time. This step
#      will ask for sudo to remove /usr/lib/qt6/plugins/...
#   3. Sweep leftovers uninstall leaves behind: empty share dirs, apps-era
#      files (install-apps.sh产物, not owned by kosctl), stray systemd wants
#      links, the optional lockscreen/app surfaces, and any kwinrc keys that
#      survived.
#   4. daemon-reload, then verify every target is gone.
#
# Idempotent: safe to run multiple times. Read-only until you confirm.

set -uo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
prefix="${XDG_DATA_HOME:-$HOME/.local}"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
unit_dir="$config_dir/systemd/user"
wants_dir="$unit_dir/graphical-session.target.wants"
kwinrc="$config_dir/kwinrc"

# --- core targets that `kosctl uninstall` owns (fixed list, for the report) ---
core_targets=(
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
    /usr/lib/qt6/plugins/kwin/effects/plugins/kos_context_menu_input.so
    /usr/lib/qt6/plugins/kwin/effects/plugins/kos_dock_window_animation.so
    /usr/lib/qt6/plugins/kwin/effects/plugins/quickshell_context_menu_input.so
    /usr/lib/qt6/plugins/kwin/effects/configs/kwin_glass_config.so
    /usr/lib/qt6/qml/Kos/SurfaceShape/libkos_surface_shape.so
    "$prefix/share/kos/kwin-system-files.manifest"
    "$prefix/share/kos/kwin-effect-state"
    "$prefix/share/kos/kwin-decoration-state"
)

# --- leftovers that uninstall does NOT cover (sweep these) ---
leftover_targets=(
    # empty share dirs (uninstall deletes contents, leaves the dirs)
    "$prefix/share/kos"
    "$prefix/share/shared"
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
    # runtime caches/state (regenerated on next start)
)

kwinrc_keys=(
    glassEnabled
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
# cache/state globs
present_caches=()
shopt -s nullglob
for f in "$HOME"/.cache/kos* "$HOME"/.local/state/kos*; do
    present_caches+=("$f")
done
shopt -u nullglob

total=$(( ${#present_core[@]} + ${#present_leftover[@]} + ${#present_keys[@]} + ${#present_caches[@]} ))
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
echo "[2] Leftovers (not covered by uninstall — safe to delete, recreated on next install):"
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
echo "[4] Runtime caches/state (regenerated on next start):"
if (( ${#present_caches[@]} == 0 )); then
    echo "    (none)"
fi
for f in "${present_caches[@]}"; do echo "    $f"; done
echo
echo "State data under ~/.local/share/kos (if any) is preserved by kosctl uninstall."
echo
read -rp "Proceed with deletion? [y/N] " confirm
[[ "$confirm" == y || "$confirm" == Y ]] || { echo "Aborted — nothing was deleted."; exit 0; }

# --- step 1: kosctl uninstall (KWin interactions + blur restore + /usr + core) ---
cd "$project_dir"
if [[ -x ./tools/kosctl ]]; then
    echo
    echo "=== Running 'kosctl uninstall' (sudo will be needed for /usr) ==="
    if ! ./tools/kosctl uninstall; then
        echo "kosctl uninstall returned non-zero; continuing with the sweep." >&2
    fi
fi

# --- step 2: delete leftover dirs/files ---
echo
echo "=== Sweeping leftovers ==="
for f in "${present_leftover[@]}"; do
    rm -rf -- "$f" 2>/dev/null || true
done
for f in "${present_caches[@]}"; do
    rm -rf -- "$f" 2>/dev/null || true
done

# --- step 3: clear kwinrc keys (kwriteconfig6 mirrors what kosctl does) ---
if (( ${#present_keys[@]} > 0 )) && command -v kwriteconfig6 >/dev/null 2>&1; then
    echo
    echo "=== Clearing kwinrc keys ==="
    for k in "${present_keys[@]}"; do
        kwriteconfig6 --file kwinrc --group Plugins --key "$k" --delete 2>/dev/null || true
    done
fi

# --- step 4: daemon-reload ---
if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload 2>/dev/null || true
fi

# --- step 5: verify ---
echo
echo "=== Verification (every line should say 'gone') ==="
fail=0
for f in "${core_targets[@]}" "${leftover_targets[@]}" "${present_caches[@]}"; do
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
if (( fail == 0 )); then
    echo "  all targets gone ✓"
    echo
    echo "Purge complete. Reboot now, then run './tools/kosctl install' for a clean install."
    echo "After install, run './tools/verify-real-install.sh' to check the result."
else
    echo
    echo "Some targets remain — check the messages above."
    echo "Common cause: sudo was refused for /usr, or a file is held open by a running process."
    echo "Reboot clears the latter; re-run this script for the former."
    exit 1
fi
