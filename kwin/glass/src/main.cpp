/*
    SPDX-FileCopyrightText: 2026 NextKDE contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "glass.h"

namespace KWin
{

KWIN_EFFECT_FACTORY_SUPPORTED_ENABLED(GlassEffect,
                                      "metadata.json",
                                      return GlassEffect::supported();,
                                      return GlassEffect::enabledByDefault();)

} // namespace KWin

#include "main.moc"
