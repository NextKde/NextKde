// Exercise the actual GLSL on a GL context; no running KWin effect is changed.
#include <QGuiApplication>
#include <QOffscreenSurface>
#include <QOpenGLContext>
#include <QOpenGLExtraFunctions>
#include <QOpenGLFramebufferObject>
#include <QOpenGLShaderProgram>
#include <QOpenGLVertexArrayObject>
#include <QFile>
#include <QLibrary>
#include <QMatrix4x4>
#include <algorithm>
#include <cmath>
#include <iostream>
#include <stdexcept>
#include <vector>

static void check(bool condition, const char *message)
{
    if (!condition) throw std::runtime_error(message);
}
static QByteArray read(const QString &path)
{
    QFile file(path);
    check(file.open(QIODevice::ReadOnly), qPrintable(path));
    return file.readAll();
}
static void compile(QOpenGLShaderProgram &program, const QByteArray &fragment)
{
    const char *vertex = R"(#version 140
out vec2 uv;
out vec2 vertex;
void main() {
    vec2 p = vec2(gl_VertexID == 1 ? 3.0 : -1.0, gl_VertexID == 2 ? 3.0 : -1.0);
    uv = p * 0.5 + 0.5;
    vertex = uv * vec2(4096.0, 1.0);
    gl_Position = vec4(p, 0.0, 1.0);
})";
    check(program.addShaderFromSourceCode(QOpenGLShader::Vertex, vertex), qPrintable(program.log()));
    check(program.addShaderFromSourceCode(QOpenGLShader::Fragment, fragment), qPrintable(program.log()));
    check(program.link(), qPrintable(program.log()));
}
int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    try {
        check(argc == 2, "Pass the repository root");
        const QString shaders = QString::fromLocal8Bit(argv[1]) + "/kwin/glass-effect/src/shaders/";
        QSurfaceFormat format;
        format.setVersion(3, 3);
        format.setProfile(QSurfaceFormat::CoreProfile);
        QOpenGLContext context;
        context.setFormat(format);
        check(context.create(), "Cannot create GL context");
        QOffscreenSurface surface;
        surface.setFormat(context.format());
        surface.create();
        check(context.makeCurrent(&surface), "Cannot make GL context current");
        auto *gl = context.extraFunctions();
        QOpenGLVertexArrayObject vao;
        check(vao.create(), "Cannot create vertex array");
        vao.bind();

        // Compile the complete material shader using KWin's real SDF helper.
        QLibrary kwin("kwin");
        check(kwin.load(), qPrintable(kwin.errorString()));
        auto src = read(shaders + "onscreen_rounded.glsl");
        auto glass = read(shaders + "glass.glsl");
        glass.replace("#include \"snells-glass.glsl\"", read(shaders + "snells-glass.glsl"));
        auto full = src;
        full.replace("#include \"sdf.glsl\"", read(":/opengl/sdf.glsl"));
        full.replace("#include \"glass.glsl\"", glass);
        full.replace("#include \"oklab.glsl\"", read(shaders + "oklab.glsl"));
        QOpenGLShaderProgram material;
        compile(material, read(shaders + "compat_core.glsl") + full);

        // Render the source's helpers directly to RGBA32F for gradient checks.
        const auto begin = src.indexOf("float localScrimLuminance");
        const auto end = src.indexOf("void main(void)");
        check(begin >= 0 && end > begin, "Cannot locate scrim helpers");
        QOpenGLShaderProgram program;
        compile(program, QByteArray(R"(#version 140
uniform sampler2D scrimLumaTex;
uniform float scrimCap;
uniform float scrimDecay;
uniform bool whiteScrim;
uniform int testMode;
in vec2 uv;
out vec4 fragColor;
)") + src.mid(begin, end - begin) + R"(
void main() {
    float lum = testMode == 3 ? localScrimLuminance(uv) : uv.x;
    vec3 background = testMode == 1 ? vec3(0.0) : testMode == 2 ? vec3(1.0) : vec3(lum);
    fragColor = vec4(testMode == 3 ? vec3(lum) : adaptiveScrim(background, lum, whiteScrim), 1.0);
})");
        QOpenGLFramebufferObjectFormat targetFormat;
        targetFormat.setInternalTextureFormat(GL_RGBA32F);
        const int width = 4096;
        QOpenGLFramebufferObject target(width, 1, targetFormat);
        check(target.isValid(), "Cannot create float render target");
        auto render = [&](int mode, float cap, float decay, bool white) {
            target.bind();
            gl->glViewport(0, 0, width, 1);
            program.bind();
            program.setUniformValue("testMode", mode);
            program.setUniformValue("scrimCap", cap);
            program.setUniformValue("scrimDecay", decay);
            program.setUniformValue("whiteScrim", white);
            program.setUniformValue("scrimLumaTex", 0);
            gl->glDrawArrays(GL_TRIANGLES, 0, 3);
            std::vector<float> pixels(width * 4), values(width);
            gl->glReadPixels(0, 0, width, 1, GL_RGBA, GL_FLOAT, pixels.data());
            for (int i = 0; i < width; ++i) values[i] = pixels[i * 4];
            check(gl->glGetError() == GL_NO_ERROR, "GL error during rendering");
            return values;
        };
        // All shipped adaptive presets, plus fade/zero/lower-cap custom cases.
        const std::vector<std::pair<float, float>> presets = {
            {0.15f, 0.45f}, {0.22f, 0.5f}, {0.47f, 0.75f}, {0.72f, 1.0f},
            {0.9f, 1.0f}, {0.0f, 0.0f}, {0.047f, 0.075f}, {0.5f, 0.2f},
            {1.0f, 1.0f}, {0.01f, 0.45f}, {0.8f, 0.0f}
        };
        float largestStep = 0.0f;
        for (auto [cap, decay] : presets) {
            for (bool white : {false, true}) {
                auto values = render(0, cap, decay, white);
                auto black = render(1, cap, decay, white);
                auto whiteBackground = render(2, cap, decay, white);
                for (int i = 0; i < width; ++i) {
                    check(std::isfinite(values[i]) && values[i] >= 0 && values[i] <= 1, "Invalid scrim color");
                    const float alpha = 1.0f - (whiteBackground[i] - black[i]);
                    check(alpha >= -1e-5f && alpha <= cap + 1e-5f, "Scrim exceeds opacity cap");
                    if (i) {
                        const float step = values[i] - values[i - 1];
                        check(step >= -1e-5f, "Scrim creates a tonal reversal on a smooth gradient");
                        check(step < 1.01f / width, "Scrim sharpens a smooth gradient");
                        largestStep = std::max(largestStep, step);
                    }
                }
            }
        }
        auto darkCurve = render(0, 0.47f, 0.75f, false);
        auto lightCurve = render(0, 0.47f, 0.75f, true);
        for (int i = 0; i < width; ++i)
            check(std::abs(darkCurve[i] + lightCurve[width - 1 - i] - 1.0f) < 2e-5f, "Light/dark curves disagree");

        GLuint texture;
        gl->glGenTextures(1, &texture);
        gl->glActiveTexture(GL_TEXTURE0);
        gl->glBindTexture(GL_TEXTURE_2D, texture);
        gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        const int mapWidth = 64;
        std::vector<float> map(mapWidth);
        for (int i = 0; i < mapWidth; ++i) map[i] = i < 42 ? 0.95f : 0.05f;
        gl->glTexImage2D(GL_TEXTURE_2D, 0, GL_R32F, mapWidth, 1, 0, GL_RED, GL_FLOAT, map.data());
        // Replicate red into RGB, matching the compositor's color capture.
        for (auto channel : {GL_TEXTURE_SWIZZLE_G, GL_TEXTURE_SWIZZLE_B})
            gl->glTexParameteri(GL_TEXTURE_2D, channel, GL_RED);
        auto split = render(3, 0.47f, 0.75f, false);
        check(split.front() > 0.9f && split.back() < 0.1f, "Local light/dark regions collapsed to an average");
        for (int i = 1; i < width; ++i)
            check(std::abs(split[i] - split[i - 1]) < 0.008f, "Hard luminance boundary survived filtering");
        for (int i = 0; i < mapWidth; ++i) map[i] = i % 2;
        gl->glTexImage2D(GL_TEXTURE_2D, 0, GL_R32F, mapWidth, 1, 0, GL_RED, GL_FLOAT, map.data());
        auto detail = render(3, 0.47f, 0.75f, false);
        for (int i = 128; i < width - 128; ++i)
            check(std::abs(detail[i] - 0.5f) < 0.001f, "Fine wallpaper detail steers the scrim");
        gl->glDeleteTextures(1, &texture);
        std::cout << "PASS: full shader compiled; gradients monotonic, symmetric, capped; local split retained; detail filtered\n"
                  << "Maximum gradient slope: " << largestStep * width << '\n';
    } catch (const std::exception &error) {
        std::cerr << "FAIL: " << error.what() << '\n';
        return 1;
    }
}
