#pragma once

#include <effect/effect.h>
#include "windowappearance/sharedwindowsource.h"
#include <memory>

namespace KOS
{

class ButtonRenderer;
class ButtonConfig;
class ButtonInput;
class WindowAppearanceManager;
namespace WindowAppearance { class ContinuousClip; }

// Simple KWin effect that draws window buttons on top of CSD windows, and
// owns the unified window appearance: corner rounding, the frame band and
// outline around every managed window, and the dynamic stacked shadow.
class BridgeEffect final : public KWin::Effect, public SharedWindowSource
{
    Q_OBJECT
    Q_INTERFACES(KOS::SharedWindowSource)

public:
    BridgeEffect();
    ~BridgeEffect() override;

    void reconfigure(ReconfigureFlags flags) override;
    bool isActive() const override;
    // Draw-chain wrappers run from lower to higher positions. Dock (50) asks
    // this provider to draw the shared source with its own mesh deformation.
    // Stage retains its legacy outer capture. Keep Bridge inside both wrappers
    // so ordinary source captures cannot cache their animated output.
    int requestedEffectChainPosition() const override { return 100; }

    void prePaintWindow(KWin::RenderView *view, KWin::EffectWindow *window,
                        KWin::WindowPrePaintData &data
#ifdef KOS_KWIN_PAINT_TIME_API
                        , std::chrono::milliseconds presentTime
#endif
                        ) override;

    void drawWindow(const KWin::RenderTarget &renderTarget,
                    const KWin::RenderViewport &viewport,
                    KWin::EffectWindow *window, int mask,
                    const KWin::Region &deviceRegion,
                    KWin::WindowPaintData &data) override;

    bool drawSharedWindow(const KWin::RenderTarget &, const KWin::RenderViewport &,
                          KWin::EffectWindow *, int, const KWin::Region &,
                          KWin::WindowPaintData &, const WindowSourceMorph &) override;

private:
    void paintButtons(const KWin::RenderTarget &, const KWin::RenderViewport &,
                      KWin::EffectWindow *, const KWin::Region &,
                      const KWin::WindowPaintData &, bool sourceCapture);
    KWin::Region visibleRegionFor(KWin::EffectWindow *window,
                                  const KWin::RenderViewport &viewport,
                                  const KWin::Region &deviceRegion) const;

    std::unique_ptr<ButtonRenderer> m_renderer;
    std::unique_ptr<ButtonConfig> m_config;
    std::unique_ptr<ButtonInput> m_input;
    std::unique_ptr<WindowAppearanceManager> m_appearance;
    std::unique_ptr<WindowAppearance::ContinuousClip> m_continuousClip;

    // The window that was active last, so that the panel it had can be repainted
    // along with the one the focus moved to -- see the windowActivated connection
    // in the constructor. Cleared when that window is deleted, which is the only
    // way an EffectWindow pointer here could stop meaning anything.
    KWin::EffectWindow *m_lastActive = nullptr;
};

} // namespace KOS
