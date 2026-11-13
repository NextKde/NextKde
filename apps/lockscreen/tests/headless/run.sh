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
# the 1x render. Check both device pixel ratios so logical layout bounds and
# the full-resolution wallpaper takeover stay correct on HiDPI displays.
#
# No QML disk cache: a stale compiled copy would let every assertion below run
# against the previous revision of the theme and pass, which is worse than a
# failing test.
if ! command -v dbus-run-session >/dev/null 2>&1; then
    echo "dbus-run-session is required for an isolated lock-screen test" >&2
    exit 92
fi

for scale in 2 1; do
    dbus-run-session -- env \
        QT_SCALE_FACTOR=$scale QT_QPA_PLATFORM=offscreen \
        QT_QUICK_BACKEND=software QML_DISABLE_DISK_CACHE=1 \
        timeout 25 qml6 wrapper.qml || exit $?
done
test -f lock.png
echo "ok: all assertions passed, lock.png rendered"

qmltest=$(command -v qmltestrunner6 || command -v qmltestrunner || true)
if [ -z "$qmltest" ] && [ -x /usr/lib/qt6/bin/qmltestrunner ]; then
    qmltest=/usr/lib/qt6/bin/qmltestrunner
fi
if [ -z "$qmltest" ]; then
    echo "qmltestrunner (Qt 6) is required for lock-screen input tests" >&2
    exit 93
fi
dbus-run-session -- env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
    QML_DISABLE_DISK_CACHE=1 timeout 30 "$qmltest" -input tst_wake.qml
