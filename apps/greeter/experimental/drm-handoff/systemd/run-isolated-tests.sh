#!/bin/bash
set -euo pipefail
TASK_ROOT=$(cd -- "$(dirname -- "$0")" && pwd)
TASK_CACHE=${KOS_HANDOFF_BUILD_ROOT:-"$HOME/.cache/nextkde-builds/drm-handoff"}
TASK_APP="$TASK_CACHE/authorizer-fixture/app"
# Fresh rootfs gives root ownership inside the disposable namespace. No sockets
# or device nodes from the host are exposed, and /run is private.
for task_test in test-authorizer.py test-entry.py; do
 bwrap --unshare-all --die-with-parent --new-session --uid 0 --gid 0 \
  --tmpfs / --dev /dev --proc /proc --ro-bind /usr/bin /usr/bin \
  --ro-bind /usr/lib /usr/lib --ro-bind /usr/share /usr/share --ro-bind /etc /etc \
  --symlink /usr/lib /lib --symlink /usr/lib /lib64 --dir /tmp --dir /run \
  --dir /var/lib/kos/greeter --dir /usr/local/lib/kos-greeter \
  --dir /usr/local/lib/kos-greeter/app \
  --ro-bind "$TASK_APP/companion" /usr/local/lib/kos-greeter/app/companion \
  --ro-bind "$TASK_ROOT" /tests --clearenv --setenv PATH /usr/bin:/bin \
  /usr/bin/python3 -I "/tests/$task_test"
done
