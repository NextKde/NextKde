#!/bin/sh
# Compatibility entry point: application sources/releases live outside core.
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
action=install
app=""
version=""
listenfree=false
backend=flatpak
confirm=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --backend=source) backend=source ;;
        --backend=flatpak) backend=flatpak ;;
        --yes) confirm=true ;;
        --app)
            [ "$#" -ge 2 ] || { printf '%s\n' 'Missing value for --app' >&2; exit 2; }
            app=$2
            shift ;;
        --app=*) app=${1#--app=} ;;
        --version)
            [ "$#" -ge 2 ] || { printf '%s\n' 'Missing value for --version' >&2; exit 2; }
            version=$2
            shift ;;
        --version=*) version=${1#--version=} ;;
        install|update|status|check|check-update|uninstall|cleanup-plan|prune) action=$1 ;;
        --update) action=update ;;
        --uninstall) action=uninstall ;;
        --with-listenfree) listenfree=true ;;
        --with-listenfree-video)
            printf '%s\n' '--with-listenfree-video is no longer supported here. Use the NextKde/ListenFree repository for explicit video-feature builds; stable Releases control installer features.' >&2
            exit 2 ;;
        --help|-h)
            printf '%s\n' \
                "Usage: $0 [install|update|status|check-update|uninstall] [--app APP] [--yes] [--backend=flatpak|source]" \
                'APP: calendar, calculator, weather, listenfree (todo is an alias for calendar).' \
                'Default: user Flatpak via kos-apps, the same backend as Settings. No automatic remote setup.' \
                'Default apps: Calendar, Calculator and Weather. ListenFree is explicit.' \
                'Mutations require terminal confirmation or --yes. Personal data is kept.' \
                'No approved published source means unavailable; no source fallback.' \
                '--backend=source selects the legacy/developer source installer explicitly; --version is source-only.' \
                'Source cleanup: --backend=source --app APP cleanup-plan; prune --yes keeps current and one rollback version.'
            exit 0 ;;
        *) printf 'Unknown application option: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

case "$app" in
    todo) app=calendar ;;
    ''|calendar|calculator|weather|listenfree) ;;
    *) printf 'Unknown application: %s\n' "$app" >&2; exit 2 ;;
esac
if [ -n "$app" ] && [ "$listenfree" = true ]; then
    printf '%s\n' 'Choose either --app or --with-listenfree, not both.' >&2
    exit 2
fi
if [ "$backend" = flatpak ]; then
    if [ "$action" = cleanup-plan ] || [ "$action" = prune ]; then
        printf '%s\n' 'Program-version cleanup requires --backend=source and an explicit --app.' >&2
        exit 2
    fi
    if [ -n "$version" ] || [ "$action" = check ]; then
        printf '%s\n' '--version and build-dependency check are source-only; choose --backend=source explicitly.' >&2
        exit 2
    fi
    cli=$(command -v kos-apps || true)
    if [ -z "$cli" ]; then
        printf '%s\n' 'kos-apps is not installed. Build and install core Settings (including kos-apps); no source fallback was attempted.' >&2
        exit 2
    fi
    run_flatpak() {
        if [ "$confirm" = true ]; then "$cli" "$action" --app "$1" --yes
        else "$cli" "$action" --app "$1"; fi
    }
    if [ -n "$app" ]; then run_flatpak "$app"; exit $?; fi
    for selected in calendar calculator weather; do run_flatpak "$selected"; done
    if [ "$listenfree" = true ]; then run_flatpak listenfree; fi
    exit 0
fi
if ! command -v python3 >/dev/null 2>&1; then
    printf '%s\n' 'Missing dependency: python3' >&2
    exit 1
fi
if [ -n "$version" ] && [ -z "$app" ]; then
    printf '%s\n' '--version requires --app; each operation selects one app (Calendar/Calculator/Weather share the kos-apps release version).' >&2
    exit 2
fi
if [ "$action" = cleanup-plan ] || [ "$action" = prune ]; then
    if [ -z "$app" ] || [ -n "$version" ]; then
        printf '%s\n' 'Cleanup requires one --app and does not accept --version.' >&2
        exit 2
    fi
    if [ "$confirm" = true ]; then
        exec python3 "$script_dir/app-installer.py" --app "$app" "$action" --yes
    fi
    exec python3 "$script_dir/app-installer.py" --app "$app" "$action"
fi
if [ -n "$app" ]; then
    if [ -n "$version" ]; then
        exec python3 "$script_dir/app-installer.py" --app "$app" "$action" --version "$version"
    fi
    exec python3 "$script_dir/app-installer.py" --app "$app" "$action"
fi
# Each app is its own transaction. Stop on error and preserve prior successes.
for app in calendar calculator weather; do
    python3 "$script_dir/app-installer.py" --app "$app" "$action"
done
if [ "$listenfree" = true ]; then
    exec python3 "$script_dir/app-installer.py" --app listenfree "$action"
fi
