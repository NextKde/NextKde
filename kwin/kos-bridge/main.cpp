#include "bridge.h"

namespace KWin
{

KWIN_EFFECT_FACTORY_SUPPORTED_ENABLED(KOS::BridgeEffect,
                                      "metadata.json",
                                      return true;,
                                      return true;)

} // namespace KWin

#include "main.moc"
