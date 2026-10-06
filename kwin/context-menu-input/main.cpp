#include "contextmenuinputeffect.h"

namespace KWin
{

KWIN_EFFECT_FACTORY_SUPPORTED_ENABLED(ContextMenuInputEffect,
                                      "metadata.json",
                                      return true;,
                                      return false;)

} // namespace KWin

#include "main.moc"
