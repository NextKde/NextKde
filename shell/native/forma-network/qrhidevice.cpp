#include "qrhidevice.h"
#include "mayonnaise/app.hpp"
#include <rhi/qrhi.h>
#include <QFile>
#include <QMatrix4x4>
#include <rhi/qshader.h>
#include <array>
#include <cstring>
#include <optional>

namespace {
thread_local mayo::rhi::Device *currentDevice = nullptr;
thread_local const mayo::Theme *currentTheme = nullptr;
template<class T> struct RhiDelete {
    void operator()(T *p) const { if (p) p->deleteLater(); }
};
template<class T> using Resource = std::unique_ptr<T, RhiDelete<T>>;
struct TextureStorage {
    mayo::rhi::Filter filter = mayo::rhi::Filter::Nearest;
    Resource<QRhiTexture> texture;
    Resource<QRhiRenderPassDescriptor> pass, preservingPass;
    Resource<QRhiTextureRenderTarget> target, preservingTarget;
};
struct Texture final : mayo::rhi::Texture {
    Texture(const mayo::rhi::TextureDesc &desc, std::shared_ptr<TextureStorage> s)
        : mayo::rhi::Texture(desc), storage(std::move(s)) {}
    std::shared_ptr<TextureStorage> storage;
};
struct Pipeline final : mayo::rhi::Pipeline {
    QString name;
    int stride = 0;
    mayo::rhi::Blend blend;
    mayo::rhi::Topology topology;
};
QShader shader(const QString &name) {
    QFile file(QStringLiteral(":/kos/forma/") + name + QStringLiteral(".qsb"));
    if (!file.open(QIODevice::ReadOnly)) qFatal("Missing Forma shader: %s", qPrintable(file.fileName()));
    auto result = QShader::fromSerialized(file.readAll());
    if (!result.isValid()) qFatal("Invalid Forma shader: %s", qPrintable(name));
    return result;
}
}

// The embedded library never starts mayo::App or its SDL event loop. Scoped
// thread-local contexts also avoid sharing one GPU device between QQuickWindows.
namespace mayo {
const Theme &theme() {
    static const Theme fallback = Theme::make(Appearance::Dark);
    return currentTheme ? *currentTheme : fallback;
}
namespace rhi {
Device *device() { return currentDevice; }
void setDevice(Device *value) { currentDevice = value; }
int bytesPerPixel(Format f) {
    switch (f) {
    case Format::R8: return 1;
    case Format::RG8: case Format::R16: return 2;
    default: return 4;
    }
}
}
}

namespace Kos::Forma {
std::recursive_mutex &nativeMutex() { static std::recursive_mutex mutex; return mutex; }
void setTheme(const mayo::Theme *theme) { currentTheme = theme; }

struct RhiDevice::Impl {
    QRhi *rhi;
    struct Upload {
        std::shared_ptr<TextureStorage> texture;
        QRhiTextureSubresourceUploadDescription data;
    };
    struct Draw {
        Pipeline *pipeline;
        std::array<std::shared_ptr<TextureStorage>, 3> textures;
        QByteArray uniforms, instances;
        int vertices, count;
        std::optional<mayo::rhi::Scissor> scissor;
        std::size_t slot = 0;
    };
    struct Pass {
        std::shared_ptr<TextureStorage> target;
        std::optional<QColor> clear;
        std::vector<Draw> draws;
    };
    struct Slot {
        Resource<QRhiBuffer> uniform, instances;
        Resource<QRhiShaderResourceBindings> bindings;
        Resource<QRhiGraphicsPipeline> pipeline;
        Pipeline *logical = nullptr;
        // Keep the descriptor used to create the pipeline alive across resizes.
        std::shared_ptr<TextureStorage> pipelineTarget;
        std::array<QRhiTexture *, 3> bound{};
    };
    std::vector<Upload> uploads;
    std::vector<Pass> passes;
    std::vector<std::unique_ptr<Slot>> drawSlots;
    std::optional<mayo::rhi::Scissor> scissor;
    std::unique_ptr<mayo::rhi::Texture> white;
    Resource<QRhiSampler> sampler;
    Resource<QRhiSampler> linearSampler;

