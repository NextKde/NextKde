#!/bin/bash
set -euo pipefail
TASK_ROOT=$(cd -- "$(dirname -- "$0")" && pwd)
TASK_CACHE=${KOS_HANDOFF_BUILD_ROOT:-"$HOME/.cache/nextkde-builds/drm-handoff"}
exec bwrap --unshare-all --die-with-parent --new-session --ro-bind / / \
 --tmpfs /run --tmpfs /tmp --dev /dev --proc /proc \
 --dir /tmp/kos-handoff-runtime --chmod 0700 /tmp/kos-handoff-runtime \
 --setenv XDG_RUNTIME_DIR /tmp/kos-handoff-runtime \
 --setenv XDG_CONFIG_HOME /tmp/kos-config --setenv XDG_CACHE_HOME /tmp/kos-cache \
 --setenv HOME /tmp --setenv KOS_ISOLATED_HANDOFF_FIXTURE 1 \
 --unsetenv DISPLAY --unsetenv WAYLAND_DISPLAY --unsetenv GREETD_SOCK \
 --unsetenv DBUS_SESSION_BUS_ADDRESS --unsetenv DBUS_SYSTEM_BUS_ADDRESS \
 --unsetenv KOS_KWIN_BOOTSTRAP_FD --unsetenv KOS_KWIN_HANDOFF_CONTROL_FD \
 python3 "$TASK_ROOT/test-kwin-coordinator.py" "$TASK_CACHE/build/bin/kwin_wayland" "$TASK_CACHE/fixture-session"
