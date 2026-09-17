#!/usr/bin/env bash
# Headless check for the lock screen package: runs the shipped QML against
# stubbed greeter context objects, asserts the input state machine via the
# process exit code, and renders lock.png for eyeballing.
#
# Usage: ./run.sh   (exit 0 = all assertions passed; nonzero = failing check)
set -euo pipefail
cd "$(dirname "$0")"

# Move any older render out of the way first, so a passing exit code cannot be
# mistaken for a stale image. `mv`, not `rm`: the sandbox wraps deletion.
if [ -f lock.png ]; then
    stale="$(mktemp -d)/lock.png"
    mv -f lock.png "$stale"
fi

# Twice: once at 2x, once at 1x, in that order so the preview left behind is
# the 1x render. The 2x pass is the one that matters for the clock: its glass
# is a Canvas drawn `devicePixelRatio` times too big and scaled back down, so
# the origin the numerals are drawn at is wrong in a way only a scaled render
# can show -- at 1x every wrong formula for it agrees with the right one.
#
# No QML disk cache: a stale compiled copy would let every assertion below run
# against the previous revision of the theme and pass, which is worse than a
# failing test.
for scale in 2 1; do
    QT_SCALE_FACTOR=$scale QT_QPA_PLATFORM=offscreen \
        QT_QUICK_BACKEND=software QML_DISABLE_DISK_CACHE=1 \
        timeout 25 qml6 wrapper.qml || exit $?
done
test -f lock.png
echo "ok: all assertions passed, lock.png rendered"
