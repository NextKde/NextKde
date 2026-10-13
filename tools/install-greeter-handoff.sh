#!/bin/bash
# Install files only. No service changes, enabling, or login restart.
set -euo pipefail
TASK_ROOT=$(cd -- "$(dirname -- "$0")" && pwd)
if [[ $# == 0 || ( $# == 1 && $1 == --check ) ]]; then
    if [[ $EUID == 0 ]]; then
        echo 'Run this command as your ordinary user; it invokes sudo only for installing verified files.' >&2
        exit 2
    fi
    TASK_TEMP=$(/usr/bin/mktemp -d /tmp/kos-handoff-bundle.XXXXXXXX)
    trap '/usr/bin/rm -rf -- "$TASK_TEMP"' EXIT
    TASK_CACHE=${KOS_HANDOFF_BUILD_ROOT:-"$HOME/.cache/nextkde-builds/drm-handoff"}
    /usr/bin/python3 -I "$TASK_ROOT/install-greeter-handoff.py" prepare --build-root "$TASK_CACHE" --bundle "$TASK_TEMP/bundle"
    TASK_HASH=$(/usr/bin/sha256sum "$TASK_TEMP/bundle/manifest.json")
    TASK_HASH=${TASK_HASH%% *}
    if [[ $# == 1 ]]; then
        /usr/bin/python3 -I "$TASK_ROOT/install-greeter-handoff.py" install --bundle "$TASK_TEMP/bundle" --manifest-sha256 "$TASK_HASH" --check
    else
        /usr/bin/sudo /usr/bin/python3 -I "$TASK_ROOT/install-greeter-handoff.py" install --bundle "$TASK_TEMP/bundle" --manifest-sha256 "$TASK_HASH"
    fi
else
    exec /usr/bin/python3 -I "$TASK_ROOT/install-greeter-handoff.py" "$@"
fi
