/*
 * Uses the same offscreen rendering and Qt texture import as KWin's
 * WindowThumbnailSource (Vlad Zahorodnii, David Edmundson).
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
#include "overviewpreview.h"
#include "overviewpanelprojection.h"
#include "overviewtexturesources.h"
#include <compositor.h>
#include <main.h>
#include <core/output.h>
#include <core/rendertarget.h>
#include <core/renderviewport.h>
#ifdef KOS_KWIN_PAINT_RESULT_API
#include <core/renderdevice.h>
#endif
#include <effect/effecthandler.h>
#include <effect/effectwindow.h>
#include <effect/quickeffect.h>
#include <opengl/glframebuffer.h>
#include <opengl/gltexture.h>
#include <scene/itemrenderer.h>
#include <scene/windowitem.h>
#include <scene/workspacescene.h>
#include <window.h>
#include <QPointer>
#include <QDebug>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSGSimpleTextureNode>
#include <QSGTexture>
#include <QSGTextureProvider>
#include <QSGRendererInterface>
#include <QRunnable>
#include <map>
#include <utility>

namespace KWin
{
namespace
{
constexpr quint64 TextureBudget = 128ull * 1024 * 1024;

bool shellPanel(const Window *window)
{
    return window && window->isDock()
        && (window->resourceClass() == QLatin1String("quickshell")
            || window->resourceClass() == QLatin1String("org.quickshell"));
}

struct PreviewFrame
{
    std::shared_ptr<GLTexture> texture;
    std::unique_ptr<GLFramebuffer> framebuffer;
    GLsync fence = nullptr;
    quint64 revision = 0;
    void releaseFence()
    {
        if (fence) glDeleteSync(std::exchange(fence, nullptr));
    }
};

class PreviewTextureProvider final : public QSGTextureProvider
{
public:
    QSGTexture *texture() const override { return m_wrapped.get(); }
    void present(QQuickWindow *window, const std::shared_ptr<PreviewFrame> &frame)
    {
        if (!window || !frame || !frame->texture) return;
        if (m_texture == frame->texture && m_revision == frame->revision) return;
        if (frame->fence) {
            glWaitSync(frame->fence, 0, GL_TIMEOUT_IGNORED);
            frame->releaseFence();
        }
        if (m_texture != frame->texture) {
            m_texture = frame->texture;
            m_wrapped.reset(QNativeInterface::QSGOpenGLTexture::fromNative(
                m_texture->texture(), window, m_texture->size(), QQuickWindow::TextureHasAlphaChannel));
            if (m_wrapped) m_wrapped->setFiltering(QSGTexture::Linear);
        }
        m_revision = frame->revision;
        if (m_wrapped) Q_EMIT textureChanged();
    }
private:
    // Only the texture crosses contexts, never the capture framebuffer.
    std::shared_ptr<GLTexture> m_texture;
    std::unique_ptr<QSGTexture> m_wrapped;
    quint64 m_revision = 0;
};

class ProviderCleanup final : public QRunnable
{
public:
    explicit ProviderCleanup(PreviewTextureProvider *provider) : m_provider(provider) {}
    void run() override { m_provider.reset(); }
private:
    std::unique_ptr<PreviewTextureProvider> m_provider;
};

class PreviewItem final : public QQuickItem
{
public:
    explicit PreviewItem(QQuickItem *source) : QQuickItem(source->parentItem())
    {
        setParent(source); // Lifetime follows the background, not its visual parent.
        setFlag(ItemHasContents);
        setVisible(false); // A texture source, never an additional scene overlay.
        const auto resize = [this, source] { setSize(source->size()); };
        connect(source, &QQuickItem::widthChanged, this, resize);
        connect(source, &QQuickItem::heightChanged, this, resize);
        connect(this, &QQuickItem::windowChanged, this, [this](QQuickWindow *view) { bindWindow(view); });
        bindWindow(window());
        resize();
    }
    ~PreviewItem() override { releaseResources(); }
    bool isTextureProvider() const override { return true; }
    QSGTextureProvider *textureProvider() const override
    {
        if (QQuickItem::isTextureProvider()) return QQuickItem::textureProvider();
        if (!m_provider) m_provider = new PreviewTextureProvider;
        // Consumers can request the provider without drawing this item (native
        // DesktopBackground is explicitly invisible). Publish here as well.
        m_provider->present(window(), frame);
        return m_provider;
    }
    std::shared_ptr<PreviewFrame> frame;
    quint64 revision = 0;
    void present(const std::shared_ptr<PreviewFrame> &next)
    {
        if (frame != next || revision != next->revision) {
            frame = next;
            revision = next->revision;
            update();
        }
    }
protected:
    void releaseResources() override
    {
        auto *provider = std::exchange(m_provider, nullptr);
        if (!provider) return;
        if (window()) window()->scheduleRenderJob(new ProviderCleanup(provider), QQuickWindow::AfterSynchronizingStage);
        else delete provider;
    }
    QSGNode *updatePaintNode(QSGNode *old, UpdatePaintNodeData *) override
    {
        if (!frame || !frame->texture || !window()) return old;
        auto *provider = textureProvider();
        auto *node = static_cast<QSGSimpleTextureNode *>(old);
        if (!node) node = new QSGSimpleTextureNode;
        node->setTexture(provider->texture());
        node->setFiltering(QSGTexture::Linear);
        // The FBO follows WindowThumbnailSource's FlipY/import convention.
        node->setTextureCoordinatesTransform(QSGSimpleTextureNode::NoTransform);
        node->setRect(boundingRect());
        node->markDirty(QSGNode::DirtyMaterial);
        return node;
    }
private:
    void bindWindow(QQuickWindow *view)
    {
        disconnect(m_sync);
        if (!view) return;
        m_sync = connect(view, &QQuickWindow::beforeSynchronizing, this, [this] {
            // Invisible texture sources need not get updatePaintNode(). Publish
            // the new frame on Qt's render thread before consumers synchronize.
            if (!m_provider) m_provider = new PreviewTextureProvider;
            m_provider->present(window(), frame);
        }, Qt::DirectConnection);
    }
    mutable PreviewTextureProvider *m_provider = nullptr;
    QMetaObject::Connection m_sync;
};

auto *workspaceScene()
{
#ifdef GLASS_KWIN_67
    return kwinApp()->scene();
#else
    return Compositor::self()->scene();
#endif
}

ItemRenderer *desktopRenderer()
{
#ifdef KOS_KWIN_PAINT_RESULT_API
    return workspaceScene()->renderer(Compositor::self()->primaryDevice());
#else
    return workspaceScene()->renderer();
#endif
}
}

class OverviewPreview::Private
{
public:
    OverviewPreview *owner;
    MaterialPass material;
    bool dirty = true;
    bool failed = false;
    std::map<LogicalOutput *, std::shared_ptr<PreviewFrame>> frames;
    std::map<QQuickItem *, QPointer<PreviewItem>> previews;
    OverviewPanelProjection panels;
    OverviewTextureSources sources;
    bool reported = false;

    void watch(EffectWindow *window)
    {
        auto *native = window->window();
        if (native && (native->isDesktop() || shellPanel(native))) {
            QObject::connect(native, &Window::damaged, owner, [this] { dirty = true; });
            QObject::connect(native, &Window::frameGeometryChanged, owner, [this] { dirty = true; });
            QObject::connect(native, &Window::opacityChanged, owner, [this] { dirty = true; });
        }
        dirty = true;
    }

    void clear()
    {
        sources.restore();
        panels.restore();
        auto items = std::exchange(previews, {});
        for (const auto &[key, item] : items)
            if (item) delete item;
        if (!frames.empty()) {
            effects->makeOpenGLContextCurrent();
            for (auto &[output, frame] : frames)
                if (frame) frame->releaseFence();
            frames.clear();
        }
        dirty = true;
        reported = false;
    }

    bool capture(LogicalOutput *output, const QSize &size)
    {
        auto &frame = frames[output];
        if (!frame || frame->texture->size() != size) {
            auto texture = GLTexture::allocate(GL_RGBA8, size);
            if (!texture) return false;
            texture->setContentTransform(OutputTransform::FlipY);
            texture->setFilter(GL_LINEAR);
            texture->setWrapMode(GL_CLAMP_TO_EDGE);
            auto framebuffer = std::make_unique<GLFramebuffer>(texture.get());
            if (!framebuffer->valid()) return false;
            if (frame) frame->releaseFence();
            frame = std::make_shared<PreviewFrame>();
            frame->texture = std::move(texture);
            frame->framebuffer = std::move(framebuffer);
        }
        frame->releaseFence();
        RenderTarget target(frame->framebuffer.get());
        RenderViewport viewport(output->geometry(), output->scale(), target, QPoint());
        auto *renderer = desktopRenderer();
        if (!renderer) return false;
        GLFramebuffer::pushFramebuffer(frame->framebuffer.get());
        renderer->beginFrame(target, viewport);
        renderer->renderBackground(target, viewport, target.transformedRect());
        renderer->endFrame();
        bool hasWallpaper = false;
        bool ok = true;
        for (auto *window : effects->stackingOrder()) {
            auto *native = window->window();
            if (!native || window->isDeleted() || !window->isVisible()
                || !native->isOnOutput(output) || !window->isOnCurrentDesktop()
                || !window->isOnCurrentActivity()
                || (!native->isDesktop() && !shellPanel(native))) continue;
            hasWallpaper |= native->isDesktop();
            // Material sees the already-rendered wallpaper, never an app or
            // Overview's own blurred backdrop. Normal capture geometry is used.
            material(target, viewport, window);
            renderer->beginFrame(target, viewport);
            WindowPaintData data;
#ifdef KOS_KWIN_PAINT_RESULT_API
            ok = renderer->renderItem(target, viewport, window->windowItem(),
                0, Region::infinite(), data, {}, {});
#else
            renderer->renderItem(target, viewport, window->windowItem(),
                0, Region::infinite(), data, {}, {});
#endif
            renderer->endFrame();
            if (!ok) break;
        }
        GLFramebuffer::popFramebuffer();
        if (!ok || !hasWallpaper) return false;
        frame->fence = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
        glFlush();
        ++frame->revision;
        return true;
    }

    void attach(QQuickItem *root, const std::shared_ptr<PreviewFrame> &frame)
    {
        // Traverse visual children: QML delegates need not share QObject parents.
        const auto children = root->childItems();
        if (root->inherits("KWin::DesktopBackgroundItem")) {
            auto &item = previews[root];
            if (!item) item = new PreviewItem(root);
            item->present(frame);
            return;
        }
        for (auto *child : children) attach(child, frame);
    }

    int redirect(QQuickItem *root)
    {
        int count = 0;
        auto *original = overviewTextureSource(root);
        if (const auto it = previews.find(original); it != previews.end() && it->second) {
            if (sources.replace(root, original, it->second)) ++count;
        } else if (original) {
            for (const auto &[background, preview] : previews)
                if (preview == original) { ++count; break; }
        }
        for (auto *child : root->childItems()) count += redirect(child);
        return count;
    }

    void projectPanels(QQuickItem *root)
    {
        const auto children = root->childItems();
        if (root->inherits("KWin::WindowThumbnailItem")
            && !root->inherits("KWin::DesktopBackgroundItem")) {
            auto *client = root->property("client").value<Window *>();
            if (shellPanel(client)) {
                panels.project(root);
                return;
            }
        }
        for (auto *child : children) projectPanels(child);
    }

    void update()
    {
        auto *effect = effects->activeFullScreenEffect();
        auto *overview = effect && effect->inherits("KWin::OverviewEffect")
            ? qobject_cast<QuickSceneEffect *>(effect) : nullptr;
        if (!overview || effects->isScreenLocked()) { clear(); failed = false; return; }
        if (failed) return;
        const auto fail = [this] {
            clear();
            failed = true;
            qWarning() << "Glass: composed Overview preview unavailable; retaining native previews";
        };
        if (QQuickWindow::graphicsApi() != QSGRendererInterface::OpenGL
            || QQuickWindow::sceneGraphBackend().startsWith(QLatin1String("software"))) { fail(); return; }
        // Admit all outputs together: on a failure retain native Overview.
        quint64 bytes = 0;
        const auto outputs = effects->screens();
        for (auto *output : outputs) {
            const QSize size = QSizeF(output->geometry().size()).toSize() * output->scale();
            if (size.isEmpty()) { fail(); return; }
            bytes += quint64(size.width()) * quint64(size.height()) * 4;
        }
        if (bytes > TextureBudget || !effects->makeOpenGLContextCurrent()) { fail(); return; }
        for (auto *output : outputs) {
            const QSize size = QSizeF(output->geometry().size()).toSize() * output->scale();
            const auto it = frames.find(output);
            if (dirty || it == frames.end() || it->second->texture->size() != size) {
                if (!capture(output, size)) { fail(); return; }
            }
        }
        dirty = false;
        int redirected = 0;
        QList<QQuickItem *> connectedRoots;
        for (auto *output : outputs) {
            if (auto *view = overview->viewForScreen(output))
                if (auto *root = view->rootItem()) {
                    attach(root, frames.at(output));
                    const int consumers = redirect(root);
                    redirected += consumers;
                    if (consumers > 0) connectedRoots.append(root);
                }
        }
        if (previews.empty()) return; // Delegate creation can finish next frame.
        if (!reported && redirected == 0) {
            qWarning() << "Glass: no native desktop texture consumer was replaced";
            fail();
            return;
        }
        for (auto *root : connectedRoots) projectPanels(root);
        if (!reported) {
            qInfo() << "Glass: composed Overview connected" << outputs.size()
                    << "outputs," << previews.size() << "backgrounds," << redirected << "texture consumers";
            reported = true;
        }
        // Keep only live QML items and connected output buffers.
        std::erase_if(previews, [](const auto &entry) { return !entry.second; });
        for (auto it = frames.begin(); it != frames.end();) {
            if (!outputs.contains(it->first)) {
                it->second->releaseFence();
                it = frames.erase(it);
            } else ++it;
        }
    }
};

OverviewPreview::OverviewPreview(MaterialPass material, QObject *parent)
    : QObject(parent), d(std::make_unique<Private>())
{
    d->owner = this;
    d->material = std::move(material);
    // Same sanctioned hook as WindowThumbnailSource, installed before native
    // thumbnail sources. No rendering is injected into a Qt Quick flush.
    connect(workspaceScene(), &WorkspaceScene::preFrameRender, this, [this] { d->update(); });
    connect(effects, &EffectsHandler::activeFullScreenEffectChanged, this, [this] {
        if (!effects->activeFullScreenEffect()
            || !effects->activeFullScreenEffect()->inherits("KWin::OverviewEffect")) d->clear();
        else { d->dirty = true; d->failed = false; }
    });
    connect(effects, &EffectsHandler::windowAdded, this, [this](EffectWindow *window) { d->watch(window); });
    connect(effects, &EffectsHandler::windowDeleted, this, [this] { d->dirty = true; });
    for (auto *window : effects->stackingOrder()) d->watch(window);
}

OverviewPreview::~OverviewPreview()
{
    disconnect(workspaceScene(), nullptr, this, nullptr);
    disconnect(effects, nullptr, this, nullptr);
    for (auto *window : effects->stackingOrder())
        if (window->window()) disconnect(window->window(), nullptr, this, nullptr);
    d->clear();
}

void OverviewPreview::invalidate() { d->dirty = true; }
}
