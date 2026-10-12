#!/bin/sh
set -eu
# The root-owned standalone recovery survives deletion/movement of the checkout.
action=--rollback
case "${1:-}" in --status) action=--status; shift ;; esac
if [ -x /usr/local/sbin/kos-greeter-rollback ]; then
    exec sudo /usr/local/sbin/kos-greeter-rollback "$action" "$@"
fi
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec sudo python3 "$script_dir/greeter-install.py" $action "$@"
