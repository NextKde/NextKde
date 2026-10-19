#pragma once
#include "render/rhi/rhi.hpp"
#include <memory>
#include <mutex>

class QRhi;
class QRhiCommandBuffer;
class QRhiTexture;
namespace mayo { struct Theme; }

namespace Kos::Forma {
// All mutable native trees and the shared FreeType cache are used under this
// lock, including when Qt uses separate render threads for different windows.
std::recursive_mutex &nativeMutex();
void setTheme(const mayo::Theme *theme);

class RhiDevice final : public mayo::rhi::Device {
public:
    explicit RhiDevice(QRhi *rhi);
    ~RhiDevice() override;
    mayo::rhi::Backend backend() const override;
    std::string description() const override;
    int maxTextureSize() const override;
    std::unique_ptr<mayo::rhi::Texture> createTexture(const mayo::rhi::TextureDesc &) override;
    void upload(mayo::rhi::Texture &, int, int, int, int, const void *, int) override;
    std::unique_ptr<mayo::rhi::Pipeline> createPipeline(const mayo::rhi::PipelineDesc &) override;
    void beginFrame(mayo::platform::PlatformWindow &) override {}
    void endFrame(mayo::platform::PlatformWindow &, mayo::rhi::Texture &) override {}
    void beginPass(mayo::rhi::Texture &, const float *) override;
    void setScissor(const mayo::rhi::Scissor *) override;
    void draw(mayo::rhi::Pipeline &, std::span<mayo::rhi::Texture *const>, const void *, std::size_t,
              std::span<const std::byte>, int, int) override;
    std::vector<std::uint8_t> readPixels(mayo::rhi::Texture &) override;
    void resetFrame();
    void submit(QRhiCommandBuffer *, mayo::rhi::Texture &scene, QRhiTexture *output);
private:
    struct Impl;
    std::unique_ptr<Impl> d;
};
}
