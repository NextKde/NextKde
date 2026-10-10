#pragma once

#include <KDecoration3/DecorationShadow>
#include <QMetaType>
#include <memory>

Q_DECLARE_METATYPE(std::shared_ptr<KDecoration3::DecorationShadow>)

namespace KOS::WindowAppearance
{
// Resolved logical radii, in KWin order (TL, TR, BR, BL). The bridge owns
// policy; the decoration consumes the result without loading another config.
inline constexpr char DecorationRadiiProperty[] = "_kos_window_appearance_radii";
inline constexpr char DecorationShadowProperty[] = "_kos_window_appearance_shadow";
inline constexpr char DecorationAppearanceSupportedProperty[] = "_kos_window_appearance_supported";
}
