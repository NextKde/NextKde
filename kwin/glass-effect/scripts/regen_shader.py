#!/usr/bin/env python3
"""Re-generate src/generated/onscreen_rounded.frag from source shaders.

Mirrors CMake's generate_shader_variants() exactly so editing glass.glsl
takes effect without a full CMake re-configure:

  GLASS_SHADER = glass.glsl with #include "snells-glass.glsl" expanded
  SHADER_SRC   = onscreen_rounded.glsl
  output       = COMPAT_CORE + SHADER_SRC with oklab.glsl + glass.glsl expanded
                 (#include "sdf.glsl" is kept for the runtime KWin include)
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent / "src" / "shaders"
GEN = pathlib.Path(__file__).resolve().parent.parent / "src" / "generated"

def read(name):
    return (ROOT / name).read_text()

compat_core = read("compat_core.glsl")
oklab = read("oklab.glsl")

# glass.glsl 内部还 include 了 snells-glass.glsl——CMake 真实链路会先展开
# 它（src/CMakeLists 的 GLASS_SHADER 两步 replace）；漏掉这步会把带无法
# 解析 include 的坏着色器写进 generated/，且旧自检查不出来
snells = read("snells-glass.glsl")
glass = read("glass.glsl").replace('#include "snells-glass.glsl"', snells)

src = read("onscreen_rounded.glsl")
expanded = src.replace('#include "oklab.glsl"', oklab)
expanded = expanded.replace('#include "glass.glsl"', glass)

out = GEN / "onscreen_rounded.frag"
out.write_text(compat_core + "\n" + expanded)
print(f"wrote {out} ({len(compat_core + expanded)} bytes)")

# Sanity checks
checks = {
    # 断言锚点须跟现行着色器符号一致：circleMap/cornerWeight 是旧代
    # 符号（早就不在源里），坏锚点让自检永远红、真回归反而被淹没
    "snells lens profile": "processSnellSample" in expanded,
    "analytic gradient gradSdRoundedBox": "gradSdRoundedBox" in expanded,
    "soft material pass": "applySoftMaterial" in expanded,
    "glass.glsl expanded (no bare include)": '#include "glass' not in expanded,
    "snells-glass.glsl expanded": '#include "snells' not in expanded,
    "sdf.glsl include kept": '#include "sdf.glsl"' in expanded,
}
for name, ok in checks.items():
    print(f"  [{'OK' if ok else 'FAIL'}] {name}")
if not all(checks.values()):
    raise SystemExit(1)
print("all checks passed")
