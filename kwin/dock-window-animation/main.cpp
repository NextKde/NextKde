#include "dockwindowanimationeffect.h"

namespace KWin
{

KWIN_EFFECT_FACTORY_SUPPORTED_ENABLED(DockWindowAnimationEffect,
                                      "metadata.json",
                                      return DockWindowAnimationEffect::supported();,
                                      return false;)

} // namespace KWin

#include "main.moc"
