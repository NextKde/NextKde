#!/usr/bin/env bash
set -euo pipefail
if [[ $# -lt 3 ]]; then
    echo "usage: run-fixture.sh BUILT_KWIN SESSION_FIXTURE ROOT_OWNED_PNG [normal|timeout|cancel|bootstrap]" >&2
    exit 2
fi
base=$(cd -- "$(dirname -- "$0")" && pwd)
kwin=$(realpath -- "$1")
session=$(realpath -- "$2")
png=$(realpath -- "$3")
case_name=${4:-normal}
python3 - "$png" <<'PY'
import os,stat,sys
fd=os.open(sys.argv[1],os.O_RDONLY|os.O_NOFOLLOW)
s=os.fstat(fd)
os.close(fd)
if not stat.S_ISREG(s.st_mode) or s.st_uid != 0 or s.st_mode & 0o022:
    raise SystemExit("fixture PNG must be root-owned before entering user namespace")
PY
# No host /run, /tmp, /dev or display/auth sockets are visible. /dev is synthetic.
exec bwrap --unshare-all --die-with-parent --new-session --ro-bind / / \
    --tmpfs /run --tmpfs /tmp --dev /dev --proc /proc \
    --dir /tmp/kos-handoff-runtime --chmod 0700 /tmp/kos-handoff-runtime \
    --setenv XDG_RUNTIME_DIR /tmp/kos-handoff-runtime \
    --setenv XDG_CONFIG_HOME /tmp/kos-config --setenv XDG_CACHE_HOME /tmp/kos-cache \
    --setenv HOME /tmp --setenv KOS_ISOLATED_HANDOFF_FIXTURE 1 \
    --unsetenv DISPLAY --unsetenv WAYLAND_DISPLAY --unsetenv GREETD_SOCK \
    --unsetenv DBUS_SESSION_BUS_ADDRESS --unsetenv DBUS_SYSTEM_BUS_ADDRESS \
    --unsetenv KOS_KWIN_BOOTSTRAP_FD --unsetenv KOS_KWIN_HANDOFF_CONTROL_FD \
    dbus-run-session -- python3 "$base/fixture.py" --kwin "$kwin" --session "$session" --png "$png" --case "$case_name"
