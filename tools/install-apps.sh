#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(dirname -- "$script_dir")
prefix=${KOS_INSTALL_PREFIX:-"$HOME/.local"}
build_dir=${KOS_APPS_BUILD_DIR:-"$project_dir/.build/apps-release"}
unit_dir=${XDG_CONFIG_HOME:-"$HOME/.config"}/systemd/user
listenfree=OFF
for argument in "$@"; do
    case "$argument" in
        --with-listenfree) listenfree=ON ;;
        --help|-h)
            echo "Usage: $0 [--with-listenfree]"
            echo "Default: Calendar, Calculator, Todo and Weather."
            echo "--with-listenfree also builds the music player and its private audio SDK."
            exit 0 ;;
        *) echo "Unknown application install option: $argument" >&2; exit 2 ;;
    esac
done

if ! command -v python3 >/dev/null 2>&1; then
    echo "Missing dependency: python3 (Arch: sudo pacman -S python; Ubuntu: sudo apt install python3)" >&2
    exit 1
fi
sdk=""
if test "$listenfree" = ON; then
    python3 "$script_dir/check-apps-dependencies.py" --with-listenfree
    if test -n "${KOS_LISTENFREE_SDK:-}"; then
        sdk="$KOS_LISTENFREE_SDK"
        if test ! -d "$sdk"; then
            echo "Configured ListenFree SDK directory does not exist: $sdk" >&2
            exit 1
        fi
    else
        sdk="$project_dir/.build/listenfree-sdk"
        "$script_dir/prepare-listenfree-sdk.sh" "$sdk"
    fi
else
    python3 "$script_dir/check-apps-dependencies.py"
    echo "Installing Calendar, Calculator, Todo and Weather (ListenFree not selected)."
fi

# An install must not build or run tests -- they have one owner,
# tools/run-tests.sh (the same policy the core kosctl build follows).
cmake --preset apps-release -S "$project_dir" -B "$build_dir" \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DKOS_LISTENFREE_SDK="$sdk" \
    -DKOS_BUILD_LISTENFREE="$listenfree" \
    -DBUILD_TESTING=OFF
jobs=${CMAKE_BUILD_PARALLEL_LEVEL:-$(nproc 2>/dev/null || echo 4)}
case "$jobs" in ''|*[!0-9]*) jobs=4 ;; esac
if [ "$jobs" -gt 12 ]; then jobs=12; fi
mkdir -p "$build_dir/tmp"
# /tmp can be a small tmpfs; the core kosctl redirects the same way.
TMPDIR="$build_dir/tmp" GOTMPDIR="$build_dir/tmp" \
    cmake --build "$build_dir" --parallel "$jobs"
cmake --install "$build_dir"

# ~/.local/share/systemd/user is a standard user-unit search path. Keep a
# config-level copy as an intentional upgrade for older NextKde installs.
mkdir -p "$unit_dir"
install -m 0644 "$prefix/share/systemd/user/kos-data.service" \
    "$unit_dir/kos-data.service"
install -m 0644 "$prefix/share/systemd/user/kos-pim-service.service" \
    "$unit_dir/kos-pim-service.service"

systemctl --user daemon-reload
systemctl --user disable --now shell-data-service.service >/dev/null 2>&1 || true
systemctl --user enable --now kos-data.service
systemctl --user restart kos-data.service

# Calendar and Todo activate the PIM owner through D-Bus. Stop and disable a
# unit left enabled by older app bundles so Shell-only logins do not create an
# unnecessary resident application service.
systemctl --user disable --now kos-pim-service.service >/dev/null 2>&1 || true
pim_pid=$(busctl --user status org.nextkde.Kos.Pim1 2>/dev/null \
    | sed -n 's/^PID=//p' | head -n 1 || true)
case "$pim_pid" in
    ''|*[!0-9]*) ;;
    *)
        pim_executable=$(readlink -f "/proc/$pim_pid/exe" 2>/dev/null || true)
        case "$pim_executable" in
            "$prefix/bin/kos-pim-service"|"$prefix/bin/kos-pim-service (deleted)")
                kill "$pim_pid"
                attempt=0
                while kill -0 "$pim_pid" 2>/dev/null && test "$attempt" -lt 20; do
                    sleep 0.1
                    attempt=$((attempt + 1))
                done
                ;;
        esac
        ;;
esac
# dbus-broker caches activation metadata. Reload it before any PIM client can
# request the name again, so activation is delegated to the user unit instead
# of creating a detached legacy process.
busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
    org.freedesktop.DBus ReloadConfig >/dev/null

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$prefix/share/applications"
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t "$prefix/share/icons/hicolor" >/dev/null
fi
if command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 --noincremental >/dev/null
fi

# Settings and its complete shared QML runtime are deployed by core install.
# Replacing only main.qml here mixes new imports with an older core runtime.
set --
if test "$listenfree" = ON; then set -- --with-listenfree; fi
python3 "$script_dir/register-default-apps.py" --prefix "$prefix" "$@"
"$script_dir/verify-apps-install.sh" "$prefix" "$@"
echo "KOS applications are installed for this user and ready from the launcher."
