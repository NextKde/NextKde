#include "networkview.h"
#include "networkscene.h"
#include "qrhidevice.h"
#include "renderer2d.hpp"
#include "render/text_system.hpp"
#include "core/event_dispatcher.hpp"
#include "mayonnaise/widgets/scroll_view.hpp"
#include <rhi/qrhi.h>
#include <limits>
#include <QHoverEvent>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QWheelEvent>
#include <QPointer>
#include <QQuickWindow>
#include <QQmlEngine>
#include <QQuickImageProvider>
#include <QQuickTextureFactory>
#include <QImageReader>
#include <QUrl>
#include <chrono>
#include <cstdio>
#include <algorithm>

static void initShaders() {
    static std::once_flag initialized;
    std::call_once(initialized, [] { Q_INIT_RESOURCE(forma_network_shaders); });
}
namespace {
double now() { return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count(); }
mayo::Modifiers modifiers(Qt::KeyboardModifiers mods) {
    auto result = mayo::Modifiers::None;
    if (mods & Qt::ShiftModifier) result = result | mayo::Modifiers::Shift;
    if (mods & Qt::ControlModifier) result = result | mayo::Modifiers::Ctrl;
    if (mods & Qt::AltModifier) result = result | mayo::Modifiers::Alt;
    return result;
}
mayo::PointerEvent pointer(QPointF p, Qt::MouseButton button = Qt::NoButton, Qt::KeyboardModifiers mods = {}) {
    return {{float(p.x()), float(p.y())}, button == Qt::LeftButton ? mayo::MouseButton::Left : mayo::MouseButton::None, 1, modifiers(mods)};
}
}

class NetworkRenderer final : public QQuickRhiItemRenderer, public mayo::WidgetHost {
    std::unique_ptr<Kos::Forma::RhiDevice> m_device;
    std::unique_ptr<mayo::render::Renderer2D> m_renderer;
    std::unique_ptr<mayo::render::TextSystem> m_text;
    std::unique_ptr<Kos::Forma::NetworkScene> m_scene;
    mayo::EventDispatcher m_events;
    mayo::Theme m_theme = mayo::Theme::make(mayo::Appearance::Dark);
    QPointer<NetworkView> m_item;
    QSizeF m_size;
    bool m_needsLayout = true, m_redraw = false, m_key = true;
    double m_time = 0, m_deadline = -1;
    QVariantMap m_data;
    QColor m_ink, m_muted;
    bool m_details = false, m_dark = true;
    int m_frames = 0;
    // Revisions handed over by NetworkView. A frame only re-applies the scene when
    // one of them moved, so hover/scroll frames no longer deep-compare the whole
    // snapshot or convert the translation map on the render thread.
    quint64 m_revision = 0, m_translationsRevision = 0;
    bool m_themeInitialized = false;
    QSize m_postedPixels;
    int m_postedComponents = -1;
    qreal m_postedScroll = 0;
    std::vector<mayo::Rect> m_hoverRects;
    // Opt-in frame timing for the verification binary (KOS_FORMA_BENCH=1).
    static const inline bool bench = qEnvironmentVariableIsSet("KOS_FORMA_BENCH");
    double syncSeconds = 0, renderSeconds = 0, syncMax = 0, renderMax = 0;
    int benchFrames = 0;

