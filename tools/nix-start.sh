#!/usr/bin/env bash
# KOS NixOS Quick Start — wrapper for kos-ctl
# This script provides a quick way to manage KOS on NixOS

set -euo pipefail

if command -v kos-ctl >/dev/null 2>&1; then
    exec kos-ctl "$@"
fi

# Fallback: inline implementation if kos-ctl not installed yet
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_ok()   { printf "${GREEN}✓${NC} %s\n" "$1"; }
print_warn() { printf "${YELLOW}⚠${NC} %s\n" "$1"; }
print_err()  { printf "${RED}✗${NC} %s\n" "$1"; }

is_nixos() { [[ -f /etc/NIXOS ]]; }

find_kos_store() {
    for dir in /nix/store/*-kos-desktop-unstable; do
        if [[ -d "$dir/share/kos-desktop/shell" ]]; then
            echo "$dir"
            return
        fi
    done
}

sync_shell_config() {
    local shell_config="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/kos"
    local kos_store
    kos_store=$(find_kos_store)

    if [[ -z "$kos_store" ]]; then
        print_err "kos-desktop package not found"
        return 1
    fi

    if [[ -d "$shell_config" ]]; then
        find "$shell_config" -type d -exec chmod u+w {} + 2>/dev/null || true
        find "$shell_config" -type f -exec chmod u+w {} + 2>/dev/null || true
        rm -rf "$shell_config"
    fi

    mkdir -p "$shell_config/shared/qml"
    cp -rL --no-preserve=mode "$kos_store/share/kos-desktop/shell/." "$shell_config/"

    local controls_src=""
    if [[ -d "$kos_store/share/shared/qml/controls" ]]; then
        controls_src="$kos_store/share/shared/qml/controls"
    elif [[ -d "$kos_store/share/kos-desktop/shared/qml/controls" ]]; then
        controls_src="$kos_store/share/kos-desktop/shared/qml/controls"
    fi
    if [[ -n "$controls_src" ]]; then
        cp -rL --no-preserve=mode "$controls_src" "$shell_config/shared/qml/"
    fi

    print_ok "Shell config synced"
}

fix_broken_links() {
    local unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    local kos_store
    kos_store=$(find_kos_store)

    if [[ -z "$kos_store" ]]; then
        return 1
    fi

    local services_dir="$kos_store/lib/systemd/user"
    [[ -d "$services_dir" ]] || return 1

    local fixed=false
    for unit in kos-platform.service kos-data.service kos-shell.service; do
        local target="$unit_dir/$unit"
        local source="$services_dir/$unit"
        
        if [[ ! -e "$target" ]]; then
            rm -f "$target" 2>/dev/null || true
            ln -s "$source" "$target"
            fixed=true
        fi
    done

    if $fixed; then
        systemctl --user daemon-reload
        print_ok "Fixed broken service links"
    fi
}

start_services() {
    local unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    
    # Auto-fix broken links
    local needs_fix=false
    for unit in kos-platform.service kos-data.service kos-shell.service; do
        if [[ ! -e "$unit_dir/$unit" ]]; then
            needs_fix=true
            break
        fi
    done
    if $needs_fix; then
        fix_broken_links
    fi

    systemctl --user daemon-reload
    sync_shell_config

    for unit in kos-platform.service kos-data.service kos-shell.service; do
        if systemctl --user is-active "$unit" >/dev/null 2>&1; then
            systemctl --user restart "$unit"
        else
            systemctl --user start "$unit" 2>/dev/null || true
        fi
    done
    print_ok "KOS services started"
}

stop_services() {
    for unit in kos-shell.service kos-platform.service kos-data.service; do
        if systemctl --user is-active "$unit" >/dev/null 2>&1; then
            systemctl --user stop "$unit"
            print_ok "$unit stopped"
        fi
    done
}

show_status() {
    printf "\n${GREEN}=== KOS Service Status ===${NC}\n"
    for unit in kos-platform.service kos-data.service kos-shell.service; do
        if systemctl --user is-active "$unit" >/dev/null 2>&1; then
            printf "  ${GREEN}●${NC} %s: running\n" "$unit"
        else
            printf "  ${RED}●${NC} %s: stopped\n" "$unit"
        fi
    done
    printf "\n"
}

usage() {
    cat <<'EOF'
KOS NixOS Quick Start

Usage: ./tools/nix-start.sh <command>

Commands:
  start     Start all KOS services
  stop      Stop all KOS services
  restart   Restart all KOS services
  status    Show service status
  logs      Follow KOS logs
  sync      Sync shell config only
  help      Show this help

EOF
}

main() {
    is_nixos || { print_err "Not running on NixOS"; exit 1; }

    case "${1:-start}" in
        start)    start_services; show_status ;;
        stop)     stop_services ;;
        restart)  stop_services; sleep 1; start_services; show_status ;;
        status)   show_status ;;
        logs)     journalctl --user -u kos-platform.service -u kos-data.service -u kos-shell.service -f ;;
        sync)     sync_shell_config ;;
        help|-h|--help) usage ;;
        *)        print_err "Unknown: $1"; usage; exit 1 ;;
    esac
}

main "$@"
