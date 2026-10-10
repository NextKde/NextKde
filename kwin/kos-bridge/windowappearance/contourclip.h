#pragma once

// Parked legacy backdrop capture/patch path; not built into kos_bridge.
// Do not reactivate it to implement continuous corners.

#include <QRectF>
#include <QSize>
#include <QString>
#include <memory>
#include <unordered_map>

namespace KWin
{
class EffectWindow;
class GLFramebuffer;
class GLShader;
class GLTexture;
class RenderTarget;
class RenderViewport;
class Region;
}

namespace KOS::WindowAppearance
{

struct CornerRadii;

// The continuous-corner clip. The per-window shader hook no longer exists in
// this KWin, so the contour is realised in two steps around the window's own
// drawing pass:
//
//   1. captureFrame() copies the screen content of the window's frame rect
//      into a per-window offscreen texture BEFORE the window draws -- at that
//      moment the framebuffer holds exactly the backdrop behind the window.
//   2. patchFrame() draws that copy back over the frame AFTER the window
//      drew, through a mask that is opaque outside the contour and
//      transparent inside it. The corners the contour cuts away are thereby
//      rebuilt from the real backdrop, and the visible window shape is the
//      continuous curve.
//
// The window's own pass is untouched: blur, glass and every other effect in
// the chain see an ordinary window. The native border radius is set to zero
// for these windows while the clip is active -- the contour is owned here.
class ContourClip
{
public:
    ContourClip();
    ~ContourClip();

    ContourClip(const ContourClip &) = delete;
    ContourClip &operator=(const ContourClip &) = delete;

    // Drops cached framebuffers, masks and the shader. Called when the
    // configuration changes, so no stale curve is ever served.
    void invalidate();

    // Step 1 -- call before the window's pixels are drawn, while the render
    // target still holds the backdrop.
    void captureFrame(const KWin::RenderTarget &renderTarget,
                      const KWin::RenderViewport &viewport,
                      KWin::EffectWindow *window, const QRectF &frameLogical);

    // Step 2 -- call after the window's pixels are drawn. Redraws the
    // captured backdrop over the frame with the outside-of-contour mask.
    // `clip` limits the draw to what is actually visible on screen; `radii`
    // and `smoothness` are the contour the window was cut with.
    void patchFrame(const KWin::RenderTarget &renderTarget,
                    const KWin::RenderViewport &viewport,
                    KWin::EffectWindow *window, const QRectF &frameLogical,
                    const CornerRadii &radii, qreal smoothness,
                    const KWin::Region &clip);

    // The window went away: its capture buffer dies with it.
    void forgetWindow(KWin::EffectWindow *window);

private:
    bool ensureShader();
    KWin::GLFramebuffer *captureBuffer(KWin::EffectWindow *window,
                                       const QSize &deviceSize);
    KWin::GLTexture *maskTexture(const QSize &deviceSize,
                                 const CornerRadii &radii, qreal smoothness,
                                 qreal scale);

    std::unique_ptr<KWin::GLShader> m_shader;
    bool m_failed = false;
    int m_mvpLocation = -1;
    int m_backdropLocation = -1;
    int m_maskLocation = -1;

    // One capture buffer per window, resized on demand. Dropped with the
    // window (the manager forgets its windows and calls invalidate() on
    // configuration changes).
    struct Capture
    {
        std::unique_ptr<KWin::GLTexture> texture;
        std::unique_ptr<KWin::GLFramebuffer> framebuffer;
        QSize size;
    };
    std::unordered_map<KWin::EffectWindow *, Capture> m_captures;

    std::unordered_map<QString, std::unique_ptr<KWin::GLTexture>> m_masks;
};

} // namespace KOS::WindowAppearance
