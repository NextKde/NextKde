#pragma once

#include <effect/effect.h>
#include <scene/itemgeometry.h>
#include <QObject>
#include <functional>

namespace KOS
{
// In-process, synchronous interface. No texture pointers or ownership cross
// plugin boundaries. The provider owns the cache; the consumer changes quads.
inline constexpr char SharedWindowSourceProperty[] = "_kos_shared_window_source_v1";
inline constexpr int WindowSourceCaptureRole = 0x4b4f5343; // KOSC
inline constexpr int LegacyWindowSourceCaptureRole = 0x4b4f5345; // KOSE
inline constexpr int DockSourceAnimationRole = 0x4b4f5344; // KOSD
using WindowSourceMorph = std::function<void(KWin::WindowPaintData &, KWin::WindowQuadList &)>;
class SharedWindowSource
{
public:
    virtual ~SharedWindowSource() = default;
    virtual bool drawSharedWindow(const KWin::RenderTarget &, const KWin::RenderViewport &,
                                  KWin::EffectWindow *, int, const KWin::Region &,
                                  KWin::WindowPaintData &, const WindowSourceMorph &) = 0;
};
}
Q_DECLARE_INTERFACE(KOS::SharedWindowSource, "org.kos.SharedWindowSource/1.0")
