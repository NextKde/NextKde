#!/usr/bin/env bash
# Rebuild only with explicit runtime authorization (normally in a VM or CI).
set -euo pipefail
cd "$(dirname "$0")"
PATH="$PATH:/usr/lib/qt6/bin"
for shader in liquid_surface liquid_reflection liquid_shadow liquid_diffuse liquid_convex liquid_convex_reflection; do
    for stage in vert frag; do
        qsb --qsbversion 64 --qt6 -o "$shader.$stage.qsb" "$shader.$stage"
    done
done
