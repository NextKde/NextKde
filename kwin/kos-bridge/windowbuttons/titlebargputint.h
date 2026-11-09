#pragma once

#include <QRect>
#include <memory>

namespace KWin
{
class GLFramebuffer;
class GLShader;
class GLTexture;
class RenderTarget;
}

namespace KOS
{

// One reusable scratch gutter and one color texel for the renderer. GPU command
// ordering makes the color usable in this paint, without a readback or fence wait.
// The result is consumed before another window overwrites it. Invalid/transparent
// samples produce alpha zero; the panel shader then uses its validated fallback.
class TitlebarGpuTint
{
public:
    TitlebarGpuTint();
    ~TitlebarGpuTint();
    bool update(const KWin::RenderTarget &target, const QRect &gutter);
    KWin::GLTexture *texture() const { return m_color.get(); }
    KWin::GLShader *panelShader() const { return m_panelShader.get(); }

private:
    bool initialize();
    bool m_attempted = false;
    std::unique_ptr<KWin::GLTexture> m_gutter;
    std::unique_ptr<KWin::GLFramebuffer> m_gutterFbo;
    std::unique_ptr<KWin::GLTexture> m_color;
    std::unique_ptr<KWin::GLFramebuffer> m_colorFbo;
    std::unique_ptr<KWin::GLShader> m_reduceShader;
    std::unique_ptr<KWin::GLShader> m_panelShader;
};

} // namespace KOS
