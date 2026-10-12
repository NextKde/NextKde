#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "$(id -u)" = 0 ]; then
    echo 'Run this script as your normal user; it uses sudo only for installation.' >&2
    exit 1
fi
case "${1:-}" in
    --check) exec sudo python3 "$script_dir/greeter-install.py" --check ;;
    --status) exec sudo python3 "$script_dir/greeter-install.py" --status ;;
    --help|-h)
        cat <<'USAGE'
Usage: ./tools/install-greeter.sh [--no-wallpaper-sync] [--files-only | --activate-now]
       ./tools/install-greeter.sh --check | --status
       ./tools/install-greeter.sh --refresh-wallpaper [--no-wallpaper-sync]
Builds the current local source as your user, then installs or updates using sudo.
No remote source download. Existing installations update without a service restart.
The original recovery snapshot and boot selection are preserved on update.
First install default: selects greetd for the next boot; the desktop stays running.
--activate-now: switch immediately from a recovery text TTY, ending the desktop.
--files-only: install app/config but preserve boot service enablement.
--refresh-wallpaper: renew the 24-hour public copy from current consent;
                    --no-wallpaper-sync revokes your existing public copy.
Rollback: ./tools/rollback-installed-greeter.sh (use a text TTY if greetd is running).
USAGE
        exit 0 ;;

esac
workspace=$(mktemp -d)
bundle=$workspace/bundle
trap 'rm -rf -- "$workspace"' EXIT HUP INT TERM
sync_flag=
refresh=false
for arg in "$@"; do
    case "$arg" in
        --no-wallpaper-sync) sync_flag=--no-wallpaper-sync ;;
        --files-only|--activate-now) ;;
        --refresh-wallpaper) refresh=true ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done
if "$refresh"; then
    for arg in "$@"; do
        case "$arg" in --refresh-wallpaper|--no-wallpaper-sync) ;; *) echo 'Refresh cannot be combined with install activation options.' >&2; exit 2 ;; esac
    done
fi
python3 "$script_dir/greeter-install.py" --build "$bundle" ${sync_flag:+"$sync_flag"}
if "$refresh"; then
    sudo python3 "$script_dir/greeter-install.py" --refresh-wallpaper "$bundle" ${sync_flag:+"$sync_flag"}
else
    sudo python3 "$script_dir/greeter-install.py" --install "$bundle" "$@"
fi
