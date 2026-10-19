"""Small, checked embedding adaptation; controls and drawing math stay in Forma."""
from pathlib import Path
import re
import sys

source, output = map(Path, sys.argv[1:])

def replace_once(text, old, new):
    if text.count(old) != 1:
        raise RuntimeError(f"Forma embedding API changed: {old[:90]}")
    return text.replace(old, new, 1)

header = (source / "src/render/renderer2d.hpp").read_text()
header = replace_once(header, "void endFrame();", "void endFrame();\n    void beginEmbedded(int width, int height, float scale);\n    rhi::Texture& scene() { return *m_scene; }")
(output / "renderer2d.hpp").write_text(header)
renderer = (source / "src/render/renderer2d.cpp").read_text()
renderer = replace_once(renderer,
    "void Renderer2D::beginFrame(platform::PlatformWindow& window, int pixelWidth, int pixelHeight, float scale) {",
    "void Renderer2D::beginFrame(platform::PlatformWindow&, int w, int h, float s) { beginEmbedded(w, h, s); }\nvoid Renderer2D::beginEmbedded(int pixelWidth, int pixelHeight, float scale) {")
renderer = replace_once(renderer, "    m_device.beginFrame(window);", "    // The Qt Quick frame and command buffer are already active.")
(output / "renderer2d.cpp").write_text(renderer)

# QRhi uses reflected uniform buffers instead of GL uniforms/Vulkan push
# constants. This leaves the original SDF, text, gradients and blur formulas.
block = "layout(std140, binding = 0) uniform Embedded { mat4 u_correction; vec2 u_viewport; vec2 u_halfPixel; float u_offset; };"
for name in ("ui.vert", "ui.frag", "fullscreen.vert", "blur_down.frag", "blur_up.frag"):
    shader = (source / "shaders" / name).read_text()
    shader = shader.replace("#version 330 core", "#version 440").replace("#ifdef VULKAN", "#if 1")
    # Select the Vulkan declarations, discarding the GL branches.
    shader = re.sub(r"#if 1\n(.*?)#else\n.*?#endif", lambda m: m[1], shader, flags=re.S)
    shader = re.sub(r"#if 1\n(.*?)#endif", lambda m: m[1], shader, flags=re.S)
    shader = re.sub(r"layout\(push_constant\) uniform Push\s*\{.*?\};", block, shader, flags=re.S)
    if "uniform Embedded" not in shader:
        shader = shader.replace("void main()", block + "\nvoid main()")
    shader = shader.replace("#define BINDING(n) layout(set = 0, binding = n)", "#define BINDING(n) layout(binding = n + 1)")
    if name.endswith(".vert"):
        shader = shader.replace("gl_Position = vec4(", "gl_Position = u_correction * vec4(")
    (output / name).write_text(shader)