    void context() {
        mayo::rhi::setDevice(m_device.get());
        Kos::Forma::setTheme(&m_theme);
    }
    template<class F> void post(F fn) {
        const QPointer<NetworkView> item = m_item;
        if (item) QMetaObject::invokeMethod(item, [item, fn] { if (item) fn(item.data()); }, Qt::QueuedConnection);
    }
public:
    ~NetworkRenderer() override {
        std::lock_guard lock(Kos::Forma::nativeMutex());
        context();
        m_scene.reset(); m_text.reset(); m_renderer.reset();
        mayo::rhi::setDevice(nullptr); Kos::Forma::setTheme(nullptr); m_device.reset();
    }
    void initialize(QRhiCommandBuffer *) override {
        if (m_device) return;
        std::lock_guard lock(Kos::Forma::nativeMutex());
        m_device = std::make_unique<Kos::Forma::RhiDevice>(rhi()); context();
        m_renderer = std::make_unique<mayo::render::Renderer2D>();
        m_text = std::make_unique<mayo::render::TextSystem>();
    }
    void synchronize(QQuickRhiItem *base) override {
        const double benchStart = bench ? now() : 0;
        std::lock_guard lock(Kos::Forma::nativeMutex());
        auto *item = static_cast<NetworkView *>(base);
        m_item = item; m_time = now(); context();
        const QSizeF size(item->width(), item->height());
        if (m_size != size) { m_size = size; m_needsLayout = true; }
        m_key = item->window() && item->window()->isActive();
        // The language list is only rebuilt when it actually changed, so switching
        // language still discards the native tree (and its layout) exactly as before.
        if (m_scene && item->m_translationsRevision != m_translationsRevision) {
            m_events.cancelPointer();
            m_events = mayo::EventDispatcher{};
            m_scene.reset();
            m_data.clear();
            // The replacement tree has not seen any snapshot yet, so force the
            // next synchronize past the revision check even if QML did not resend.
            m_revision = std::numeric_limits<quint64>::max();
        }
        if (!m_scene) {
            m_translationsRevision = item->m_translationsRevision;
            m_scene = std::make_unique<Kos::Forma::NetworkScene>(
                [this] { post([](NetworkView *i) { emit i->closeRequested(); }); },
                [this] { post([](NetworkView *i) { emit i->detailsToggleRequested(); }); },
                [this] { post([](NetworkView *i) { emit i->refreshRequested(); }); },
                [this] { post([](NetworkView *i) { emit i->resetTotalsRequested(); }); }, item->m_translations);
            m_scene->root()->setHost(this); m_events.setRoot(m_scene->root());
            m_themeInitialized = false;
            m_needsLayout = true;
        }
        if (!m_themeInitialized || item->m_dark != m_dark || item->m_ink != m_ink || item->m_muted != m_muted) {
            m_dark = item->m_dark;
            m_ink = item->m_ink; m_muted = item->m_muted;
            m_theme = mayo::Theme::make(m_dark ? mayo::Appearance::Dark : mayo::Appearance::Light);
            m_theme.colors.label = {float(m_ink.redF()), float(m_ink.greenF()), float(m_ink.blueF()), float(m_ink.alphaF())};
            m_theme.colors.secondaryLabel = {float(m_muted.redF()), float(m_muted.greenF()), float(m_muted.blueF()), float(m_muted.alphaF())};
            m_themeInitialized = true;
            m_scene->applyTheme(m_ink, m_muted);
            m_needsLayout = true;
        }
        if (item->m_revision != m_revision || item->m_details != m_details) {
            m_revision = item->m_revision; m_details = item->m_details;
            m_data = item->m_snapshot;
            m_scene->applyData(m_data, m_details);
            m_needsLayout = true;
        }
        layout();
        for (const auto &e : item->m_input) {
            switch (e.type) {
            case NetworkView::Input::Press: m_events.pointerDown(e.pointer); break;
            case NetworkView::Input::Release: m_events.pointerUp(e.pointer); break;
            case NetworkView::Input::Move: m_events.pointerMove(e.pointer); break;
            case NetworkView::Input::Leave: m_events.pointerLeave(); break;
            case NetworkView::Input::Scroll: m_events.scroll(e.scroll); break;
            case NetworkView::Input::Key: m_events.keyDown(e.key); break;
            case NetworkView::Input::Cancel: m_events.cancelPointer(); m_events.setFocus(nullptr, false); break;
            }
        }
        item->m_input.clear();
        if (bench) {
            const double elapsed = now() - benchStart;
            syncSeconds += elapsed; syncMax = std::max(syncMax, elapsed);
        }
    }
    void layout() {
        if (!m_needsLayout || !m_scene) return;
        m_needsLayout = false;
        m_scene->root()->measure({float(m_size.width()), float(m_size.height())});
        m_scene->root()->arrange({0, 0, float(m_size.width()), float(m_size.height())});
        m_events.refreshHover();
        publishHoverTargets();
    }
    // Publishing where hover actually matters is cheaper and more precise than
    // letting the GUI thread repaint the popup for every pointer move: Forma only
    // reacts to hover on controls and on the overlay scrollbar track.
    static void collectHoverTargets(mayo::Widget *w, std::vector<mayo::Rect> &out) {
        if (!w->isVisible()) return;
        if (w->isInteractive() || w->cursor() != mayo::CursorShape::Arrow) out.push_back(w->frame());
        if (dynamic_cast<mayo::ScrollViewView *>(w)) {
            const auto frame = w->frame();
            out.push_back({frame.right() - 16, frame.y, 16, frame.height});
        }
        for (const auto &child : w->children()) collectHoverTargets(child.get(), out);
    }
    void publishHoverTargets() {
        std::vector<mayo::Rect> targets;
        collectHoverTargets(m_scene->root().get(), targets);
        if (targets == m_hoverRects) return;
        m_hoverRects = targets;
        post([targets = std::move(targets)](NetworkView *item) {
            item->m_hoverRects = targets;
            item->m_hoverRectsReady = true;
        });
    }
    void render(QRhiCommandBuffer *cb) override {
        const double benchStart = bench ? now() : 0;
        std::lock_guard lock(Kos::Forma::nativeMutex());
        context(); m_time = now(); m_redraw = false;
        if (!m_scene || m_size.width() <= 0 || m_size.height() <= 0) return;
        layout();
        const auto pixels = colorTexture()->pixelSize();
        const float scale = float(pixels.width() / m_size.width());
        m_device->resetFrame();
        m_renderer->beginEmbedded(pixels.width(), pixels.height(), scale);
        mayo::Painter painter(*m_renderer, *m_text);
        painter.pushClip({0, 0, float(m_size.width()), float(m_size.height())}, 16);
        m_scene->root()->paint(painter);
        for (auto &overlay : m_events.overlays()) overlay->paint(painter);
        painter.popClip();
        m_renderer->endFrame();
        m_device->submit(cb, m_renderer->scene(), colorTexture());
        const int components = m_scene->nativeComponentCount();
        const int frames = ++m_frames;
        const qreal scrollOffset = m_scene->scrollOffset();
        const bool diagnosticChange = pixels != m_postedPixels || components != m_postedComponents
            || scrollOffset != m_postedScroll;
        m_postedPixels = pixels; m_postedComponents = components; m_postedScroll = scrollOffset;
        // The frame counter still reaches the GUI thread (idle detection reads it),
        // but bindings are only notified when an exposed value actually changed.
        post([pixels, components, frames, scrollOffset, diagnosticChange](NetworkView *item) {
            item->m_pixels = pixels; item->m_components = components; item->m_frames = frames;
            item->m_scrollOffset = scrollOffset;
            if (diagnosticChange) emit item->diagnosticsChanged();
        });
        if (bench) {
            const double elapsed = now() - benchStart;
            renderSeconds += elapsed; renderMax = std::max(renderMax, elapsed);
            if (++benchFrames >= 30) {
                std::fprintf(stderr, "[bench] frames=%d sync=%.3fms/max%.3f render=%.3fms/max%.3f draws=%d\n",
                             benchFrames, syncSeconds / benchFrames * 1000, syncMax * 1000,
                             renderSeconds / benchFrames * 1000, renderMax * 1000,
                             m_renderer->drawCallsLastFrame());
                benchFrames = 0; syncSeconds = renderSeconds = syncMax = renderMax = 0;
            }
        }
        if (m_redraw) update();
        if (m_deadline >= 0) {
            const int ms = std::max(1, int(std::ceil((m_deadline - now()) * 1000)));
            post([ms](NetworkView *i) { i->scheduleWake(ms); }); m_deadline = -1;
        }
    }
    void requestRedraw() override { m_redraw = true; }
    void requestLayout() override { m_needsLayout = true; m_redraw = true; }
    double time() const override { return m_time; }
    void scheduleFrame(double t) override { if (m_deadline < 0 || t < m_deadline) m_deadline = t; }
    void setFocus(mayo::Widget *w, bool visible) override { m_events.setFocus(w, visible); }
    mayo::Widget *focusedWidget() const override { return m_events.focused(); }
    bool focusVisible() const override { return m_events.focusVisible(); }
    bool isKeyWindow() const override { return m_key; }
    void setCursor(mayo::CursorShape c) override {
        post([c](NetworkView *i) { i->setCursor(c == mayo::CursorShape::PointingHand ? Qt::PointingHandCursor : Qt::ArrowCursor); });
    }
    void showOverlay(std::shared_ptr<mayo::Widget> overlay) override {
        overlay->setHost(this); m_events.pushOverlay(overlay); requestLayout();
    }
    void dismissOverlay(mayo::Widget *w) override { m_events.removeOverlay(w); requestLayout(); }
    std::string clipboardText() const override { return {}; }
    void setClipboardText(const std::string &) override {}
    void setTextInput(bool, mayo::Rect) override {}
    mayo::Size windowSize() const override { return {float(m_size.width()), float(m_size.height())}; }
};

