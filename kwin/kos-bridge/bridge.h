#pragma once

#include <effect/effect.h>
#include <memory>

namespace KOS
{

class ButtonRenderer;
class ButtonConfig;
class ButtonInput;

// Simple KWin effect that draws window buttons on top of CSD windows.
class BridgeEffect final : public KWin::Effect
{
    Q_OBJECT

public:
    BridgeEffect();
    ~BridgeEffect() override;

    void reconfigure(ReconfigureFlags flags) override;
    bool isActive() const override;

    void drawWindow(const KWin::RenderTarget &renderTarget,
                    const KWin::RenderViewport &viewport,
                    KWin::EffectWindow *window, int mask,
                    const KWin::Region &deviceRegion,
                    KWin::WindowPaintData &data) override;

private:
    KWin::Region visibleRegionFor(KWin::EffectWindow *window,
                                  const KWin::RenderViewport &viewport,
                                  const KWin::Region &deviceRegion) const;

    std::unique_ptr<ButtonRenderer> m_renderer;
    std::unique_ptr<ButtonConfig> m_config;
    std::unique_ptr<ButtonInput> m_input;

    // The window that was active last, so that the panel it had can be repainted
    // along with the one the focus moved to -- see the windowActivated connection
    // in the constructor. Cleared when that window is deleted, which is the only
    // way an EffectWindow pointer here could stop meaning anything.
    KWin::EffectWindow *m_lastActive = nullptr;
};

} // namespace KOS
