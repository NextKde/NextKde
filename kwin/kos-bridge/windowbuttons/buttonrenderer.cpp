#include "buttonrenderer.h"
#include "buttonconfig.h"

#include <effect/effectwindow.h>
#include <effect/effecthandler.h>
#include <window.h>
#include <core/rendertarget.h>
#include <core/renderviewport.h>
#include <opengl/gltexture.h>
#include <opengl/glshader.h>
#include <opengl/glshadermanager.h>
#include <opengl/glframebuffer.h>

#include <QPainter>
#include <QPainterPath>
#include <QPalette>
#include <QTimer>
#include <QVector4D>

#include <epoxy/gl.h>

#include <algorithm>
#include <chrono>
#include <cmath>

namespace KOS
{

namespace
{
// Supersampling factor used when rasterising the panel image.
constexpr int Supersample = 4;
// Bound textures created by repeated panel size/spacing adjustments. These
// are GPU uploads kept for reuse, not per-window resources.
constexpr qsizetype MaxTextureCacheBytes = 16 * 1024 * 1024;
// How long a reading of the title bar has to hold before it displaces the tint
// already on screen.
//
// Repetition is not evidence when the repeat is 16ms later: a window is at its
// least representative in the moment it appears -- a splash screen, a loading
// view, a surface that has not painted at all -- and two readings taken there
// are the same bad reading twice. Time is what separates that transient from
// the settled bar an application is left showing, and what keeps a one-frame
// flash (a tooltip passing over the bar, an animation frame) from flipping the
// panel.
constexpr auto ConfirmTime = std::chrono::milliseconds(500);
// Four early readings let a newly opened title bar finish painting and provide
// a reading after ConfirmTime. Later reads stay sparse even on busy windows.
constexpr int WarmupReads = 4;
constexpr auto WarmupInterval = std::chrono::milliseconds(250);
constexpr auto RecheckInterval = std::chrono::seconds(3);
// Window sizes are compared with this tolerance, in logical pixels. KWin's
// geometry is fractional -- a restored window reports a width like
// 1345.9999999999998 -- so comparing exactly re-reads the tint on sub-pixel
// jitter.
constexpr qreal SizeTolerance = 0.5;

// Extra logical pixels around the panel in which pointer events are swallowed
// as well -- see AppConfig::interceptMargin. The controls an application draws
// are larger than the panel that covers them, and a pointer that reaches the
// difference makes them light up around the panel's edge.
qreal interceptMargin(const AppConfig &config)
{
    return std::max(0.0, config.interceptMargin);
}

bool sameSize(const QSizeF &a, const QSizeF &b)
{
    return std::abs(a.width() - b.width()) <= SizeTolerance
        && std::abs(a.height() - b.height()) <= SizeTolerance;
}

// Whether `point` (global logical) is on a part of `window` that no window
// above it covers.
//
// This mirrors BridgeEffect::visibleRegionFor, which is what decides whether
// the panel is painted at all, and it is asked at the moment of the click
// rather than when the window was last painted: a panel hidden behind another
// window is not on screen, so a pointer there belongs to whatever is above it.
// Swallowing it would mean a click on an upper window doing something to a
// lower one -- closing it, at worst.
bool exposedAt(KWin::EffectWindow *window, const QPointF &point)
{
    if (!KWin::effects) {
        return true;
    }
    const QList<KWin::EffectWindow *> windows = KWin::effects->stackingOrder();
    const int index = windows.indexOf(window);
    if (index < 0) {
        return true;
    }
    for (int j = index + 1; j < windows.size(); ++j) {
        KWin::EffectWindow *above = windows[j];
        if (!above || !above->isVisible()) {
            continue;
        }
        // Keep hit testing aligned with BridgeEffect::visibleRegionFor.
        // Skip-switcher shell surfaces may have transparent frames spanning
        // the desktop; ordinary translucent windows still occlude the panel.
        if (above->isSkipSwitcher() || above->isDesktop() || above->isDock()
            || above->isOnScreenDisplay() || above->isNotification()) {
            continue;
        }
        if (above->frameGeometry().contains(point)) {
            return false;
        }
    }
    return true;
}

// The part of a rectangle this effect draws for a window that the compositor
// has not already covered: `deviceRegion` is the region of this window that is
// actually being painted (KWin has subtracted every opaque window stacked
// above it), intersected with the rectangle itself.
KWin::Region clippedToWindow(const KWin::Region &deviceRegion,
                             const KWin::RenderViewport &viewport,
                             const QRectF &logicalRect)
{
    const QRect relRect =
        viewport.mapToDeviceCoordinates(logicalRect).toAlignedRect();
    return deviceRegion
        & KWin::Region(relRect.x(), relRect.y(), relRect.width(), relRect.height());
}

// The pictogram in one cell of the tiling menu: a screen with the part of it
// the preset gives the window drawn filled.
//
// There are no words in the menu. The cells are 30 pixels square, so a label
// would be smaller than the picture it names, and the whole point of the
// pictogram is that the arrangement is what is being chosen -- the same way the
// three lights are read as colours rather than as the words close, minimize and
// zoom.
void drawTilePictogram(QPainter &painter, const QRectF &cell, TilePreset preset,
                       bool dark)
{
    // The screen, inset from the cell so that the pictograms of two
    // neighbouring cells cannot come near each other.
    const QRectF screen = cell.adjusted(4.5, 5.5, -4.5, -5.5);
    const QColor outline = dark ? QColor(255, 255, 255, 0x8C) : QColor(0, 0, 0, 0x66);

    painter.setPen(QPen(outline, 1.1));
    painter.setBrush(Qt::NoBrush);
    painter.drawRoundedRect(screen, 2.5, 2.5);

    if (preset == TilePreset::Restore) {
        // An arrow turning back on itself. Every other cell is a part of the
        // screen, and this one is not a part of anything: it is the window
        // going back to the size it had before it was placed.
        const QPointF centre = screen.center();
        const qreal radius = std::min(screen.width(), screen.height()) / 2.0 - 1.0;
        const QRectF circle(centre.x() - radius, centre.y() - radius,
                            radius * 2.0, radius * 2.0);
        painter.setPen(QPen(outline, 1.3, Qt::SolidLine, Qt::RoundCap));
        // Three quarters of the way round, clockwise from the top and stopping
        // at the left: the quarter that is left out is where the head goes.
        painter.drawArc(circle, 90 * 16, -270 * 16);

        // The head, at the end of the arc and pointing the way the arc was
        // travelling when it got there.
        QPainterPath head;
        head.moveTo(centre.x() - radius, centre.y() - 0.5);
        head.lineTo(centre.x() - radius - 2.8, centre.y() + 3.0);
        head.lineTo(centre.x() - radius + 2.8, centre.y() + 3.0);
        head.closeSubpath();
        painter.setPen(Qt::NoPen);
        painter.setBrush(outline);
        painter.drawPath(head);
        return;
    }

    // The region the preset gives the window. The thirds come from
    // tilePresetRect -- the same function the placements themselves are made
    // with, so a pictogram cannot promise somewhere the window would not go.
    // Its screen is the work area here, which is exactly the substitution the
    // picture is: the shape is the whole of what is being chosen.
    QRectF region = tilePresetRect(preset, screen);
    switch (preset) {
    case TilePreset::Fill:
        region = screen;
        break;
    case TilePreset::LeftHalf:
        region = QRectF(screen.left(), screen.top(), screen.width() / 2.0,
                        screen.height());
        break;
    case TilePreset::RightHalf:
        region = QRectF(screen.center().x(), screen.top(), screen.width() / 2.0,
                        screen.height());
        break;
    default:
        break;
    }
    if (region.isEmpty()) {
        return;
    }

    painter.setPen(Qt::NoPen);
    painter.setBrush(QColor(0x0A, 0x84, 0xFF));
    painter.drawRoundedRect(region, 2.0, 2.0);
}
}

ButtonRenderer *ButtonRenderer::s_instance = nullptr;
ButtonRenderer::ButtonRenderer() { s_instance = this; }
ButtonRenderer::~ButtonRenderer() { if (s_instance == this) s_instance = nullptr; }

void ButtonRenderer::paint(const KWin::RenderTarget &renderTarget,
                            const KWin::RenderViewport &viewport,
                            KWin::EffectWindow *window,
                            const AppConfig &config,
                            const KWin::Region &deviceRegion,
                            const PaintTransform &transform, bool sourceCapture)
{
    if (!window) {
        return;
    }

    // The panel is reconsidered from scratch on every paint: the hit rects are
    // added back at the end of this function, so an early return below -- a
    // window being animated, one the panel is not drawn for, a window whose
    // panel is entirely covered -- leaves it with none, and a panel that is not
    // on screen never takes the pointer.
    m_hits.remove(window);
    if (sourceCapture) m_sourceHits.remove(window);

    // The same rule for the tiling menu, whose rectangle is what the input filter
    // hit-tests: cleared here and published again at the end of this function, so
    // that a frame which returns early -- a window with no panel for the menu to
    // hang from -- leaves it with none. It is published from the panel's and the
    // window's geometry and NOT from what this frame repaints, for the reason
    // spelled out where it is set.
    if (m_menu.window == window) {
        m_menu.rect = QRectF();
    }

    if (!sourceCapture && !window->isVisible()) {
        return;
    }

    // KWin's own user interface is not an application window. The OSD the
    // desktop-change script draws, the outline, the tab switcher, the tile
    // editor: those are internal windows, made in this process for a QWindow
    // that has no client behind it (see the QPA plugin), so there is no title
    // bar of its own to cover and no application the controls could belong to.
    // Nothing above catches them either -- an internal window reports itself as
    // a managed, undecorated normal window, which is how the desktop-change OSD
    // -- a 57x35 pill in the middle of the screen -- used to grow three
    // buttons.
    if (KWin::Window *w = window->window(); w && w->isInternal()) {
        return;
    }

    // Only normal application windows and dialogs are candidates.
    if (!window->isNormalWindow() && !window->isDialog()) {
        return;
    }

    // Unmanaged (override-redirect) windows are not real top-levels: this is
    // how many toolkits implement tooltips, menus and drop-downs, even though
    // they otherwise look like normal windows.
    if (!window->isManaged()) {
        return;
    }

    // Reject every popup-like role explicitly. Transient surfaces such as
    // tooltips, menus and combo boxes can otherwise slip through as "normal"
    // on some backends and end up with their own panel.
    if (window->isSpecialWindow()
        || window->isPopupWindow()
        || window->isPopupMenu()
        || window->isDropdownMenu()
        || window->isComboBox()
        || window->isMenu()
        || window->isTooltip()
        || window->isAppletPopup()
        || window->isOnScreenDisplay()
        || window->isNotification()
        || window->isCriticalNotification()
        || window->isSplash()
        || window->isUtility()
        || window->isDock()
        || window->isDesktop()
        || window->isDNDIcon()) {
        return;
    }

    // Panels, docks and other shell surfaces (e.g. the Quickshell bar) claim to
    // be normal windows but are skipped by the task switcher.
    if (window->isSkipSwitcher()) {
        return;
    }

    const QString appId = window->windowClass();
    if (appId.contains(QStringLiteral("fcitx"), Qt::CaseInsensitive)
        || appId.contains(QStringLiteral("ibus"), Qt::CaseInsensitive)
        || appId.contains(QStringLiteral("inputmethod"), Qt::CaseInsensitive)) {
        return;
    }

    // The panel is the KOS decoration's window controls: the decoration draws a
    // title bar and a caption and nothing else, so the panel is where a window
    // wearing it gets its three lights. Selecting a different decoration in
    // System Settings therefore has to take the panel with it. It is not drawn
    // anywhere then -- not on a server-side window, where the other decoration
    // is painting controls of its own, and not on a client-side one either: an
    // application that draws its own title bar draws its own controls in it,
    // and a KOS panel in the corner of that is a panel nobody asked for. That
    // second half is why this is not just a rule about decorated windows.
    //
    // `decoratedWindows: "always"` is the exception, and the only way to ask
    // for the panel without the decoration. It is an explicit choice in the
    // user's own hand-written file -- the rules this plugin writes never carry
    // it -- so it is honoured rather than filtered out here.
    //
    // KWin does not tell an effect which decoration is in use, so the flag is
    // read out of kwinrc by the configuration and the redraw for a change comes
    // from its watcher (ButtonConfig::recheckDecoration).
    if (!config.kosDecorationSelected
        && config.decoratedWindows != DecoratedWindows::Always) {
        return;
    }

    // Server-side decorations: KWin paints their controls itself, so the panel
    // would sit on top of Breeze's own buttons. `drawOnDecoratedWindows` is how
    // that is overridden, and it resolves to true by itself when the decoration
    // in use is ours -- a decoration draws its frame and no buttons at all, so
    // without the panel a KOS-decorated window would have none.
    //
    // It is resolved here rather than by asking which decoration the window has,
    // because a decoration cannot be asked: `window->decoration()` is on the
    // decoration's side of the API, and an effect sees only whether KWin
    // decorated the window.
    if (window->hasDecoration() && !config.drawOnDecoratedWindows) {
        return;
    }

    // Everything below this line draws the window's panel with one geometry.
    // A window being adjusted uses the draft, and nothing else in this function
    // has to know which of the two it is: the drawn panel, the hit rects, the
    // tint band and hitTest() all follow from `geometry`.
    const PanelGeometry geometry = effectiveGeometry(window, config);

    // The panel goes where the configuration says, not where the application's
    // own controls happen to be: those can be told apart from a logo, a
    // toolbar or a half-painted frame only by guesswork, and a panel that
    // lands in the wrong place is worse than one that is a few pixels off the
    // controls it covers.
    const QPointF windowTopLeft = window->frameGeometry().topLeft();
    const QRectF local = panelRect(geometry, window->frameGeometry().size());
    const QSizeF panelSize = local.size();

    // The panel is opaque, so its tint has to come from the title bar
    // underneath before that is covered. Until the read succeeds nothing is
    // drawn: a guessed tint is exactly the misalignment this replaced.
    bool dark = false;
    switch (config.background) {
    case PanelBackground::Dark:
        dark = true;
        break;
    case PanelBackground::Light:
        dark = false;
        break;
    case PanelBackground::Auto:
        // The KOS decoration paints this strip from the window palette itself.
        // Reuse that exact source instead of synchronously reading the rendered
        // title bar back from the GPU. Client-side decorations still need the
        // pixel sampler because their title-bar color is not exposed to KWin.
        if (config.kosDecorationSelected && window->hasDecoration()
            && window->window()) {
            const QColor color = window->window()->palette().color(QPalette::Window);
            const int luma = (54 * color.red() + 183 * color.green()
                              + 19 * color.blue()) >> 8;
            dark = luma < 128;
        } else if (!tintFor(renderTarget, viewport, window, local, deviceRegion,
                            &dark)) {
            // No panel this frame, so no click should land on one either.
            m_hits.remove(window);
            return;
        }
        break;
    }

    // Apply the window's animation transform: scale about the window's
    // top-left, then translate, matching what KWin does to the window itself.
    const QPointF origin = windowTopLeft
        + QPointF(transform.xTranslate, transform.yTranslate);
    const QPointF localScaled(local.x() * transform.xScale,
                              local.y() * transform.yScale);
    const QSizeF sizeScaled(panelSize.width() * transform.xScale,
                            panelSize.height() * transform.yScale);
    const QRectF logicalRect(origin + localScaled, sizeScaled);

    // Remember the panel and the three dots in global logical coordinates so
    // the input filter can hit-test clicks against them. The dots come from
    // the same layout buildPanel() draws, so the two cannot drift apart.
    const QPointF panelOrigin = windowTopLeft + local.topLeft();
    HitRects hit;
    hit.windowOrigin = windowTopLeft;
    hit.panelRect = QRectF(panelOrigin, panelSize);
    // The margin is part of the panel as far as the pointer is concerned --
    // see AppConfig::interceptMargin -- but it is not allowed outside the
    // window: a margin hanging over the edge would swallow clicks aimed at
    // whatever is behind the window, which is not what the panel is for.
    const qreal margin = interceptMargin(config);
    hit.interceptRect =
        hit.panelRect.adjusted(-margin, -margin, margin, margin)
            .intersected(QRectF(windowTopLeft, window->frameGeometry().size()));
    for (int i = 0; i < TypeCount; ++i) {
        hit.dots[i] = dotRect(panelSize, geometry, i).translated(panelOrigin);
    }

    // The tiling menu, if one is open on this window. It hangs from the panel
    // being drawn now -- the draft, while the panel is being positioned -- and
    // from the light that opens it, and it is drawn under the same transform
    // and the same clip as the panel: it belongs to this window, so a window
    // stacked above covers it exactly as it covers anything else here.
    //
    // Where it is, though, is a question about the panel and the window and
    // nothing else -- not about which pixels this frame happens to repaint. It
    // is set here on every frame that gets this far, and the menu's rectangle is
    // the one the input filter hit-tests, so a frame that repaints the panel and
    // not the menu (the hover ring going out under the light, say) must leave it
    // exactly where it is. Making it depend on the frame's damage instead is how
    // a menu ends up on screen taking no clicks: damaged once at the moment it
    // opened, then never again while its pixels sit there undisturbed.
    //
    // Empty when the menu has nowhere to go -- the window was made shorter under
    // it -- and the input filter closes it on the next event.
    QRectF menuRect;
    QRectF menuLogical;
    KWin::Region menuClip;
    if (m_menu.window == window) {
        const auto menu = tileMenuRect(hit.panelRect, window->frameGeometry(),
                                       hit.dots[zoomDotIndex()].center());
        m_menu.rect = menu.value_or(QRectF());
        m_menu.dark = dark;
        if (menu) {
            menuRect = *menu;
            const QRectF menuLocal = menuRect.translated(-windowTopLeft);
            menuLogical = QRectF(origin
                                     + QPointF(menuLocal.x() * transform.xScale,
                                               menuLocal.y() * transform.yScale),
                                 QSizeF(menuLocal.width() * transform.xScale,
                                        menuLocal.height() * transform.yScale));
            menuClip = clippedToWindow(deviceRegion, viewport, menuLogical);
        }
    }
    m_hits[window] = hit;
    if (sourceCapture) m_sourceHits[window] = hit;

    // What this frame has to draw: the panel, and then the menu under it if one
    // is open. `deviceRegion` is this frame's damage, not a statement about
    // where either of the two is -- and the two are different rectangles, the
    // menu hanging below the panel, so it is ordinary for one of them to have
    // nothing to paint while the other has plenty. An application repainting
    // its content under an open menu damages the menu and not the panel, and
    // that is the normal case whenever the pointer is anywhere over the window.
    //
    // So neither is allowed to decide whether the other is drawn. A single early
    // return on the panel's clip used to: the menu's pixels were then left for
    // the window's own content to paint over -- the menu flicking out and
    // patches of the application showing through it, once per repaint
    // underneath, until something damaged the menu again.
    //
    // Both are asked after the hit rects are published rather than before, so
    // that a frame with nothing to paint still ends with the panel and the menu
    // where they are, and taking the pointer with them.
    const KWin::Region clip = clippedToWindow(deviceRegion, viewport, logicalRect);
    if (!clip.isEmpty()) {
        const bool active = (KWin::effects->activeWindow() == window);
        // The hover ring is not drawn while the window is being adjusted: the
        // panel is being positioned, and a ring following the pointer across it
        // says nothing about that.
        const bool adjusting = m_adjusting.contains(window);
        const Action hovered =
            (!adjusting && m_hoverWindow == window) ? m_hovered : Action::None;
        // What the green dot's glyph is drawn from. `performAction` toggles on
        // exactly this test, so the mark and the click agree by construction
        // rather than by two conditions that happen to match today.
        const KWin::Window *w = window->window();
        const bool maximized =
            w && w->maximizeMode() == KWin::MaximizeFull;
        if (KWin::GLTexture *tex = panelTexture(panelSize, active, dark, geometry,
                                                hovered, adjusting, maximized)) {
            blit(viewport, clip, logicalRect, tex);
        }
    }

    // The menu, over the panel. The two do not overlap -- the menu's top edge
    // is the panel's bottom edge, and the panel is a rounded chip inside its
    // own rectangle -- so the order between them does not matter; drawing it
    // second is simply the order they are stacked in if that ever changes.
    //
    // Its clip is its own, and it is drawn whether or not the panel was: the
    // clip is the part of the menu this frame repaints, and nothing to draw
    // there is the only reason not to draw it.
    if (!menuClip.isEmpty()) {
        if (KWin::GLTexture *menu = tileMenuTexture(m_menu.dark, m_menu.hovered)) {
            blit(viewport, menuClip, menuLogical, menu);
        }
    }
}

void ButtonRenderer::blit(const KWin::RenderViewport &viewport,
                          const KWin::Region &clip, const QRectF &logicalRect,
                          KWin::GLTexture *texture)
{
    if (!texture || clip.isEmpty()) {
        return;
    }

    // The projection matrix takes scaled global coordinates, while damage and
    // visible regions are in viewport device coordinates. Keep both origins so
    // a visible piece can be positioned and sampled from the same panel image.
    const qreal scale = viewport.scale();
    const QRectF deviceAbs(logicalRect.topLeft() * scale, logicalRect.size() * scale);
    const QRectF panelDevice = viewport.mapToDeviceCoordinates(logicalRect);
    if (panelDevice.isEmpty()) {
        return;
    }
    const KWin::Rect panelBounds = panelDevice.toAlignedRect();
    const KWin::Region visiblePieces = clip & KWin::Region(panelBounds);
    if (visiblePieces.isEmpty()) {
        return;
    }

    auto *shaderManager = KWin::ShaderManager::instance();
    // NOTE: do not add ShaderTrait::Modulate here. It changes how the texture's
    // alpha is blended and makes the transparent corners of the panel come out
    // as opaque dark blocks. Opacity during animations is handled by hiding the
    // panel while the window is transformed (see BridgeEffect::drawWindow).
    shaderManager->pushShader(KWin::ShaderTrait::MapTexture);
    KWin::GLShader *shader = shaderManager->getBoundShader();
    shader->setUniform(KWin::GLShader::IntUniform::TextureWidth, texture->width());
    shader->setUniform(KWin::GLShader::IntUniform::TextureHeight, texture->height());

    // These textures are premultiplied ARGB with transparent rounded corners.
    // Without an explicit blend the corners would be written straight into the
    // framebuffer as alpha 0 (which shows up as opaque black), so blend them
    // properly and restore the previous state afterwards.
    const GLboolean blendWasEnabled = glIsEnabled(GL_BLEND);
    GLint prevSrcRgb = 0;
    GLint prevDstRgb = 0;
    GLint prevSrcAlpha = 0;
    GLint prevDstAlpha = 0;
    glGetIntegerv(GL_BLEND_SRC_RGB, &prevSrcRgb);
    glGetIntegerv(GL_BLEND_DST_RGB, &prevDstRgb);
    glGetIntegerv(GL_BLEND_SRC_ALPHA, &prevSrcAlpha);
    glGetIntegerv(GL_BLEND_DST_ALPHA, &prevDstAlpha);

    glEnable(GL_BLEND);
    glBlendFuncSeparate(GL_ONE, GL_ONE_MINUS_SRC_ALPHA,
                        GL_ONE, GL_ONE_MINUS_SRC_ALPHA);

    // GLTexture's hardware-clipping path needs framebuffer-local scissor
    // coordinates. The effect's region is in viewport device coordinates, so
    // feeding it to that path can either ignore the cover or hide the whole
    // panel. Draw only the visible geometry instead: each rectangle maps to
    // the corresponding source slice of the cached panel texture.
    if (visiblePieces.contains(panelBounds)) {
        QMatrix4x4 mvp = viewport.projectionMatrix();
        mvp.translate(deviceAbs.x(), deviceAbs.y());
        shader->setUniform(KWin::GLShader::Mat4Uniform::ModelViewProjectionMatrix,
                           mvp);
        texture->render(deviceAbs.size());
    } else {
        const qreal sourceScaleX = texture->width() / panelDevice.width();
        const qreal sourceScaleY = texture->height() / panelDevice.height();
        for (const KWin::Rect &piece : visiblePieces.rects()) {
            const qreal dx = piece.x() - panelDevice.x();
            const qreal dy = piece.y() - panelDevice.y();
            const QRectF source(dx * sourceScaleX, dy * sourceScaleY,
                                piece.width() * sourceScaleX,
                                piece.height() * sourceScaleY);
            QMatrix4x4 mvp = viewport.projectionMatrix();
            mvp.translate(deviceAbs.x() + dx, deviceAbs.y() + dy);
            shader->setUniform(KWin::GLShader::Mat4Uniform::ModelViewProjectionMatrix,
                               mvp);
            texture->render(source, KWin::Region::infinite(), piece.size());
        }
    }

    glBlendFuncSeparate(prevSrcRgb, prevDstRgb, prevSrcAlpha, prevDstAlpha);
    if (!blendWasEnabled) {
        glDisable(GL_BLEND);
    }

    shaderManager->popShader();
}

bool ButtonRenderer::tintFor(const KWin::RenderTarget &renderTarget,
                              const KWin::RenderViewport &viewport,
                              KWin::EffectWindow *window,
                              const QRectF &panel,
                              const KWin::Region &deviceRegion,
                              bool *dark)
{
    // A cached tint still draws on an inactive window, but only the active
    // window is allowed to read pixels or keep a sampling timer alive.
    if (!KWin::effects || KWin::effects->activeWindow() != window) {
        const auto cached = m_cache.constFind(window);
        if (cached == m_cache.constEnd() || !cached->known) {
            return false;
        }
        *dark = cached->dark;
        return true;
    }

    const QSizeF windowSize = window->frameGeometry().size();
    const Clock::time_point now = Clock::now();

    auto it = m_cache.find(window);
    if (it == m_cache.end()) {
        it = m_cache.insert(window, CacheEntry{});
        it->sampleToken = ++m_nextSampleToken;
    } else if (!sameSize(it->windowSize, windowSize)) {
        // Resize can paint every frame. Keep the cadence and the displayed
        // tint; the next scheduled read will use the new band.
        it->pending = false;
    }
    it->windowSize = windowSize;
    it->panel = panel;

    const auto interval = it->warmupReads < WarmupReads
        ? WarmupInterval : RecheckInterval;
    if (it->lastRead == Clock::time_point{} || now - it->lastRead >= interval) {
        bool sampled = false;
        // Count attempts, including unreadable bars. An obscured window cannot
        // keep triggering the fast sampling phase indefinitely.
        it->lastRead = now;
        if (it->warmupReads < WarmupReads) {
            ++it->warmupReads;
        }
        if (sampleTitlebarTint(renderTarget, viewport, window, deviceRegion,
                               panel, &sampled)) {
            if (!it->known) {
                // Show the first usable tint immediately. Later readings can
                // still correct it after the title bar has settled.
                it->known = true;
                it->dark = sampled;
                it->pending = true;
                it->pendingDark = sampled;
                it->pendingSince = now;
            } else if (it->pending && sampled == it->pendingDark
                       && now - it->pendingSince >= ConfirmTime) {
                it->dark = sampled;
                it->pending = false;
            } else if (it->pending && sampled != it->pendingDark) {
                // A conflicting reading resets confirmation. If it matches
                // the displayed tint there is no change left to confirm.
                it->pending = sampled != it->dark;
                it->pendingDark = sampled;
                it->pendingSince = now;
            } else if (!it->pending && sampled != it->dark) {
                it->pending = true;
                it->pendingDark = sampled;
                it->pendingSince = now;
            }
        }
    }

    scheduleSample(window);
    if (!it->known) {
        return false;
    }
    *dark = it->dark;
    return true;
}

void ButtonRenderer::scheduleSample(KWin::EffectWindow *window)
{
    auto it = m_cache.find(window);
    if (it == m_cache.end() || it->sampleScheduled) {
        return;
    }
    const auto interval = it->warmupReads < WarmupReads
        ? WarmupInterval : RecheckInterval;
    const auto due = it->lastRead + interval;
    const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(
        due - Clock::now());
    const int delay = std::max(1, int(remaining.count()) + 1);
    const quint64 token = it->sampleToken;
    it->sampleScheduled = true;
    QTimer::singleShot(delay, this,
                       [this, guarded = QPointer<KWin::EffectWindow>(window),
                        token]() {
        if (!guarded) {
            return;
        }
        auto entry = m_cache.find(guarded);
        if (entry == m_cache.end() || entry->sampleToken != token) {
            return;
        }
        entry->sampleScheduled = false;
        if (!KWin::effects || KWin::effects->activeWindow() != guarded) {
            return;
        }
        requestSample(guarded, entry->panel);
    });
}

void ButtonRenderer::requestSample(KWin::EffectWindow *window, const QRectF &panel)
{
    if (!KWin::effects || !window) {
        return;
    }
    const QRectF frame = window->frameGeometry();
    // The band the tint is read from: the panel's rows, across the window's
    // whole width. addRepaint takes global logical coordinates.
    const QRectF band(frame.x(), frame.y() + panel.y(), frame.width(),
                      panel.height());
    repaintRect(band);
}

void ButtonRenderer::repaintRect(const QRectF &globalRect)
{
    if (!KWin::effects || globalRect.isEmpty()) {
        return;
    }
    if (s_instance) Q_EMIT s_instance->sourceRepaint(globalRect);
    KWin::effects->addRepaint(KWin::RectF(globalRect.x(), globalRect.y(),
                                          globalRect.width(),
                                          globalRect.height()));
}

PanelGeometry ButtonRenderer::effectiveGeometry(KWin::EffectWindow *window,
                                                const AppConfig &config) const
{
    const auto it = m_pending.constFind(window);
    return it == m_pending.constEnd() ? config.geometry : it.value();
}

QRectF ButtonRenderer::panelRectFor(KWin::EffectWindow *window,
                                    const PanelGeometry &geometry) const
{
    if (!window) {
        return {};
    }
    const QRectF frame = window->frameGeometry();
    return panelRect(geometry, frame.size()).translated(frame.topLeft());
}

QRectF ButtonRenderer::currentRect(KWin::EffectWindow *window) const
{
    const auto pending = m_pending.constFind(window);
    if (pending != m_pending.constEnd()) {
        return panelRectFor(window, pending.value());
    }
    // No draft: the rectangle the panel was last drawn at, which is what is on
    // screen. Absent for a window whose panel is not drawn at all -- a window
    // being animated, or one the guards reject -- and then there is nothing to
    // damage.
    const auto hit = m_hits.constFind(window);
    return hit == m_hits.constEnd() ? QRectF() : hit.value().panelRect;
}

PanelGeometry ButtonRenderer::pendingGeometry(KWin::EffectWindow *window) const
{
    return m_pending.value(window);
}

bool ButtonRenderer::hasPendingGeometry(KWin::EffectWindow *window) const
{
    return m_pending.contains(window);
}

void ButtonRenderer::setPendingGeometry(KWin::EffectWindow *window,
                                        const PanelGeometry &draft)
{
    if (!window) {
        return;
    }
    const auto existing = m_pending.constFind(window);
    if (existing != m_pending.constEnd()
        && sameGeometry(existing.value(), draft)) {
        return;
    }

    // The panel that is on screen now has to be repainted as well as the one
    // that is about to be, or the draft leaves a copy of itself behind at every
    // step of a drag.
    repaintRect(currentRect(window));
    m_pending[window] = draft;
    repaintRect(panelRectFor(window, draft));
}

void ButtonRenderer::clearPendingGeometry(KWin::EffectWindow *window,
                                          const PanelGeometry &base)
{
    if (!window || !m_pending.contains(window)) {
        return;
    }
    repaintRect(panelRectFor(window, m_pending.value(window)));
    m_pending.remove(window);
    // `base` rather than currentRect(): after the removal the hit rects still
    // hold the draft, because that is what the last frame was painted with. The
    // geometry the configuration resolves to is the one the next frame draws,
    // and only the caller knows it.
    repaintRect(panelRectFor(window, base));
}

void ButtonRenderer::setAdjusting(KWin::EffectWindow *window, bool adjusting)
{
    if (!window) {
        return;
    }
    const bool was = m_adjusting.contains(window);
    if (was == adjusting) {
        return;
    }
    const QRectF rect = currentRect(window);
    if (adjusting) {
        m_adjusting.insert(window);
        // The hover ring goes away with the adjust ring.
        if (m_hoverWindow == window) {
            m_hovered = Action::None;
        }
    } else {
        m_adjusting.remove(window);
    }
    // The panel is drawn differently either way, and the texture is keyed on
    // which, so the whole rectangle has to be redrawn.
    repaintRect(rect);
}

bool ButtonRenderer::adjusting(KWin::EffectWindow *window) const
{
    return m_adjusting.contains(window);
}

KWin::GLTexture *ButtonRenderer::panelTexture(const QSizeF &panelSize, bool active,
                                               bool dark,
                                               const PanelGeometry &geometry,
                                               Action hovered, bool adjusting,
                                               bool maximized)
{
    // The panel size is part of the key so that a configuration change that
    // alters it yields a new texture rather than a stretched one. The maximized
    // flag is part of it for the same reason: it is not a separate texture, it
    // is the same panel with the other restore glyph on its green dot, and a
    // window that has just been maximized must not be served the one it had
    // before.
    const QString key = QStringLiteral("%1x%2_%3_%4_%5_%6_%7_%8_%9_%10_%11")
                            .arg(qRound(panelSize.width()))
                            .arg(qRound(panelSize.height()))
                            .arg(active ? 1 : 0)
                            .arg(dark ? 1 : 0)
                            .arg(geometry.buttonSize)
                            .arg(geometry.buttonSpacing)
                            .arg(static_cast<int>(hovered))
                            .arg(qRound(geometry.panelPadding))
                            // Horizontal padding, which is not the panel's
                            // height: two panels can agree on every rounded
                            // value above and still be different widths.
                            .arg(qRound(effectivePanelPaddingX(geometry) * 4))
                            .arg(adjusting ? 1 : 0)
                            .arg(maximized ? 1 : 0);
    auto it = m_textures.find(key);
    if (it == m_textures.end()) {
        return cacheTexture(key, buildPanel(panelSize, active, dark, geometry,
                                            hovered, adjusting, maximized));
    }
    return it->second.get();
}

KWin::GLTexture *ButtonRenderer::cacheTexture(const QString &key, QImage image)
{
    const qsizetype bytes = image.sizeInBytes();
    if (m_textureBytes + bytes > MaxTextureCacheBytes) {
        m_textures.clear();
        m_textureBytes = 0;
    }
    auto texture = KWin::GLTexture::upload(image);
    if (!texture) {
        return nullptr;
    }
    // Sliced draws can sample just beyond an outer texel at a fractional-scale
    // edge. Repeating would pull pixels from the opposite side of the panel.
    texture->setWrapMode(GL_CLAMP_TO_EDGE);
    m_textureBytes += bytes;
    return m_textures.emplace(key, std::move(texture)).first->second.get();
}

void ButtonRenderer::setHovered(KWin::EffectWindow *window, Action action)
{
    if (m_hoverWindow == window && m_hovered == action) {
        return;
    }

    // Through the compositor rather than through the window:
    // EffectWindow::addRepaintFull() called from a pointer-motion handler has
    // been crashing KWin, and only the panel rectangle changes anyway.
    repaintRect(currentRect(m_hoverWindow));
    m_hoverWindow = window;
    m_hovered = action;
    repaintRect(currentRect(window));
}

void ButtonRenderer::repaintPanels(KWin::EffectWindow *a, KWin::EffectWindow *b)
{
    // Through the compositor, for the reason setHovered() gives. Only the panels
    // that are on screen: currentRect() is the rectangle a panel was last drawn
    // at, and empty for a window that has none.
    repaintRect(currentRect(a));
    if (b != a) {
        const QRectF panel = currentRect(b);
        // An inactive CSD window may have no cached tint and therefore no
        // panel yet. Give it one paint on activation so its first read runs.
        repaintRect(panel.isEmpty() && b ? QRectF(b->frameGeometry()) : panel);
    }
}

int ButtonRenderer::zoomDotIndex()
{
    // The light the tiling menu hangs from: the one that performs the action
    // the menu is about. Asked through the order table rather than written down
    // as a number, so that reordering the panel moves the anchor with the light
    // it belongs to -- the same reason hitTest() asks.
    for (int i = 0; i < TypeCount; ++i) {
        if (actionFor(typeAt(i)) == Action::Maximize) {
            return i;
        }
    }
    return 0;
}

bool ButtonRenderer::openTileMenu(KWin::EffectWindow *window)
{
    if (!window) {
        return false;
    }
    if (m_menu.window == window) {
        return true;
    }

    // A window that cannot be resized has nothing to choose here: every cell but
    // Restore is a size the window takes on, and KWin's own tiling refuses a
    // window without a resize -- as does maximizing it. Offering eight cells of
    // which seven do nothing is worse than offering none, so there is no menu to
    // open.
    if (KWin::Window *w = window->window(); !w || !w->isResizable()) {
        return false;
    }

    // The menu hangs from a panel that is on screen. A window whose panel was
    // not drawn this frame -- one being animated, one that is covered, one
    // whose tint has not been read yet -- has nothing for it to hang from, and
    // m_hits holds nothing for it either.
    const auto hit = m_hits.constFind(window);
    if (hit == m_hits.constEnd()) {
        return false;
    }
    const QRectF panelRect = hit.value().panelRect;
    const std::optional<QRectF> menu =
        tileMenuRect(panelRect, window->frameGeometry(),
                     hit.value().dots[zoomDotIndex()].center());
    if (!menu) {
        return false;
    }

    // One at a time. Opening a second one is what the input filter does when
    // the pointer moves from one window's panel to another's.
    closeTileMenu();
    m_menu.window = window;
    m_menu.hovered = std::nullopt;
    // Where it is, known before the frame that draws it: the motion that is
    // already on its way must find the menu where it is about to be, or it
    // would arrive outside it and close it again. Every later frame recomputes
    // this from where the panel and the window are then.
    m_menu.rect = *menu;
    repaintRect(panelRect);
    repaintRect(*menu);
    return true;
}

void ButtonRenderer::closeTileMenu()
{
    if (!m_menu.window) {
        return;
    }
    const QRectF rect = m_menu.rect;
    m_menu = TileMenuState{};
    // The menu is not there any more, so the pixels it was drawn over have to
    // be painted again.
    repaintRect(rect);
}

KWin::EffectWindow *ButtonRenderer::tileMenuWindow() const
{
    return m_menu.window;
}

bool ButtonRenderer::tileMenuRegionContains(const QPointF &logicalPos) const
{
    // The menu's rectangle is set from the panel's and the window's geometry on
    // every frame the panel is drawn, and cleared on the frames it is not: empty
    // means there is no menu, wherever the pointer is.
    if (!m_menu.window || m_menu.rect.isEmpty()) {
        return false;
    }
    const auto hit = m_hits.constFind(m_menu.window);
    if (hit == m_hits.constEnd()) {
        return false;
    }

    // And, as for the panel itself, a part of the window that something is
    // stacked above belongs to that window rather than to this one. That is what
    // the drawing's clip used to stand in for -- and no longer can, now that the
    // clip is the frame's damage rather than the window's visible region.
    if (!exposedAt(m_menu.window, logicalPos)) {
        return false;
    }
    if (m_menu.rect.contains(logicalPos)) {
        return true;
    }

    const HitRects &rects = hit.value();
    if (rects.interceptRect.contains(logicalPos)) {
        return true;
    }

    // The column between the panel and the menu, as wide as the panel. The
    // menu's top edge is the panel's bottom edge, so in the ordinary case this
    // is a column of no height and the walk from the light down into the menu
    // passes from one straight into the other. It has height when the menu was
    // slid sideways to fit inside the window: then the pointer can leave the
    // panel's columns above the menu's, and this is what keeps the two ends of
    // that walk joined.
    const QRectF column(rects.panelRect.left(), rects.panelRect.bottom(),
                        rects.panelRect.width(),
                        m_menu.rect.bottom() - rects.panelRect.bottom());
    return column.contains(logicalPos);
}

std::optional<TilePreset> ButtonRenderer::tileMenuPresetAt(
    const QPointF &logicalPos) const
{
    return KOS::tileMenuPresetAt(m_menu.rect, logicalPos);
}

void ButtonRenderer::setTileMenuHovered(const QPointF &logicalPos)
{
    if (!m_menu.window) {
        return;
    }
    const std::optional<TilePreset> preset =
        KOS::tileMenuPresetAt(m_menu.rect, logicalPos);
    if (preset == m_menu.hovered) {
        return;
    }
    // The whole box rather than the two cells: it is 139x73, and a highlight
    // that moved from one cell to the next would otherwise have to be drawn out
    // of one rectangle and into another on the same frame.
    repaintRect(m_menu.rect);
    m_menu.hovered = preset;
}

QImage ButtonRenderer::buildPanel(const QSizeF &panelSize, bool active, bool dark,
                                   const PanelGeometry &geometry, Action hovered,
                                   bool adjusting, bool maximized) const
{
    const qreal w = panelSize.width();
    const qreal h = panelSize.height();

    QImage image(qRound(w * Supersample), qRound(h * Supersample),
                 QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);

    QPainter painter(&image);
    painter.setRenderHint(QPainter::Antialiasing, true);
    painter.scale(Supersample, Supersample);

    // Opaque rounded panel. This is what covers the application's own window
    // controls rather than merely floating above them.
    const QColor panel = dark ? QColor(28, 28, 32)
                              : QColor(242, 242, 245);
    painter.setPen(Qt::NoPen);
    painter.setBrush(panel);
    painter.drawRoundedRect(QRectF(0, 0, w, h), h / 2.0, h / 2.0);

    if (adjusting) {
        // The panel is being positioned. A ring says which panel is being
        // positioned without covering any of it -- and without a numeric
        // readout, which would need a second texture over the thing whose
        // position is the whole point of the exercise. The file the commit
        // writes is the readout.
        constexpr qreal RingWidth = 1.5;
        painter.setPen(QPen(QColor(0x0A, 0x84, 0xFF), RingWidth));
        painter.setBrush(Qt::NoBrush);
        painter.drawRoundedRect(QRectF(0, 0, w, h).adjusted(RingWidth / 2.0,
                                                           RingWidth / 2.0,
                                                           -RingWidth / 2.0,
                                                           -RingWidth / 2.0),
                                h / 2.0, h / 2.0);

        // The grips, one bar on each edge. They are what makes the width and the
        // height adjustable on their own rather than through the dot size, and
        // they are drawn from gripRect() -- the same rects the session
        // hit-tests -- so the handle that is under the pointer is always the
        // handle that moves.
        painter.setPen(QPen(dark ? QColor(255, 255, 255, 0x90)
                                 : QColor(0, 0, 0, 0x30),
                            0.75));
        painter.setBrush(QColor(0x0A, 0x84, 0xFF));
        for (const PanelEdge edge : {PanelEdge::Left, PanelEdge::Right,
                                     PanelEdge::Top, PanelEdge::Bottom}) {
            painter.drawRect(gripRect(geometry, edge));
        }
    }

    for (int i = 0; i < TypeCount; ++i) {
        const Type type = typeAt(i);
        const QRectF disc = dotRect(panelSize, geometry, i);

        // Hover: a contrasting ring around the dot. Drawn here rather than in
        // drawLight(), which knows nothing about the pointer: the ring is an
        // affordance of this panel and takes its colour from the panel's own
        // tint, while the light under it is the same light in every panel.
        if (actionFor(type) == hovered) {
            const QColor ring = dark ? QColor(255, 255, 255, 0xE0)
                                     : QColor(30, 30, 30, 0xB0);
            painter.setPen(QPen(ring,
                                std::max(1.0, geometry.buttonSize * 0.11)));
            painter.setBrush(Qt::NoBrush);
            painter.drawEllipse(disc.adjusted(-2.5, -2.5, 2.5, 2.5));
        }

        drawLight(painter, disc, type, active, maximized);
    }

    painter.end();
    return image;
}

KWin::GLTexture *ButtonRenderer::tileMenuTexture(bool dark,
                                                 std::optional<TilePreset> hovered)
{
    const QSizeF size = tileMenuSize();
    // The size is in the key although nothing here changes it: it comes from
    // the layout constants, and a change to one of those has to yield a new
    // texture rather than a stretched one -- the same reason the panel's key
    // carries its own size.
    const QString key = QStringLiteral("menu_%1x%2_%3_%4")
                            .arg(qRound(size.width()))
                            .arg(qRound(size.height()))
                            .arg(dark ? 1 : 0)
                            .arg(hovered ? static_cast<int>(*hovered) : -1);
    auto it = m_textures.find(key);
    if (it == m_textures.end()) {
        return cacheTexture(key, buildTileMenu(dark, hovered));
    }
    return it->second.get();
}

QImage ButtonRenderer::buildTileMenu(bool dark,
                                     std::optional<TilePreset> hovered) const
{
    const QSizeF size = tileMenuSize();

    QImage image(qRound(size.width() * Supersample),
                 qRound(size.height() * Supersample),
                 QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);

    QPainter painter(&image);
    painter.setRenderHint(QPainter::Antialiasing, true);
    painter.scale(Supersample, Supersample);

    // Opaque, like the panel, and with a hairline of its own: the menu hangs
    // over the window's own content rather than over its title bar, and a menu
    // that happened to match what is behind it would have no edge at all.
    const QRectF box(QPointF(0, 0), size);
    painter.setPen(QPen(dark ? QColor(255, 255, 255, 0x1A) : QColor(0, 0, 0, 0x1A),
                        0.75));
    painter.setBrush(dark ? QColor(28, 28, 32) : QColor(242, 242, 245));
    painter.drawRoundedRect(box, TileMenuRadius, TileMenuRadius);

    const TileMenuCells cells = tileMenuCells(box);
    for (int i = 0; i < TilePresetCount; ++i) {
        const TilePreset preset = tilePresetAt(i);

        if (hovered && *hovered == preset) {
            painter.setPen(Qt::NoPen);
            painter.setBrush(dark ? QColor(255, 255, 255, 0x1F)
                                  : QColor(0, 0, 0, 0x16));
            painter.drawRoundedRect(cells[i], 6.0, 6.0);
        }

        drawTilePictogram(painter, cells[i], preset, dark);
    }

    painter.end();
    return image;
}

Type ButtonRenderer::typeAt(int index)
{
    // Which light sits in each of the three positions, left to right. The
    // colours, the glyphs, the hit-testing and the actions all follow this, so
    // reordering the panel is this line and nothing else.
    constexpr Type Order[TypeCount] = {Maximize, Minimize, Close};

    if (index < 0 || index >= TypeCount) {
        return Close;
    }
    return Order[index];
}

ButtonRenderer::Action ButtonRenderer::actionFor(Type type)
{
    switch (type) {
    case Close: return Action::Close;
    case Minimize: return Action::Minimize;
    case Maximize: return Action::Maximize;
    case TypeCount: break;
    }
    return Action::None;
}

ButtonRenderer::Action ButtonRenderer::hitTest(const QPointF &logicalPos,
                                               KWin::EffectWindow **window,
                                               bool *insidePanel) const
{
    if (window) {
        *window = nullptr;
    }
    if (insidePanel) {
        *insidePanel = false;
    }

    // Most motion events land nowhere near a panel, and the stacking order is
    // only needed for the ones that do.
    bool nearPanel = false;
    for (auto it = m_hits.constBegin(); it != m_hits.constEnd(); ++it) {
        if (it.value().interceptRect.contains(logicalPos)) {
            nearPanel = true;
            break;
        }
    }
    if (!nearPanel || !KWin::effects) {
        return Action::None;
    }

    // Topmost first. Two windows can have their panels over the same pixels --
    // a stacked pair sharing a top-left corner, say -- and only the one on top
    // is on screen; taking the other would act on a window the pointer is not
    // even pointing at.
    const QList<KWin::EffectWindow *> windows = KWin::effects->stackingOrder();
    for (int i = windows.size() - 1; i >= 0; --i) {
        KWin::EffectWindow *w = windows[i];
        if (!w || !w->isVisible()) {
            continue;
        }
        const auto found = m_hits.constFind(w);
        if (found == m_hits.constEnd()) {
            continue;
        }
        const HitRects &hit = found.value();
        if (!hit.interceptRect.contains(logicalPos)) {
            continue;
        }
        if (!exposedAt(w, logicalPos)) {
            continue;
        }

        if (window) {
            *window = w;
        }
        if (insidePanel) {
            *insidePanel = true;
        }

        for (int i = 0; i < TypeCount; ++i) {
            if (hit.dots[i].contains(logicalPos)) {
                return actionFor(typeAt(i));
            }
        }
        // Inside the panel but not on a dot: swallow the click, no action.
        return Action::None;
    }

    return Action::None;
}

void ButtonRenderer::syncHits(KWin::EffectWindow *window)
{
    if (!m_hits.contains(window)) {
        const auto source = m_sourceHits.constFind(window);
        if (source == m_sourceHits.cend()) return;
        m_hits.insert(window, source.value());
    }
    auto it = m_hits.find(window);
    if (it == m_hits.end()) return;
    const QPointF origin = window->frameGeometry().topLeft();
    const QPointF delta = origin - it->windowOrigin;
    it->windowOrigin = origin;
    it->panelRect.translate(delta);
    it->interceptRect.translate(delta);
    for (auto &dot : it->dots) dot.translate(delta);
    if (m_menu.window == window) {
        m_menu.rect = tileMenuRect(it->panelRect, window->frameGeometry(),
            it->dots[zoomDotIndex()].center()).value_or(QRectF());
    }
}

void ButtonRenderer::clearHits(KWin::EffectWindow *window, bool clearSource)
{
    m_hits.remove(window);
    if (clearSource) m_sourceHits.remove(window);
    if (m_menu.window == window) m_menu.rect = QRectF();
}

void ButtonRenderer::forget(KWin::EffectWindow *window)
{
    m_hits.remove(window);
    m_sourceHits.remove(window);
    m_cache.remove(window);
    // A draft and an adjust ring belong to a window that has gone away. The
    // session that was holding them is told separately by AdjustSession, which
    // is the only thing that could still be pointing at the pointer.
    m_pending.remove(window);
    m_adjusting.remove(window);

    // The menu hangs from this window's panel, so it goes with it. Nothing is
    // repainted -- there is no window to repaint -- and the hit rects it was
    // tested against are gone with m_hits above.
    if (m_menu.window == window) {
        m_menu = TileMenuState{};
    }

    // Critical: drop the hover reference too. Otherwise the next mouse move
    // would call addRepaintFull() on a window that has already been destroyed.
    if (m_hoverWindow == window) {
        m_hoverWindow = nullptr;
        m_hovered = Action::None;
    }
}

void ButtonRenderer::invalidateAll()
{
    m_cache.clear();
    m_hits.clear();
    m_sourceHits.clear();
    m_hoverWindow = nullptr;
    m_hovered = Action::None;
    // m_pending and m_adjusting are deliberately kept: they belong to a session
    // that is still running, and reloading the configuration is not a reason to
    // throw away the panel the user is in the middle of positioning.
}

} // namespace KOS