NetworkView::NetworkView(QQuickItem *parent) : QQuickRhiItem(parent) {
    initShaders();
    setAlphaBlending(true);
    setAcceptedMouseButtons(Qt::LeftButton);
    setAcceptHoverEvents(true);
    setFlag(ItemIsFocusScope);
    setActiveFocusOnTab(true);
    m_wake.setSingleShot(true);
    connect(&m_wake, &QTimer::timeout, this, &NetworkView::update);
}
QQuickRhiItemRenderer *NetworkView::createRenderer() { return new NetworkRenderer; }
void NetworkView::setSnapshot(const QVariantMap &v) {
    // QML rebuilds the snapshot object for every service tick. Compare the raw
    // map (no resolved icons in it) instead of comparing decoded images, and skip
    // icon lookup, copying and a frame request when nothing changed at all.
    if (m_hasSnapshot && m_source == v) return;
    m_source = v;
    m_hasSnapshot = true;
    QVariantMap data = v;
    const auto revision = data.value("iconRevision").toULongLong();
    if (m_iconRevision != revision) { m_iconRevision = revision; m_icons.clear(); }
    auto applications = data.value("applications").toList();
    for (auto &value : applications) {
        auto row = value.toMap();
        const auto source = row.value("iconSource").toString();
        if (!source.isEmpty()) {
            if (!m_icons.contains(source)) {
                QImage image;
                const QUrl url(source);
                QSize actualSize;
                if (url.scheme() == "image") {
                    auto *engine = qmlEngine(this);
                    auto *provider = engine ? dynamic_cast<QQuickImageProvider *>(engine->imageProvider(url.host())) : nullptr;
                    if (provider && provider->imageType() == QQmlImageProviderBase::Image)
                        image = provider->requestImage(url.path().mid(1), &actualSize, {32,32});
                    else if (provider && provider->imageType() == QQmlImageProviderBase::Pixmap)
                        image = provider->requestPixmap(url.path().mid(1), &actualSize, {32,32}).toImage();
                    else if (provider && provider->imageType() == QQmlImageProviderBase::Texture) {
                        std::unique_ptr<QQuickTextureFactory> factory(provider->requestTexture(url.path().mid(1), &actualSize, {32,32}));
                        if (factory) image = factory->image();
                    }
                } else if (url.isLocalFile() || source.startsWith(":/") || url.scheme() == "qrc") {
                    QImageReader reader(url.isLocalFile() ? url.toLocalFile() : url.scheme() == "qrc" ? ":" + url.path() : source);
                    reader.setScaledSize({32,32}); image = reader.read();
                }
                if (m_icons.size() >= 128) m_icons.clear();
                m_icons.insert(source, image.convertToFormat(QImage::Format_RGBA8888));
            }
            row.insert("iconImage", m_icons.value(source));
            value = row;
        }
    }
    data.insert("applications", applications);
    const auto translations = data.value("translations").toMap();
    if (translations != m_translations) { m_translations = translations; ++m_translationsRevision; }
    ++m_revision;
    m_snapshot = std::move(data);
    emit snapshotChanged(); update();
}
void NetworkView::setDetailsExpanded(bool v) { if (m_details == v) return; m_details = v; emit detailsExpandedChanged(); update(); }
void NetworkView::setDark(bool v) { if (m_dark == v) return; m_dark = v; emit darkChanged(); update(); }
void NetworkView::setInk(const QColor &v) { if (m_ink == v) return; m_ink = v; emit inkChanged(); update(); }
void NetworkView::setMutedInk(const QColor &v) { if (m_muted == v) return; m_muted = v; emit mutedInkChanged(); update(); }
void NetworkView::scheduleWake(int ms) { if (!m_wake.isActive() || ms < m_wake.remainingTime()) m_wake.start(ms); }
void NetworkView::enqueue(Input e) { m_input.push_back(e); update(); }
void NetworkView::mousePressEvent(QMouseEvent *e) { forceActiveFocus(Qt::MouseFocusReason); enqueue({Input::Press, pointer(e->position(), e->button(), e->modifiers())}); e->accept(); }
void NetworkView::mouseReleaseEvent(QMouseEvent *e) { enqueue({Input::Release, pointer(e->position(), e->button(), e->modifiers())}); e->accept(); }
void NetworkView::mouseMoveEvent(QMouseEvent *e) { enqueue({Input::Move, pointer(e->position(), e->button(), e->modifiers())}); e->accept(); }
bool NetworkView::hoverTarget(QPointF p) const {
    for (const auto &rect : m_hoverRects) {
        if (p.x() >= rect.x && p.x() < rect.right() && p.y() >= rect.y && p.y() < rect.bottom())
            return true;
    }
    return false;
}
void NetworkView::hoverEnterEvent(QHoverEvent *e) {
    m_lastHoverSensitive = hoverTarget(e->position());
    enqueue({Input::Move, pointer(e->position())});
    e->accept();
}
void NetworkView::hoverMoveEvent(QHoverEvent *e) {
    const bool sensitive = hoverTarget(e->position());
    // Outside the controls and the scrollbar track Forma's hover state cannot
    // change, so repainting the whole glass popup for that move would only cost
    // a composite. Entering or leaving such a target still repaints, which is what
    // keeps hover feedback and cursors exactly as before.
    if (!m_hoverRectsReady || sensitive || m_lastHoverSensitive)
        enqueue({Input::Move, pointer(e->position())});
    m_lastHoverSensitive = sensitive;
    e->accept();
}
void NetworkView::hoverLeaveEvent(QHoverEvent *e) {
    m_lastHoverSensitive = false;
    enqueue({Input::Leave, {}});
    e->accept();
}
void NetworkView::wheelEvent(QWheelEvent *e) {
    Input input{Input::Scroll, {}};
    input.scroll.position = {float(e->position().x()), float(e->position().y())};
    const bool precise = !e->pixelDelta().isNull();
    const QPointF delta = precise ? QPointF(e->pixelDelta()) : QPointF(e->angleDelta()) / 3;
    input.scroll.delta = {float(-delta.x()), float(-delta.y())};
    input.scroll.precise = precise; input.scroll.modifiers = modifiers(e->modifiers());
    input.scroll.reportsEnd = e->phase() != Qt::NoScrollPhase;
    input.scroll.phase = e->phase() == Qt::ScrollEnd ? mayo::ScrollPhase::Ended : mayo::ScrollPhase::Changed;
    enqueue(input); e->accept();
}
void NetworkView::keyPressEvent(QKeyEvent *e) {
    if (e->key() == Qt::Key_Escape) { emit closeRequested(); e->accept(); return; }
    Input input{Input::Key, {}};
    switch (e->key()) {
    case Qt::Key_Tab: case Qt::Key_Backtab: input.key.key = mayo::Key::Tab; break;
    case Qt::Key_Space: input.key.key = mayo::Key::Space; break;
    case Qt::Key_Enter: case Qt::Key_Return: input.key.key = mayo::Key::Enter; break;
    default: e->ignore(); return;
    }
    input.key.modifiers = modifiers(e->modifiers());
    if (e->key() == Qt::Key_Backtab) input.key.modifiers = input.key.modifiers | mayo::Modifiers::Shift;
    enqueue(input); e->accept();
}
void NetworkView::focusOutEvent(QFocusEvent *e) { enqueue({Input::Cancel, {}}); QQuickRhiItem::focusOutEvent(e); }
