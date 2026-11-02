/*
 * Uses the same offscreen rendering and Qt texture import as KWin's
 * WindowThumbnailSource (Vlad Zahorodnii, David Edmundson).
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
#include "overviewpreview.h"
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
#include <QSGRendererInterface>
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
    std::unique_ptr<GLTexture> texture;
    std::unique_ptr<GLFramebuffer> framebuffer;
    GLsync fence = nullptr;
    quint64 revision = 0;
    void releaseFence()
    {
        if (fence) glDeleteSync(std::exchange(fence, nullptr));
    }
};

class PreviewNode final : public QSGSimpleTextureNode
{
public:
    std::shared_ptr<PreviewFrame> frame;
    std::unique_ptr<QSGTexture> wrapped;
};

class PreviewItem final : public QQuickItem
{
public:
    explicit PreviewItem(QQuickItem *parent) : QQuickItem(parent)
    {
        setFlag(ItemHasContents);
        setZ(1);
        const auto resize = [this, parent] { setSize(parent->size()); };
        connect(parent, &QQuickItem::widthChanged, this, resize);
        connect(parent, &QQuickItem::heightChanged, this, resize);
        resize();
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
    QSGNode *updatePaintNode(QSGNode *old, UpdatePaintNodeData *) override
    {
        if (!frame || !frame->texture || !window()) return old;
        if (frame->fence) {
            glWaitSync(frame->fence, 0, GL_TIMEOUT_IGNORED);
            frame->releaseFence();
        }
        auto *node = static_cast<PreviewNode *>(old);
        if (!node) node = new PreviewNode;
        if (node->frame != frame) {
            node->frame = frame;
            node->wrapped.reset(QNativeInterface::QSGOpenGLTexture::fromNative(
                frame->texture->texture(), window(), frame->texture->size(),
                QQuickWindow::TextureHasAlphaChannel));
            node->setTexture(node->wrapped.get());
            node->setFiltering(QSGTexture::Linear);
        }
        // The FBO follows WindowThumbnailSource's FlipY/import convention.
        node->setTextureCoordinatesTransform(QSGSimpleTextureNode::NoTransform);
        node->setRect(boundingRect());
        node->markDirty(QSGNode::DirtyMaterial);
        return node;
    }
};

auto *workspaceScene()
{
#ifdef KOS_KWIN_PAINT_RESULT_API
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
    struct Panel { QPointer<QQuickItem> item; qreal opacity; };
    std::map<QQuickItem *, Panel> panels;

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
        // Never change client visibility/focus. Restore only the redundant
        // native panel thumbnail; its pixels are in the composed desktop now.
        auto saved = std::exchange(panels, {});
        for (const auto &[key, panel] : saved)
            if (panel.item) panel.item->setOpacity(panel.opacity);
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
        if (root->inherits("KWin::WindowThumbnailItem")) {
            auto *client = root->property("client").value<Window *>();
            if (shellPanel(client)) {
                auto &saved = panels[root];
                if (!saved.item) saved = {root, root->opacity()};
                root->setOpacity(0);
                return;
            }
        }
        for (auto *child : children) attach(child, frame);
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
        for (auto *output : outputs) {
            if (auto *view = overview->viewForScreen(output))
                if (auto *root = view->rootItem()) attach(root, frames.at(output));
        }
        // Keep only live QML items and connected output buffers.
        std::erase_if(previews, [](const auto &entry) { return !entry.second; });
        std::erase_if(panels, [](const auto &entry) { return !entry.second.item; });
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
