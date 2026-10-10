#pragma once

namespace KOS::WindowAppearance
{
// QVector4D in KWin's TL/TR/BR/BL order. Zero is intentional in continuous
// mode: a single final compositor mask owns the complete window contour.
inline constexpr char WindowRadiiProperty[] = "_kos_window_appearance_native_radii";
inline constexpr char VisualRadiiProperty[] = "_kos_window_appearance_visual_radii";
inline constexpr char CurveExponentProperty[] = "_kos_window_appearance_curve_exponent";
}
