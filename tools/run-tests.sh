#!/usr/bin/env bash
#
# run-tests.sh — the single entry point for the test suite.
#
# Local runs and CI drive the same script so "it passed here" means the same
# thing in both places. Layers map to ctest labels:
#
#   data      services and the code they own (Go, Qt, D-Bus)  <- default
#   logic     pure computation, node, no display
#   platform  the platform contract test
#   ui        needs a QML engine; the panel tests also want a compositor
#
# The default is `data`: it is the layer that must never crash and it is the
# only one that runs identically with or without a session. `--all` opts into
# everything, which is what a desktop machine can do but a CI container cannot.
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(dirname -- "$script_dir")
build_dir=${KOS_TEST_BUILD_DIR:-"$project_dir/.build/tests"}

# /tmp is a small tmpfs on many systems, and both gcc and the Go toolchain dump
# multi-hundred-megabyte temporaries into it while compiling. Keeping every
# scratch directory inside the build tree is what makes a parallel run survive.
export TMPDIR="${KOS_TEST_TMPDIR:-$build_dir/tmp}"
export GOTMPDIR="${GOTMPDIR:-$build_dir/tmp}"
mkdir -p "$TMPDIR"

# GOCACHE is deliberately not set here. services/data-service/CMakeLists.txt
# (:18, :47) passes an absolute GOCACHE to every `go` invocation it makes, so a
# value exported here is overridden before it is ever read. CI caches the real
# one -- .build/tests/services/data-service/go-test-cache -- instead.

layers=()
build_jobs=${CMAKE_BUILD_PARALLEL_LEVEL:-}
while (( $# > 0 )); do
    case "$1" in
        --all) layers=(data logic platform ui) ;;
        --layer)
            shift
            [[ -n "${1:-}" ]] || { echo "--layer needs a value" >&2; exit 2; }
            layers+=("$1")
            ;;
        --jobs)
            shift
            build_jobs="${1:-}"
            [[ -n "$build_jobs" ]] || { echo "--jobs needs a value" >&2; exit 2; }
            ;;
        -h|--help)
            cat <<'EOF'
Usage: ./tools/run-tests.sh [--all] [--layer <name>] [--jobs N]

  (no arguments)   run the data/service layer (default)
  --all            run every layer
  --layer <name>   run one layer: data, logic, platform, ui
  --jobs N         parallel build jobs (default: derived from nproc, capped at 12)

Environment:
  KOS_TEST_BUILD_DIR   build directory (default .build/tests)
  KOS_TEST_TMPDIR      scratch directory for compilers and Go
  KOS_BUILD_TYPE       Debug (default) or Release
EOF
            exit 0
            ;;
        *) echo "Unknown argument: $1 (try --help)" >&2; exit 2 ;;
    esac
    shift
done
(( ${#layers[@]} > 0 )) || layers=(data)

if [[ -z "$build_jobs" ]]; then
    # Past ~12 the C++ steps contend for memory bandwidth and the wall clock
    # goes back up, so cap rather than matching nproc on a large machine.
    cpu_count=$(nproc 2>/dev/null || echo 4)
    build_jobs=$(( cpu_count > 12 ? 12 : cpu_count ))
fi

label_regex=$(IFS='|'; echo "${layers[*]}")

printf '==> configuring %s\n' "$build_dir"
cmake -S "$project_dir" -B "$build_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE="${KOS_BUILD_TYPE:-Debug}" \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DKOS_BUILD_KWIN_PLUGINS=OFF \
    -DBUILD_TESTING=ON >/dev/null

printf '==> building (--parallel %s)\n' "$build_jobs"
cmake --build "$build_dir" --parallel "$build_jobs"

printf '==> testing label%s: %s\n' \
    "$([[ ${#layers[@]} -gt 1 ]] && echo s)" "$(IFS=', '; echo "${layers[*]}")"
ctest --test-dir "$build_dir" --output-on-failure -L "$label_regex"
