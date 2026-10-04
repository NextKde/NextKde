#include "kosovervieweffect.h"

namespace KWin
{

KWIN_EFFECT_FACTORY_SUPPORTED_ENABLED(KosOverviewEffect,
                                      "metadata.json",
                                      return QuickSceneEffect::supported();,
                                      return false;)

} // namespace KWin

#include "main.moc"
