#pragma once

#include <QObject>
#include <functional>
#include <memory>

namespace KWin
{
class EffectWindow;
class RenderTarget;
class RenderViewport;

// Composes desktop surfaces through Glass before native Overview scales them.
// Native application thumbnails and Overview's layout remain KWin-owned.
class OverviewPreview final : public QObject
{
public:
    using MaterialPass = std::function<void(const RenderTarget &, const RenderViewport &, EffectWindow *)>;
    explicit OverviewPreview(MaterialPass material, QObject *parent = nullptr);
    ~OverviewPreview() override;
    void invalidate();

private:
    class Private;
    std::unique_ptr<Private> d;
};
}
