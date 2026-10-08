#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
qsb_bin=$(command -v qsb || true)
if [[ -z "$qsb_bin" ]]; then qsb_bin=/usr/lib/qt6/bin/qsb; fi
"$qsb_bin" --qt6 -o glass-reveal.frag.qsb glass-reveal.frag