    QRhiTextureRenderTarget *target(const std::shared_ptr<TextureStorage> &s, bool preserve) {
        if (!s->target) {
            s->target.reset(rhi->newTextureRenderTarget({s->texture.get()}));
            s->pass.reset(s->target->newCompatibleRenderPassDescriptor());
            s->target->setRenderPassDescriptor(s->pass.get());
            if (!s->target->create()) qFatal("Cannot create Forma render target");
            s->preservingTarget.reset(rhi->newTextureRenderTarget({s->texture.get()}, QRhiTextureRenderTarget::PreserveColorContents));
            // Vulkan bakes LOAD/CLEAR into the render pass. Sharing the clear
            // descriptor here erased earlier batches when a native Image or
            // glyph atlas change flushed Renderer2D midway through the scene.
            s->preservingPass.reset(s->preservingTarget->newCompatibleRenderPassDescriptor());
            s->preservingTarget->setRenderPassDescriptor(s->preservingPass.get());
            if (!s->preservingTarget->create()) qFatal("Cannot preserve Forma render target");
        }
        return preserve ? s->preservingTarget.get() : s->target.get();
    }
};

RhiDevice::RhiDevice(QRhi *rhi) : d(std::make_unique<Impl>()) {
    d->rhi = rhi;
    d->sampler.reset(rhi->newSampler(QRhiSampler::Nearest, QRhiSampler::Nearest,
                                   QRhiSampler::None, QRhiSampler::ClampToEdge, QRhiSampler::ClampToEdge));
    if (!d->sampler->create()) qFatal("Cannot create Forma sampler");
    d->linearSampler.reset(rhi->newSampler(QRhiSampler::Linear, QRhiSampler::Linear,
                                         QRhiSampler::None, QRhiSampler::ClampToEdge, QRhiSampler::ClampToEdge));
    if (!d->linearSampler->create()) qFatal("Cannot create Forma image sampler");
    d->white = createTexture({.width = 1, .height = 1});
    const std::uint8_t white[4] = {255,255,255,255};
    upload(*d->white, 0, 0, 1, 1, white, 0);
}
RhiDevice::~RhiDevice() = default;
mayo::rhi::Backend RhiDevice::backend() const {
    return d->rhi->backend() == QRhi::Vulkan ? mayo::rhi::Backend::Vulkan : mayo::rhi::Backend::OpenGL;
}
std::string RhiDevice::description() const { return d->rhi->backendName(); }
int RhiDevice::maxTextureSize() const { return d->rhi->resourceLimit(QRhi::TextureSizeMax); }

std::unique_ptr<mayo::rhi::Texture> RhiDevice::createTexture(const mayo::rhi::TextureDesc &desc) {
    using F = mayo::rhi::Format;
    QRhiTexture::Format format = QRhiTexture::RGBA8;
    switch (desc.format) {
    case F::R8: format = QRhiTexture::R8; break;
    case F::RG8: format = QRhiTexture::RG8; break;
    case F::R16: format = QRhiTexture::R16; break;
    case F::RG16: format = QRhiTexture::RG16; break;
    default: break;
    }
    auto storage = std::make_shared<TextureStorage>();
    storage->filter = desc.filter;
    auto flags = desc.renderTarget ? QRhiTexture::RenderTarget | QRhiTexture::UsedAsTransferSource : QRhiTexture::Flags{};
    storage->texture.reset(d->rhi->newTexture(format, {desc.width, desc.height}, 1, flags));
    if (!storage->texture->create()) qFatal("Cannot create Forma texture");
    auto texture = std::make_unique<Texture>(desc, storage);
    if (!desc.renderTarget) {
        QByteArray zeros(desc.width * desc.height * mayo::rhi::bytesPerPixel(desc.format), '\0');
        upload(*texture, 0, 0, desc.width, desc.height, zeros.constData(), 0);
    }
    return texture;
}
void RhiDevice::upload(mayo::rhi::Texture &base, int x, int y, int w, int h, const void *pixels, int stride) {
    auto &texture = static_cast<Texture &>(base);
    const int rowBytes = w * mayo::rhi::bytesPerPixel(texture.desc().format);
    if (!stride) stride = rowBytes;
    QByteArray data(rowBytes * h, Qt::Uninitialized);
    for (int row = 0; row < h; ++row)
        std::memcpy(data.data() + row * rowBytes, static_cast<const char *>(pixels) + row * stride, rowBytes);
    QRhiTextureSubresourceUploadDescription desc(data);
    desc.setSourceSize({w, h});
    desc.setDestinationTopLeft({x, y});
    d->uploads.push_back({texture.storage, desc});
}
std::unique_ptr<mayo::rhi::Pipeline> RhiDevice::createPipeline(const mayo::rhi::PipelineDesc &desc) {
    auto result = std::make_unique<Pipeline>();
    result->name = QString::fromUtf8(desc.name.data(), desc.name.size());
    result->stride = desc.instanceVec4s * 16;
    result->blend = desc.blend;
    result->topology = desc.topology;
    return result;
}
void RhiDevice::resetFrame() { d->passes.clear(); d->scissor.reset(); }
void RhiDevice::beginPass(mayo::rhi::Texture &texture, const float *clear) {
    auto storage = static_cast<Texture &>(texture).storage;
    d->scissor.reset();
    // Forma's GL API rebinds the same target at every batch flush. Keep those
    // batches in one QRhi pass; split only for an actual target/clear change.
    if (!clear && !d->passes.empty() && d->passes.back().target == storage) return;
    d->passes.push_back({storage, clear ? std::optional(QColor::fromRgbF(clear[0], clear[1], clear[2], clear[3])) : std::nullopt, {}});
}
void RhiDevice::setScissor(const mayo::rhi::Scissor *scissor) {
    d->scissor = scissor ? std::optional(*scissor) : std::nullopt;
}
void RhiDevice::draw(mayo::rhi::Pipeline &pipeline, std::span<mayo::rhi::Texture *const> textures,
                     const void *uniforms, std::size_t uniformBytes, std::span<const std::byte> instances,
                     int vertices, int count) {
    Impl::Draw draw;
    draw.pipeline = static_cast<Pipeline *>(&pipeline);
    draw.uniforms = QByteArray(static_cast<const char *>(uniforms), uniformBytes);
    draw.instances = QByteArray(reinterpret_cast<const char *>(instances.data()), instances.size());
    draw.vertices = vertices;
    draw.count = count;
    draw.scissor = d->scissor;
    for (std::size_t i = 0; i < 3; ++i) {
        auto *t = i < textures.size() && textures[i] ? textures[i] : d->white.get();
        draw.textures[i] = static_cast<Texture *>(t)->storage;
    }
    d->passes.back().draws.push_back(std::move(draw));
}
std::vector<std::uint8_t> RhiDevice::readPixels(mayo::rhi::Texture &) {
    // Captures use QQuickWindow::grabWindow; normal frames never read back.
    return {};
}

void RhiDevice::submit(QRhiCommandBuffer *cb, mayo::rhi::Texture &scene, QRhiTexture *output) {
    auto *batch = d->rhi->nextResourceUpdateBatch();
    for (auto &u : d->uploads) batch->uploadTexture(u.texture->texture.get(), {{0, 0, u.data}});
    d->uploads.clear();
    std::size_t slotIndex = 0;
    for (auto &pass : d->passes) {
        d->target(pass.target, !pass.clear.has_value());
        for (auto &draw : pass.draws) {
            draw.slot = slotIndex++;
            if (draw.slot == d->drawSlots.size()) d->drawSlots.push_back(std::make_unique<Impl::Slot>());
            auto &s = *d->drawSlots[draw.slot];
            if (!s.uniform) {
                s.uniform.reset(d->rhi->newBuffer(QRhiBuffer::Dynamic, QRhiBuffer::UniformBuffer, 96));
                s.uniform->create();
            }
            if (draw.pipeline->stride && (!s.instances || s.instances->size() < quint32(draw.instances.size()))) {
                s.instances.reset(d->rhi->newBuffer(QRhiBuffer::Dynamic, QRhiBuffer::VertexBuffer, std::max(256, int(draw.instances.size()))));
                s.instances->create();
            }
            std::array<QRhiTexture *, 3> bound;
            for (int i = 0; i < 3; ++i) bound[i] = draw.textures[i]->texture.get();
            if (!s.bindings || s.bound != bound) {
                auto sampler = [&](int i) { return draw.textures[i]->filter == mayo::rhi::Filter::Linear
                    ? d->linearSampler.get() : d->sampler.get(); };
                s.bindings.reset(d->rhi->newShaderResourceBindings());
                s.bindings->setBindings({
                    QRhiShaderResourceBinding::uniformBuffer(0, QRhiShaderResourceBinding::VertexStage | QRhiShaderResourceBinding::FragmentStage, s.uniform.get()),
                    QRhiShaderResourceBinding::sampledTexture(1, QRhiShaderResourceBinding::FragmentStage, bound[0], sampler(0)),
                    QRhiShaderResourceBinding::sampledTexture(2, QRhiShaderResourceBinding::FragmentStage, bound[1], sampler(1)),
                    QRhiShaderResourceBinding::sampledTexture(3, QRhiShaderResourceBinding::FragmentStage, bound[2], sampler(2))});
                if (!s.bindings->create()) qFatal("Cannot bind Forma textures");
                s.bound = bound;
            }
            if (!s.pipeline || s.logical != draw.pipeline) {
                s.pipeline.reset(d->rhi->newGraphicsPipeline());
                auto &p = *draw.pipeline;
                const QString vertex = p.name == "ui" ? QStringLiteral("ui.vert") : QStringLiteral("fullscreen.vert");
                const QString fragment = p.name == "ui" ? QStringLiteral("ui.frag") : p.name + QStringLiteral(".frag");
                s.pipeline->setShaderStages({{QRhiShaderStage::Vertex, shader(vertex)}, {QRhiShaderStage::Fragment, shader(fragment)}});
                QRhiVertexInputLayout layout;
                if (p.stride) {
                    layout.setBindings({{quint32(p.stride), QRhiVertexInputBinding::PerInstance}});
                    QList<QRhiVertexInputAttribute> attributes;
                    for (int i = 0; i < p.stride / 16; ++i) attributes.push_back({0, i, QRhiVertexInputAttribute::Float4, quint32(i * 16)});
                    layout.setAttributes(attributes.cbegin(), attributes.cend());
                }
                s.pipeline->setVertexInputLayout(layout);
                s.pipeline->setTopology(p.topology == mayo::rhi::Topology::TriangleStrip ? QRhiGraphicsPipeline::TriangleStrip : QRhiGraphicsPipeline::Triangles);
                s.pipeline->setFlags(QRhiGraphicsPipeline::UsesScissor);
                QRhiGraphicsPipeline::TargetBlend blend;
                blend.enable = p.blend == mayo::rhi::Blend::Premultiplied;
                blend.srcColor = blend.srcAlpha = QRhiGraphicsPipeline::One;
                blend.dstColor = blend.dstAlpha = QRhiGraphicsPipeline::OneMinusSrcAlpha;
                s.pipeline->setTargetBlends({blend});
                s.pipeline->setShaderResourceBindings(s.bindings.get());
                s.pipeline->setRenderPassDescriptor(pass.target->pass.get());
                if (!s.pipeline->create()) qFatal("Cannot create Forma GPU pipeline");
                s.logical = draw.pipeline;
                s.pipelineTarget = pass.target;
            }
            std::array<char, 96> uniform{};
            const auto correction = d->rhi->clipSpaceCorrMatrix();
            std::memcpy(uniform.data(), correction.constData(), 64);
            const int offset = draw.pipeline->name == "ui" ? 64 : 72;
            std::memcpy(uniform.data() + offset, draw.uniforms.constData(), std::min(int(draw.uniforms.size()), 96 - offset));
            batch->updateDynamicBuffer(s.uniform.get(), 0, 96, uniform.data());
            if (!draw.instances.isEmpty()) batch->updateDynamicBuffer(s.instances.get(), 0, draw.instances.size(), draw.instances.constData());
        }
    }
    cb->resourceUpdate(batch);
    for (auto &pass : d->passes) {
        auto *target = d->target(pass.target, !pass.clear.has_value());
        const auto size = target->pixelSize();
        cb->beginPass(target, pass.clear.value_or(Qt::transparent), {1, 0});
        for (auto &draw : pass.draws) {
            auto &s = *d->drawSlots[draw.slot];
            cb->setGraphicsPipeline(s.pipeline.get());
            cb->setViewport({0, 0, float(size.width()), float(size.height())});
            const auto scissor = draw.scissor.value_or(mayo::rhi::Scissor{0, 0, size.width(), size.height()});
            cb->setScissor({scissor.x, scissor.y, scissor.width, scissor.height});
            cb->setShaderResources(s.bindings.get());
            if (draw.pipeline->stride) {
                QRhiCommandBuffer::VertexInput input(s.instances.get(), 0);
                cb->setVertexInput(0, 1, &input);
            }
            cb->draw(draw.vertices, draw.count);
        }
        cb->endPass();
    }
    auto *copy = d->rhi->nextResourceUpdateBatch();
    copy->copyTexture(output, static_cast<Texture &>(scene).storage->texture.get());
    cb->resourceUpdate(copy);
}
}
