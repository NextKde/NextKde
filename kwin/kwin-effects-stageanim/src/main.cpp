/*
    SPDX-FileCopyrightText: 2026 fg-sched stage animation
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "stageanim.h"

namespace KWin
{

KWIN_EFFECT_FACTORY_SUPPORTED_ENABLED(StageAnimEffect,
                                      "metadata.json",
                                      return StageAnimEffect::supported();
                                      ,
                                      return false;)

} // namespace KWin

#include "main.moc"
