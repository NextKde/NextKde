#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(dirname -- "$script_dir")
prefix=${KOS_INSTALL_PREFIX:-"$HOME/.local"}
build_dir=${KOS_APPS_BUILD_DIR:-"$project_dir/.build/apps-release"}
unit_dir=${XDG_CONFIG_HOME:-"$HOME/.config"}/systemd/user

for command_name in busctl cmake ctest ninja readlink systemctl; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Missing install dependency: $command_name" >&2
        exit 1
    fi
done

cmake --preset apps-release -S "$project_dir" \
    -DCMAKE_INSTALL_PREFIX="$prefix"
cmake --build "$build_dir" --parallel
ctest --test-dir "$build_dir" --output-on-failure
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

"$script_dir/verify-apps-install.sh" "$prefix"
echo "KOS applications are installed for this user and ready from the launcher."
