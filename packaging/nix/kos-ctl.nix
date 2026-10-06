{
  lib,
  writeShellScriptBin,
  jq,
  coreutils,
  systemd,
  gnugrep,
  ...
}:

writeShellScriptBin "kos-ctl" ''
  # KOS NixOS Control Interface
  # Unified interface for managing KOS Desktop Shell on NixOS

  set -euo pipefail

  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  CYAN='\033[0;36m'
  NC='\033[0m'

  UNIT_DIR="''${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  SHELL_CONFIG="''${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/kos"

  print_ok()   { printf "$GREEN✓$NC %s\n" "$1"; }
  print_warn() { printf "$YELLOW⚠$NC %s\n" "$1"; }
  print_err()  { printf "$RED✗$NC %s\n" "$1"; }
  print_info() { printf "$CYANℹ$NC %s\n" "$1"; }

  usage() {
    cat <<'EOF'
kos-ctl — NixOS KOS Desktop Shell Controller

Usage: kos-ctl <command> [options]

Commands:
  start       Start all KOS services
  stop        Stop all KOS services
  restart     Restart all KOS services
  status      Show service status
  logs        Follow KOS logs
  sync        Sync shell config from Nix store
  doctor      Check KOS installation health
  enable      Enable KOS services for autostart
  disable     Disable KOS autostart

Examples:
  kos-ctl start      # Start KOS
  kos-ctl status     # Check status
  kos-ctl logs       # View logs

EOF
  }

  check_nixos() {
    if [[ ! -f /etc/NIXOS ]]; then
      print_err "This command is only for NixOS systems"
      exit 1
    fi
  }

  find_kos_store() {
    for dir in /nix/store/*-kos-desktop-unstable; do
      if [[ -d "$dir/share/kos-desktop/shell" ]]; then
        echo "$dir"
        return
      fi
    done
  }

  sync_shell_config() {
    local kos_store
    kos_store=$(find_kos_store)

    if [[ -z "$kos_store" ]]; then
      print_err "kos-desktop package not found in Nix store"
      print_info "Run: sudo nixos-rebuild switch"
      return 1
    fi

    print_info "Syncing shell config from Nix store..."

    # Remove old config (fix permissions first)
    if [[ -d "$SHELL_CONFIG" ]]; then
      find "$SHELL_CONFIG" -type d -exec chmod u+w {} + 2>/dev/null || true
      find "$SHELL_CONFIG" -type f -exec chmod u+w {} + 2>/dev/null || true
      rm -rf "$SHELL_CONFIG"
    fi

    # Create fresh directories
    mkdir -p "$SHELL_CONFIG/shared/qml"

    # Copy shell QML (follow symlinks, ignore source permissions)
    cp -rL --no-preserve=mode "$kos_store/share/kos-desktop/shell/." "$SHELL_CONFIG/"

    # Copy shared controls
    local controls_src=""
    if [[ -d "$kos_store/share/shared/qml/controls" ]]; then
      controls_src="$kos_store/share/shared/qml/controls"
    elif [[ -d "$kos_store/share/kos-desktop/shared/qml/controls" ]]; then
      controls_src="$kos_store/share/kos-desktop/shared/qml/controls"
    fi
    if [[ -n "$controls_src" ]]; then
      cp -rL --no-preserve=mode "$controls_src" "$SHELL_CONFIG/shared/qml/"
    fi

    print_ok "Shell config synced"
  }

  start_services() {
    systemctl --user daemon-reload

    # Sync shell config first
    sync_shell_config

    # Start all services
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
    printf "\n$GREEN=== KOS Service Status ===$NC\n"
    for unit in kos-platform.service kos-data.service kos-shell.service; do
      if systemctl --user is-active "$unit" >/dev/null 2>&1; then
        printf "  $GREEN●$NC %s: running\n" "$unit"
      else
        printf "  $RED●$NC %s: stopped\n" "$unit"
      fi
    done
    printf "\n"
  }

  enable_autostart() {
    for unit in kos-platform.service kos-data.service kos-shell.service; do
      systemctl --user enable "$unit"
      print_ok "$unit enabled"
    done
  }

  disable_autostart() {
    for unit in kos-shell.service kos-platform.service kos-data.service; do
      systemctl --user disable "$unit" 2>/dev/null || true
      print_ok "$unit disabled"
    done
  }

  doctor() {
    print_info "Checking KOS installation..."

    # Check binaries
    for bin in kos-platform kos-data-service; do
      if command -v "$bin" >/dev/null 2>&1 || [[ -f "/run/current-system/sw/libexec/$bin" ]]; then
        print_ok "$bin found"
      else
        print_err "$bin not found"
      fi
    done

    # Check quickshell
    if command -v quickshell >/dev/null 2>&1; then
      print_ok "quickshell: $(command -v quickshell)"
    else
      print_err "quickshell not found"
    fi

    # Check shell config
    if [[ -d "$SHELL_CONFIG/shell" ]]; then
      print_ok "Shell config exists"
    else
      print_warn "Shell config missing (run: kos-ctl sync)"
    fi

    # Check systemd services
    for unit in kos-platform.service kos-data.service kos-shell.service; do
      if [[ -f "$UNIT_DIR/$unit" ]]; then
        print_ok "$unit: installed"
      else
        print_warn "$unit: not installed"
      fi
    done

    # Check for broken symlinks
    local broken=0
    for unit in kos-platform.service kos-data.service kos-shell.service; do
      if [[ -L "$UNIT_DIR/$unit" ]] && [[ ! -e "$UNIT_DIR/$unit" ]]; then
        print_err "$unit: broken symlink"
        broken=1
      fi
    done
    if (( broken )); then
      print_warn "Run: kos-ctl start (will auto-fix broken links)"
    fi

    printf "\n"
  }

  # Main
  check_nixos

  case "''${1:-help}" in
    start)    start_services ;;
    stop)     stop_services ;;
    restart)  stop_services; sleep 1; start_services ;;
    status)   show_status ;;
    logs)     journalctl --user -u kos-platform.service -u kos-data.service -u kos-shell.service -f ;;
    sync)     sync_shell_config ;;
    doctor)   doctor ;;
    enable)   enable_autostart ;;
    disable)  disable_autostart ;;
    help|-h|--help) usage ;;
    *)
      print_err "Unknown command: ''${1:-}"
      usage
      exit 1
      ;;
  esac
''
